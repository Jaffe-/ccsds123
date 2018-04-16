library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity residual_mapper is
  generic (
    D  : integer;
    NZ : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid         : in std_logic;
    in_ctrl          : in ctrl_t;
    in_z             : in integer range 0 to NZ-1;
    in_s             : in signed(D-1 downto 0);
    in_scaled_pred_s : in signed(D downto 0);

    out_valid : out std_logic;
    out_ctrl  : out ctrl_t;
    out_z     : out integer range 0 to NZ-1;
    out_delta : out unsigned(D-1 downto 0)
    );

end residual_mapper;

architecture rtl of residual_mapper is
  signal residual             : signed(D + 1 downto 0);
  signal theta                : integer range -2**D to 2**D-1;
  signal in_scaled_pred_s_odd : std_logic;

  signal ctrl_reg   : ctrl_t;
  signal z_reg      : integer range 0 to NZ-1;
  signal valid_regs : std_logic_vector(1 downto 0);

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
    variable abs_residual : unsigned(D+1 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        valid_regs <= (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - compute residual and Theta
        --------------------------------------------------------------------------------
        pred_s := resize(shift_right(in_scaled_pred_s, 1), D);

        residual             <= resize(in_s, D+2) - pred_s;
        theta                <= get_min(to_integer(pred_s) + 2**(D-1), (2**(D-1)-1) - to_integer(pred_s));
        in_scaled_pred_s_odd <= in_scaled_pred_s(0);

        valid_regs(0) <= in_valid;
        ctrl_reg      <= in_ctrl;
        z_reg         <= in_z;

        --------------------------------------------------------------------------------
        -- Stage 2 - choose mapped residual
        --------------------------------------------------------------------------------
        abs_residual := unsigned(abs(residual));
        if (to_integer(abs_residual) > theta) then
          out_delta <= resize(abs_residual + theta, D);
        elsif ((in_scaled_pred_s_odd = '0' and to_integer(residual) >= 0)
               or (in_scaled_pred_s_odd = '1' and to_integer(residual) <= 0)) then
          out_delta <= resize(shift_left(abs_residual, 1), D);
        else
          out_delta <= resize(shift_left(abs_residual, 1) - 1, D);
        end if;

        valid_regs(1) <= valid_regs(0);
        out_ctrl      <= ctrl_reg;
        out_z         <= z_reg;
      end if;
    end if;
  end process;
  out_valid <= valid_regs(1);
end rtl;
