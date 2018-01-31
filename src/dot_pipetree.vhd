library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity dot_product is
  generic (
    N      : integer := 16;
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
    s       : out signed(A_SIZE + B_SIZE - 1 downto 0);
    s_valid : out std_logic;

    in_locsum  : in signed(D+2 downto 0);
    in_ctrl    : in ctrl_t;
    in_z       : in integer range 0 to NZ-1;
    in_t       : in integer range 0 to NX*NY-1;
    in_s       : in signed(D-1 downto 0);
    in_weights : in signed(CZ*(OMEGA+3)-1 downto 0);
    in_diffs   : in signed(CZ*(D+3)-1 downto 0);

    out_locsum  : out signed(D+2 downto 0);
    out_ctrl    : out ctrl_t;
    out_z       : out integer range 0 to NZ-1;
    out_t       : out integer range 0 to NX*NY-1;
    out_s       : out signed(D-1 downto 0);
    out_weights : out signed(CZ*(OMEGA+3)-1 downto 0);
    out_diffs   : out signed(CZ*(D+3)-1 downto 0)
    );
end dot_product;

architecture rtl of dot_product is
  constant STAGES   : integer := integer(ceil(log2(real(N))));
  signal valid_regs : std_logic_vector(STAGES downto 0);

  type side_data_t is record
    ctrl    : ctrl_t;
    z       : integer range 0 to NZ-1;
    t       : integer range 0 to NX*NY-1;
    s       : signed(D-1 downto 0);
    weights : signed(CZ*(OMEGA+3)-1 downto 0);
    diffs   : signed(CZ*(D+3)-1 downto 0);
    locsum  : signed(D+2 downto 0);
  end record side_data_t;

  type side_data_arr_t is array (0 to STAGES) of side_data_t;

  signal side_data_regs : side_data_arr_t;

  type s_vec_t is array(0 to 2**(STAGES+1)-2) of signed(A_SIZE+B_SIZE-1 downto 0);
  signal sums : s_vec_t;
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
        side_data_regs(0) <= (
          ctrl    => in_ctrl,
          z       => in_z,
          t       => in_t,
          s       => in_s,
          weights => in_weights,
          diffs   => in_diffs,
          locsum  => in_locsum);
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

        For i in 1 to STAGES loop
          valid_regs(i)     <= valid_regs(i-1);
          side_data_regs(i) <= side_data_regs(i-1);
        end loop;
      end if;
    end if;
  end process;

  -- The last index of the sums array is the final sum
  s       <= sums(sums'high);
  s_valid <= valid_regs(STAGES);

  out_ctrl    <= side_data_regs(STAGES).ctrl;
  out_z       <= side_data_regs(STAGES).z;
  out_t       <= side_data_regs(STAGES).t;
  out_s       <= side_data_regs(STAGES).s;
  out_weights <= side_data_regs(STAGES).weights;
  out_diffs   <= side_data_regs(STAGES).diffs;
  out_locsum  <= side_data_regs(STAGES).locsum;
end rtl;
