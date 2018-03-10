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
    in_last    : in std_logic;

    out_words : out std_logic_vector(((BLOCK_SIZE + N_WORDS * MAX_LENGTH)/BLOCK_SIZE + 1)*BLOCK_SIZE - 1 downto 0);
    out_count : out integer range 0 to (BLOCK_SIZE + N_WORDS * MAX_LENGTH) / BLOCK_SIZE + 1;
    out_valid : out std_logic;
    out_last  : out std_logic
    );
end combiner;

architecture rtl of combiner is
  constant LENGTH_BITS         : integer := integer(ceil(log2(real(MAX_LENGTH))));
  constant BLOCK_SIZE_BITS     : integer := integer(ceil(log2(real(BLOCK_SIZE))));
  constant MAX_BLOCKS_PER_WORD : integer := (BLOCK_SIZE + MAX_LENGTH) / BLOCK_SIZE;
  constant MAX_BLOCKS          : integer := (BLOCK_SIZE + N_WORDS * MAX_LENGTH) / BLOCK_SIZE + 1;

  type word_arr_t is array (0 to 1, 0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH - 2 downto 0);
  type shift_arr_t is array (0 to N_WORDS-1) of integer range 0 to BLOCK_SIZE-1;
  type n_blocks_arr_t is array (0 to 1, 0 to N_WORDS-1) of integer range 0 to MAX_BLOCKS_PER_WORD;
  type full_blocks_t is array (0 to MAX_BLOCKS - 1) of std_logic_vector(BLOCK_SIZE-1 downto 0);

  signal shift_arr    : shift_arr_t;
  signal n_blocks_arr : n_blocks_arr_t;
  signal words        : word_arr_t;
  signal full_blocks  : full_blocks_t;
  signal valid_regs   : std_logic_vector(1 downto 0);
  signal last_regs    : std_logic_vector(1 downto 0);

  function limit(x : integer; LIM : integer) return integer is
    variable v : integer range 0 to LIM;
  begin
    v := x;
    return x;
  end limit;
begin

  process (full_blocks)
  begin
    for i in full_blocks'range loop
      out_words((i+1)*BLOCK_SIZE-1 downto i*BLOCK_SIZE) <= full_blocks(i);
    end loop;
  end process;

  process (clk)
    constant SUM_SIZE           : integer := integer(ceil(log2(real(BLOCK_SIZE + MAX_LENGTH))));
    variable sum                : unsigned(SUM_SIZE-1 downto 0);
    variable num_remaining_bits : unsigned(BLOCK_SIZE_BITS-1 downto 0);
    variable remaining_bits     : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable temp               : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable count              : integer range 0 to MAX_BLOCKS - 1;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        full_blocks        <= (others => (others => '0'));
        remaining_bits     := (others => '0');
        words              <= (others => (others => (others => '0')));
        num_remaining_bits := (others => '0');
        valid_regs         <= (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - Compute shift amounts and number of blocks
        --------------------------------------------------------------------------------
        if (in_valid = '1') then
          for i in 0 to N_WORDS-1 loop
            words(0, i) <= in_words((i+1)*MAX_LENGTH-1 downto i*MAX_LENGTH) & (BLOCK_SIZE-2 downto 0 => '0');

            -- Compute bits left after this word is shifted in
            sum                := resize(num_remaining_bits, SUM_SIZE) + in_lengths((i+1)*LENGTH_BITS-1 downto i*LENGTH_BITS);
            shift_arr(i)       <= to_integer(num_remaining_bits);
            n_blocks_arr(0, i) <= to_integer(sum(sum'high downto BLOCK_SIZE_BITS));
            num_remaining_bits := sum(BLOCK_SIZE_BITS-1 downto 0);
          end loop;
        end if;
        valid_regs(0) <= in_valid;
        last_regs(0)  <= in_last;

        --------------------------------------------------------------------------------
        -- Stage 2 - Shift each incoming word
        --------------------------------------------------------------------------------
        if (valid_regs(0) = '1') then
          for i in 0 to N_WORDS-1 loop
            n_blocks_arr(1, i) <= n_blocks_arr(0, i);
            words(1, i)        <= std_logic_vector(shift_right(unsigned(words(0, i)), shift_arr(i)));
          end loop;
        end if;
        valid_regs(1) <= valid_regs(0);
        last_regs(1)  <= last_regs(0);

        --------------------------------------------------------------------------------
        -- Stage 3 - Combine shifted words and extract blocks
        --------------------------------------------------------------------------------
        count := 0;
        if (valid_regs(1) = '1') then
          for i in 0 to N_WORDS-1 loop
            temp := remaining_bits or words(1, i);

            for blk in 0 to MAX_BLOCKS_PER_WORD-1 loop
              if (n_blocks_arr(1, i) > blk) then
                full_blocks(count) <= temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);
                temp               := temp(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
                count              := count + 1;
              end if;
            end loop;
            remaining_bits := temp;
          end loop;

          --if (last_regs(1) = '1') then
          --  full_blocks(count) <= remaining_bits(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);
          --  count := count + 1;
          --end if;
        end if;
        out_count <= count;
        out_valid <= valid_regs(1);
        out_last  <= last_regs(1);
      end if;
    end if;
  end process;

end rtl;