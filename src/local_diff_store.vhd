library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity local_diff_store is
  generic (
    NZ : integer;
    P  : integer;
    D  : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr            : in std_logic;
    wr_local_diff : in signed(D+2 downto 0);
    z             : in integer range 0 to NZ-1;

    local_diffs : out signed((D+3)*P-1 downto 0)
    );
end local_diff_store;

architecture rtl of local_diff_store is
  signal local_diffs_reg : signed((D+3)*P-1 downto 0);
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        local_diffs_reg <= (others => '0');
      else
        if (wr = '1') then
          local_diffs_reg(D+2 downto 0) <= wr_local_diff;
          if (z = NZ-1) then
            local_diffs_reg(local_diffs_reg'high downto 0) <= (others => '0');
          else
            local_diffs_reg(local_diffs_reg'high downto D+3) <= local_diffs_reg(local_diffs_reg'high-(D+3) downto 0);
          end if;
        end if;
      end if;
    end if;
  end process;

  local_diffs <= local_diffs_reg;
end rtl;
