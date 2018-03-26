library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

library xpm;
use xpm.vcomponents.all;

entity combiner is
  generic (
    BLOCK_SIZE : integer := 64;
    N_WORDS    : integer := 4;
    MAX_LENGTH : integer := 48
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_words   : in std_logic_vector(N_WORDS * MAX_LENGTH - 1 downto 0);
    in_lengths : in unsigned(N_WORDS * integer(ceil(log2(real(MAX_LENGTH)))) - 1 downto 0);
    in_valid   : in std_logic;
    in_last    : in std_logic;

    out_data  : out std_logic_vector(BLOCK_SIZE - 1 downto 0);
    out_valid : out std_logic;
    out_last  : out std_logic
    );
end combiner;

architecture rtl of combiner is
  constant LENGTH_BITS         : integer := integer(ceil(log2(real(MAX_LENGTH))));
  constant BLOCK_SIZE_BITS     : integer := integer(ceil(log2(real(BLOCK_SIZE))));
  constant MAX_BLOCKS_PER_WORD : integer := (BLOCK_SIZE + MAX_LENGTH) / BLOCK_SIZE;
  constant MAX_BLOCKS          : integer := (BLOCK_SIZE + N_WORDS * MAX_LENGTH) / BLOCK_SIZE + 1;

  type word_arr_t is array (0 to N_WORDS-1) of std_logic_vector(MAX_LENGTH - 1 downto 0);
  type words_arr_t is array (0 to 1) of word_arr_t;
  type length_arr_t is array (0 to N_WORDS-1) of integer range 0 to MAX_LENGTH;

  signal from_fifo_words   : word_arr_t;
  signal from_fifo_lengths : length_arr_t;
  signal words             : words_arr_t;
  signal lengths           : length_arr_t;

  signal first_fifo      : integer range 0 to N_WORDS-1;
  signal to_fifo_rden    : std_logic_vector(N_WORDS-1 downto 0);
  signal from_fifo_empty : std_logic_vector(N_WORDS-1 downto 0);
  signal fifo_empty      : std_logic_vector(N_WORDS-1 downto 0);
  signal fifo_read       : std_logic_vector(N_WORDS-1 downto 0);

  type sums_arr_t is array (0 to N_WORDS-1) of integer range 0 to N_WORDS*MAX_LENGTH;
  signal sums : sums_arr_t;

  signal blk_idx   : integer range 0 to N_WORDS-1;
  signal block_out : std_logic;

  type shift_arr_t is array (0 to N_WORDS-1) of integer range 0 to BLOCK_SIZE-1;
  signal shift_arr : shift_arr_t;
