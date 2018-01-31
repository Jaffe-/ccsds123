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
-- (Boxes indicate delays, numbers indicate number of clock cycles)
--------------------------------------------------------------------------------

entity sample_store is
  generic (
    D  : integer := 8;
    NX : integer := 500;
    NZ : integer := 100
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_sample : in std_logic_vector(D-1 downto 0);
    in_valid  : in std_logic;

    out_s_ne : out std_logic_vector(D-1 downto 0);
    out_s_n  : out std_logic_vector(D-1 downto 0);
    out_s_nw : out std_logic_vector(D-1 downto 0);
    out_s_w  : out std_logic_vector(D-1 downto 0)
    );
end sample_store;

architecture rtl of sample_store is
  signal from_w_fifo_sample  : std_logic_vector(D-1 downto 0);
  signal from_ne_fifo_sample : std_logic_vector(D-1 downto 0);
  signal from_n_fifo_sample  : std_logic_vector(D-1 downto 0);
  signal from_nw_fifo_sample : std_logic_vector(D-1 downto 0);
begin
  i_w_fifo : entity work.fifo
    generic map (
      ELEMENT_SIZE => D,
      SIZE         => NZ)
    port map (
      clk      => clk,
      aresetn  => aresetn,
      in_data  => in_sample,
      in_valid => in_valid,
      out_data => from_w_fifo_sample);

  i_ne_fifo : entity work.fifo
    generic map (
      ELEMENT_SIZE => D,
      SIZE         => (NX-2)*NZ)
    port map (
      clk      => clk,
      aresetn  => aresetn,
      in_data  => from_w_fifo_sample,
      in_valid => in_valid,
      out_data => from_ne_fifo_sample);

  i_n_fifo : entity work.fifo
    generic map (
      ELEMENT_SIZE => D,
      SIZE         => NZ)
    port map (
      clk      => clk,
      aresetn  => aresetn,
      in_data  => from_ne_fifo_sample,
      in_valid => in_valid,
      out_data => from_n_fifo_sample);

  i_nw_fifo : entity work.fifo
    generic map (
      ELEMENT_SIZE => D,
      SIZE         => NZ)
    port map (
      clk      => clk,
      aresetn  => aresetn,
      in_data  => from_n_fifo_sample,
      in_valid => in_valid,
      out_data => from_nw_fifo_sample);

  out_s_w  <= from_w_fifo_sample;
  out_s_ne <= from_ne_fifo_sample;
  out_s_n  <= from_n_fifo_sample;
  out_s_nw <= from_nw_fifo_sample;
end rtl;
