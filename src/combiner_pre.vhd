--------------------------------------------------------------------------------
-- Variable length word combiner
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

entity combiner is
  generic (
    BLOCK_SIZE : integer := 32;
    N_WORDS    : integer := 4;
    MAX_LENGTH : integer := 48
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_words   : in std_logic_vector(N_WORDS * MAX_LENGTH - 1 downto 0);
    in_lengths : in unsigned(N_WORDS * integer(ceil(log2(real(MAX_LENGTH)))) - 1 downto 0);
    in_valid   : in std_logic;

    out_words  : out std_logic_vector(N_WORDS * BLOCK_SIZE - 1 downto 0);
    out_valids : out std_logic_vector(N_WORDS - 1 downto 0)
    );
end combiner;

architecture rtl of combiner is
  constant LENGTH_BITS         : integer := integer(ceil(log2(real(MAX_LENGTH))));
  constant BLOCK_SIZE_BITS     : integer := integer(ceil(log2(real(BLOCK_SIZE))));
  constant MAX_BLOCKS_PER_WORD : integer := (BLOCK_SIZE + MAX_LENGTH) / BLOCK_SIZE;

  type word_arr_t is array (0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH - 2 downto 0);
  type in_lengths_arr_t is array (0 to N_WORDS-1) of integer range 0 to MAX_LENGTH;
  type full_blocks_arr_t is array (0 to MAX_BLOCKS_PER_WORD * N_WORDS - 1) of std_logic_vector(BLOCK_SIZE-1 downto 0);

  type shift_arr_t is array (0 to N_WORDS-1) of integer range 0 to BLOCK_SIZE-1;
  type n_blocks_arr_t is array (0 to N_WORDS-1) of integer range 0 to MAX_BLOCKS_PER_WORD;
  signal shift_arr     : shift_arr_t;
  signal n_blocks_arr  : n_blocks_arr_t;
  signal n_blocks_arr2 : n_blocks_arr_t;

  signal words             : word_arr_t;
  signal in_words_arr      : word_arr_t;
  signal in_lengths_arr    : in_lengths_arr_t;
  signal full_blocks_arr   : full_blocks_arr_t;
  signal full_blocks_valid : std_logic_vector(MAX_BLOCKS_PER_WORD * N_WORDS - 1 downto 0);

  signal preshift      : unsigned(BLOCK_SIZE_BITS-1 downto 0);
  signal preshift_next : unsigned(BLOCK_SIZE_BITS-1 downto 0);

  type rembits_t is array (0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH-1 downto 0);
  signal rembits : rembits_t;
begin

  process (in_words, in_lengths, words, full_blocks_arr, preshift, n_blocks_arr2)
    constant SUM_SIZE  : integer := integer(ceil(log2(real(BLOCK_SIZE + MAX_LENGTH))));
    variable sum       : unsigned(SUM_SIZE-1 downto 0);
    variable bits_left : unsigned(BLOCK_SIZE_BITS-1 downto 0);
  begin
    -- Extract words and lengths
    bits_left := preshift;
    for i in 0 to N_WORDS-1 loop
      in_words_arr(i) <= in_words((i+1)*MAX_LENGTH-1 downto i*MAX_LENGTH) & (BLOCK_SIZE-2 downto 0 => '0');

      out_words((i+1)*BLOCK_SIZE-1 downto i*BLOCK_SIZE) <= full_blocks_arr(i);
--      out_valids <= full_blocks_valid;

      -- Compute bits left after this word is shifted in
      sum             := resize(bits_left, SUM_SIZE) + in_lengths((i+1)*LENGTH_BITS-1 downto i*LENGTH_BITS);
      shift_arr(i)    <= to_integer(bits_left);
      n_blocks_arr(i) <= to_integer(sum(sum'high downto BLOCK_SIZE_BITS));
      bits_left       := sum(BLOCK_SIZE_BITS-1 downto 0);
      if (i = N_WORDS-1) then
        preshift_next <= bits_left;
      end if;
    end loop;

  end process;

  process (clk)
    variable remaining_bits : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable temp           : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        preshift          <= (others => '0');
        full_blocks_valid <= (others => '0');
        full_blocks_arr   <= (others => (others => '0'));
        remaining_bits    := (others => '0');
        words             <= (others => (others => '0'));
      else
        n_blocks_arr2 <= n_blocks_arr;
        for i in 0 to N_WORDS-1 loop
          -- Step 1
          words(i) <= std_logic_vector(shift_right(unsigned(in_words_arr(i)), shift_arr(i)));
          preshift <= preshift_next;

          -- Step 2
          full_blocks_valid <= (others => '0');
          temp              := remaining_bits or words(i);
          if (n_blocks_arr2(i) = 0) then
            for blk in 0 to MAX_BLOCKS_PER_WORD-1 loop
              full_blocks_arr(MAX_BLOCKS_PER_WORD*i + blk) <= (others => 'X');
            end loop;
          else
            for blk in 0 to MAX_BLOCKS_PER_WORD-1 loop
              if (n_blocks_arr2(i) > blk) then
                full_blocks_arr(MAX_BLOCKS_PER_WORD*i + blk)   <= temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);
                full_blocks_valid(MAX_BLOCKS_PER_WORD*i + blk) <= '1';
                temp                                           := temp(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
              end if;
            end loop;
          end if;
          remaining_bits := temp;
--            rembits(i)     <= remaining_bits & '0';
        end loop;
      end if;
    end if;
  end process;

end rtl;
