library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity combiner_chain is
  generic (
    BLOCK_SIZE    : integer := 64;
    N_WORDS       : integer := 4;
    LAST_IN_CHAIN : boolean := true;
    MAX_LENGTH    : integer := 48;
    IN_MAX_BLOCKS : integer := 2;
    MAX_BLOCKS    : integer := 2
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_remaining         : in std_logic_vector(BLOCK_SIZE-2 downto 0);
    in_remaining_length  : in unsigned(len2bits(BLOCK_SIZE)-1 downto 0);
    in_words             : in std_logic_vector(N_WORDS * MAX_LENGTH - 1 downto 0);
    in_lengths           : in unsigned(N_WORDS * num2bits(MAX_LENGTH) - 1 downto 0);
    in_valid             : in std_logic;
    in_last              : in std_logic;
    in_full_blocks       : in std_logic_vector(BLOCK_SIZE*IN_MAX_BLOCKS-1 downto 0);
    in_full_blocks_count : in integer range 0 to IN_MAX_BLOCKS;

    out_remaining                : out std_logic_vector(BLOCK_SIZE-2 downto 0);
    out_remaining_length         : out unsigned(len2bits(BLOCK_SIZE)-1 downto 0);
    out_remaining_length_delayed : out unsigned(len2bits(BLOCK_SIZE)-1 downto 0);
    out_full_blocks              : out std_logic_vector(BLOCK_SIZE*(IN_MAX_BLOCKS + MAX_BLOCKS)-1 downto 0);
    out_full_blocks_count        : out integer range 0 to BLOCK_SIZE*(IN_MAX_BLOCKS + MAX_BLOCKS);
    out_last                     : out std_logic;
    out_valid                    : out std_logic
    );
end combiner_chain;

architecture rtl of combiner_chain is
  constant LENGTH_BITS         : integer := num2bits(MAX_LENGTH);
  constant BLOCK_SIZE_BITS     : integer := len2bits(BLOCK_SIZE);
  constant MAX_BLOCKS_PER_WORD : integer := (BLOCK_SIZE + MAX_LENGTH) / BLOCK_SIZE;

  type word_arr_t is array (0 to 1, 0 to N_WORDS-1) of std_logic_vector(BLOCK_SIZE + MAX_LENGTH - 2 downto 0);
  type shift_arr_t is array (0 to N_WORDS-1) of integer range 0 to BLOCK_SIZE-1;
  type n_blocks_arr_t is array (0 to 1, 0 to N_WORDS-1) of integer range 0 to MAX_BLOCKS_PER_WORD;

  signal shift_arr       : shift_arr_t;
  signal n_blocks_arr    : n_blocks_arr_t;
  signal words           : word_arr_t;
  signal valid_regs      : std_logic_vector(1 downto 0);
  signal last_regs       : std_logic_vector(1 downto 0);
  signal last_flush_regs : std_logic_vector(1 downto 0);
