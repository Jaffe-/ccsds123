library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

library xpm;
use xpm.vcomponents.all;

entity xpm_fifo_wrapper is
  generic (
    DEPTH    : integer;
    WIDTH    : integer;
    MARGIN   : integer;
    READMODE : string := "std"
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    wren           : in  std_logic;
    wrdata         : in  std_logic_vector(WIDTH-1 downto 0);
    rden           : in  std_logic;
    rddata         : out  std_logic_vector(WIDTH-1 downto 0);
    empty          : out std_logic;
    over_threshold : out std_logic
    );
end xpm_fifo_wrapper;

architecture rtl of xpm_fifo_wrapper is
  signal rst : std_logic;
begin
  rst <= not aresetn;

  i_fifo : xpm_fifo_sync
    generic map (
      FIFO_MEMORY_TYPE    => "auto",
      ECC_MODE            => "no_ecc",
      FIFO_WRITE_DEPTH    => DEPTH,
      WRITE_DATA_WIDTH    => WIDTH,
      WR_DATA_COUNT_WIDTH => num2bits(DEPTH),
      PROG_FULL_THRESH    => DEPTH - MARGIN,
      FULL_RESET_VALUE    => 0,
      READ_MODE           => READMODE,
      FIFO_READ_LATENCY   => 1,
      READ_DATA_WIDTH     => WIDTH,
      RD_DATA_COUNT_WIDTH => num2bits(DEPTH),
      PROG_EMPTY_THRESH   => 10,
      DOUT_RESET_VALUE    => "0",
      WAKEUP_TIME         => 0
      )
    port map (
      rst           => rst,
      wr_clk        => clk,
      wr_en         => wren,
      din           => wrdata,
      full          => open,
      overflow      => open,
      wr_rst_busy   => open,
      rd_en         => rden,
      dout          => rddata,
      empty         => empty,
      underflow     => open,
      rd_rst_busy   => open,
      prog_full     => over_threshold,
      wr_data_count => open,
      prog_empty    => open,
      rd_data_count => open,
      sleep         => '0',
      injectsbiterr => '0',
      injectdbiterr => '0',
      sbiterr       => open,
      dbiterr       => open
      );
end rtl;
