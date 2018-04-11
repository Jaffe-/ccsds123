library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

package common is
  type ctrl_t is record
    first_line     : std_logic;
    first_in_line  : std_logic;
    last_in_line   : std_logic;
    last           : std_logic;
    scale_exponent : integer range -6 to 9;
  end record ctrl_t;

  constant CTRL_ZERO : ctrl_t := ('0', '0', '0', '0', 0);

  function or_slv(slv : std_logic_vector) return std_logic;
  function clip(val : integer; val_min : integer; val_max : integer) return integer;
  function wrap_inc(val : integer; max : integer) return integer;
  function max(a : integer; b : integer) return integer;
  function len2bits(val : integer) return integer;
end common;

package body common is
  function or_slv(slv : std_logic_vector) return std_logic is
    variable val : std_logic;
  begin
    val := '0';
    for i in slv'range loop
      val := val or slv(i);
    end loop;
    return val;
  end function or_slv;

  function len2bits(val : integer) return integer is
  begin
    return integer(ceil(log2(real(val))));
  end len2bits;

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
