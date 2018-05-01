library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;
use ieee.math_real.all;

--------------------------------------------------------------------------------
-- Dual port Block RAM wrapper
--
-- RAM is split into two parts beacuse of Vivado's incompetence in inferring
-- block RAMs effectively; the depth is always expanded to nearest power of 2.
--------------------------------------------------------------------------------

entity dp_bram is
  generic (
    ELEMENTS     : integer := 21760;
    ELEMENT_SIZE : integer := 16;
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
end dp_bram;

architecture rtl of dp_bram is

  constant LOWER_POW2 : integer := 2**integer(log2(real(ELEMENTS)));
  constant REMAINS    : integer := ELEMENTS - LOWER_POW2;

  -- Only split RAMs when size is big enough, REMAINS > 0 and we actually want block RAMs
  constant SPLIT_RAMS : boolean := LOWER_POW2 >= 1024 and REMAINS > 0 and RAM_TYPE = "block";

  function LOWER_SIZE return integer is
  begin
    if (SPLIT_RAMS) then
      return LOWER_POW2;
    else
      return ELEMENTS;
    end if;
  end function LOWER_SIZE;

  signal upper_rddata : std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal lower_rddata : std_logic_vector(ELEMENT_SIZE-1 downto 0);

  signal wr_is_lower     : std_logic;
  signal rd_is_lower     : std_logic;
  signal rd_is_lower_reg : std_logic;
  signal lower_wr        : std_logic;
  signal lower_rd        : std_logic;
begin
  g_ctrls : if (SPLIT_RAMS) generate
  end generate g_ctrls;

  lower_wr <= wr when not SPLIT_RAMS or wr_is_lower = '1' else '0';
  lower_rd <= rd when not SPLIT_RAMS or rd_is_lower = '1' else '0';

  process (lower_rddata, upper_rddata, rd_is_lower_reg)
  begin
    rddata <= lower_rddata;
    if (SPLIT_RAMS and rd_is_lower_reg = '0') then
      rddata <= upper_rddata;
    end if;
  end process;

  i_lower_ram : entity work.dp_ram
    generic map (
      ELEMENTS     => LOWER_SIZE,
      ELEMENT_SIZE => ELEMENT_SIZE,
      RAM_TYPE     => RAM_TYPE)
    port map (
      clk     => clk,
      aresetn => aresetn,
      wr      => lower_wr,
      wraddr  => wraddr,
      wrdata  => wrdata,
      rd      => lower_rd,
      rdaddr  => rdaddr,
      rddata  => lower_rddata);

  g_upper : if (SPLIT_RAMS) generate
    signal upper_wraddr : integer range 0 to REMAINS-1;
    signal upper_rdaddr : integer range 0 to REMAINS-1;
    signal upper_rd     : std_logic;
    signal upper_wr     : std_logic;
  begin
    wr_is_lower <= '1' when wraddr < LOWER_POW2 else '0';
    rd_is_lower <= '1' when rdaddr < LOWER_POW2 else '0';

    rd_is_lower_reg <= rd_is_lower when rising_edge(clk);

    upper_wraddr <= wraddr - LOWER_POW2;
    upper_rdaddr <= rdaddr - LOWER_POW2;
    upper_wr     <= wr when wr_is_lower = '0' else '0';
    upper_rd     <= rd when rd_is_lower = '0' else '0';

    i_upper_ram : entity work.dp_ram
      generic map (
        ELEMENTS     => REMAINS,
        ELEMENT_SIZE => ELEMENT_SIZE,
        RAM_TYPE     => RAM_TYPE)
      port map (
        clk     => clk,
        aresetn => aresetn,
        wr      => upper_wr,
        wraddr  => upper_wraddr,
        wrdata  => wrdata,
        rd      => upper_rd,
        rdaddr  => upper_rdaddr,
        rddata  => upper_rddata);
  end generate g_upper;

end rtl;
