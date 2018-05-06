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
    N_WORDS           : integer := 4;
    N_WORDS_PER_CHAIN : integer := 2;
    MAX_LENGTH        : integer := 48;
    LITTLE_ENDIAN     : boolean := true
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
  constant MAX_BLOCKS : integer := (BLOCK_SIZE - 1 + N_WORDS * MAX_LENGTH) / BLOCK_SIZE + 1;

  constant N_CHAINS : integer := integer(ceil(real(N_WORDS)/real(N_WORDS_PER_CHAIN)));
  type full_blocks_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(BLOCK_SIZE*MAX_BLOCKS-1 downto 0);
  type full_blocks_count_arr_t is array (0 to N_CHAINS-1) of integer range 0 to MAX_BLOCKS;
  type remaining_arr_t is array (0 to N_CHAINS-1) of std_logic_vector(BLOCK_SIZE-2 downto 0);
  type remaining_length_arr_t is array (0 to N_CHAINS-1) of unsigned(len2bits(BLOCK_SIZE)-1 downto 0);

  constant MAX_BLOCKS_PER_CHAIN : integer := (BLOCK_SIZE - 1 + N_WORDS_PER_CHAIN * MAX_LENGTH) / BLOCK_SIZE;

  signal from_chain_full_blocks       : full_blocks_arr_t;
  signal from_chain_full_blocks_count : full_blocks_count_arr_t;
  signal from_chain_remaining         : remaining_arr_t;
  signal from_chain_remaining_length  : remaining_length_arr_t;
  signal from_chain_last              : std_logic_vector(N_CHAINS-1 downto 0);
  signal from_chain_valid             : std_logic_vector(N_CHAINS-1 downto 0);

  constant COUNTER_SIZE : integer := num2bits(MAX_BLOCKS);

  constant FIFO_DEPTH : integer := 128;

  -- The FIFO margin is the number of empty spaces in the FIFO when
  -- over_threshold is asserted. This must be large enough so that the FIFO can
  -- store the words coming out of the pipelines after the stream coming into
  -- the core has been stopped.
  constant FIFO_MARGIN : integer := 30;

  -- Element size in FIFO:
  --   * Data (blocks): MAX_BLOCKS * BLOCK_SIZE bits
  --   * Counter:       COUNTER_SIZE bits
  --   * Last flag:     1 bit
  constant FIFO_SIZE : integer := MAX_BLOCKS * BLOCK_SIZE + COUNTER_SIZE + 1;

  type full_blocks_t is array (0 to MAX_BLOCKS-1) of std_logic_vector(BLOCK_SIZE-1 downto 0);

  signal fifo_rst         : std_logic;
  signal fifo_rden        : std_logic;
  signal fifo_wren        : std_logic;
  signal fifo_empty       : std_logic;
  signal fifo_in          : std_logic_vector(FIFO_SIZE-1 downto 0);
  signal fifo_out         : std_logic_vector(FIFO_SIZE-1 downto 0);
  signal to_fifo_count    : integer range 0 to MAX_BLOCKS;
  signal to_fifo_last     : std_logic;
  signal from_fifo_last   : std_logic;
  signal from_fifo_valid  : std_logic;
  signal from_fifo_count  : integer range 0 to MAX_BLOCKS;
  signal from_fifo_blocks : full_blocks_t;

  signal out_handshake : std_logic;

  signal counter : integer range 0 to MAX_BLOCKS-1;
