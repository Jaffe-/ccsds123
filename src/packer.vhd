--------------------------------------------------------------------------------
-- Variable length word combiner
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;
use ieee.math_real.all;

library xpm;
use xpm.vcomponents.all;

entity packer is
  generic (
    BLOCK_SIZE        : integer := 32;
    N_WORDS           : integer := 4;
    N_WORDS_PER_CHAIN : integer := 4;
    MAX_LENGTH        : integer := 48;
    LITTLE_ENDIAN     : boolean := false
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_words   : in std_logic_vector(N_WORDS * MAX_LENGTH - 1 downto 0);
    in_lengths : in unsigned(N_WORDS * num2bits(MAX_LENGTH) - 1 downto 0);
    in_valid   : in std_logic;
    in_last    : in std_logic;

    out_data  : out std_logic_vector(BLOCK_SIZE-1 downto 0);
    out_valid : out std_logic;
    out_last  : out std_logic;
    out_ready : in  std_logic;

    over_threshold : out std_logic
    );
end packer;

architecture rtl of packer is
  constant N_CHAINS : integer := integer(ceil(real(N_WORDS)/real(N_WORDS_PER_CHAIN)));

  -- The maximum number of blocks from the largest chains
  constant MAX_BLOCKS_PER_CHAIN : integer := integer(ceil(real(N_WORDS_PER_CHAIN * MAX_LENGTH)/real(BLOCK_SIZE)));
  constant MAX_BLOCKS_PER_WORD  : integer := (BLOCK_SIZE + MAX_LENGTH) / BLOCK_SIZE;

  function num_words(i : integer) return integer is
  begin
    if (N_WORDS mod N_WORDS_PER_CHAIN /= 0 and i = N_CHAINS-1) then
      return N_WORDS mod N_WORDS_PER_CHAIN;
    else
      return N_WORDS_PER_CHAIN;
    end if;
  end num_words;

  function block_set_size(i : integer) return integer is
  begin
    return integer(ceil(real(num_words(i) * MAX_LENGTH)/real(BLOCK_SIZE)));
  end block_set_size;

  constant LENGTH_BITS : integer := num2bits(MAX_LENGTH);

  type block_set_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE-1 downto 0);
  type blocks_count_arr_t is array (0 to N_CHAINS-1) of integer range 0 to MAX_BLOCKS_PER_CHAIN;
  type remaining_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(BLOCK_SIZE-2 downto 0);
  type remaining_length_arr_t is array (0 to N_CHAINS-1) of integer range 0 to BLOCK_SIZE-1;

  signal from_delay_words : std_logic_vector(N_WORDS*MAX_LENGTH-1 downto 0);

  signal from_calc_remaining_length : remaining_length_arr_t;

  signal from_combine_blocks     : block_set_arr_t;
  signal from_combine_remaining  : remaining_arr_t;
  signal from_combine_has_blocks : std_logic_vector(N_CHAINS-1 downto 0);

  type word_delay_arr_t is array (0 to N_CHAINS) of std_logic_vector(N_WORDS*MAX_LENGTH-1 downto 0);
  signal word_regs  : word_delay_arr_t;
  signal valid_regs : std_logic_vector(2*N_CHAINS + 1 downto 0);
  signal last_regs  : std_logic_vector(2*N_CHAINS + 1 downto 0);

  signal prev_remaining        : std_logic_vector(BLOCK_SIZE-2 downto 0);
  signal prev_remaining_next   : std_logic_vector(BLOCK_SIZE-2 downto 0);
  signal prev_remaining_length : integer range 0 to BLOCK_SIZE-1;

  signal to_fifo_blocks       : block_set_arr_t;
  signal to_fifo_blocks_count : blocks_count_arr_t;
  signal to_fifo_valid        : std_logic;
  signal to_fifo_last         : std_logic;
  signal last_block_reg       : std_logic_vector(BLOCK_SIZE-2 downto 0);
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        valid_regs <= (others => '0');
        last_regs  <= (others => '0');
        word_regs  <= (others => (others => '0'));
      else
        valid_regs(0) <= in_valid;
        last_regs(0)  <= in_last;
        word_regs(0)  <= in_words;
        for i in 1 to valid_regs'high loop
          valid_regs(i) <= valid_regs(i-1);
          last_regs(i)  <= last_regs(i-1);
        end loop;
        for i in 1 to word_regs'high loop
          word_regs(i) <= word_regs(i-1);
        end loop;
      end if;
    end if;
  end process;

  from_delay_words <= word_regs(word_regs'high);

  g_combiners : for i in 0 to N_CHAINS-1 generate
    constant IN_DELAY_CYCLES  : integer := i;
    constant OUT_DELAY_CYCLES : integer := N_CHAINS - 1 - i;

    type shift_arr_t is array (0 to num_words(i)-1) of integer range 0 to BLOCK_SIZE-1;
    type extract_arr_t is array (0 to num_words(i)-1) of integer range 0 to MAX_BLOCKS_PER_WORD;
    type shifted_word_arr_t is array (0 to num_words(i)-1) of std_logic_vector(MAX_LENGTH+BLOCK_SIZE-2 downto 0);

    signal to_delay_shift   : shift_arr_t;
    signal to_delay_lengths : unsigned(num_words(i)*num2bits(MAX_LENGTH)-1 downto 0);

    signal to_calc_lengths          : unsigned(num_words(i)*num2bits(MAX_LENGTH)-1 downto 0);
    signal to_combine_shifted_words : shifted_word_arr_t;
    signal to_combine_extract_count : extract_arr_t;

    signal to_delay_shifted_words : shifted_word_arr_t;
    signal to_delay_extract_count : extract_arr_t;

    signal to_delay_blocks       : std_logic_vector(block_set_size(i)*BLOCK_SIZE-1 downto 0);
    signal to_delay_blocks_count : integer range 0 to block_set_size(i);
    signal to_delay_has_blocks   : std_logic;

    signal from_calc_shift           : shift_arr_t;
    signal from_calc_lengths         : unsigned(num_words(i)*num2bits(MAX_LENGTH)-1 downto 0);
    signal from_adjust_shift         : shift_arr_t;
    signal from_adjust_extract_count : extract_arr_t;
    signal extract_count_reg         : extract_arr_t;
  begin
    g_delay_inputs : if (IN_DELAY_CYCLES > 0) generate
      type delayed_length_arr_t is array (0 to IN_DELAY_CYCLES) of unsigned(num_words(i)*num2bits(MAX_LENGTH)-1 downto 0);
      type delayed_word_arr_t is array (0 to IN_DELAY_CYCLES) of std_logic_vector(num_words(i)*MAX_LENGTH-1 downto 0);
      type delayed_shifted_words_arr_t is array (0 to IN_DELAY_CYCLES-1) of shifted_word_arr_t;
      type delayed_extract_count_arr_t is array (0 to IN_DELAY_CYCLES-1) of extract_arr_t;
      signal delayed_lengths       : delayed_length_arr_t;
      signal delayed_words         : delayed_word_arr_t;
      signal delayed_shifted_words : delayed_shifted_words_arr_t;
      signal delayed_extract_count : delayed_extract_count_arr_t;
    begin
      process (clk)
      begin
        if (rising_edge(clk)) then
          delayed_lengths(0)       <= in_lengths((i*N_WORDS_PER_CHAIN + num_words(i))*num2bits(MAX_LENGTH)-1 downto i*N_WORDS_PER_CHAIN*num2bits(MAX_LENGTH));
          delayed_shifted_words(0) <= to_delay_shifted_words;
          delayed_extract_count(0) <= to_delay_extract_count;
          for j in 1 to IN_DELAY_CYCLES-1 loop
            delayed_lengths(j)       <= delayed_lengths(j-1);
            delayed_shifted_words(j) <= delayed_shifted_words(j-1);
            delayed_extract_count(j) <= delayed_extract_count(j-1);
          end loop;
        end if;
      end process;
      to_calc_lengths          <= delayed_lengths(IN_DELAY_CYCLES-1);
      to_combine_shifted_words <= delayed_shifted_words(IN_DELAY_CYCLES-1);
      to_combine_extract_count <= delayed_extract_count(IN_DELAY_CYCLES-1);
    end generate g_delay_inputs;

    g_no_input_delay : if (IN_DELAY_CYCLES = 0) generate
      to_calc_lengths          <= in_lengths((i*N_WORDS_PER_CHAIN + num_words(i))*num2bits(MAX_LENGTH)-1 downto i*N_WORDS_PER_CHAIN*num2bits(MAX_LENGTH));
      to_combine_shifted_words <= to_delay_shifted_words;
      to_combine_extract_count <= to_delay_extract_count;
    end generate g_no_input_delay;

    process (clk)
      constant SUM_SIZE           : integer := num2bits(BLOCK_SIZE + MAX_LENGTH);
      constant BLOCK_SIZE_BITS    : integer := len2bits(BLOCK_SIZE);
      variable sum                : unsigned(SUM_SIZE-1 downto 0);
      variable num_remaining_bits : unsigned(BLOCK_SIZE_BITS-1 downto 0);
    begin
      if (rising_edge(clk)) then
        if (i = 0) then
          num_remaining_bits := (others => '0');
        else
          num_remaining_bits := to_unsigned(from_calc_remaining_length(i-1), BLOCK_SIZE_BITS);
        end if;

        for j in 0 to num_words(i)-1 loop
          -- Compute bits left after this word is shifted in
          sum                := resize(num_remaining_bits, SUM_SIZE) + to_calc_lengths((j+1)*LENGTH_BITS-1 downto j*LENGTH_BITS);
          to_delay_shift(j)  <= to_integer(num_remaining_bits);
          num_remaining_bits := sum(BLOCK_SIZE_BITS-1 downto 0);
        end loop;
        to_delay_lengths              <= to_calc_lengths;
        from_calc_remaining_length(i) <= to_integer(num_remaining_bits);
      end if;
    end process;

    g_delay_outputs : if (OUT_DELAY_CYCLES > 0) generate
      type shift_delay_arr_t is array (0 to OUT_DELAY_CYCLES) of shift_arr_t;
      type extract_delay_arr_t is array (0 to OUT_DELAY_CYCLES) of extract_arr_t;
      type length_arr_t is array (0 to OUT_DELAY_CYCLES) of unsigned(num_words(i)*num2bits(MAX_LENGTH)-1 downto 0);
      type blocks_delay_arr_t is array (0 to OUT_DELAY_CYCLES-1) of std_logic_vector(block_set_size(i)*BLOCK_SIZE-1 downto 0);
      type blocks_count_delay_arr_t is array (0 to OUT_DELAY_CYCLES-1) of integer range 0 to block_set_size(i);

      signal delayed_shift        : shift_delay_arr_t;
      signal delayed_lengths      : length_arr_t;
      signal delayed_blocks       : blocks_delay_arr_t;
      signal delayed_blocks_count : blocks_count_delay_arr_t;
      signal delayed_has_blocks   : std_logic_vector(OUT_DELAY_CYCLES-1 downto 0);
    begin
      process (clk)
      begin
        if (rising_edge(clk)) then
          delayed_shift(0)        <= to_delay_shift;
          delayed_lengths(0)      <= to_delay_lengths;
          delayed_blocks(0)       <= to_delay_blocks;
          delayed_blocks_count(0) <= to_delay_blocks_count;
          delayed_has_blocks(0)   <= to_delay_has_blocks;
          for j in 1 to OUT_DELAY_CYCLES-1 loop
            delayed_shift(j)        <= delayed_shift(j-1);
            delayed_lengths(j)      <= delayed_lengths(j-1);
            delayed_blocks(j)       <= delayed_blocks(j-1);
            delayed_blocks_count(j) <= delayed_blocks_count(j-1);
            delayed_has_blocks(j)   <= delayed_has_blocks(j-1);
          end loop;
        end if;
      end process;
      from_calc_shift        <= delayed_shift(OUT_DELAY_CYCLES-1);
      from_calc_lengths      <= delayed_lengths(OUT_DELAY_CYCLES-1);
      from_combine_blocks(i) <= (BLOCK_SIZE*(MAX_BLOCKS_PER_CHAIN-block_set_size(i))-1 downto 0 => '0')
                                & delayed_blocks(OUT_DELAY_CYCLES-1);
      to_fifo_blocks_count(i)    <= delayed_blocks_count(OUT_DELAY_CYCLES-1);
      from_combine_has_blocks(i) <= delayed_has_blocks(OUT_DELAY_CYCLES-1);
    end generate g_delay_outputs;

    g_nodelay_out : if (OUT_DELAY_CYCLES = 0) generate
      from_calc_shift        <= to_delay_shift;
      from_calc_lengths      <= to_delay_lengths;
      from_combine_blocks(i) <= (BLOCK_SIZE*(MAX_BLOCKS_PER_CHAIN-block_set_size(i))-1 downto 0 => '0')
                                & to_delay_blocks;
      to_fifo_blocks_count(i)    <= to_delay_blocks_count;
      from_combine_has_blocks(i) <= to_delay_has_blocks;
    end generate g_nodelay_out;

    --------------------------------------------------------------------------------
    -- Combiner chain
    --------------------------------------------------------------------------------
    process (clk)
      variable sum            : integer range 0 to 2*BLOCK_SIZE-1;
      variable remaining_bits : std_logic_vector(BLOCK_SIZE - 2 downto 0);
      variable extended_word  : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
      variable temp           : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
      variable count          : integer range 0 to block_set_size(i);
      variable blocks         : std_logic_vector(BLOCK_SIZE*block_set_size(i)-1 downto 0);
      variable has_blocks     : std_logic;
    begin
      if (rising_edge(clk)) then
        --------------------------------------------------------------------------------
        -- Stage 1 - Perform adjustment of shifts and extract counts
        --------------------------------------------------------------------------------
        for j in 0 to num_words(i)-1 loop
          sum := from_calc_shift(j) + prev_remaining_length;
          if (sum >= BLOCK_SIZE) then
            sum := sum - BLOCK_SIZE;
          end if;
          from_adjust_shift(j)         <= sum;
          sum                          := sum + to_integer(from_calc_lengths((j+1)*LENGTH_BITS-1 downto j*LENGTH_BITS));
          from_adjust_extract_count(j) <= sum / BLOCK_SIZE;
        end loop;

        --------------------------------------------------------------------------------
        -- Stage 2 - Shift each incoming word
        --------------------------------------------------------------------------------
        to_delay_extract_count <= from_adjust_extract_count;
        for j in 0 to num_words(i)-1 loop
          extended_word             := from_delay_words((i*N_WORDS_PER_CHAIN + j + 1)*MAX_LENGTH-1 downto (i*N_WORDS_PER_CHAIN + j)*MAX_LENGTH) & (BLOCK_SIZE-2 downto 0 => '0');
          to_delay_shifted_words(j) <= std_logic_vector(shift_right(unsigned(extended_word), from_adjust_shift(j)));
        end loop;

        --------------------------------------------------------------------------------
        -- Stage 3 - Combine shifted words and extract blocks
        --------------------------------------------------------------------------------
        if (i = 0) then
          remaining_bits := (others => '0');
        else
          remaining_bits := from_combine_remaining(i-1);
        end if;

        count      := 0;
        blocks     := (others => '0');
        has_blocks := '0';
        for j in 0 to num_words(i)-1 loop
          temp := (remaining_bits & (MAX_LENGTH-1 downto 0 => '0')) or to_combine_shifted_words(j);

          for blk in 0 to MAX_BLOCKS_PER_WORD-1 loop
            if (to_combine_extract_count(j) > blk) then
              blocks(BLOCK_SIZE*(count+1)-1 downto BLOCK_SIZE*count) := temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);

              temp       := temp(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
              count      := count + 1;
              has_blocks := '1';
            end if;
          end loop;
          remaining_bits := temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH);
        end loop;

        to_delay_blocks           <= blocks;
        to_delay_blocks_count     <= count;
        to_delay_has_blocks       <= has_blocks;
        from_combine_remaining(i) <= remaining_bits;
      end if;
    end process;
  end generate g_combiners;

  to_fifo_valid <= valid_regs(valid_regs'high);
  to_fifo_last  <= last_regs(last_regs'high);

  --------------------------------------------------------------------------------
  -- Combine remaining bits and or into produced blocks
  --------------------------------------------------------------------------------
  process (from_combine_blocks, from_combine_remaining, prev_remaining, from_combine_has_blocks)
    variable lowest_idx : integer;
  begin
    lowest_idx := 0;
    for i in N_CHAINS-1 downto 0 loop
      if (from_combine_has_blocks(i) = '1') then
        lowest_idx := i;
      end if;
    end loop;

    to_fifo_blocks <= from_combine_blocks;
    if (or_slv(from_combine_has_blocks) = '1') then
      to_fifo_blocks(lowest_idx)(BLOCK_SIZE-1 downto 1) <= from_combine_blocks(lowest_idx)(BLOCK_SIZE-1 downto 1) or prev_remaining;
      prev_remaining_next                               <= from_combine_remaining(N_CHAINS-1);
    else
      prev_remaining_next <= from_combine_remaining(N_CHAINS-1) or prev_remaining;
    end if;
  end process;

  -- Store bits from previous reg
  process (clk)
    variable sum : integer range 0 to 2 * BLOCK_SIZE - 2;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        prev_remaining        <= (others => '0');
        prev_remaining_length <= 0;
      else
        if (valid_regs(N_CHAINS-1) = '1') then
          if (last_regs(N_CHAINS-1) = '1') then
            prev_remaining_length <= 0;
          else
            sum := prev_remaining_length + from_calc_remaining_length(N_CHAINS-1);
            if (sum >= BLOCK_SIZE) then
              prev_remaining_length <= sum - BLOCK_SIZE;
            else
              prev_remaining_length <= sum;
            end if;
          end if;
        end if;

        if (to_fifo_valid = '1') then
          if (to_fifo_last = '1') then
            prev_remaining <= (others => '0');
            last_block_reg <= prev_remaining_next;
          else
            prev_remaining <= prev_remaining_next;
          end if;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------------
  ---- Block output logic
  ----------------------------------------------------------------------------------
  b_output : block is
    constant COUNTER_SIZE : integer := num2bits(MAX_BLOCKS_PER_CHAIN);

    constant FIFO_MARGIN    : integer := 30;
    constant CTRL_FIFO_SIZE : integer := N_CHAINS + 1;
    constant FIFO_DEPTH     : integer := 256;

    signal fifo_rden           : std_logic;
    signal fifo_wren           : std_logic;
    signal ctrl_fifo_empty     : std_logic;
    signal ctrl_fifo_in        : std_logic_vector(CTRL_FIFO_SIZE-1 downto 0);
    signal ctrl_fifo_out       : std_logic_vector(CTRL_FIFO_SIZE-1 downto 0);
    signal ctrl_over_threshold : std_logic;

    signal block_fifo_over_threshold : std_logic_vector(N_CHAINS-1 downto 0);

    signal from_fifo_blocks       : block_set_arr_t;
    signal from_fifo_block_counts : blocks_count_arr_t;
    signal from_fifo_has_blocks   : std_logic_vector(N_CHAINS-1 downto 0);
    signal from_fifo_last         : std_logic;

    signal current_blocks     : block_set_arr_t;
    signal current_counts     : blocks_count_arr_t;
    signal current_has_blocks : std_logic_vector(N_CHAINS-1 downto 0);
    signal current_last       : std_logic;
    signal current_valid      : std_logic;

    signal counter           : integer range 0 to MAX_BLOCKS_PER_CHAIN;
    signal output_last_block : std_logic;

    signal current_block         : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal current_block_set     : std_logic_vector(MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE-1 downto 0);
    signal current_block_set_idx : integer range 0 to N_CHAINS-1;
    signal first_block_set_idx   : integer range 0 to N_CHAINS-1;
    signal next_block_set_idx    : integer range 0 to N_CHAINS-1;
    signal last_block_set        : std_logic;
    signal is_last_block         : std_logic;

    signal out_handshake : std_logic;
  begin
    process (from_combine_has_blocks, to_fifo_last, to_fifo_valid)
    begin
      ctrl_fifo_in(N_CHAINS-1 downto 0) <= from_combine_has_blocks;
      ctrl_fifo_in(N_CHAINS)            <= to_fifo_last;

      if (to_fifo_valid = '1' and (or_slv(from_combine_has_blocks) = '1' or to_fifo_last = '1')) then
        fifo_wren <= '1';
      else
        fifo_wren <= '0';
      end if;
    end process;

    over_threshold <= ctrl_over_threshold or or_slv(block_fifo_over_threshold);

    i_ctrl_fifo : entity work.xpm_fifo_wrapper
      generic map (
        DEPTH    => 2**integer(ceil(log2(real(N_CHAINS))))*FIFO_DEPTH,
        WIDTH    => CTRL_FIFO_SIZE,
        MARGIN   => FIFO_MARGIN,
        READMODE => "fwft")
      port map (
        clk     => clk,
        aresetn => aresetn,

        wren           => fifo_wren,
        wrdata         => ctrl_fifo_in,
        rden           => fifo_rden,
        rddata         => ctrl_fifo_out,
        empty          => ctrl_fifo_empty,
        over_threshold => ctrl_over_threshold);

    g_block_set_fifos : for i in 0 to N_CHAINS-1 generate
      constant BLOCK_FIFO_SIZE : integer := block_set_size(i)*BLOCK_SIZE + COUNTER_SIZE;
      signal block_fifo_in     : std_logic_vector(BLOCK_FIFO_SIZE-1 downto 0);
      signal block_fifo_out    : std_logic_vector(BLOCK_FIFO_SIZE-1 downto 0);
      signal rden, wren        : std_logic;
    begin
      i_fifo : entity work.xpm_fifo_wrapper
        generic map (
          DEPTH    => FIFO_DEPTH,
          WIDTH    => BLOCK_FIFO_SIZE,
          MARGIN   => FIFO_MARGIN,
          READMODE => "fwft")
        port map (
          clk     => clk,
          aresetn => aresetn,

          wren           => wren,
          wrdata         => block_fifo_in,
          rden           => rden,
          rddata         => block_fifo_out,
          empty          => open,
          over_threshold => block_fifo_over_threshold(i));

      wren <= fifo_wren and from_combine_has_blocks(i);
      rden <= fifo_rden and from_fifo_has_blocks(i);

      block_fifo_in <= to_fifo_blocks(i)(BLOCK_SIZE*block_set_size(i)-1 downto 0)
                       & std_logic_vector(to_unsigned(to_fifo_blocks_count(i), COUNTER_SIZE));
      from_fifo_blocks(i) <= (BLOCK_SIZE*(MAX_BLOCKS_PER_CHAIN-block_set_size(i))-1 downto 0 => '0')
                             & block_fifo_out(block_set_size(i)*BLOCK_SIZE + COUNTER_SIZE-1 downto COUNTER_SIZE);
      from_fifo_block_counts(i) <= to_integer(unsigned(block_fifo_out(COUNTER_SIZE-1 downto 0)));
    end generate g_block_set_fifos;

    fifo_rden <= '1' when ctrl_fifo_empty = '0' and (current_valid = '0' or
                                                (out_handshake = '1' and ((current_last = '0' and is_last_block = '1')
                                                                          or output_last_block = '1')))
                 else '0';

    from_fifo_has_blocks <= ctrl_fifo_out(N_CHAINS-1 downto 0);
    from_fifo_last       <= ctrl_fifo_out(N_CHAINS);

    process (from_fifo_has_blocks, current_has_blocks, current_block_set_idx)
    begin
      last_block_set      <= '1';
      next_block_set_idx  <= 0;
      first_block_set_idx <= 0;
      for i in N_CHAINS-1 downto 0 loop
        if (from_fifo_has_blocks(i) = '1') then
          first_block_set_idx <= i;
        end if;
      end loop;

      for i in N_CHAINS-1 downto 0 loop
        if (current_has_blocks(i) = '1' and i > current_block_set_idx) then
          next_block_set_idx <= i;
          last_block_set     <= '0';
        end if;
      end loop;
    end process;

    is_last_block <= '1' when counter = current_counts(current_block_set_idx) - 1 and last_block_set = '1' else '0';

    current_block <= current_block_set(BLOCK_SIZE-1 downto 0) when output_last_block = '0' else last_block_reg & '0';

    process (clk)
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          counter           <= 0;
          current_valid     <= '0';
          output_last_block <= '0';
        else
          if (fifo_rden = '1') then
            counter               <= 0;
            current_valid         <= '1';
            current_block_set_idx <= first_block_set_idx;
            current_block_set     <= from_fifo_blocks(first_block_set_idx);

            current_blocks     <= from_fifo_blocks;
            current_counts     <= from_fifo_block_counts;
            current_has_blocks <= from_fifo_has_blocks;
            current_last       <= from_fifo_last;
            if (from_fifo_last = '1' and or_slv(from_fifo_has_blocks) = '0') then
              output_last_block <= '1';
            else
              output_last_block <= '0';
            end if;
          elsif (out_handshake = '1') then
            if (output_last_block = '1') then
              current_valid <= '0';
            end if;

            if (current_counts(current_block_set_idx) = 0 or counter = current_counts(current_block_set_idx) - 1) then
              if (last_block_set = '1') then
                if (current_last = '1') then
                  if (output_last_block = '0') then
                    output_last_block <= '1';
                  end if;
                else
                  current_valid <= '0';
                end if;
              end if;
              counter               <= 0;
              current_block_set_idx <= next_block_set_idx;
              current_block_set     <= current_blocks(next_block_set_idx);
            else
              counter <= counter + 1;
              for j in 0 to MAX_BLOCKS_PER_CHAIN-2 loop
                current_block_set((j+1)*BLOCK_SIZE-1 downto j*BLOCK_SIZE) <= current_block_set((j+2)*BLOCK_SIZE-1 downto (j+1)*BLOCK_SIZE);
              end loop;
            end if;
          end if;
        end if;
      end if;
    end process;

    out_handshake <= current_valid and out_ready;
    out_valid     <= current_valid;

    process (current_last, current_block, is_last_block)
    begin
      -- Perform optional endianness swap
      if (LITTLE_ENDIAN) then
        for i in 0 to BLOCK_SIZE/8-1 loop
          out_data((i+1)*8-1 downto i*8) <= current_block((BLOCK_SIZE/8-i)*8-1 downto ((BLOCK_SIZE/8-i-1)*8));
        end loop;
      else
        out_data <= current_block;
      end if;

      if (current_last = '1' and output_last_block = '1') then
        out_last <= '1';
      else
        out_last <= '0';
      end if;
    end process;
  end block b_output;
end rtl;
