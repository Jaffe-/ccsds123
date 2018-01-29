library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

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
    NX : integer := 500;
    NY : integer := 500;
    NZ : integer := 100;
    D  : integer := 12
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    tick : in std_logic;

    out_ctrl : out ctrl_t;
    out_z    : out integer range 0 to NZ - 1;
    out_t    : out integer range 0 to NX*NY - 1
    );

end control;

architecture rtl of control is
  signal x : integer range 0 to NX-1;
  signal y : integer range 0 to NY-1;
  signal z : integer range 0 to NZ-1;
  signal t : integer range 0 to NX*NY-1;
begin

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
            t <= t + 1;
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
    variable first_line : std_logic;
    variable first_pix  : std_logic;
    variable last_pix   : std_logic;
    variable last       : std_logic;
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

    out_ctrl <= (first_line    => first_line,
                 first_in_line => first_pix,
                 last_in_line  => last_pix,
                 last          => last);
    out_z <= z;
    out_t <= t;
  end process;
end rtl;

