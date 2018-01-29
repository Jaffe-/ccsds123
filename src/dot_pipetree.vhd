library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

entity dot_product is
  generic (
    N      : integer := 16;
    A_SIZE : integer := 12;
    B_SIZE : integer := 12
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    a       : in  signed(N*A_SIZE-1 downto 0);
    a_valid : in  std_logic;
    b       : in  signed(N*B_SIZE-1 downto 0);
    b_valid : in  std_logic;
    s       : out signed(A_SIZE + B_SIZE - 1 downto 0);
    s_valid : out std_logic
    );
end dot_product;

architecture rtl of dot_product is
  constant STAGES   : integer := integer(ceil(log2(real(N))));
  signal valid_regs : std_logic_vector(STAGES downto 0);

  type s_vec_t is array(natural range <>) of signed(A_SIZE+B_SIZE-1 downto 0);
  signal sums : s_vec_t(2**(STAGES+1)-2 downto 0);
begin

  -- Generate the pipeline stages
  -- N is expanded to the closest power of two for the sake of simplicity.
  -- When N is not a power of 2, the elaboration phase will shred away unused
  -- multipliers and registers.
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        sums       <= (others => to_signed(0, A_SIZE+B_SIZE));
        valid_regs <= (others => '0');
      else
        valid_regs(0) <= a_valid and b_valid;

        for i in 0 to 2**STAGES-1 loop
          if (i < N) then
            sums(i) <= a((i+1)*A_SIZE-1 downto i*A_SIZE) * b((i+1)*B_SIZE-1 downto i*B_SIZE);
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
