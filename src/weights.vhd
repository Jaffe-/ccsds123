library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

entity weight_store is
  generic (
    DELAY : integer := 1;
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
  type weight_vec_t is array (0 to NZ-1) of signed(CZ*(OMEGA+3)-1 downto 0);
  signal weights         : weight_vec_t := (others => (others => '0'));

  type delay_stages_t is array (0 to DELAY-1) of signed(CZ*(OMEGA+3)-1 downto 0);
  signal delay_stages : delay_stages_t;
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
        delay_stages <= (others => (others => '0'));
      end if;
      if (rd = '1') then
        delay_stages(0) <= weights(rd_z);
        if (DELAY > 0) then
          for i in 1 to DELAY-1 loop
            delay_stages(i) <= delay_stages(i-1);
          end loop;
        end if;
      end if;
    end if;
  end process;
  rd_weight <= delay_stages(DELAY-1);
end rtl;
