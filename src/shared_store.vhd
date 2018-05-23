library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity shared_store is
  generic (
    PIPELINES    : integer;
    DELAY        : integer;
    ELEMENT_SIZE : integer;
    ELEMENTS     : integer
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr      : in std_logic;
    wr_data : in std_logic_vector(PIPELINES*ELEMENT_SIZE-1 downto 0);

    rd      : in  std_logic;
    rd_data : out std_logic_vector(PIPELINES*ELEMENT_SIZE-1 downto 0)
    );
end shared_store;

architecture rtl of shared_store is
  constant STEP     : integer := ELEMENTS mod PIPELINES;
  constant RAM_SIZE : integer := integer(ceil(real(ELEMENTS)/real(PIPELINES)));

  signal rd_cnt : integer range 0 to RAM_SIZE-1;
  signal wr_cnt : integer range 0 to RAM_SIZE-1;

  type idx_arr_t is array (0 to PIPELINES-1) of integer range 0 to RAM_SIZE-1;
  signal rd_idx : idx_arr_t;

  type data_arr_t is array (0 to PIPELINES-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal rd_data_arr : data_arr_t;

  signal delay_rd     : std_logic;
  signal delay_rd_reg : std_logic_vector(DELAY downto 0);

begin
  g_rams : for i in 0 to PIPELINES-1 generate
    -- Write data and address must be remapped based on relationship between
    -- number of pipelines and number of planes in the cube
    rd_idx(i) <= rd_cnt when i + STEP < PIPELINES else wrap_dec(rd_cnt, RAM_SIZE-1);

    -- Read data maps directly to pipelines
    rd_data((i+1)*ELEMENT_SIZE-1 downto i*ELEMENT_SIZE) <= rd_data_arr(i);

    i_ram : entity work.dp_ram_wrapper
      generic map (
        ELEMENTS     => RAM_SIZE,
        ELEMENT_SIZE => ELEMENT_SIZE,
        RAM_TYPE     => "distributed")
      port map (
        clk     => clk,
        aresetn => aresetn,

        wr     => wr,
        wraddr => wr_cnt,
        wrdata => wr_data((i+1)*ELEMENT_SIZE-1 downto i*ELEMENT_SIZE),

        rd     => delay_rd,
        rdaddr => rd_idx(i),
        rddata => rd_data_arr(f_shift(i, 1, ELEMENTS, PIPELINES)));
  end generate g_rams;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rd_cnt <= 0;

        -- Make distance between read and write pointer equal to delay(0, 1)
        wr_cnt <= f_delay(0, 1, ELEMENTS, PIPELINES) mod RAM_SIZE;

        delay_rd_reg <= (others => '0');
      else
        if (delay_rd = '1') then
          rd_cnt <= wrap_inc(rd_cnt, RAM_SIZE-1);
        end if;
        if (wr = '1') then
          wr_cnt <= wrap_inc(wr_cnt, RAM_SIZE-1);
        end if;

        if (DELAY > 0) then
          delay_rd_reg(0) <= rd;

          for i in 1 to DELAY loop
            delay_rd_reg(i) <= delay_rd_reg(i-1);
          end loop;
        end if;
      end if;
    end if;
  end process;

  delay_rd <= delay_rd_reg(DELAY-1) when DELAY > 0 else rd;
end rtl;