begin
  --------------------------------------------------------------------------------
  -- Combiner chains
  --------------------------------------------------------------------------------

  g_chains : for i in 0 to N_CHAINS-1 generate
    constant LAST_IN_CHAIN : boolean := i = N_CHAINS-1;

    function num_words return integer is
    begin
      if (N_WORDS mod N_WORDS_PER_CHAIN /= 0 and LAST_IN_CHAIN) then
        return N_WORDS mod N_WORDS_PER_CHAIN;
      else
        return N_WORDS_PER_CHAIN;
      end if;
    end num_words;

    function num_blocks(n : integer) return integer is
    begin
      if (n = N_WORDS) then
        return MAX_BLOCKS;
      else
        return (BLOCK_SIZE - 1 + n * MAX_LENGTH) / BLOCK_SIZE;
      end if;
    end num_blocks;

    constant MAX_BLOCKS_PREV_CHAINS : integer := num_blocks(i*N_WORDS_PER_CHAIN);
    constant MAX_BLOCKS_FROM_CHAIN  : integer := num_blocks(i*N_WORDS_PER_CHAIN + num_words) - MAX_BLOCKS_PREV_CHAINS;

    constant DELAY_CYCLES : integer := i;

    signal to_chain_full_blocks       : std_logic_vector(BLOCK_SIZE*MAX_BLOCKS-1 downto 0);
    signal to_chain_full_blocks_count : integer range 0 to MAX_BLOCKS;
    signal to_chain_remaining         : std_logic_vector(BLOCK_SIZE-2 downto 0);
    signal to_chain_remaining_length  : unsigned(len2bits(BLOCK_SIZE)-1 downto 0);
    signal to_chain_words             : std_logic_vector(num_words*MAX_LENGTH-1 downto 0);
    signal to_chain_lengths           : unsigned(num_words*num2bits(MAX_LENGTH)-1 downto 0);
    signal to_chain_last              : std_logic;
    signal to_chain_valid             : std_logic;
  begin
    g_delay_inputs : if (i > 0) generate
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

    g_nodelay : if (i = 0) generate
      to_chain_words   <= in_words(num_words*MAX_LENGTH-1 downto 0);
      to_chain_lengths <= in_lengths(num_words*num2bits(MAX_LENGTH)-1 downto 0);
      to_chain_last    <= in_last;
      to_chain_valid   <= in_valid;
    end generate g_nodelay;

    process (from_chain_full_blocks, from_chain_full_blocks_count, from_chain_remaining, from_chain_remaining_length,
             from_chain_last, from_chain_valid, in_last, in_valid)
      variable leftover_length : integer range 0 to 2*(BLOCK_SIZE-1);
      variable fb_count        : integer range 0 to MAX_BLOCKS;
    begin
      if (i = 0) then
        to_chain_full_blocks       <= (others => '0');
        to_chain_full_blocks_count <= 0;

        -- Special case when only one combiner chain is used, then we take
        -- leftovers from the same combiner chain
        if (i = N_CHAINS-1) then
          to_chain_remaining        <= from_chain_remaining(0);
          to_chain_remaining_length <= from_chain_remaining_length(0);
        else
          to_chain_remaining        <= (others => '0');
          to_chain_remaining_length <= (others => '0');
        end if;
      else
        to_chain_full_blocks       <= from_chain_full_blocks(i-1);
        to_chain_full_blocks_count <= from_chain_full_blocks_count(i-1);
        to_chain_remaining         <= from_chain_remaining(i-1);
        to_chain_remaining_length  <= from_chain_remaining_length(i-1);

        if (i = N_CHAINS-1) then
          to_chain_full_blocks <= (from_chain_remaining(i) & ((MAX_BLOCKS-1)*BLOCK_SIZE downto 0 => '0'))
                                  or std_logic_vector(shift_right(unsigned(from_chain_full_blocks(i-1)),
                                                                  to_integer(from_chain_remaining_length_delayed(i))));

          leftover_length := to_integer(from_chain_remaining_length_delayed(i) + from_chain_remaining_length_delayed(i-1));
          if (leftover_length >= BLOCK_SIZE) then
            fb_count                   := from_chain_full_blocks_count(i-1) + 1;
            to_chain_full_blocks_count <= fb_count;
            to_chain_remaining_length  <= to_unsigned(leftover_length - BLOCK_SIZE, len2bits(BLOCK_SIZE));
            to_chain_remaining         <= from_chain_full_blocks(i-1)(fb_count*BLOCK_SIZE+BLOCK_SIZE-2 downto fb_count*BLOCK_SIZE);
          end if;
        end if;
      end if;
    end process;

    i_combiner_chain : entity work.combiner_chain
      generic map (
        BLOCK_SIZE    => BLOCK_SIZE,
        N_WORDS       => num_words,
        LAST_IN_CHAIN => LAST_IN_CHAIN,
        MAX_LENGTH    => MAX_LENGTH,
        IN_MAX_BLOCKS => MAX_BLOCKS_PREV_CHAINS,
        MAX_BLOCKS    => MAX_BLOCKS_FROM_CHAIN)
      port map (
        clk     => clk,
        aresetn => aresetn,

        in_remaining         => to_chain_remaining,
        in_remaining_length  => to_chain_remaining_length,
        in_words             => to_chain_words,
        in_lengths           => to_chain_lengths,
        in_valid             => to_chain_valid,
        in_last              => to_chain_last,
        in_full_blocks       => to_chain_full_blocks(MAX_BLOCKS_PREV_CHAINS*BLOCK_SIZE-1 downto 0),
        in_full_blocks_count => to_chain_full_blocks_count,

        out_remaining         => from_chain_remaining(i),
        out_remaining_length  => from_chain_remaining_length(i),
        out_full_blocks       => from_chain_full_blocks(i)((MAX_BLOCKS_PREV_CHAINS + MAX_BLOCKS_FROM_CHAIN)*BLOCK_SIZE-1 downto 0),
        out_full_blocks_count => from_chain_full_blocks_count(i),
        out_last              => from_chain_last(i),
        out_valid             => from_chain_valid(i));
  end generate g_chains;

  --------------------------------------------------------------------------------
  -- Block output
  --------------------------------------------------------------------------------
  process (from_chain_full_blocks, from_chain_full_blocks_count, from_chain_last, from_chain_valid)
  begin
    if (from_chain_valid(N_CHAINS-1) = '1' and from_chain_full_blocks_count(N_CHAINS-1) /= 0) then
      fifo_wren <= '1';
    else
      fifo_wren <= '0';
    end if;

    fifo_in(MAX_BLOCKS*BLOCK_SIZE-1 downto 0) <= from_chain_full_blocks(N_CHAINS-1);
    fifo_in(MAX_BLOCKS*BLOCK_SIZE+COUNTER_SIZE-1 downto MAX_BLOCKS*BLOCK_SIZE)
      <= std_logic_vector(to_unsigned(from_chain_full_blocks_count(N_CHAINS-1), COUNTER_SIZE));
    fifo_in(fifo_in'high) <= from_chain_last(N_CHAINS-1);
  end process;

  fifo_rst <= not aresetn;

  i_fifo : xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE    => "auto",
      ECC_MODE            => "no_ecc",
      FIFO_WRITE_DEPTH    => FIFO_DEPTH,
      WRITE_DATA_WIDTH    => FIFO_SIZE,
      WR_DATA_COUNT_WIDTH => num2bits(FIFO_DEPTH),
      PROG_FULL_THRESH    => FIFO_DEPTH - FIFO_MARGIN,
      FULL_RESET_VALUE    => 0,
      read_mode           => "std",
      FIFO_READ_LATENCY   => 1,
      READ_DATA_WIDTH     => FIFO_SIZE,
      RD_DATA_COUNT_WIDTH => num2bits(FIFO_DEPTH),
      PROG_EMPTY_THRESH   => 10,
      DOUT_RESET_VALUE    => "0",
      WAKEUP_TIME         => 0
      )
    port map (
      rst           => fifo_rst,
      wr_clk        => clk,
      wr_en         => fifo_wren,
      din           => fifo_in,
      full          => open,
      overflow      => open,
      wr_rst_busy   => open,
      rd_en         => fifo_rden,
      dout          => fifo_out,
      empty         => fifo_empty,
      underflow     => open,
      rd_rst_busy   => open,
      prog_full     => over_threshold,
      wr_data_count => open,
      prog_empty    => open,
      rd_data_count => open,
      sleep         => '0',
      injectsbiterr => '0',
      injectdbiterr => '0',
      sbiterr       => open,
      dbiterr       => open
      );

  fifo_rden <= '1' when fifo_empty = '0' and (from_fifo_valid = '0' or
                                              (out_handshake = '1' and counter = from_fifo_count - 1))
               else '0';
  from_fifo_count <= to_integer(unsigned(fifo_out(fifo_out'high - 1 downto fifo_out'high - COUNTER_SIZE)));
  from_fifo_last  <= fifo_out(fifo_out'high);
  process (fifo_out)
  begin
    for i in from_fifo_blocks'range loop
      from_fifo_blocks(i) <= fifo_out((i+1)*BLOCK_SIZE-1 downto i*BLOCK_SIZE);
    end loop;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        counter         <= 0;
        from_fifo_valid <= '0';
      else
        if (fifo_rden = '1') then
          from_fifo_valid <= '1';
          counter         <= 0;
        elsif (out_handshake = '1' and counter = from_fifo_count - 1) then
          from_fifo_valid <= '0';
        elsif (out_handshake = '1') then
          counter <= counter + 1;
        end if;
      end if;
    end if;
  end process;

  out_handshake <= from_fifo_valid and out_ready;
  out_valid     <= from_fifo_valid;

  process (counter, from_fifo_last, from_fifo_count, from_fifo_blocks)
  begin
    -- Perform optional endianness swap
    if (LITTLE_ENDIAN) then
      for i in 0 to BLOCK_SIZE/8-1 loop
        out_data((i+1)*8-1 downto i*8) <= from_fifo_blocks(counter)((BLOCK_SIZE/8-i)*8-1 downto ((BLOCK_SIZE/8-i-1)*8));
      end loop;
    else
      out_data <= from_fifo_blocks(counter);
    end if;

    if (from_fifo_last = '1' and counter = from_fifo_count - 1) then
      out_last <= '1';
    else
      out_last <= '0';
    end if;
  end process;
end rtl;
