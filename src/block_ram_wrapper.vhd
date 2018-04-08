library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

--------------------------------------------------------------------------------
-- Dual port Block RAM wrapper
--------------------------------------------------------------------------------

entity dp_bram is
  generic (
    ELEMENTS     : integer := 100;
    ELEMENT_SIZE : integer := 32
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
  type ram_t is array (0 to ELEMENTS-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal ram : ram_t := (others => (others => '0'));
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rddata <= (others => '0');
      end if;

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
