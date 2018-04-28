library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity sa_encoder is
  generic (
    PIPELINES     : integer;
    NZ            : integer;
    D             : integer;
    UMAX          : integer;
    KZ_PRIME      : integer;
    COUNTER_SIZE  : integer;
    INITIAL_COUNT : integer
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid    : in std_logic;
    in_ctrl     : in ctrl_t;
    in_z        : in integer range 0 to NZ-1;
    in_residual : in unsigned(D-1 downto 0);

    accumulator_rd_data : in  std_logic_vector(D+COUNTER_SIZE-1 downto 0);
    accumulator_wr      : out std_logic;
    accumulator_wr_data : out std_logic_vector(D+COUNTER_SIZE-1 downto 0);

    out_valid    : out std_logic;
    out_last     : out std_logic;
    out_data     : out std_logic_vector(UMAX + D-1 downto 0);
    out_num_bits : out unsigned(num2bits(UMAX + D) - 1 downto 0)
    );
end sa_encoder;

architecture rtl of sa_encoder is
  signal counter : integer range 0 to 2**COUNTER_SIZE-1;

  type counter_arr_t is array(0 to 1) of integer range 0 to 2**COUNTER_SIZE-1;
  signal counter_regs : counter_arr_t;

  type residual_arr_t is array (0 to 3) of std_logic_vector(D-1 downto 0);
  signal residual_regs      : residual_arr_t;
  signal k_shifted_residual : std_logic_vector(D-1 downto 0);

  type ctrl_arr_t is array (0 to 4) of ctrl_t;
  signal ctrl_regs : ctrl_arr_t;

  signal valid_regs : std_logic_vector(4 downto 0);

  signal rhs      : integer range 0 to 2**(D+COUNTER_SIZE+1)-1;
  signal rhs_part : integer range 0 to 2**COUNTER_SIZE-1;

  signal k_z           : integer range 0 to D-2;
  signal u_z           : integer range 0 to 2**D-1;
  signal code_word     : std_logic_vector(UMAX + D - 1 downto 0);
  signal code_num_bits : integer range 0 to UMAX + D;

  type code_word_cases_t is array (0 to D - 2) of boolean;
  signal code_word_cases : code_word_cases_t;

  subtype accumulator_t is integer range 0 to 2**(D+COUNTER_SIZE)-1;
  signal accumulator_in  : accumulator_t;
  signal accumulator_out : accumulator_t;
begin

  -- Counter update
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        counter <= 0;
      else
        if (in_valid = '1') then
          if (in_ctrl.first_in_line = '1' and in_ctrl.first_line = '1') then
            counter <= 2**INITIAL_COUNT;
          else
            if (in_z + PIPELINES > NZ - 1) then
              if (counter < 2**COUNTER_SIZE-1) then
                counter <= counter + 1;
              else
                counter <= (counter + 1)/2;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  accumulator_in      <= to_integer(unsigned(accumulator_rd_data));
  accumulator_wr_data <= std_logic_vector(to_unsigned(accumulator_out, D+COUNTER_SIZE));

  -- Pipeline
  process (clk)
    type code_word_arr_t is array(0 to UMAX - 1) of std_logic_vector(UMAX + D - 1 downto 0);
    type code_num_bits_arr_t is array(0 to UMAX - 1) of integer range 0 to UMAX + D;
    variable code_word_arr     : code_word_arr_t;
    variable code_num_bits_arr : code_num_bits_arr_t;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        valid_regs <= (others => '0');
      else
        --------------------------------------------------------------------------------
        -- Stage 1 - Compute floor(49/2^7 * counter(t))
        -- Accumulator for current band is fetched from RAM during this cycle
        --------------------------------------------------------------------------------
        rhs_part <= (49 * counter) / 2**7;

        counter_regs(0)  <= counter;
        valid_regs(0)    <= in_valid;
        ctrl_regs(0)     <= in_ctrl;
        residual_regs(0) <= std_logic_vector(in_residual);

        --------------------------------------------------------------------------------
        -- Stage 2 - Compute right hand side in the inequalities for
        -- determining k_z(t), compute next accumulator
        --------------------------------------------------------------------------------
        rhs <= accumulator_in + rhs_part;

        if (ctrl_regs(0).first_in_line = '1' and ctrl_regs(0).first_line = '1') then
          accumulator_out <= ((3 * 2**(KZ_PRIME + 6) - 49) * 2**INITIAL_COUNT) / 2**7;
        else
          if (counter_regs(0) < 2**COUNTER_SIZE - 1) then
            accumulator_out <= accumulator_in + to_integer(unsigned(residual_regs(0)));
          else
            accumulator_out <= (accumulator_in + to_integer(unsigned(residual_regs(0))) + 1) / 2;
          end if;
        end if;
        accumulator_wr <= valid_regs(0);

        counter_regs(1)  <= counter_regs(0);
        valid_regs(1)    <= valid_regs(0);
        ctrl_regs(1)     <= ctrl_regs(0);
        residual_regs(1) <= residual_regs(0);

        --------------------------------------------------------------------------------
        -- Stage 3 - Calculate the different inequalities used for selecting
        -- k_z and u_z
        --------------------------------------------------------------------------------
        code_word_cases(0) <= 2 * counter_regs(1) > rhs;
        for i in 1 to D - 2 loop
          code_word_cases(i) <= counter_regs(1) * 2**i <= rhs;
        end loop;

        residual_regs(2) <= residual_regs(1);
        valid_regs(2)    <= valid_regs(1);
        ctrl_regs(2)     <= ctrl_regs(1);

        --------------------------------------------------------------------------------
        -- Stage 4 - Calculate u_z, k_z and the k_z LSBs of the residual shifted to
        -- occupy the most significant bits
        --------------------------------------------------------------------------------
        for i in 0 to D - 2 loop
          if (code_word_cases(i)) then
            k_z                <= i;
            u_z                <= to_integer(unsigned(residual_regs(2))) / 2**i;
            k_shifted_residual <= residual_regs(2)(i-1 downto 0) & (D-i-1 downto 0 => '0');
          end if;
        end loop;

        residual_regs(3) <= residual_regs(2);
        valid_regs(3)    <= valid_regs(2);
        ctrl_regs(3)     <= ctrl_regs(2);

        --------------------------------------------------------------------------------
        -- Stage 5 - Compute code word
        --------------------------------------------------------------------------------
        if (valid_regs(3) = '0') then
          code_num_bits <= 0;
          code_word     <= (others => '0');
        else
          if (ctrl_regs(3).first_line = '1' and ctrl_regs(3).first_in_line = '1') then
            code_word     <= residual_regs(3) & (UMAX-1 downto 0 => '0');
            code_num_bits <= D;
          elsif (u_z >= UMAX) then
            code_word     <= (UMAX-1 downto 0 => '0') & residual_regs(3);
            code_num_bits <= UMAX + D;
          else
            for i in 0 to UMAX - 1 loop
              code_word_arr(i)     := (i-1 downto 0 => '0') & '1' & k_shifted_residual & (UMAX - i - 2 downto 0 => '0');
              code_num_bits_arr(i) := i + 1 + k_z;
            end loop;
            code_word     <= code_word_arr(u_z);
            code_num_bits <= code_num_bits_arr(u_z);
          end if;
        end if;
        valid_regs(4) <= valid_regs(3);
        ctrl_regs(4)  <= ctrl_regs(3);
      end if;
    end if;
  end process;

  out_valid    <= valid_regs(4);
  out_last     <= ctrl_regs(4).last;
  out_data     <= code_word;
  out_num_bits <= to_unsigned(code_num_bits, num2bits(UMAX + D));
end rtl;
