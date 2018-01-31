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
    COL_ORIENTED : boolean := true;
    NX           : integer := 500;
    NY           : integer := 500;
    NZ           : integer := 100;
    CZ           : integer := 1;
    D            : integer := 12
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    s_cur : in signed(D-1 downto 0);
    s_ne  : in signed(D-1 downto 0);
    s_n   : in signed(D-1 downto 0);
    s_nw  : in signed(D-1 downto 0);
    s_w   : in signed(D-1 downto 0);

    in_valid : in std_logic;
    in_ctrl  : in ctrl_t;
    in_t     : in integer range 0 to NX*NY-1;
    in_z     : in integer range 0 to NZ-1;

    local_sum : out signed(D+2 downto 0);
    d_c       : out signed(D+2 downto 0);
    d_n       : out signed(D+2 downto 0);
    d_nw      : out signed(D+2 downto 0);
    d_w       : out signed(D+2 downto 0);

    out_valid : out std_logic;
    out_ctrl  : out ctrl_t;
    out_t     : out integer range 0 to NX*NY-1;
    out_z     : out integer range 0 to NZ-1;
    out_s     : out signed(D-1 downto 0)
    );
end local_diff;

architecture rtl of local_diff is
  signal local_sum_reg : integer range -2**(D+2) to 2**(D+2)-1;

  -- Registers to keep control signals in sync with data
  signal valid_reg : std_logic;
  signal ctrl_reg  : ctrl_t;
  signal t_reg     : integer range 0 to NX*NY-1;
  signal z_reg     : integer range 0 to NZ-1;
  signal s_reg     : signed(D-1 downto 0);

  subtype sample_range is integer range -2**(D-1) to 2**(D-1)-1;
  signal s_cur_reg : sample_range;
  signal s_n_reg   : sample_range;
  signal s_nw_reg  : sample_range;
  signal s_w_reg   : sample_range;
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
        local_sum_reg <= 0;
        d_c           <= to_signed(0, D+3);
        d_n           <= to_signed(0, D+3);
        d_w           <= to_signed(0, D+3);
        d_nw          <= to_signed(0, D+3);
        valid_reg     <= '0';
        ctrl_reg      <= ('0', '0', '0', '0');
        t_reg         <= 0;
        z_reg         <= 0;
        s_reg         <= (others => '0');
        s_cur_reg     <= 0;
        s_n_reg       <= 0;
        s_nw_reg      <= 0;
        s_w_reg       <= 0;
      else
        s_cur_i := to_integer(signed(s_cur));
        s_n_i   := to_integer(signed(s_n));
        s_nw_i  := to_integer(signed(s_nw));
        s_w_i   := to_integer(signed(s_w));
        s_ne_i  := to_integer(signed(s_ne));

        --------------------------------------------------------------------------------
        -- Stage 1 - Compute local sum
        --------------------------------------------------------------------------------
        if (COL_ORIENTED) then
          if (in_ctrl.first_line = '0') then
            local_sum_reg <= 4 * s_n_i;
          else
            local_sum_reg <= 4 * s_w_i;
          end if;
        else
          if (in_ctrl.first_line = '0' and in_ctrl.first_in_line = '0' and in_ctrl.last_in_line = '0') then
            local_sum_reg <= s_w_i + s_nw_i + s_n_i + s_ne_i;
          elsif (in_ctrl.first_line = '1' and in_ctrl.first_in_line = '0') then
            local_sum_reg <= 4 * s_w_i;
          elsif (in_ctrl.first_line = '0' and in_ctrl.first_in_line = '1') then
            local_sum_reg <= 2 * s_n_i + 2 * s_ne_i;
          elsif (in_ctrl.first_line = '0' and in_ctrl.last_in_line = '1') then
            local_sum_reg <= s_w_i + s_nw_i + 2 * s_n_i;
          end if;
        end if;

        valid_reg <= in_valid;
        ctrl_reg  <= in_ctrl;
        t_reg     <= in_t;
        z_reg     <= in_z;
        s_reg     <= s_cur;
        s_cur_reg <= s_cur_i;
        s_n_reg   <= s_n_i;
        s_nw_reg  <= s_nw_i;
        s_w_reg   <= s_w_i;

        --------------------------------------------------------------------------------
        -- Stage 2 - Compute local differences
        --------------------------------------------------------------------------------

        -- Central local difference
        if (ctrl_reg.first_line = '1' and ctrl_reg.first_in_line = '1') then
          d_c       <= to_signed(0, D+3);
          local_sum <= to_signed(0, D+3);
        else
          d_c       <= to_signed(4 * s_cur_reg - local_sum_reg, D+3);
          local_sum <= to_signed(local_sum_reg, D+3);
        end if;

        -- Directional local differences
        if (ctrl_reg.first_line = '0') then
          d_n <= to_signed(4 * s_n_reg - local_sum_reg, D+3);
        else
          d_n <= to_signed(0, D+3);
        end if;

        if (ctrl_reg.first_in_line = '0' and ctrl_reg.first_line = '0') then
          d_w  <= to_signed(4 * s_w_reg - local_sum_reg, D+3);
          d_nw <= to_signed(4 * s_nw_reg - local_sum_reg, D+3);
        elsif (ctrl_reg.first_in_line = '1' and ctrl_reg.first_line = '0') then
          d_w  <= to_signed(4 * s_n_reg - local_sum_reg, D+3);
          d_nw <= to_signed(4 * s_n_reg - local_sum_reg, D+3);
        else
          d_w  <= to_signed(0, D+3);
          d_nw <= to_signed(0, D+3);
        end if;

        out_valid <= valid_reg;
        out_ctrl  <= ctrl_reg;
        out_t     <= t_reg;
        out_z     <= z_reg;
        out_s     <= s_reg;
      end if;
    end if;
  end process;

end rtl;

