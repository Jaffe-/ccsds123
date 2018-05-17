library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

--------------------------------------------------------------------------------
-- Sample storage
--
-- ... | ... | ... | ... | ...
-- ----+-----+-----+-----+-----
-- ... | NW  |  N  | NE  | ...
-- ----+-----+-----+-----+-----
-- ... |  W  | CUR | ... | ...
-- ----+-----+-----+-----+-----
-- ... | ... | ... | ... | ...
--
--
--     +----------------------------------------------------------> CUR
--     |
--     |           +----------------------------------------------> W
--     |   +----+  |   +-------------+
-- in -+-->| NZ |--+-->| (NX-2)*NZ   |---+------------------------> NE
--         +----+      +-------------+   |   +----+
--                                       +-->| NZ |--+------------> N
--                                           +----+  |   +----+
--                                                   +-->| NZ |---> NW
--                                                       +----+
--
-- (Boxes indicate delays, labels indicate number of clock cycles)
--------------------------------------------------------------------------------

entity sample_store is
  generic (
    PIPELINES : integer;
    D         : integer;
    NX        : integer;
    NZ        : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_s     : in std_logic_vector(PIPELINES*D-1 downto 0);
    in_valid : in std_logic;

    out_s_ne : out std_logic_vector(PIPELINES*D-1 downto 0);
    out_s_n  : out std_logic_vector(PIPELINES*D-1 downto 0);
    out_s_nw : out std_logic_vector(PIPELINES*D-1 downto 0);
    out_s_w  : out std_logic_vector(PIPELINES*D-1 downto 0)
    );
end sample_store;

architecture rtl of sample_store is
  type sample_arr_t is array (0 to PIPELINES-1) of std_logic_vector(D-1 downto 0);
  signal to_fifo      : sample_arr_t;
  signal from_w_fifo  : sample_arr_t;
  signal from_ne_fifo : sample_arr_t;
  signal from_n_fifo  : sample_arr_t;
  signal from_nw_fifo : sample_arr_t;

  constant STEP : integer := NZ mod PIPELINES;
begin
  g_fifos : for i in 0 to PIPELINES-1 generate
    to_fifo(i) <= in_s((i+1)*D-1 downto i*D);

    i_w_fifo : entity work.fifo
      generic map (
        ELEMENT_SIZE => D,
        SIZE         => f_delay(i, 1, NZ, PIPELINES),
        RAM_TYPE     => "distributed")
      port map (
        clk      => clk,
        aresetn  => aresetn,
        in_data  => to_fifo(i),
        in_valid => in_valid,
        out_data => from_w_fifo(f_shift(i, 1, NZ, PIPELINES)));

    out_s_w((i+1)*D-1 downto i*D) <= from_w_fifo(i);

    i_ne_fifo : entity work.fifo
      generic map (
        ELEMENT_SIZE => D,
        SIZE         => f_delay(i, NX-2, NZ, PIPELINES))
      port map (
        clk      => clk,
        aresetn  => aresetn,
        in_data  => from_w_fifo(i),
        in_valid => in_valid,
        out_data => from_ne_fifo(f_shift(i, NX-2, NZ, PIPELINES)));

    out_s_ne((i+1)*D-1 downto i*D) <= from_ne_fifo(i);

    i_n_fifo : entity work.fifo
      generic map (
        ELEMENT_SIZE => D,
        SIZE         => f_delay(i, 1, NZ, PIPELINES),
        RAM_TYPE     => "distributed")
      port map (
        clk      => clk,
        aresetn  => aresetn,
        in_data  => from_ne_fifo(i),
        in_valid => in_valid,
        out_data => from_n_fifo(f_shift(i, 1, NZ, PIPELINES)));

    out_s_n((i+1)*D-1 downto i*D) <= from_n_fifo(i);

    i_nw_fifo : entity work.fifo
      generic map (
        ELEMENT_SIZE => D,
        SIZE         => f_delay(i, 1, NZ, PIPELINES),
        RAM_TYPE     => "distributed")
      port map (
        clk      => clk,
        aresetn  => aresetn,
        in_data  => from_n_fifo(i),
        in_valid => in_valid,
        out_data => from_nw_fifo(f_shift(i, 1, NZ, PIPELINES)));

    out_s_nw((i+1)*D-1 downto i*D) <= from_nw_fifo(i);

  end generate g_fifos;
end rtl;
