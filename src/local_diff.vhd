library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

use work.common.all;

--------------------------------------------------------------------------------
-- Local sum and difference computations
--
-- The local sum and differences are computed in a two step pipeline
--------------------------------------------------------------------------------

entity local_diff is
  generic (
    COL_ORIENTED : boolean;
    NZ           : integer;
    D            : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    s_cur : in signed(D-1 downto 0);
    s_ne  : in signed(D-1 downto 0);
    s_n   : in signed(D-1 downto 0);
    s_nw  : in signed(D-1 downto 0);
    s_w   : in signed(D-1 downto 0);

    in_valid  : in std_logic;
    in_ctrl   : in ctrl_t;
    in_z      : in integer range 0 to NZ-1;
    in_prev_s : in signed(D-1 downto 0);

    local_sum : out signed(D+2 downto 0);
    d_c       : out signed(D+2 downto 0);
    d_n       : out signed(D+2 downto 0);
    d_nw      : out signed(D+2 downto 0);
    d_w       : out signed(D+2 downto 0);

    out_valid  : out std_logic;
    out_ctrl   : out ctrl_t;
    out_z      : out integer range 0 to NZ-1;
    out_s      : out signed(D-1 downto 0);
    out_prev_s : out signed(D-1 downto 0)
    );
end local_diff;

architecture rtl of local_diff is
  signal local_sum_reg   : integer range -2**(D+2) to 2**(D+2)-1;
  signal local_sum_term1 : integer range -2**(D+2) to 2**(D+2)-1;
  signal local_sum_term2 : integer range -2**(D+2) to 2**(D+2)-1;

  -- Registers to keep control signals in sync with data
  type side_data_t is record
    ctrl   : ctrl_t;
    z      : integer range 0 to NZ-1;
    s      : signed(D-1 downto 0);
    prev_s : signed(D-1 downto 0);
  end record side_data_t;

  type side_data_arr_t is array(0 to 2) of side_data_t;
  signal side_data_regs : side_data_arr_t;
  signal valid_regs     : std_logic_vector(2 downto 0);

  subtype sample_range is integer range -2**(D-1) to 2**(D-1)-1;
  type sample_arr_t is array(0 to 1) of sample_range;

  signal s_cur_regs : sample_arr_t;
  signal s_n_regs   : sample_arr_t;
  signal s_nw_regs  : sample_arr_t;
  signal s_w_regs   : sample_arr_t;
begin

  process (clk)
    variable s_cur_i : sample_range;
    variable s_n_i   : sample_range;
    variable s_nw_i  : sample_range;
    variable s_w_i   : sample_range;
    variable s_ne_i  : sample_range;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        valid_regs <= (others => '0');
      else
        s_cur_i := to_integer(signed(s_cur));
        s_n_i   := to_integer(signed(s_n));
        s_nw_i  := to_integer(signed(s_nw));
        s_w_i   := to_integer(signed(s_w));
        s_ne_i  := to_integer(signed(s_ne));

        --------------------------------------------------------------------------------
        -- Stage 1 - Compute terms in local sum
        --------------------------------------------------------------------------------
        local_sum_term2 <= 0;
        if (COL_ORIENTED) then
          if (in_ctrl.first_line = '0') then
            local_sum_term1 <= 4 * s_n_i;
          else
            local_sum_term1 <= 4 * s_w_i;
          end if;
        else
          if (in_ctrl.first_line = '0' and in_ctrl.first_in_line = '0' and in_ctrl.last_in_line = '0') then
            local_sum_term1 <= s_w_i + s_nw_i;
            local_sum_term2 <= s_n_i + s_ne_i;
          elsif (in_ctrl.first_line = '1' and in_ctrl.first_in_line = '0') then
            local_sum_term1 <= 4 * s_w_i;
          elsif (in_ctrl.first_line = '0' and in_ctrl.first_in_line = '1') then
            local_sum_term1 <= 2 * s_n_i;
            local_sum_term2 <= 2 * s_ne_i;
          elsif (in_ctrl.first_line = '0' and in_ctrl.last_in_line = '1') then
            local_sum_term1 <= s_w_i + s_nw_i;
            local_sum_term2 <= 2 * s_n_i;
          end if;
        end if;

        side_data_regs(0) <= (
          ctrl   => in_ctrl,
          z      => in_z,
          s      => s_cur,
          prev_s => in_prev_s);

        valid_regs(0) <= in_valid;

        s_cur_regs(0) <= s_cur_i;
        s_n_regs(0)   <= s_n_i;
        s_nw_regs(0)  <= s_nw_i;
        s_w_regs(0)   <= s_w_i;

        --------------------------------------------------------------------------------
        -- Stage 2 - Compute local sum from the two terms from previous stage
        --------------------------------------------------------------------------------
        side_data_regs(1) <= side_data_regs(0);
        valid_regs(1)     <= valid_regs(0);

        local_sum_reg <= local_sum_term1 + local_sum_term2;
        s_cur_regs(1) <= s_cur_regs(0);
        s_n_regs(1)   <= s_n_regs(0);
        s_nw_regs(1)  <= s_nw_regs(0);
        s_w_regs(1)   <= s_w_regs(0);

        --------------------------------------------------------------------------------
        -- Stage 3 - Compute local differences
        --------------------------------------------------------------------------------

        -- Central local difference
        if (side_data_regs(1).ctrl.first_line = '1' and side_data_regs(1).ctrl.first_in_line = '1') then
          d_c       <= to_signed(0, D+3);
          local_sum <= to_signed(0, D+3);
        else
          d_c       <= to_signed(4 * s_cur_regs(1) - local_sum_reg, D+3);
          local_sum <= to_signed(local_sum_reg, D+3);
        end if;

        -- Directional local differences
        if (side_data_regs(1).ctrl.first_line = '0') then
          d_n <= to_signed(4 * s_n_regs(1) - local_sum_reg, D+3);
        else
          d_n <= to_signed(0, D+3);
        end if;

        if (side_data_regs(1).ctrl.first_in_line = '0' and side_data_regs(1).ctrl.first_line = '0') then
          d_w  <= to_signed(4 * s_w_regs(1) - local_sum_reg, D+3);
          d_nw <= to_signed(4 * s_nw_regs(1) - local_sum_reg, D+3);
        elsif (side_data_regs(1).ctrl.first_in_line = '1' and side_data_regs(1).ctrl.first_line = '0') then
          d_w  <= to_signed(4 * s_n_regs(1) - local_sum_reg, D+3);
          d_nw <= to_signed(4 * s_n_regs(1) - local_sum_reg, D+3);
        else
          d_w  <= to_signed(0, D+3);
          d_nw <= to_signed(0, D+3);
        end if;

        side_data_regs(2) <= side_data_regs(1);
        valid_regs(2)     <= valid_regs(1);
      end if;
    end if;
  end process;

  out_valid  <= valid_regs(2);
  out_ctrl   <= side_data_regs(2).ctrl;
  out_z      <= side_data_regs(2).z;
  out_s      <= side_data_regs(2).s;
  out_prev_s <= side_data_regs(2).prev_s;
end rtl;

