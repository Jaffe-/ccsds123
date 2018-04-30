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

  type ram_t is array (natural range <>) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal ram_lower : ram_t(0 to LOWER_POW2-1) := (others => (others => '0'));
  signal ram_upper : ram_t(0 to REMAINS-1)    := (others => (others => '0'));

  attribute ram_style              : string;
  attribute ram_style of ram_lower : signal is RAM_TYPE;
  attribute ram_style of ram_upper : signal is RAM_TYPE;

  signal rddata_upper : std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal rddata_lower : std_logic_vector(ELEMENT_SIZE-1 downto 0);

  signal wr_is_lower   : std_logic;
  signal rd_is_lower   : std_logic;
  signal wr_upper_addr : integer range 0 to REMAINS-1;
  signal rd_upper_addr : integer range 0 to REMAINS-1;
begin
  wr_is_lower   <= '1' when wraddr < LOWER_POW2 else '0';
  wr_upper_addr <= wraddr - LOWER_POW2;
  rd_is_lower   <= '1' when rdaddr < LOWER_POW2 else '0';
  rd_upper_addr <= rdaddr - LOWER_POW2;

  rddata <= rddata_lower when rd_is_lower = '1' else rddata_upper;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rddata_lower <= (others => '0');
      end if;

      if (rd = '1' and rd_is_lower = '1') then
        rddata_lower <= ram_lower(rdaddr);
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rddata_upper <= (others => '0');
      end if;

      if (rd = '1' and rd_is_lower = '0') then
        rddata_upper <= ram_upper(rd_upper_addr);
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (wr = '1' and wr_is_lower = '1') then
        ram_lower(wraddr) <= wrdata;
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (wr = '1' and wr_is_lower = '0') then
        ram_upper(wr_upper_addr) <= wrdata;
      end if;
    end if;
  end process;
end rtl;
