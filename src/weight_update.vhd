library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity weight_update is
  generic (
    NX    : integer := 500;
    NY    : integer := 500;
    NZ    : integer := 100;
    OMEGA : integer := 8;
    D     : integer := 8;
    R     : integer := 16;
    V_MIN : integer := -6;
    V_MAX : integer := 9;
    CZ    : integer := 4
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_ctrl    : in ctrl_t;
    in_z       : in integer range 0 to NZ-1;
    in_s       : in signed(D-1 downto 0);
    in_pred_s  : in signed(D downto 0);
    in_diffs   : in signed((D+3)*CZ-1 downto 0);
    in_valid   : in std_logic;
    in_weights : in signed(CZ*(OMEGA+3)-1 downto 0);

    out_valid   : out std_logic;
    out_z       : out integer range 0 to NZ-1;
    out_weights : out signed(CZ*(OMEGA+3)-1 downto 0)
    );
end weight_update;

architecture rtl of weight_update is
  signal sgn_error      : std_logic;

  type diff_vec_t is array (0 to CZ-1) of signed(D+2 downto 0);
  type weight_vec_t is array(0 to CZ-1) of signed(OMEGA+2 downto 0);
  type weight_arr_t is array(0 to 1) of weight_vec_t;
  signal diff_vec       : diff_vec_t;
  signal weight_vec     : weight_vec_t;
  signal diff_regs      : diff_vec_t;
  signal weight_regs    : weight_arr_t;
  signal new_weight_vec : weight_vec_t;

  type mux_arr_t is array (0 to CZ-1) of signed(D+2+4 downto 0);
  signal mux_reg : mux_arr_t;

  signal valid_regs : std_logic_vector(2 downto 0);

  type z_arr_t is array (0 to 2) of integer range 0 to NZ-1;
  signal z_regs : z_arr_t;

  type ctrl_arr_t is array (0 to 1) of ctrl_t;
  signal ctrl_regs : ctrl_arr_t;

  -- Function for initializing weights at t = 0
  function init_weight_vec return weight_vec_t is
    variable weight_vec : weight_vec_t;
  begin
    weight_vec(0) := to_signed(7 * (2**OMEGA / 8), OMEGA+3);
    for i in 1 to CZ-4 loop
      weight_vec(i) := to_signed(to_integer(weight_vec(i-1) / 8), OMEGA+3);
    end loop;
    weight_vec(CZ-3) := to_signed(0, OMEGA+3);
    weight_vec(CZ-2) := to_signed(0, OMEGA+3);
    weight_vec(CZ-1) := to_signed(0, OMEGA+3);
    return weight_vec;
  end function init_weight_vec;

begin
  process (in_diffs, in_weights)
  begin
    for i in 0 to CZ-1 loop
      diff_vec(i)   <= in_diffs((D+3)*(i+1)-1 downto (D+3)*i);
      weight_vec(i) <= in_weights((OMEGA+3)*(i+1)-1 downto (OMEGA+3)*i);
    end loop;
  end process;

  process (clk)
    variable numerator  : signed(integer(ceil(log2(real(NX*NY+NX))))-1 downto 0);
    variable increment  : integer range 0 to V_MAX - V_MIN;
    variable pred_error : signed(D+1 downto 0);

    variable mux_temp : mux_arr_t;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        sgn_error      <= '0';
        diff_regs      <= (others => (others => '0'));
        weight_regs    <= (others => (others => (others => '0')));
        valid_regs     <= (others => '0');
        z_regs         <= (others => 0);
        ctrl_regs      <= (others => ('0', '0', '0', '0', 0));
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - calculate scaling exponent and prediction error
        --------------------------------------------------------------------------------
        weight_regs(0)     <= weight_vec;
        valid_regs(0)      <= in_valid;
        z_regs(0)          <= in_z;
        ctrl_regs(0)       <= in_ctrl;

        -- Compute sgn(e_z(t)) * U(t) for each component
        if (2*to_integer(in_s) >= to_integer(in_pred_s)) then
          for i in 0 to CZ-1 loop
            diff_regs(i) <= diff_vec(i);
          end loop;
        else
          for i in 0 to CZ-1 loop
            diff_regs(i) <= -diff_vec(i);
          end loop;
        end if;

        --------------------------------------------------------------------------------
        -- Stage 2 - compute 0.5[sgn(e(z))*2^(-p(t))*U(t) + 1] for each
        -- component in parallel
        --------------------------------------------------------------------------------
        weight_regs(1) <= weight_regs(0);
        valid_regs(1)  <= valid_regs(0);
        z_regs(1)      <= z_regs(0);
        ctrl_regs(1)   <= ctrl_regs(0);

        for comp in 0 to CZ-1 loop
          for i in V_MIN + D - OMEGA to V_MAX + D - OMEGA loop
            if (ctrl_regs(0).scale_exponent = i - (D - OMEGA)) then
              -- p(t) is positive, meaning that the exponent -p(t) is NEGATIVE,
              -- and shifting is to the right
              if (i > 0) then
                mux_temp(comp) := resize(shift_right(diff_regs(comp), i), mux_temp(0)'length);
              elsif (i = 0) then
                mux_temp(comp) := resize(diff_regs(comp), mux_temp(0)'length);
              elsif (i < 0) then
                mux_temp(comp) := shift_left(resize(diff_regs(comp), mux_temp(0)'length), -i);
              end if;
            end if;
          end loop;
          mux_reg(comp) <= shift_right(mux_temp(comp) + to_signed(1, 2), 1);

        end loop;

        --------------------------------------------------------------------------------
        -- Stage 3 - compute W(t+1) = clip(W(t) + mux_reg)
        --------------------------------------------------------------------------------
        valid_regs(2) <= valid_regs(1);
        z_regs(2)     <= z_regs(1);

        if (ctrl_regs(1).first_line = '1' and ctrl_regs(1).first_in_line = '1') then
          new_weight_vec <= init_weight_vec;
        else
          for comp in 0 to CZ-1 loop
            new_weight_vec(comp) <= to_signed(clip(to_integer(weight_regs(1)(comp)) + to_integer(mux_reg(comp)),
                                                   -2**(OMEGA+2), 2**(OMEGA+2)-1), OMEGA+3);
          end loop;
        end if;
      end if;
    end if;
  end process;

  process (new_weight_vec)
  begin
    for i in 0 to CZ-1 loop
      out_weights((OMEGA+3)*(i+1)-1 downto (OMEGA+3)*i) <= new_weight_vec(i);
    end loop;
  end process;
  out_valid <= valid_regs(2);
  out_z     <= z_regs(2);
end rtl;
