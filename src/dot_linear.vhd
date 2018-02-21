library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity dot_product is
  generic (
    N      : integer := 4;
    A_SIZE : integer := 12;
    B_SIZE : integer := 12;
    NX     : integer := 500;
    NY     : integer := 500;
    NZ     : integer := 100;
    D      : integer := 8;
    CZ     : integer := 4;
    OMEGA  : integer := 10
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    a       : in  signed(N*A_SIZE-1 downto 0);
    a_valid : in  std_logic;
    b       : in  signed(N*B_SIZE-1 downto 0);
    b_valid : in  std_logic;
    s       : out signed(A_SIZE + B_SIZE + N - 1 - 1 downto 0);
    s_valid : out std_logic;

    in_locsum  : in signed(D+2 downto 0);
    in_ctrl    : in ctrl_t;
    in_z       : in integer range 0 to NZ-1;
    in_s       : in signed(D-1 downto 0);
    in_weights : in signed(CZ*(OMEGA+3)-1 downto 0);
    in_diffs   : in signed(CZ*(D+3)-1 downto 0);

    out_locsum  : out signed(D+2 downto 0);
    out_ctrl    : out ctrl_t;
    out_z       : out integer range 0 to NZ-1;
    out_s       : out signed(D-1 downto 0);
    out_weights : out signed(CZ*(OMEGA+3)-1 downto 0);
    out_diffs   : out signed(CZ*(D+3)-1 downto 0)
    );
end dot_product;

architecture rtl of dot_product is
  constant STAGES   : integer := N;
  signal valid_regs : std_logic_vector(STAGES downto 0);

  type side_data_t is record
    ctrl    : ctrl_t;
    z       : integer range 0 to NZ-1;
    s       : signed(D-1 downto 0);
    weights : signed(CZ*(OMEGA+3)-1 downto 0);
    diffs   : signed(CZ*(D+3)-1 downto 0);
    locsum  : signed(D+2 downto 0);
  end record side_data_t;

  type side_data_arr_t is array (0 to STAGES) of side_data_t;

  signal side_data_regs : side_data_arr_t;

  type s_vec_t is array(0 to STAGES) of signed(A_SIZE+B_SIZE+N-1-1 downto 0);
  type a_arr_t is array(1 to STAGES-1, 0 to STAGES-1) of signed(A_SIZE-1 downto 0);
  type b_arr_t is array(1 to STAGES-1, 0 to STAGES-1) of signed(B_SIZE-1 downto 0);
  signal sums     : s_vec_t;
  signal a_delays : a_arr_t;
  signal b_delays : b_arr_t;
begin

  -- Generate the pipeline stages
  -- N is expanded to the closest power of two for the sake of simplicity.
  -- When N is not a power of 2, the elaboration phase will shred away unused
  -- multipliers and registers.
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        sums           <= (others => to_signed(0, A_SIZE+B_SIZE+N-1));
        a_delays       <= (others => (others => to_signed(0, A_SIZE)));
        b_delays       <= (others => (others => to_signed(0, B_SIZE)));
        valid_regs     <= (others => '0');
      else
        side_data_regs(0) <= (
          ctrl    => in_ctrl,
          z       => in_z,
          s       => in_s,
          weights => in_weights,
          diffs   => in_diffs,
          locsum  => in_locsum);
        valid_regs(0) <= a_valid and b_valid;

        sums(0) <= resize(a(A_SIZE-1 downto 0) * b(B_SIZE-1 downto 0), A_SIZE+B_SIZE+N-1);
        for i in 1 to STAGES-1 loop
          a_delays(i, 0) <= a((i+1)*A_SIZE-1 downto i*A_SIZE);
          b_delays(i, 0) <= b((i+1)*B_SIZE-1 downto i*B_SIZE);

          sums(i)           <= sums(i-1) + a_delays(i, i-1) * b_delays(i, i-1);
          valid_regs(i)     <= valid_regs(i-1);
          side_data_regs(i) <= side_data_regs(i-1);

          for j in 1 to i loop
            a_delays(i, j) <= a_delays(i, j-1);
            b_delays(i, j) <= b_delays(i, j-1);
          end loop;
        end loop;
      end if;
    end if;
  end process;

  -- The last index of the sums array is the final sum
  s       <= sums(STAGES-1);
  s_valid <= valid_regs(STAGES-1);

  out_ctrl    <= side_data_regs(STAGES-1).ctrl;
  out_z       <= side_data_regs(STAGES-1).z;
  out_s       <= side_data_regs(STAGES-1).s;
  out_weights <= side_data_regs(STAGES-1).weights;
  out_diffs   <= side_data_regs(STAGES-1).diffs;
  out_locsum  <= side_data_regs(STAGES-1).locsum;
end rtl;
