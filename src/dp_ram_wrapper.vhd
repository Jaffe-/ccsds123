library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;
use ieee.math_real.all;

--------------------------------------------------------------------------------
-- Dual port Block RAM wrapper
--
-- RAM is split into several parts beacuse of Vivado's incompetence in inferring
-- block RAMs effectively; the depth is always expanded to nearest power of 2.
--
-- The number of elements is decomposed into powers of 2 by the decompose function.
-- The decompose function returns an array with two properties:
--------------------------------------------------------------------------------

entity dp_ram_wrapper is
  generic (
    ELEMENTS     : integer;
    ELEMENT_SIZE : integer;
    RAM_TYPE     : string  := "block"
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr     : in  std_logic;
    wraddr : in  integer range 0 to ELEMENTS-1;
    wrdata : in  std_logic_vector(ELEMENT_SIZE-1 downto 0);
    rd     : in  std_logic;
    rdaddr : in  integer range 0 to ELEMENTS-1;
    rddata : out std_logic_vector(ELEMENT_SIZE-1 downto 0)
    );
end dp_ram_wrapper;

architecture rtl of dp_ram_wrapper is
  constant SMALLEST_BANK_LOG2 : integer := 10;
  constant OPTIMIZE           : boolean := RAM_TYPE = "block" and ELEMENTS > 2**SMALLEST_BANK_LOG2;

  function calc_n_banks return integer is
  begin
    if (OPTIMIZE) then
      return max(1, integer(log2(real(ELEMENTS))) - SMALLEST_BANK_LOG2 + 2);
    else
      return 1;
    end if;
  end calc_n_banks;

  constant N_BANKS : integer := calc_n_banks;

  type int_arr_t is array (natural range <>) of integer;

  -- Decompose n into powers of 2
  function decompose(n : integer; lower : integer; num : integer) return int_arr_t is
    constant upper      : integer := integer(log2(real(n)));
    variable bank_start : int_arr_t(0 to num-1);
    variable remains    : integer := n;
    variable sum        : integer := 0;
  begin
    if (OPTIMIZE and upper > lower) then
      for i in upper downto lower loop
        if (remains > 2**i) then
          bank_start(1 + i - lower) := sum;
          remains                   := remains - 2**i;
          sum                       := sum + 2**i;
        else
          bank_start(1 + i - lower) := -1;
        end if;
      end loop;
    end if;

    if (remains > 0) then
      bank_start(0) := sum;
    else
      bank_start(0) := -1;
    end if;

    return bank_start;
  end decompose;

  constant BANK_START : int_arr_t := decompose(ELEMENTS, SMALLEST_BANK_LOG2, N_BANKS);

  type rddata_arr_t is array(0 to N_BANKS-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal rddata_arr : rddata_arr_t;

  signal rd_arr     : std_logic_vector(N_BANKS-1 downto 0);
  signal rd_arr_reg : std_logic_vector(N_BANKS-1 downto 0);
begin
  g_banks : for i in BANK_START'range generate
    g_bank : if (BANK_START(i) /= -1) generate
      function get_size return integer is
      begin
        if (i > 0) then
          return 2**(SMALLEST_BANK_LOG2 + i - 1);
        else
          return ELEMENTS - BANK_START(0);
        end if;
      end get_size;

      constant SIZE : integer := get_size;

      signal this_wraddr : integer range 0 to SIZE-1;
      signal this_rdaddr : integer range 0 to SIZE-1;
      signal this_wr     : std_logic;
      signal this_rd     : std_logic;
    begin
      this_wr     <= wr when wraddr >= BANK_START(i) and wraddr < BANK_START(i) + SIZE else '0';
      this_rd     <= rd when rdaddr >= BANK_START(i) and rdaddr < BANK_START(i) + SIZE else '0';
      rd_arr(i)   <= this_rd;
      this_wraddr <= wraddr - BANK_START(i);
      this_rdaddr <= rdaddr - BANK_START(i);
      i_ram : entity work.dp_ram
        generic map (
          ELEMENTS     => SIZE,
          ELEMENT_SIZE => ELEMENT_SIZE,
          RAM_TYPE     => RAM_TYPE)
        port map (
          clk     => clk,
          aresetn => aresetn,
          wr      => this_wr,
          wraddr  => this_wraddr,
          wrdata  => wrdata,
          rd      => this_rd,
          rdaddr  => this_rdaddr,
          rddata  => rddata_arr(i));
    end generate g_bank;
  end generate g_banks;

  rd_arr_reg <= rd_arr when rising_edge(clk) and rd = '1';

  -- Select which bank to get read data from
  process (rddata_arr, rd_arr_reg)
  begin
    rddata <= rddata_arr(0);
    for i in BANK_START'range loop
      if (BANK_START(i) /= -1 and rd_arr_reg(i) = '1') then
        rddata <= rddata_arr(i);
      end if;
    end loop;
  end process;

end rtl;
