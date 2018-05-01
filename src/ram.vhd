library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

--------------------------------------------------------------------------------
-- Dual port RAM
--------------------------------------------------------------------------------

entity dp_ram is
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
end dp_ram;

architecture rtl of dp_ram is
  type ram_t is array (0 to ELEMENTS-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  attribute ram_style        : string;
  attribute ram_style of ram : signal is RAM_TYPE;
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (rd = '1') then
        rddata <= ram(rdaddr);
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (wr = '1') then
        ram(wraddr) <= wrdata;
      end if;
    end if;
  end process;
end rtl;
