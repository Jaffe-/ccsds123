library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity sa_encoder is
  generic (
    NZ            : integer := 500;
    D             : integer := 12;
    UMAX          : integer := 9;
    COUNTER_SIZE  : integer := 8;
    INITIAL_COUNT : integer := 6
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid    : in std_logic;
    in_ctrl     : in ctrl_t;
    in_z        : in integer range 0 to NZ-1;
    in_residual : in unsigned(D-1 downto 0);

    accumulator_rd_z    : out integer range 0 to NZ-1;
    accumulator_rd_data : in  integer range 0 to 2**(D+COUNTER_SIZE)-1;
    accumulator_wr_z    : out integer range 0 to NZ-1;
    accumulator_wr_data : out integer range 0 to 2**(D+COUNTER_SIZE)-1;

    out_valid    : out std_logic;
    out_data     : out std_logic_vector(UMAX + D-1 downto 0);
    out_num_bits : out integer range 0 to UMAX + D
    );
end sa_encoder;

architecture rtl of sa_encoder is
  signal counter : integer range 0 to 2**COUNTER_SIZE-1;

  type z_arr_t is array (0 to 1) of integer range 0 to NZ-1;
  signal z_regs : z_arr_t;

  type residual_arr_t is array (0 to 2) of std_logic_vector(D-1 downto 0);
  signal residual_regs : residual_arr_t;

  type ctrl_arr_t is array (0 to 3) of ctrl_t;
  signal ctrl_regs : ctrl_arr_t;

  signal valid_regs : std_logic_vector(3 downto 0);

  signal rhs      : integer range 0 to 2**(D+COUNTER_SIZE+1)-1;
  signal rhs_part : integer range 0 to 2**COUNTER_SIZE-1;

  signal k_z           : integer range 0 to D-2;
  signal code_word     : std_logic_vector(UMAX + D - 1 downto 0);
  signal code_num_bits : integer range 0 to UMAX + D;
begin
  -- Counter and accumulator update
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        counter             <= 0;
        accumulator_wr_data <= 0;
      else
        if (in_valid = '1') then
          if (counter < 2**COUNTER_SIZE-1) then
            counter             <= counter + 1;
            accumulator_wr_data <= accumulator_rd_data + to_integer(in_residual);
          else
            counter             <= (counter + 1)/2;
            accumulator_wr_data <= (accumulator_rd_data + to_integer(in_residual) + 1)/2;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Pipeline
  process (clk)
    variable u_z : integer range 0 to 2**D-1;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        counter       <= 2**INITIAL_COUNT;
        rhs           <= 0;
        rhs_part      <= 0;
        z_regs        <= (others => 0);
        ctrl_regs     <= (others => ('0', '0', '0', '0'));
        residual_regs <= (others => (others => '0'));
        valid_regs    <= (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - Compute floor(49/2^7 * counter(t))
        --------------------------------------------------------------------------------
        rhs_part         <= (49 * counter) / 2**7;
        valid_regs(0)    <= in_valid;
        z_regs(0)        <= in_z;
        ctrl_regs(0)     <= in_ctrl;
        residual_regs(0) <= std_logic_vector(in_residual);

        --------------------------------------------------------------------------------
        -- Stage 2 - Compute right hand side in the inequalities for
        -- determining k_z(t)
        --------------------------------------------------------------------------------
        rhs              <= accumulator_rd_data + rhs_part;
        valid_regs(1)    <= valid_regs(0);
        z_regs(1)        <= z_regs(0);
        ctrl_regs(1)     <= ctrl_regs(0);
        residual_regs(1) <= residual_regs(0);

        --------------------------------------------------------------------------------
        -- Stage 3 - Compute k_z(t)
        --------------------------------------------------------------------------------
        if (2 * counter > rhs) then
          k_z <= 0;
        else
          k_z <= 0;
          for i in 1 to D - 2 loop
            if (counter * 2**i <= rhs) then
              k_z <= i;
            end if;
          end loop;
        end if;

        residual_regs(2) <= residual_regs(1);
        valid_regs(2)    <= valid_regs(1);
        ctrl_regs(2)     <= ctrl_regs(1);

        --------------------------------------------------------------------------------
        -- Stage 4 - Compute code word
        --------------------------------------------------------------------------------
        if (ctrl_regs(2).first_line = '1' and ctrl_regs(2).first_in_line = '1') then
          code_word     <= (code_word'high downto D => '0') & residual_regs(2);
          code_num_bits <= D;
        else
          for i in 0 to D - 2 loop
            if (k_z = i) then
              u_z := to_integer(unsigned(residual_regs(2))) / 2**i;
              if (u_z < UMAX) then
                code_word     <= (code_word'high downto i+1 => '0') & '1' & residual_regs(2)(i-1 downto 0);
                code_num_bits <= u_z + k_z + 1;
              else
                code_word     <= (code_word'high downto D => '0') & residual_regs(2);
                code_num_bits <= UMAX + D;
              end if;
            end if;
          end loop;
        end if;
        valid_regs(3) <= valid_regs(2);
        ctrl_regs(3)  <= ctrl_regs(2);
      end if;
    end if;
  end process;

  accumulator_rd_z <= in_z;
  out_valid        <= valid_regs(3);
  out_last         <= ctrl_regs(3).last;
  out_data         <= code_word;
  out_num_bits     <= code_num_bits;
end rtl;
