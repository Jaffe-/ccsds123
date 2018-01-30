library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity predictor is
  generic (
    NX    : integer := 100;
    NY    : integer := 100;
    NZ    : integer := 100;
    D     : integer := 8;
    R     : integer := 12;
    OMEGA : integer := 8;
    P     : integer := 2;
    CZ    : integer := 5
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid  : in std_logic;
    in_ctrl   : in ctrl_t;
    in_d_c    : in signed(D+3+OMEGA+3-1 downto 0);
    in_locsum : in signed(D+2 downto 0);

    in_z       : in integer range 0 to NZ-1;
    in_t       : in integer range 0 to NX*NY-1;
    in_s       : in signed(D-1 downto 0);
    in_weights : in signed(CZ*(OMEGA+3)-1 downto 0);
    in_diffs   : in signed(CZ*(D+3)-1 downto 0);

    out_valid  : out std_logic;
    out_pred_s : out signed(D downto 0);

    out_ctrl    : out ctrl_t;
    out_z       : out integer range 0 to NZ-1;
    out_t       : out integer range 0 to NX*NY-1;
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
    t       : integer range 0 to NX*NY-1;
    s       : signed(D-1 downto 0);
    weights : signed(CZ*(OMEGA+3)-1 downto 0);
    diffs   : signed(CZ*(D+3)-1 downto 0);
    locsum  : signed(D+2 downto 0);
  end record side_data_t;

  type side_data_arr_t is array (0 to 1) of side_data_t;
  signal side_data_regs : side_data_arr_t;
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        numerator  <= (others => '0');
        pred_s     <= (others => '0');
        valid_regs <= (others => '0');
      else
        side_data_regs(0) <= (
          ctrl    => in_ctrl,
          z       => in_z,
          t       => in_t,
          s       => in_s,
          weights => in_weights,
          diffs   => in_diffs,
          locsum  => in_locsum);
        side_data_regs(1) <= side_data_regs(0);

        if (in_ctrl.first_in_line = '1' and in_ctrl.first_line = '1') then
          if (P > 0 and side_data_regs(1).z > 0) then
            pred_s <= shift_left(resize(side_data_regs(1).s, D+1), 1);  -- 2s_{z-1}(t)
          else
            pred_s <= (others => '0');                         -- 2s_mid
          end if;
          numerator <= (others => '0');
        else
          numerator <= resize(in_d_c + shift_left(resize(side_data_regs(1).locsum, D+OMEGA+3), OMEGA), R);
          pred_s    <= to_signed(clip(to_integer(shift_right(numerator, OMEGA+1) + 1), -2**D, 2**D-1), D+1);
        end if;

        -- Propagate valid signal
        valid_regs(0) <= in_valid;
        valid_regs(1) <= valid_regs(0);
      end if;
    end if;
  end process;

  out_pred_s <= pred_s;
  out_valid  <= valid_regs(1);

  out_ctrl    <= side_data_regs(1).ctrl;
  out_z       <= side_data_regs(1).z;
  out_t       <= side_data_regs(1).t;
  out_s       <= side_data_regs(1).s;
  out_weights <= side_data_regs(1).weights;
  out_diffs   <= side_data_regs(1).diffs;
end rtl;