begin

  g_fifos : for i in 0 to N_WORDS-1 generate
    function one_when_zero(val : integer) return integer is
    begin
      if (val = 0) then return 1;
      else return 0; end if;
    end one_when_zero;

    constant FIFO_SIZE : integer := MAX_LENGTH + LENGTH_BITS + one_when_zero(i);

    signal fifo_in  : std_logic_vector(FIFO_SIZE-1 downto 0);
    signal fifo_out : std_logic_vector(FIFO_SIZE-1 downto 0);
  begin
    fifo_in(LENGTH_BITS-1 downto 0)                      <= std_logic_vector(in_lengths((i+1)*LENGTH_BITS-1 downto i*LENGTH_BITS));
    fifo_in(MAX_LENGTH+LENGTH_BITS-1 downto LENGTH_BITS) <= in_words((i+1)*MAX_LENGTH-1 downto i*MAX_LENGTH);

    g_first : if (i = 0) generate
      fifo_in(fifo_in'high) <= in_last;
    end generate g_first;

    i_fifo : xpm_fifo_sync
      generic map (

        FIFO_MEMORY_TYPE    => "auto",  --string; "auto", "block", "distributed", or "ultra" ;
        ECC_MODE            => "no_ecc",   --string; "no_ecc" or "en_ecc";
        FIFO_WRITE_DEPTH    => 256,     --positive integer
        WRITE_DATA_WIDTH    => FIFO_SIZE,  --positive integer
        WR_DATA_COUNT_WIDTH => 9,       --positive integer
        PROG_FULL_THRESH    => 10,      --positive integer
        FULL_RESET_VALUE    => 0,       --positive integer; 0 or 1;
        READ_MODE           => "std",  --string; "std" or "fwft";
        FIFO_READ_LATENCY   => 1,       --positive integer;
        READ_DATA_WIDTH     => FIFO_SIZE,  --positive integer
        RD_DATA_COUNT_WIDTH => 9,       --positive integer
        PROG_EMPTY_THRESH   => 10,      --positive integer
        DOUT_RESET_VALUE    => "0",     --string
        WAKEUP_TIME         => 0        --positive integer; 0 or 2;
        )
      port map (
        rst           => not aresetn,
        wr_clk        => clk,
        wr_en         => in_valid,
        din           => fifo_in,
        full          => open,
        overflow      => open,
        wr_rst_busy   => open,
        rd_en         => to_fifo_rden(i),
        dout          => fifo_out,
        empty         => from_fifo_empty(i),
        underflow     => open,
        rd_rst_busy   => open,
        prog_full     => open,
        wr_data_count => open,
        prog_empty    => open,
        rd_data_count => open,
        sleep         => '0',
        injectsbiterr => '0',
        injectdbiterr => '0',
        sbiterr       => open,
        dbiterr       => open
        );

    from_fifo_words(i)   <= fifo_out(MAX_LENGTH+LENGTH_BITS-1 downto LENGTH_BITS);
    from_fifo_lengths(i) <= to_integer(unsigned(fifo_out(LENGTH_BITS-1 downto 0)));
  end generate g_fifos;

  process (from_fifo_words, first_fifo, from_fifo_empty, from_fifo_lengths, fifo_read)
    type mux_data_t is record
      data   : word_arr_t;
      length : length_arr_t;
      rd     : std_logic_vector(N_WORDS-1 downto 0);
      empty  : std_logic_vector(N_WORDS-1 downto 0);
    end record;

    type mux_arr_t is array (0 to N_WORDS-1) of mux_data_t;
    variable mux_arr : mux_arr_t;
  begin
    for i in 0 to N_WORDS-1 loop
      for j in 0 to N_WORDS-1 loop
          mux_arr(i).data(j)   := from_fifo_words((i+j) mod N_WORDS);
          mux_arr(i).length(j) := from_fifo_lengths((i+j) mod N_WORDS);
          mux_arr(i).rd(j)     := fifo_read((i+j) mod N_WORDS);
          mux_arr(i).empty(j)  := from_fifo_empty((i+j) mod N_WORDS);
      end loop;
    end loop;
    words(0)     <= mux_arr(first_fifo).data;
    lengths      <= mux_arr(first_fifo).length;
    fifo_empty   <= mux_arr(first_fifo).empty;
    to_fifo_rden <= mux_arr(first_fifo).rd;
  end process;

  process (clk)
    constant SUM_SIZE           : integer := integer(ceil(log2(real(BLOCK_SIZE + MAX_LENGTH))));
    variable sum                : unsigned(SUM_SIZE-1 downto 0);
    variable num_remaining_bits : unsigned(BLOCK_SIZE_BITS-1 downto 0);
    variable remaining_bits     : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable temp               : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable padded_word        : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        first_fifo         <= 0;
        num_remaining_bits := (others => '0');
        remaining_bits     := (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - Compute shift amounts and block pos
        --------------------------------------------------------------------------------
        fifo_read <= (others => '0');
        words(1)  <= words(0);
        block_out <= '0';
        for i in 0 to N_WORDS-1 loop
          -- Compute bits left after this word is shifted in
          sum                := resize(num_remaining_bits, SUM_SIZE) + to_unsigned(lengths(i), LENGTH_BITS);
          shift_arr(i)       <= to_integer(num_remaining_bits);
          fifo_read(i)       <= '1';
          num_remaining_bits := sum(BLOCK_SIZE_BITS-1 downto 0);
          if (to_integer(sum(sum'high downto BLOCK_SIZE_BITS)) /= 0) then
            blk_idx    <= i;
            block_out  <= '1';
            first_fifo <= (first_fifo + i + 1) mod N_WORDS;
            exit;
          end if;
        end loop;

        out_valid <= '0';
        for i in 0 to N_WORDS-1 loop
          if ((block_out = '1' and blk_idx = i)
              or (block_out = '0' and i = N_WORDS-1)) then
            for j in 0 to i loop
              padded_word := words(1)(j) & (BLOCK_SIZE - 2 downto 0 => '0');
              temp        := remaining_bits or std_logic_vector(shift_right(unsigned(padded_word), shift_arr(j)));
              if (block_out = '1' and j = i) then
                out_data  <= temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);
                out_valid <= '1';
                temp      := temp(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
              end if;
              remaining_bits := temp;
            end loop;
          end if;
        end loop;
      end if;
    end if;
  end process;

end rtl;
