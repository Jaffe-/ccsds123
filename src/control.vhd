library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

--------------------------------------------------------------------------------
-- Control signal generation
--
-- Keeps track of the current component's position in the cube and generates
-- the appropriate control signals that go along with the component through the
-- pipeline.
--
-- The control signals for component s_{x,y,z} are available in the same cycle.
--------------------------------------------------------------------------------

entity control is
  generic (
    V_MIN    : integer;
    V_MAX    : integer;
    TINC_LOG : integer;
    NX       : integer;
    NY       : integer;
    NZ       : integer;
    CZ       : integer;
    D        : integer
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    tick            : in  std_logic;
    w_upd_handshake : in  std_logic;
    ready           : out std_logic;

    out_ctrl : out ctrl_t;
    out_z    : out integer range 0 to NZ - 1
    );

end control;

architecture rtl of control is
  signal x : integer range 0 to NX-1;
  signal y : integer range 0 to NY-1;
  signal z : integer range 0 to NZ-1;
  signal t : integer range 0 to NX*NY-1;

  constant C_INCL_PIPE_CTRL : boolean := NZ < 3 + integer(ceil(log2(real(CZ)))) + 2 + 3;
begin
  -- Stall input if the pipeline is deeper than NZ, and we have filled up NZ
  -- components already
  --
  --  Local diff calculations: 3
  --  Dot product:             CZ
  --  Predictor:               2
  --  Weight update:           3
  g_pipe_ctrl : if (C_INCL_PIPE_CTRL) generate
    signal count : integer range 0 to NZ;
  begin
    process (clk)
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          count <= 0;
        else
          if (tick = '1' and w_upd_handshake = '0') then
            count <= count + 1;
          elsif (w_upd_handshake = '1' and tick = '0') then
            count <= count - 1;
          end if;
        end if;
      end if;
    end process;

    ready <= '1' when count < NZ else '0';
  end generate g_pipe_ctrl;

  g_nopipe_ctrl : if (not C_INCL_PIPE_CTRL) generate
    ready <= '1';
  end generate g_nopipe_ctrl;

  -- Component counting logic
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        x <= 0;
        y <= 0;
        z <= 0;
        t <= 0;
      else
        if (tick = '1') then
          if (z = Nz - 1) then
            z <= 0;
            t <= wrap_inc(t, NX*NY-1);
            if (x = Nx - 1) then
              x <= 0;
              if (y = Ny - 1) then
                y <= 0;
              else
                y <= y + 1;
              end if;
            else
              x <= x + 1;
            end if;
          else
            z <= z + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Create ctrl signals
  process (x, y, z, t)
    variable first_line     : std_logic;
    variable first_pix      : std_logic;
    variable last_pix       : std_logic;
    variable last           : std_logic;
    variable scale_exponent : integer range V_MIN to V_MAX;
  begin
    first_line := '0';
    first_pix  := '0';
    last_pix   := '0';
    last       := '0';
    if (y = 0) then
      first_line := '1';
    end if;

    if (x = 0) then
      first_pix := '1';
    elsif (x = NX - 1) then
      last_pix := '1';
      if (y = NY - 1 and z = NZ - 1) then
        last := '1';
      end if;
    end if;

    -- Perform clip(v_min + floor((t - NX)/2**TINC_LOG), {v_min, v_max})
    --
    -- Reformulated inequality to have only t on lhs and just constants on rhs,
    -- which improves synthesis results
    if (t >= 2**TINC_LOG*(V_MAX - V_MIN) + NX) then
      scale_exponent := V_MAX;
    elsif (t <= NX) then
      scale_exponent := V_MIN;
    else
      scale_exponent := V_MIN + (t - NX) / 2**TINC_LOG;
    end if;

    out_ctrl <= (first_line     => first_line,
                 first_in_line  => first_pix,
                 last_in_line   => last_pix,
                 last           => last,
                 scale_exponent => scale_exponent);
    out_z <= z;
  end process;
end rtl;

