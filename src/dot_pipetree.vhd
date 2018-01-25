library IEEE;
use IEEE.NUMERIC_STD.all;

package sVec is
  type sVec is array(natural range <>) of signed;
end package sVec;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.sVec.all;

entity top is
  generic (
    N      : integer := 16;
    A_SIZE : integer := 12;
    B_SIZE : integer := 12
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    a       : in  sVec(N-1 downto 0)(A_SIZE-1 downto 0);
    a_valid : in  std_logic;
    b       : in  sVec(N-1 downto 0)(B_SIZE-1 downto 0);
    b_valid : in  std_logic;
    s       : out signed(A_SIZE + B_SIZE - 1 downto 0);
    s_valid : out std_logic
    );
end top;

architecture rtl of top is
  signal a_reg      : sVec(N-1 downto 0)(A_SIZE-1 downto 0);
  signal b_reg      : sVec(N-1 downto 0)(B_SIZE-1 downto 0);
  constant STAGES   : integer := integer(ceil(log2(real(N))));
  signal valid_regs : std_logic_vector(STAGES downto 0);
  signal sums       : sVec(2**(STAGES+1)-2 downto 0)(A_SIZE+B_SIZE-1 downto 0);
begin

  -- Generate the pipeline stages
  -- N is expanded to the closest power of two for the sake of simplicity.
  -- When N is not a power of 2, the elaboration phase will shred away unused
  -- multipliers and registers.
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        a_reg      <= (others => to_signed(0, A_SIZE));
        b_reg      <= (others => to_signed(0, B_SIZE));
        sums       <= (others => to_signed(0, A_SIZE+B_SIZE));
        valid_regs <= (others => '0');
      else
--        a_reg         <= a;
--        b_reg         <= b;
        valid_regs(0) <= a_valid and b_valid;

        for i in 0 to 2**STAGES-1 loop
          if (i < N) then
            sums(i) <= a(i) * b(i);
          else
            sums(i) <= to_signed(0, A_SIZE+B_SIZE);
          end if;
        end loop;

        for i in 0 to 2**STAGES-2 loop
          sums(2**STAGES + i) <= sums(2*i) + sums(2*i+1);
        end loop;

        for i in 1 to STAGES loop
          valid_regs(i) <= valid_regs(i-1);
        end loop;
      end if;
    end if;
  end process;

  -- The last index of the sums array is the final sum
  s       <= sums(sums'high);
  s_valid <= valid_regs(valid_regs'high);
end rtl;