begin

  process (clk)
    constant SUM_SIZE           : integer := len2bits(BLOCK_SIZE + MAX_LENGTH);
    variable sum                : unsigned(SUM_SIZE-1 downto 0);
    variable num_remaining_bits : unsigned(BLOCK_SIZE_BITS-1 downto 0);
    variable remaining_bits     : std_logic_vector(BLOCK_SIZE - 2 downto 0);
    variable temp               : std_logic_vector(BLOCK_SIZE + MAX_LENGTH-2 downto 0);
    variable count              : integer range 0 to IN_MAX_BLOCKS + MAX_BLOCKS;
    variable full_blocks        : std_logic_vector(BLOCK_SIZE*(IN_MAX_BLOCKS + MAX_BLOCKS)-1 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        words                 <= (others => (others => (others => '0')));
        valid_regs            <= (others => '0');
        last_flush_regs       <= (others => '0');
        out_remaining_length  <= (others => '0');
        out_remaining         <= (others => '0');
        out_full_blocks_count <= 0;
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - Compute shift amounts and number of blocks
        --------------------------------------------------------------------------------
        if (in_valid = '1') then
          num_remaining_bits := in_remaining_length;
          for i in 0 to N_WORDS-1 loop
            words(0, i) <= in_words((i+1)*MAX_LENGTH-1 downto i*MAX_LENGTH) & (BLOCK_SIZE-2 downto 0 => '0');

            -- Compute bits left after this word is shifted in
            sum                := resize(num_remaining_bits, SUM_SIZE) + in_lengths((i+1)*LENGTH_BITS-1 downto i*LENGTH_BITS);
            shift_arr(i)       <= to_integer(num_remaining_bits);
            n_blocks_arr(0, i) <= to_integer(sum(sum'high downto BLOCK_SIZE_BITS));
            num_remaining_bits := sum(BLOCK_SIZE_BITS-1 downto 0);
          end loop;

          if (LAST_IN_CHAIN and in_last = '1') then
            if (num_remaining_bits /= 0) then
              last_flush_regs(0) <= '1';
            else
              last_flush_regs(0) <= '0';
            end if;
            num_remaining_bits := (others => '0');
          end if;

          out_remaining_length <= num_remaining_bits;
        end if;
        valid_regs(0)            <= in_valid;
        last_regs(0)             <= in_last;
        remaining_length_regs(0) <= num_remaining_bits;

        --------------------------------------------------------------------------------
        -- Stage 2 - Shift each incoming word
        --------------------------------------------------------------------------------
        if (valid_regs(0) = '1') then
          for i in 0 to N_WORDS-1 loop
            n_blocks_arr(1, i) <= n_blocks_arr(0, i);
            words(1, i)        <= std_logic_vector(shift_right(unsigned(words(0, i)), shift_arr(i)));
          end loop;
        end if;
        valid_regs(1)            <= valid_regs(0);
        last_regs(1)             <= last_regs(0);
        last_flush_regs(1)       <= last_flush_regs(0);
        remaining_length_regs(1) <= remaining_length_regs(0);

        --------------------------------------------------------------------------------
        -- Stage 3 - Combine shifted words and extract blocks
        --------------------------------------------------------------------------------
        remaining_bits := in_remaining;
        count          := in_full_blocks_count;
        full_blocks    := in_full_blocks & (MAX_BLOCKS*BLOCK_SIZE-1 downto 0 => '0');
        if (valid_regs(1) = '1') then
          for i in 0 to N_WORDS-1 loop
            temp := (remaining_bits & (MAX_LENGTH-1 downto 0 => '0')) or words(1, i);

            for blk in 0 to MAX_BLOCKS_PER_WORD-1 loop
              if (n_blocks_arr(1, i) > blk) then
                full_blocks(BLOCK_SIZE*(count+1)-1 downto BLOCK_SIZE*count) := temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH-1);

                temp  := temp(MAX_LENGTH-2 downto 0) & (BLOCK_SIZE-1 downto 0 => '0');
                count := count + 1;
              end if;
            end loop;
            remaining_bits := temp(BLOCK_SIZE+MAX_LENGTH-2 downto MAX_LENGTH);
          end loop;

          -- If last is 1 and we have some bits left over after extracting
          -- blocks, then we put these into a new block
          if (LAST_IN_CHAIN and last_regs(1) = '1' and last_flush_regs(1) = '1') then
            full_blocks(BLOCK_SIZE*(count+1)-1 downto BLOCK_SIZE*count) := remaining_bits & '0';

            count          := count + 1;
            remaining_bits := (others => '0');
          end if;
        end if;
        out_full_blocks              <= full_blocks;
        out_full_blocks_count        <= count;
        out_remaining                <= remaining_bits;
        out_remaining_length_delayed <= remaining_length_regs(1);
        out_last                     <= last_regs(1);
        out_valid                    <= valid_regs(1);
      end if;
    end if;
  end process;
end rtl;
