library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity local_diff_store is
  generic (
    PIPELINES : integer;
    P         : integer;
    D         : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr            : in std_logic;
    wr_local_diff : in signed(PIPELINES*(D+3)-1 downto 0);

    local_diffs : out signed(P*(D+3)-1 downto 0)
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
          if (PIPELINES < P) then
            local_diffs_reg(PIPELINES*(D+3)-1 downto 0)                  <= wr_local_diff;
            local_diffs_reg(local_diffs_reg'high downto PIPELINES*(D+3)) <= local_diffs_reg(local_diffs_reg'high-PIPELINES*(D+3) downto 0);
          else
            local_diffs_reg <= wr_local_diff(P*(D+3)-1 downto 0);
          end if;
        end if;
      end if;
    end if;
  end process;

  local_diffs <= local_diffs_reg;
end rtl;
