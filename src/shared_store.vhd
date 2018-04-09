library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity shared_store is
  generic (
    PIPELINES    : integer := 1;
    DELAY        : integer := 1;
    ELEMENT_SIZE : integer := 1;
    ELEMENTS     : integer := 100
    );

  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wr         : in std_logic;
    wr_weights : in signed(PIPELINES*ELEMENT_SIZE-1 downto 0);

    rd         : in  std_logic;
    rd_weights : out signed(PIPELINES*ELEMENT_SIZE-1 downto 0)
    );
end shared_store;

architecture rtl of shared_store is
  type delay_stages_t is array (0 to DELAY-1) of signed(PIPELINES*ELEMENT_SIZE-1 downto 0);
  signal delay_stages   : delay_stages_t;
  signal rd_weight_vecs : signed(PIPELINES*ELEMENT_SIZE-1 downto 0);

  signal rd_cnt : integer range 0 to ELEMENTS/PIPELINES-1;
  signal wr_cnt : integer range 0 to ELEMENTS/PIPELINES-1;

  type idx_arr_t is array (0 to PIPELINES-1) of integer range 0 to ELEMENTS/PIPELINES-1;
  signal wr_idx : idx_arr_t;

  type weight_arr_t is array (0 to PIPELINES-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);
  signal wr_data : weight_arr_t;
  signal rd_data : weight_arr_t;

  constant STEP : integer := ELEMENTS mod PIPELINES;
begin
  g_rams : for i in 0 to PIPELINES-1 generate
    -- Write data and address must be remapped based on relationship between
    -- number of pipelines and number of planes in the cube
    wr_data((i + STEP) mod PIPELINES) <= std_logic_vector(wr_weights((i+1)*ELEMENT_SIZE-1 downto i*ELEMENT_SIZE));
    wr_idx(i)                         <= wr_cnt when i + STEP < PIPELINES else wrap_inc(wr_cnt, ELEMENTS/PIPELINES-1);

    -- Read data maps directly to pipelines
    rd_weight_vecs((i+1)*ELEMENT_SIZE-1 downto i*ELEMENT_SIZE) <= signed(rd_data(i));

    i_bram : entity work.dp_bram
      generic map (
        ELEMENTS     => ELEMENTS/PIPELINES,
        ELEMENT_SIZE => ELEMENT_SIZE)
      port map (
        clk     => clk,
        aresetn => aresetn,

        wr     => wr,
        wraddr => wr_idx(i),
        wrdata => wr_data(i),

        rd     => rd,
        rdaddr => rd_cnt,
        rddata => rd_data(i));
  end generate g_rams;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        wr_cnt       <= 0;
        rd_cnt       <= 0;
        delay_stages <= (others => (others => '0'));
      else
        if (rd = '1') then
          rd_cnt <= wrap_inc(rd_cnt, ELEMENTS/PIPELINES-1);
        end if;
        if (wr = '1') then
          wr_cnt <= wrap_inc(wr_cnt, ELEMENTS/PIPELINES-1);
        end if;

        delay_stages(0) <= rd_weight_vecs;

        if (DELAY > 0) then
          for i in 1 to DELAY-1 loop
            delay_stages(i) <= delay_stages(i-1);
          end loop;
        end if;
      end if;
    end if;
  end process;

  rd_weights <= delay_stages(DELAY-1);
end rtl;
