library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

entity weight_store is
  generic (
    OMEGA : integer := 8;
    CZ    : integer := 4;
    NZ    : integer := 100
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr        : in std_logic;
    wr_z      : in integer range 0 to NZ-1;
    wr_weight : in signed(CZ*(OMEGA+3)-1 downto 0);

    rd        : in  std_logic;
    rd_z      : in  integer range 0 to NZ-1;
    rd_weight : out signed(CZ*(OMEGA+3)-1 downto 0)
    );
end weight_store;

architecture rtl of weight_store is
  type weight_vec_t is array (natural range 0 to NZ-1) of signed(CZ*(OMEGA+3)-1 downto 0);
  signal weights         : weight_vec_t;
  signal weight_from_ram : signed(CZ*(OMEGA+3)-1 downto 0);
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (wr = '1') then
        weights(wr_z) <= wr_weight;
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rd_weight <= (others => '0');
      end if;
      if (rd = '1') then
        weight_from_ram <= weights(rd_z);
      end if;
      rd_weight <= weight_from_ram;
    end if;
  end process;
end rtl;
