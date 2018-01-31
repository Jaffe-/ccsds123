library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity w_upd_tb is
end w_upd_tb;

architecture rtl of w_upd_tb is
  constant COL_ORIENTED : boolean := false;
  constant OMEGA        : integer := 8;
  constant CZ           : integer := 7;
  constant D            : integer := 8;
  constant P            : integer := 4;
  constant R            : integer := 32;
  constant NX           : integer := 500;
  constant NY           : integer := 500;
  constant NZ           : integer := 100;

  signal clk     : std_logic := '0';
  signal aresetn : std_logic := '0';

  signal in_ctrl     : ctrl_t;
  signal in_t        : integer range 0 to NX*NY-1;
  signal in_z        : integer range 0 to NZ-1;
  signal in_s        : signed(D-1 downto 0);
  signal in_pred_s   : signed(D downto 0);
  signal in_diffs    : signed((D+3)*CZ-1 downto 0);
  signal in_valid    : std_logic;
  signal in_weights  : signed(CZ*(OMEGA+3)-1 downto 0);
  signal out_valid   : std_logic;
  signal out_z       : integer range 0 to NZ-1;
  signal out_weights : signed(CZ*(OMEGA+3)-1 downto 0);

  type vec_t is array (natural range <>) of integer;

  signal diff_vec   : vec_t(0 to CZ-1) := (1, 2, 3, 4, 5, 6, 7);
  signal weight_vec : vec_t(0 to CZ-1) := (1, 2, 3, 4, 5, 6, 7);

  function int_to_sgn_vec(int_in : vec_t; EL_SIZE : integer) return signed is
    variable sgn : signed(int_in'length*EL_SIZE-1 downto 0);
  begin
    for i in 0 to int_in'high loop
      sgn((i+1)*(D+3)-1 downto i*(D+3)) := to_signed(int_in(i), EL_SIZE);
    end loop;
    return sgn;
  end function int_to_sgn_vec;

begin
  i_dut : entity work.weight_update
    generic map (
      NX    => NX,
      NY    => NY,
      NZ    => NZ,
      OMEGA => OMEGA,
      D     => D,
      R     => R,
      V_MIN => -6,
      V_MAX => 9,
      CZ    => CZ)
    port map (
      clk         => clk,
      aresetn     => aresetn,
      in_ctrl     => in_ctrl,
      in_t        => in_t,
      in_z        => in_z,
      in_s        => in_s,
      in_pred_s   => in_pred_s,
      in_diffs    => in_diffs,
      in_valid    => in_valid,
      in_weights  => in_weights,
      out_valid   => out_valid,
      out_z       => out_z,
      out_weights => out_weights);

  process
  begin
    wait for 5ns;
    clk <= not clk;
  end process;

  process
  begin
    aresetn    <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    aresetn    <= '1';
    wait until rising_edge(clk);
    in_ctrl    <= ('1', '0', '0', '0');
    in_z       <= 0;
    in_t       <= NX;
    in_s       <= to_signed(100, in_s'length);
    in_pred_s  <= to_signed(51, in_pred_s'length);
    in_diffs   <= int_to_sgn_vec(diff_vec, D+3);
    in_weights <= int_to_sgn_vec(weight_vec, OMEGA+3);
    in_valid <= '1';
    wait until rising_edge(clk);
    in_valid <= '0';
    wait;
  end process;

end rtl;
