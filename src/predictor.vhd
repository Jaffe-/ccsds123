library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity predictor is
  generic (
    NX    : integer;
    NZ    : integer;
    D     : integer;
    R     : integer;
    OMEGA : integer;
    P     : integer;
    CZ    : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid  : in std_logic;
    in_ctrl   : in ctrl_t;
    in_d_c    : in signed(D+3+OMEGA+3+CZ-1-1 downto 0);
    in_locsum : in signed(D+2 downto 0);

    in_z       : in integer range 0 to NZ-1;
    in_prev_s  : in signed(D-1 downto 0);
    in_s       : in signed(D-1 downto 0);
    in_weights : in signed(CZ*(OMEGA+3)-1 downto 0);
    in_diffs   : in signed(CZ*(D+3)-1 downto 0);

    out_valid  : out std_logic;
    out_pred_s : out signed(D downto 0);

    out_ctrl    : out ctrl_t;
    out_z       : out integer range 0 to NZ-1;
    out_s       : out signed(D-1 downto 0);
    out_weights : out signed(CZ*(OMEGA+3)-1 downto 0);
    out_diffs   : out signed(CZ*(D+3)-1 downto 0)
    );
end predictor;

architecture rtl of predictor is
  signal pred_s     : signed(D downto 0);
  signal numerator  : signed(R-1 downto 0);
  signal valid_regs : std_logic_vector(1 downto 0);

  type side_data_t is record
    ctrl    : ctrl_t;
    z       : integer range 0 to NZ-1;
    s       : signed(D-1 downto 0);
    prev_s  : signed(D-1 downto 0);
    weights : signed(CZ*(OMEGA+3)-1 downto 0);
    diffs   : signed(CZ*(D+3)-1 downto 0);
    locsum  : signed(D+2 downto 0);
  end record side_data_t;

  type side_data_arr_t is array (0 to 1) of side_data_t;
  signal side_data_regs : side_data_arr_t;
begin
  process (clk)
    variable temp : signed(D+3+OMEGA+3+CZ-1 downto 0);
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        numerator  <= (others => '0');
        pred_s     <= (others => '0');
        valid_regs <= (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - compute numerator in scaled predicted sample expression
        --------------------------------------------------------------------------------
        temp := resize(in_d_c, D+3+OMEGA+3+CZ) + shift_left(resize(in_locsum, D+OMEGA+3), OMEGA);

        -- Perform modR*(temp, R)
        if (D+3+OMEGA+3+CZ > R) then
          numerator <= temp(R-1 downto 0);
        else
          numerator <= resize(temp, R);
        end if;

        valid_regs(0) <= in_valid;
        side_data_regs(0) <= (
          ctrl    => in_ctrl,
          z       => in_z,
          s       => in_s,
          prev_s  => in_prev_s,
          weights => in_weights,
          diffs   => in_diffs,
          locsum  => in_locsum);

        --------------------------------------------------------------------------------
        -- Stage 2 - compute the scaled predicted sample
        --------------------------------------------------------------------------------
        if (side_data_regs(0).ctrl.first_in_line = '1' and side_data_regs(0).ctrl.first_line = '1') then
          if (P > 0 and side_data_regs(0).z > 0) then
            pred_s <= shift_left(resize(side_data_regs(0).prev_s, D+1), 1);  -- 2s_{z-1}(t)
          else
            pred_s <= (others => '0');  -- 2s_mid
          end if;
        else
          pred_s <= to_signed(clip(to_integer(shift_right(numerator, OMEGA+1) + 1), -2**D, 2**D-1), D+1);
        end if;

        side_data_regs(1) <= side_data_regs(0);
        valid_regs(1)     <= valid_regs(0);
      end if;
    end if;
  end process;

  out_pred_s <= pred_s;
  out_valid  <= valid_regs(1);

  out_ctrl    <= side_data_regs(1).ctrl;
  out_z       <= side_data_regs(1).z;
  out_s       <= side_data_regs(1).s;
  out_weights <= side_data_regs(1).weights;
  out_diffs   <= side_data_regs(1).diffs;
end rtl;
