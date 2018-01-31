library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity residual_mapper is
  generic (
    D : integer := 8
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid         : in std_logic;
    in_s             : in signed(D-1 downto 0);
    in_scaled_pred_s : in signed(D downto 0);

    out_valid : out std_logic;
    out_delta : out unsigned(D-1 downto 0)
    );

end residual_mapper;

architecture rtl of residual_mapper is
  signal residual             : signed(D-1 downto 0);
  signal theta                : integer range -2**D to 2**D-1;
  signal valid_reg            : std_logic;
  signal in_scaled_pred_s_odd : std_logic;

  function get_min(a : integer; b : integer) return integer is
  begin
    if (a < b) then
      return a;
    else
      return b;
    end if;
  end function get_min;

begin
  process (clk)
    variable pred_s       : signed(D-1 downto 0);
    variable abs_residual : unsigned(D-1 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        residual             <= (others => '0');
        theta                <= 0;
        valid_reg            <= '0';
        in_scaled_pred_s_odd <= '0';
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - compute residual and Theta
        --------------------------------------------------------------------------------
        pred_s := resize(shift_right(in_scaled_pred_s, 1), D);

        residual             <= in_s - pred_s;
        theta                <= get_min(to_integer(pred_s) + 2**(D-1), (2**(D-1)-1) - to_integer(pred_s));
        valid_reg            <= in_valid;
        in_scaled_pred_s_odd <= in_scaled_pred_s(0);

        --------------------------------------------------------------------------------
        -- Stage 2 - choose mapped residual
        --------------------------------------------------------------------------------
        abs_residual := unsigned(abs(residual));
        if (to_integer(abs_residual) > theta) then
          out_delta <= abs_residual + theta;
        elsif ((in_scaled_pred_s_odd = '0' and to_integer(residual) >= 0 and to_integer(residual) <= theta)
               or (in_scaled_pred_s_odd = '1' and to_integer(residual) <= 0 and -to_integer(residual) <= theta)) then
          out_delta <= shift_left(abs_residual, 1);
        else
          out_delta <= shift_left(abs_residual, 1) - 1;
        end if;
        out_valid <= valid_reg;
      end if;
    end if;
  end process;
end rtl;
