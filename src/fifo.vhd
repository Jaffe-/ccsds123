library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity fifo is
  generic (
    ELEMENT_SIZE : integer;
    SIZE         : integer;
    RAM_TYPE     : string := "block"
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
  signal rd_idx : integer range 0 to SIZE-1;
  signal wr_idx : integer range 0 to SIZE-1;
begin
  i_dp_bram : entity work.dp_ram_wrapper
    generic map (
      ELEMENTS     => SIZE,
      ELEMENT_SIZE => ELEMENT_SIZE,
      RAM_TYPE     => RAM_TYPE)
    port map (
      clk     => clk,
      aresetn => aresetn,
      wr      => in_valid,
      wraddr  => wr_idx,
      wrdata  => in_data,
      rd      => in_valid,
      rdaddr  => rd_idx,
      rddata  => out_data);

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        rd_idx <= 0;
        wr_idx <= SIZE-1;
      else
        if (in_valid = '1') then
          rd_idx <= wrap_inc(rd_idx, SIZE-1);
          wr_idx <= wrap_inc(wr_idx, SIZE-1);
        end if;
      end if;
    end if;
  end process;
end rtl;
