--------------------------------------------------------------------------------
-- Variable length word combiner
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

entity combiner is
  generic (
    BLOCK_SIZE : integer := 64;
    N_WORDS    : integer := 4;
    MAX_LENGTH : integer := 28
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
  constant LENGTH_BITS : integer := integer(ceil(log2(real(MAX_LENGTH))));

  type in_words_arr_t is array (0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH - 2 downto 0);
  type word_arr_t is array (0 to N_WORDS, 0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH - 2 downto 0);
  type in_lengths_arr_t is array (0 to N_WORDS-1) of integer range 0 to MAX_LENGTH;
  type length_arr_t is array (0 to N_WORDS-1, 0 to N_WORDS-1) of integer range 0 to BLOCK_SIZE + MAX_LENGTH - 1;
  type full_blocks_arr_t is array (0 to N_WORDS-1, 0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE-1 downto 0);
  type full_blocks_valid_t is array (0 to N_WORDS-1) of std_logic_vector(N_WORDS-1 downto 0);

  signal words             : word_arr_t;
  signal in_words_arr      : in_words_arr_t;
  signal lengths           : length_arr_t;
  signal in_lengths_arr    : in_lengths_arr_t;
  signal full_blocks_arr   : full_blocks_arr_t;
  signal full_blocks_valid : full_blocks_valid_t;

  signal preshift  : integer range 0 to BLOCK_SIZE-1;
  signal leftovers : std_logic_vector(MAX_LENGTH+BLOCK_SIZE-2 downto 0);
begin

  process (in_words, in_lengths, words, full_blocks_arr, full_blocks_valid)
  begin
    -- Extract words and lengths
    for i in 0 to N_WORDS-1 loop
      in_words_arr(i)   <= in_words((i+1)*MAX_LENGTH-1 downto i*MAX_LENGTH) & (BLOCK_SIZE-2 downto 0 => '0');
      in_lengths_arr(i) <= to_integer(in_lengths((i+1)*LENGTH_BITS-1 downto i*LENGTH_BITS));

      out_words((i+1)*BLOCK_SIZE-1 downto i*BLOCK_SIZE) <= full_blocks_arr(N_WORDS-1, i);
      out_valids(i)                                     <= full_blocks_valid(N_WORDS-1)(i);
    end loop;

  end process;

  process (clk)
    variable to_shift       : integer range 0 to MAX_LENGTH;
    variable remaining_bits : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable preshift_sum   : unsigned(5 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        preshift          <= 0;
        full_blocks_valid <= (others => (others => '0'));
        full_blocks_arr   <= (others => (others => (others => '0')));
      else
        preshift_sum  := to_unsigned(preshift, 6);
        words(0, 0)   <= std_logic_vector(shift_right(unsigned(in_words_arr(0)), preshift));
        lengths(0, 0) <= in_lengths_arr(0) + preshift;
        for i in 1 to N_WORDS-1 loop
          preshift_sum := preshift_sum + to_unsigned(in_lengths_arr(i), 6);

          -- Store input words
          words(0, i)   <= in_words_arr(i);
          lengths(0, i) <= in_lengths_arr(i);

          -- Perform shifts and block extractions
          for j in 0 to N_WORDS - 1 loop
            if (j = i) then
              if (lengths(i-1, j-1) >= BLOCK_SIZE) then
                full_blocks_valid(i-1)(j-1) <= '1';
                full_blocks_arr(i-1, j-1)   <= words(i-1, j-1)(MAX_LENGTH+BLOCK_SIZE-2 downto MAX_LENGTH-1);
                remaining_bits              := words(i-1, j-1)(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
                to_shift                    := lengths(i-1, j-1) - BLOCK_SIZE;
              else
                full_blocks_valid(i-1)(j-1) <= '0';
                remaining_bits              := words(i-1, j-1);
                to_shift                    := lengths(i-1, j-1);
              end if;

              words(i, j)   <= remaining_bits or std_logic_vector(shift_right(unsigned(words(i-1, j)), to_shift));
              lengths(i, j) <= to_shift + lengths(i-1, j);

            elsif (j > i) then
              words(i, j)   <= words(i-1, j);
              lengths(i, j) <= lengths(i-1, j);
            elsif (j < i) then
              full_blocks_valid(i)(j) <= full_blocks_valid(i-1)(j);
              full_blocks_arr(i, j)   <= full_blocks_arr(i-1, j);
            end if;

          end loop;
        end loop;

        preshift <= to_integer(preshift_sum);

        if (lengths(N_WORDS-1, N_WORDS-1) >= BLOCK_SIZE) then
          full_blocks_arr(N_WORDS-1, N_WORDS-1)   <= words(N_WORDS-1, N_WORDS-1)(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);
          full_blocks_valid(N_WORDS-1)(N_WORDS-1) <= '1';
          leftovers                               <= words(N_WORDS-1, N_WORDS-1)(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
        else
          full_blocks_valid(N_WORDS-1)(N_WORDS-1) <= '0';
          leftovers                               <= words(N_WORDS-1, N_WORDS-1)(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
        end if;

      end if;
    end if;
  end process;

end rtl;
