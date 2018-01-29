library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;

entity dot_tb is
end dot_tb;

architecture rtl of dot_tb is
  constant N_TEST : integer := 3;
  constant N      : integer := 5;
  constant A_SIZE : integer := 12;
  constant B_SIZE : integer := 12;

  signal clk     : std_logic := '0';
  signal aresetn : std_logic := '0';

  signal a       : signed(N*A_SIZE-1 downto 0);
  signal a_valid : std_logic;
  signal b       : signed(N*B_SIZE-1 downto 0);
  signal b_valid : std_logic;
  signal s       : signed(A_SIZE+B_SIZE-1 downto 0);
  signal s_valid : std_logic;

  type intarr_t is array(natural range <>) of integer;
  type testvec_t is array(natural range <>) of intarr_t(N-1 downto 0);
  signal testvec_a : testvec_t(N_TEST-1 downto 0) := (
    (0, 0, 0, 0, 0),
    (1, 2, 3, 4, 5),
    (9, 3, 4, 2, 1));
  signal testvec_b : testvec_t(N_TEST-1 downto 0) := (
    (0, 0, 0, 0, 0),
    (1, 2, 3, 4, 5),
    (9, 3, 4, 2, 1));
begin
  i_dot : entity work.dot_product
    generic map (
      N      => N,
      A_SIZE => A_SIZE,
      B_SIZE => B_SIZE)
    port map (
      clk     => clk,
      aresetn => aresetn,
      a       => a,
      a_valid => a_valid,
      b       => b,
      b_valid => b_valid,
      s       => s,
      s_valid => s_valid);

  process
  begin
    wait for 5ns;
    clk <= not clk;
  end process;

  process
  begin
    aresetn <= '0';
    wait for 25ns;
    aresetn <= '1';
    wait;
  end process;

  process
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    for i in 0 to N_TEST-1 loop
      for j in 0 to N-1 loop
        a((j+1)*A_SIZE-1 downto j*A_SIZE) <= to_signed(testvec_a(i)(j), A_SIZE);
        b((j+1)*B_SIZE-1 downto j*B_SIZE) <= to_signed(testvec_b(i)(j), B_SIZE);
      end loop;
      a_valid <= '1';
      b_valid <= '1';
      wait until rising_edge(clk);
    end loop;
    wait;
  end process;
end rtl;
