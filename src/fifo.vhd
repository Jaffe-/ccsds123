library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity fifo is
  generic (
    ELEMENT_SIZE : integer;
    SIZE         : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_data  : in std_logic_vector(ELEMENT_SIZE-1 downto 0);
    in_valid : in std_logic;

    out_data : out std_logic_vector(ELEMENT_SIZE-1 downto 0)
    );
end fifo;

architecture rtl of fifo is
  type fifo_t is array(0 to SIZE-1) of std_logic_vector(ELEMENT_SIZE-1 downto 0);

  signal fifo   : fifo_t;
  signal rd_idx : integer range 0 to fifo'high;
  signal wr_idx : integer range 0 to fifo'high;
begin
  process (clk)
  begin
    if (rising_edge(clk)) then
      if (in_valid = '1') then
        fifo(wr_idx) <= in_data;
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (in_valid = '1') then
        out_data <= fifo(rd_idx);
      end if;
    end if;
  end process;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rd_idx <= 0;
        wr_idx <= fifo'high;
      else
        rd_idx <= wrap_inc(rd_idx, fifo'high);
        wr_idx <= wrap_inc(wr_idx, fifo'high);
      end if;
    end if;
  end process;
end rtl;
