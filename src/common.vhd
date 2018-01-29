library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

package common is
  type ctrl_t is record
    first_line    : std_logic;
    first_in_line : std_logic;
    last_in_line  : std_logic;
    last          : std_logic;
  end record ctrl_t;

  function clip(val : integer; val_min : integer; val_max : integer) return integer;
  function sgn(val : integer) return integer;
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

  function sgn(val : integer) return integer is
  begin
    if (val >= 0) then
      return 1;
    else
      return -1;
    end if;
  end sgn;

end common;
