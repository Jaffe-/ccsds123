library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

package common is
  --constant NX : integer := 4;
  --constant NY : integer := 4;
  --constant NZ : integer := 8;

  --constant P  : integer := 2;
  --constant CZ : integer := P + 3;

  --constant D            : integer := 8;
  --constant R            : integer := 16;
  --constant OMEGA        : integer := 4;

  --constant COL_ORIENTED : boolean := false;

  type ctrl_t is record
    first_line     : std_logic;
    first_in_line  : std_logic;
    last_in_line   : std_logic;
    last           : std_logic;
    scale_exponent : integer range -6 to 9;
  end record ctrl_t;

  function clip(val     : integer; val_min : integer; val_max : integer) return integer;
  function wrap_inc(val : integer; max : integer) return integer;
  function max(a : integer; b : integer) return integer;
end common;

package body common is
  function clip(val : integer; val_min : integer; val_max : integer) return integer is
  begin
    if (val < val_min) then
      return val_min;
    elsif (val > val_max) then
      return val_max;
    else
      return val;
    end if;
  end clip;

  function wrap_inc(val : integer; max : integer) return integer is
  begin
    if (val + 1 > max) then
      return 0;
    else
      return val + 1;
    end if;
  end wrap_inc;

  function max(a : integer; b : integer) return integer is
  begin
    if (a > b) then
      return a;
    else
      return b;
    end if;
  end max;
end common;
