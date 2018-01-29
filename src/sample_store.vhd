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
--     +--------------------------------------------------------> CUR
--     |
--     |           +--------------------------------------------> W
--     |   +----+  |   +-------------+
-- in -+-->| NZ |--+-->| (NX-1)*NZ-1 |---+----------------------> NE
--         +----+      +-------------+   |   +---+
--                                       +-->| 1 |--+-----------> N
--                                           +---+  |   +---+
--                                                  +-->| 1 |---> NW
--                                                      +---+
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

    out_valid : out std_logic;
    out_s_ne  : out std_logic_vector(D-1 downto 0);
    out_s_n   : out std_logic_vector(D-1 downto 0);
    out_s_nw  : out std_logic_vector(D-1 downto 0);
    out_s_w   : out std_logic_vector(D-1 downto 0)
    );
end sample_store;

architecture rtl of sample_store is
  type band_fifo_arr_t is array (0 to NZ-1) of std_logic_vector(D-1 downto 0);
  type row_fifo_arr_t is array(0 to (NX-1)*NZ-2) of std_logic_vector(D-1 downto 0);

  signal from_band_fifo_sample : in_sample'subtype;
  signal from_row_fifo_sample : in_sample'subtype;

  signal band_fifo : band_fifo_arr_t;
  signal row_fifo  : row_fifo_arr_t;

  signal band_rd_idx : integer range 0 to NZ-1;
  signal band_wr_idx : integer range 0 to NZ-1;

  signal row_rd_idx : integer range 0 to (NX-1)*NZ-2;
  signal row_wr_idx : integer range 0 to (NX-1)*NZ-2;

  signal s_reg1 : in_sample'subtype;
  signal s_reg2 : in_sample'subtype;
begin

  -- Infer dual port block RAMs
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (in_valid = '1') then
        band_fifo(band_wr_idx) <= in_sample;
        row_fifo(row_wr_idx)   <= from_band_fifo_sample;
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (in_valid = '1') then
        from_band_fifo_sample <= band_fifo(band_rd_idx);
        from_row_fifo_sample  <= row_fifo(row_rd_idx);
      end if;
    end if;
  end process;

  -- Update indices
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        band_rd_idx <= 0;
        band_wr_idx <= band_fifo'high;
        row_rd_idx  <= 0;
        row_wr_idx  <= row_fifo'high;
      else
        if (in_valid = '1') then
          band_rd_idx <= wrap_inc(band_rd_idx, band_fifo'high);
          band_wr_idx <= wrap_inc(band_wr_idx, band_fifo'high);
          row_rd_idx  <= wrap_inc(row_rd_idx, row_fifo'high);
          row_wr_idx  <= wrap_inc(row_wr_idx, row_fifo'high);
        end if;
      end if;
    end if;
  end process;

  out_s_w  <= from_band_fifo_sample;
  out_s_ne <= from_row_fifo_sample;

  -- Delays for s_n and s_nw
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        s_reg1 <= (others => '0');
        s_reg2 <= (others => '0');
      else
        s_reg1 <= from_row_fifo_sample;
        s_reg2 <= s_reg1;
      end if;
    end if;
  end process;

  out_s_n  <= s_reg1;
  out_s_nw <= s_reg2;
end rtl;
