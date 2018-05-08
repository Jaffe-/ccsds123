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
    BLOCK_SIZE        : integer := 64;
    N_WORDS           : integer := 8;
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

  constant MAX_BLOCKS : integer := MAX_BLOCKS_PER_CHAIN * N_CHAINS;

  type full_blocks_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(BLOCK_SIZE*MAX_BLOCKS_PER_CHAIN-1 downto 0);
  type full_blocks_count_arr_t is array (0 to N_CHAINS-1) of integer range 0 to MAX_BLOCKS_PER_CHAIN;
  type remaining_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(BLOCK_SIZE-2 downto 0);
  type remaining_length_arr_t is array (0 to N_CHAINS-1) of unsigned(len2bits(BLOCK_SIZE)-1 downto 0);

  signal from_chain_full_blocks       : full_blocks_arr_t;
  signal from_chain_full_blocks_count : full_blocks_count_arr_t;
  signal from_chain_remaining         : remaining_arr_t;
  signal from_chain_remaining_length  : remaining_length_arr_t;
  signal from_chain_last              : std_logic_vector(N_CHAINS-1 downto 0);
  signal from_chain_valid             : std_logic_vector(N_CHAINS-1 downto 0);
begin
  --------------------------------------------------------------------------------
  -- Combiner chains
  --------------------------------------------------------------------------------

  g_chains : for i in 0 to N_CHAINS-1 generate
    function num_words return integer is
    begin
      if (N_WORDS mod N_WORDS_PER_CHAIN /= 0 and i = N_CHAINS-1) then
        return N_WORDS mod N_WORDS_PER_CHAIN;
      else
        return N_WORDS_PER_CHAIN;
      end if;
    end num_words;

    constant DELAY_CYCLES     : integer := i;
    constant OUT_DELAY_CYCLES : integer := N_CHAINS - 1 - i;

    signal to_chain_remaining        : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal to_chain_remaining_length : unsigned(len2bits(BLOCK_SIZE)-1 downto 0);
    signal to_chain_words            : std_logic_vector(num_words*MAX_LENGTH-1 downto 0);
    signal to_chain_lengths          : unsigned(num_words*num2bits(MAX_LENGTH)-1 downto 0);
    signal to_chain_last             : std_logic;
    signal to_chain_valid            : std_logic;

    signal to_delay_full_blocks       : std_logic_vector(MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE-1 downto 0);
    signal to_delay_full_blocks_count : integer range 0 to MAX_BLOCKS_PER_CHAIN;
  begin
    g_delay_inputs : if (DELAY_CYCLES > 0) generate
      type delayed_word_arr_t is array (0 to DELAY_CYCLES) of std_logic_vector(num_words*MAX_LENGTH-1 downto 0);
      type delayed_length_arr_t is array (0 to DELAY_CYCLES) of unsigned(num_words*num2bits(MAX_LENGTH)-1 downto 0);

      signal delayed_words   : delayed_word_arr_t;
      signal delayed_lengths : delayed_length_arr_t;
      signal delayed_last    : std_logic_vector(DELAY_CYCLES-1 downto 0);
      signal delayed_valid   : std_logic_vector(DELAY_CYCLES-1 downto 0);
    begin
      process (clk)
      begin
        if (rising_edge(clk)) then
          delayed_words(0)   <= in_words((i*N_WORDS_PER_CHAIN + num_words)*MAX_LENGTH-1 downto i*N_WORDS_PER_CHAIN*MAX_LENGTH);
          delayed_lengths(0) <= in_lengths((i*N_WORDS_PER_CHAIN + num_words)*num2bits(MAX_LENGTH)-1 downto i*N_WORDS_PER_CHAIN*num2bits(MAX_LENGTH));
          delayed_last(0)    <= in_last;
          delayed_valid(0)   <= in_valid;
          for j in 1 to DELAY_CYCLES-1 loop
            delayed_words(j)   <= delayed_words(j-1);
            delayed_lengths(j) <= delayed_lengths(j-1);
            delayed_last(j)    <= delayed_last(j-1);
            delayed_valid(j)   <= delayed_valid(j-1);
          end loop;
        end if;
      end process;
      to_chain_words   <= delayed_words(DELAY_CYCLES-1);
      to_chain_lengths <= delayed_lengths(DELAY_CYCLES-1);
      to_chain_last    <= delayed_last(DELAY_CYCLES-1);
      to_chain_valid   <= delayed_valid(DELAY_CYCLES-1);
    end generate g_delay_inputs;

    g_nodelay : if (DELAY_CYCLES = 0) generate
      to_chain_words   <= in_words(num_words*MAX_LENGTH-1 downto 0);
      to_chain_lengths <= in_lengths(num_words*num2bits(MAX_LENGTH)-1 downto 0);
      to_chain_last    <= in_last;
      to_chain_valid   <= in_valid;
    end generate g_nodelay;

    g_delay_outputs : if (OUT_DELAY_CYCLES > 0) generate
      type delayed_full_blocks_arr_t is array (0 to OUT_DELAY_CYCLES) of std_logic_vector(MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE-1 downto 0);
      type delayed_full_blocks_count_arr_t is array (0 to OUT_DELAY_CYCLES) of integer range 0 to MAX_BLOCKS_PER_CHAIN;

      signal delayed_full_blocks       : delayed_full_blocks_arr_t;
      signal delayed_full_blocks_count : delayed_full_blocks_count_arr_t;
    begin
      process (clk)
      begin
        if (rising_edge(clk)) then
          delayed_full_blocks(0)       <= to_delay_full_blocks;
          delayed_full_blocks_count(0) <= to_delay_full_blocks_count;
          for j in 1 to OUT_DELAY_CYCLES-1 loop
            delayed_full_blocks(j)       <= delayed_full_blocks(j-1);
            delayed_full_blocks_count(j) <= delayed_full_blocks_count(j-1);
          end loop;
        end if;
      end process;
      from_chain_full_blocks(i)       <= delayed_full_blocks(OUT_DELAY_CYCLES-1);
      from_chain_full_blocks_count(i) <= delayed_full_blocks_count(OUT_DELAY_CYCLES-1);
    end generate g_delay_outputs;

    g_nodelay_out : if (OUT_DELAY_CYCLES = 0) generate
      from_chain_full_blocks(i)       <= to_delay_full_blocks;
      from_chain_full_blocks_count(i) <= to_delay_full_blocks_count;
    end generate g_nodelay_out;

    process (from_chain_remaining, from_chain_remaining_length)
    begin
      if (i = 0) then
        to_chain_remaining        <= (others => '0');
        to_chain_remaining_length <= (others => '0');
      else
        to_chain_remaining        <= from_chain_remaining(i-1);
        to_chain_remaining_length <= from_chain_remaining_length(i-1);
      end if;
    end process;

    i_combiner_chain : entity work.combiner_chain
      generic map (
        BLOCK_SIZE    => BLOCK_SIZE,
        N_WORDS       => num_words,
        LAST_IN_CHAIN => i = N_CHAINS-1,
        MAX_LENGTH    => MAX_LENGTH,
        MAX_BLOCKS    => MAX_BLOCKS_PER_CHAIN)
      port map (
        clk     => clk,
        aresetn => aresetn,

        in_remaining        => to_chain_remaining,
        in_remaining_length => to_chain_remaining_length,
        in_words            => to_chain_words,
        in_lengths          => to_chain_lengths,
        in_valid            => to_chain_valid,
        in_last             => to_chain_last,

        out_remaining         => from_chain_remaining(i),
        out_remaining_length  => from_chain_remaining_length(i),
        out_full_blocks       => to_delay_full_blocks,
        out_full_blocks_count => to_delay_full_blocks_count,
        out_last              => from_chain_last(i),
        out_valid             => from_chain_valid(i));
  end generate g_chains;

  --------------------------------------------------------------------------------
  -- Block output
  --------------------------------------------------------------------------------
  b_output : block is
    constant COUNTER_SIZE : integer := num2bits(MAX_BLOCKS);

    -- The FIFO margin is the number of empty spaces in the FIFO when
    -- over_threshold is asserted. This must be large enough so that the FIFO can
    -- store the words coming out of the pipelines after the stream coming into
    -- the core has been stopped.
    constant FIFO_MARGIN : integer := 30;

    -- Element size in FIFO:
    --   * Data (blocks):  MAX_BLOCKS * BLOCK_SIZE
    --   * Counter:        COUNTER_SIZE bits
    --   * Remaining bits: BLOCK_SIZE - 1
    --   * Remaining len:  len2bits(BLOCK_SIZE)
    --   * Has blocks flag: 1
    --   * Last flag:       1
    constant BLOCK_FIFO_SIZE  : integer := MAX_BLOCKS * BLOCK_SIZE;
    constant BLOCK_FIFO_DEPTH : integer := 128;
    constant CTRL_FIFO_SIZE   : integer := N_CHAINS * COUNTER_SIZE + BLOCK_SIZE-1 + len2bits(BLOCK_SIZE) + 1 + 1;
    constant CTRL_FIFO_DEPTH  : integer := 128;

    signal block_fifo_rden           : std_logic;
    signal block_fifo_wren           : std_logic;
    signal block_fifo_empty          : std_logic;
    signal block_fifo_in             : std_logic_vector(BLOCK_FIFO_SIZE-1 downto 0);
    signal block_fifo_out            : std_logic_vector(BLOCK_FIFO_SIZE-1 downto 0);
    signal block_fifo_over_threshold : std_logic;

    signal ctrl_fifo_rden           : std_logic;
    signal ctrl_fifo_wren           : std_logic;
    signal ctrl_fifo_empty          : std_logic;
    signal ctrl_fifo_in             : std_logic_vector(CTRL_FIFO_SIZE-1 downto 0);
    signal ctrl_fifo_out            : std_logic_vector(CTRL_FIFO_SIZE-1 downto 0);
    signal ctrl_fifo_over_threshold : std_logic;

    signal from_fifo_last             : std_logic;
    signal from_fifo_count            : full_blocks_count_arr_t;
    signal from_fifo_remaining        : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal from_fifo_remaining_length : integer range 0 to BLOCK_SIZE-1;
    signal from_fifo_blocks           : full_blocks_arr_t;
    signal from_fifo_has_blocks       : std_logic;

    signal current_last             : std_logic;
    signal current_valid            : std_logic;
    signal current_counts           : full_blocks_count_arr_t;
    signal current_remaining        : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal current_remaining_length : integer range 0 to BLOCK_SIZE-1;

    type current_blocks_t is array (0 to N_CHAINS-1, 0 to MAX_BLOCKS_PER_CHAIN-1) of std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal current_blocks     : current_blocks_t;
    signal current_has_blocks : std_logic;
    signal output_ready       : std_logic;

    signal out_handshake   : std_logic;
    signal out_block       : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal out_block_valid : std_logic;

    signal counter : integer range 0 to MAX_BLOCKS_PER_CHAIN-1;

    signal is_last_block : std_logic;

    signal shifted_block : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal shifted_valid : std_logic;
    signal extra_block   : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal extra_valid   : std_logic;
    signal last_block    : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal last_valid    : std_logic;

    signal leftovers       : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal leftovers_next  : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal n_leftover      : integer range 0 to BLOCK_SIZE-2;
    signal n_leftover_next : integer range 0 to BLOCK_SIZE-2;

    signal out_sel_ready : std_logic;
    signal out_pending   : std_logic_vector(2 downto 0);

    signal current_block_set_idx : integer range 0 to N_CHAINS-1;
    signal first_block_set_idx   : integer range 0 to N_CHAINS-1;
    signal next_block_set_idx    : integer range 0 to N_CHAINS-1;
    signal current_block         : std_logic_vector(BLOCK_SIZE-1 downto 0);
    signal last_block_set        : std_logic;
  begin

    process (from_chain_full_blocks, from_chain_full_blocks_count, from_chain_remaining, from_chain_remaining_length,
             from_chain_last, from_chain_valid)
      variable idx        : integer;
      variable has_blocks : std_logic;
    begin
      ctrl_fifo_wren  <= '0';
      block_fifo_wren <= '0';

      has_blocks := '0';
      for i in 0 to N_CHAINS-1 loop
        if (from_chain_full_blocks_count(i) /= 0) then
          has_blocks := '1';
        end if;
      end loop;

      if (from_chain_valid(N_CHAINS-1) = '1') then
        ctrl_fifo_wren <= '1';
        if (has_blocks = '1') then
          block_fifo_wren <= '1';
        end if;
      end if;

      for i in from_chain_full_blocks'range loop
        block_fifo_in((i+1)*MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE-1 downto i*MAX_BLOCKS_PER_CHAIN*BLOCK_SIZE) <= from_chain_full_blocks(i);

        ctrl_fifo_in((i+1)*COUNTER_SIZE-1 downto i*COUNTER_SIZE) <= std_logic_vector(to_unsigned(from_chain_full_blocks_count(i), COUNTER_SIZE));
      end loop;
      idx := N_CHAINS*COUNTER_SIZE;

      ctrl_fifo_in(idx + BLOCK_SIZE-2 downto idx) <= from_chain_remaining(N_CHAINS-1);
      idx                                         := idx + BLOCK_SIZE - 1;

      ctrl_fifo_in(idx + len2bits(BLOCK_SIZE)-1 downto idx) <= std_logic_vector(from_chain_remaining_length(N_CHAINS-1));
      idx                                                   := idx + len2bits(BLOCK_SIZE);

      ctrl_fifo_in(idx)   <= has_blocks;
      ctrl_fifo_in(idx+1) <= from_chain_last(N_CHAINS-1);

    end process;

    full_blocks_fifo : entity work.xpm_fifo_wrapper
      generic map (
        DEPTH    => BLOCK_FIFO_DEPTH,
        WIDTH    => BLOCK_FIFO_SIZE,
        MARGIN   => FIFO_MARGIN,
        READMODE => "fwft")
      port map (
        clk     => clk,
        aresetn => aresetn,

        wren           => block_fifo_wren,
        wrdata         => block_fifo_in,
        rden           => block_fifo_rden,
        rddata         => block_fifo_out,
        empty          => block_fifo_empty,
        over_threshold => block_fifo_over_threshold);

    control_fifo : entity work.xpm_fifo_wrapper
      generic map (
        DEPTH    => CTRL_FIFO_DEPTH,
        WIDTH    => CTRL_FIFO_SIZE,
        MARGIN   => FIFO_MARGIN,
        READMODE => "fwft")
      port map (
        clk     => clk,
        aresetn => aresetn,

        wren           => ctrl_fifo_wren,
        wrdata         => ctrl_fifo_in,
        rden           => ctrl_fifo_rden,
        rddata         => ctrl_fifo_out,
        empty          => ctrl_fifo_empty,
        over_threshold => ctrl_fifo_over_threshold);

    ctrl_fifo_rden  <= not ctrl_fifo_empty and output_ready;
    block_fifo_rden <= output_ready and not ctrl_fifo_empty and not block_fifo_empty and from_fifo_has_blocks;
    over_threshold  <= block_fifo_over_threshold or ctrl_fifo_over_threshold;

    process (block_fifo_out, ctrl_fifo_out)
      variable idx : integer;
    begin
      for i in from_fifo_blocks'range loop
        from_fifo_blocks(i) <= block_fifo_out(MAX_BLOCKS_PER_CHAIN * (i + 1) * BLOCK_SIZE-1 downto MAX_BLOCKS_PER_CHAIN * i * BLOCK_SIZE);
        from_fifo_count(i)  <= to_integer(unsigned(ctrl_fifo_out((i+1)*COUNTER_SIZE - 1 downto i*COUNTER_SIZE)));
      end loop;
      idx := N_CHAINS*COUNTER_SIZE;

      from_fifo_remaining <= ctrl_fifo_out(idx + BLOCK_SIZE - 2 downto idx);
      idx                 := idx + BLOCK_SIZE - 1;

      from_fifo_remaining_length <= to_integer(unsigned(ctrl_fifo_out(idx + len2bits(BLOCK_SIZE) - 1 downto idx)));
      idx                        := idx + len2bits(BLOCK_SIZE);

      from_fifo_has_blocks <= ctrl_fifo_out(idx);
      from_fifo_last       <= ctrl_fifo_out(idx+1);
    end process;

    --------------------------------------------------------------------------------
    -- Output logic
    --------------------------------------------------------------------------------
    output_ready <= '1' when (current_valid = '0' or current_has_blocks = '0' or is_last_block = '1') and out_sel_ready = '1' else '0';

    process (current_counts, current_block_set_idx, from_fifo_count)
    begin
      last_block_set      <= '1';
      next_block_set_idx  <= 0;
      first_block_set_idx <= 0;
      for i in N_CHAINS-1 downto 0 loop
        if (from_fifo_count(i) /= 0) then
          first_block_set_idx <= i;
        end if;
      end loop;

      for i in 0 to N_CHAINS-1 loop
        if (current_counts(i) /= 0) then
          if (i > current_block_set_idx) then
            next_block_set_idx <= i;
            last_block_set     <= '0';
          end if;
        end if;
      end loop;
    end process;

    process (clk)
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          counter               <= 0;
          current_block_set_idx <= 0;
          current_valid         <= '0';
        else
          if (ctrl_fifo_rden = '1') then
            counter               <= 0;
            current_block_set_idx <= first_block_set_idx;

            for i in 0 to N_CHAINS-1 loop
              for j in 0 to MAX_BLOCKS_PER_CHAIN-1 loop
                current_blocks(i, j) <= from_fifo_blocks(i)((j+1)*BLOCK_SIZE-1 downto j*BLOCK_SIZE);
              end loop;
            end loop;
            current_counts           <= from_fifo_count;
            current_remaining        <= from_fifo_remaining;
            current_remaining_length <= from_fifo_remaining_length;
            current_last             <= from_fifo_last;
            current_has_blocks       <= from_fifo_has_blocks;
            current_valid            <= '1';
          elsif (current_valid = '1' and out_sel_ready = '1') then
            if (current_counts(current_block_set_idx) = 0 or counter = current_counts(current_block_set_idx) - 1) then
              if (last_block_set = '1') then
                current_valid <= '0';
              end if;
              counter               <= 0;
              current_block_set_idx <= next_block_set_idx;
            else
              counter <= counter + 1;
            end if;
          end if;
        end if;
      end if;
    end process;

    is_last_block <= '1' when counter = current_counts(current_block_set_idx) - 1 and last_block_set = '1' else '0';
    current_block <= current_blocks(current_block_set_idx, counter);

    process (current_valid, current_block, current_remaining, current_remaining_length, current_has_blocks, is_last_block,
             leftovers, n_leftover, current_last)
      variable leftovers_temp  : std_logic_vector(BLOCK_SIZE-2 downto 0);
      variable n_leftover_temp : integer range 0 to BLOCK_SIZE-2;
      variable extended_block  : std_logic_vector(2*BLOCK_SIZE-2 downto 0);
      variable combined_block  : std_logic_vector(2*BLOCK_SIZE-2 downto 0);
      variable n_sum           : integer range 0 to 2*(BLOCK_SIZE-1);
    begin
      shifted_block <= (others => '0');
      shifted_valid <= '0';
      extra_block   <= (others => '0');
      extra_valid   <= '0';
      last_block    <= (others => '0');
      last_valid    <= '0';

      leftovers_temp  := leftovers;
      n_leftover_temp := n_leftover;

      if (current_valid = '1') then
        -- If we have a valid block, shift it
        if (current_has_blocks = '1') then
          extended_block := current_block & (BLOCK_SIZE-2 downto 0   => '0');
          combined_block := (leftovers_temp & (BLOCK_SIZE-1 downto 0 => '0'))
                            or std_logic_vector(shift_right(unsigned(extended_block), n_leftover_temp));
          leftovers_temp := combined_block(BLOCK_SIZE-2 downto 0);
          shifted_block  <= combined_block(2*BLOCK_SIZE-2 downto BLOCK_SIZE-1);
          shifted_valid  <= '1';
        end if;

        -- If we have no block, or if this was the last block, then we must
        -- add the incoming remaining bits to the current remaining bits and
        -- extract a block if the combined remaining bits are bigger than the
        -- block size
        if (current_has_blocks = '0' or is_last_block = '1') then
          extended_block := current_remaining & (BLOCK_SIZE-1 downto 0 => '0');
          combined_block := (leftovers_temp & (BLOCK_SIZE-1 downto 0   => '0'))
                            or std_logic_vector(shift_right(unsigned(extended_block), n_leftover_temp));
          n_sum := n_leftover + current_remaining_length;
          if (n_sum >= BLOCK_SIZE) then
            leftovers_temp  := combined_block(BLOCK_SIZE-2 downto 0);
            n_leftover_temp := n_sum - BLOCK_SIZE;
            extra_block     <= combined_block(2*BLOCK_SIZE-2 downto BLOCK_SIZE-1);
            extra_valid     <= '1';
          else
            leftovers_temp  := combined_block(2*BLOCK_SIZE-2 downto BLOCK_SIZE);
            n_leftover_temp := n_sum;
          end if;

          -- If last is asserted, output whatever is left and remove leftovers
          if (current_last = '1' and n_leftover_temp /= 0) then
            last_block      <= leftovers_temp & '0';
            last_valid      <= '1';
            leftovers_temp  := (others => '0');
            n_leftover_temp := 0;
          end if;
        end if;
      end if;

      leftovers_next  <= leftovers_temp;
      n_leftover_next <= n_leftover_temp;
    end process;

    process (clk)
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          leftovers  <= (others => '0');
          n_leftover <= 0;
        else
          if (out_sel_ready = '1' and current_valid = '1') then
            leftovers  <= leftovers_next;
            n_leftover <= n_leftover_next;
          end if;
        end if;
      end if;
    end process;

    out_handshake <= out_block_valid and out_ready;
    out_valid     <= out_block_valid;

    out_sel_ready <= '1' when out_pending = "000" or
                     (out_handshake = '1' and (out_pending = "001" or out_pending = "010" or out_pending = "100")) else '0';

    process (clk)
      variable pending : std_logic_vector(2 downto 0);

      type pending_data_t is array (0 to 2) of std_logic_vector(BLOCK_SIZE-1 downto 0);
      variable pending_data : pending_data_t;

      variable pending_idx : integer range 0 to 2;
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          pending_data    := (others => (others => '0'));
          out_block       <= (others => '0');
          out_pending     <= (others => '0');
          out_block_valid <= '0';
        else
          pending := out_pending;

          if (out_sel_ready = '1') then
            pending         := last_valid & extra_valid & shifted_valid;
            pending_data(0) := shifted_block;
            pending_data(1) := extra_block;
            pending_data(2) := last_block;
          elsif (out_handshake = '1') then
            pending(pending_idx) := '0';
          end if;

          out_last <= '0';

          case pending is
            when "010" | "110" => pending_idx := 1;
            when "100" =>
              pending_idx := 2;
              out_last    <= '1';
            when others => pending_idx := 0;
          end case;

          out_block <= pending_data(pending_idx);

          out_pending     <= pending;
          out_block_valid <= '0';
          if (pending /= "000") then
            out_block_valid <= '1';
          end if;

        end if;
      end if;
    end process;

    --------------------------------------------------------------------------------
    -- Endianness conversion etc.
    --------------------------------------------------------------------------------
    process (out_block)
    begin
      -- Perform optional endianness swap
      if (LITTLE_ENDIAN) then
        for i in 0 to BLOCK_SIZE/8-1 loop
          out_data((i+1)*8-1 downto i*8) <= out_block((BLOCK_SIZE/8-i)*8-1 downto ((BLOCK_SIZE/8-i-1)*8));
        end loop;
      else
        out_data <= out_block;
      end if;
    end process;
  end block b_output;
end rtl;
