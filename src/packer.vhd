library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

--------------------------------------------------------------------------------
-- Bit packer
--------------------------------------------------------------------------------

entity packer is
  generic (
    LITTLE_ENDIAN : boolean;
    BUS_WIDTH     : integer;
    MAX_IN_WIDTH  : integer
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    in_valid    : in std_logic;
    in_last     : in std_logic;
    in_data     : in std_logic_vector(MAX_IN_WIDTH-1 downto 0);
    in_num_bits : in integer range 0 to MAX_IN_WIDTH;

    out_valid : out std_logic;
    out_last  : out std_logic;
    out_data  : out std_logic_vector(BUS_WIDTH-1 downto 0)
    );
end packer;

architecture rtl of packer is
  constant REG_SIZE : integer := BUS_WIDTH + MAX_IN_WIDTH - 1;

  type data_arr_t is array (0 to 1) of std_logic_vector(0 to BUS_WIDTH - 1);
  signal data_regs   : data_arr_t;
  signal current_reg : integer range 0 to 1;
  signal prev_reg    : integer range 0 to 1;

  type ptr_arr_t is array(0 to 1) of integer range 0 to BUS_WIDTH - 1;
  signal ptr_arr : ptr_arr_t;
begin

  process (clk)
    type data_arr_t is array (0 to BUS_WIDTH - 1) of std_logic_vector(0 to REG_SIZE-1);
    variable data_nxts : data_arr_t;
    variable next_reg  : integer range 0 to 1;
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        data_regs   <= (others => (others => '0'));
        current_reg <= 0;
        ptr_arr     <= (others => 0);
      else
        if (in_valid = '1') then
          for i in 0 to BUS_WIDTH - 1 loop
            data_nxts(i)                            := (others => '0');
            data_nxts(i)(0 to i + MAX_IN_WIDTH - 1) := data_regs(current_reg)(0 to i - 1) & in_data;
          end loop;

          next_reg               := (current_reg + 1) mod 2;
          data_regs(current_reg) <= data_nxts(ptr_arr(current_reg))(0 to BUS_WIDTH-1);
          data_regs(next_reg)    <= data_nxts(ptr_arr(current_reg))(BUS_WIDTH to REG_SIZE - 1) & (2*BUS_WIDTH-1 downto REG_SIZE => '0');

          if (in_last = '1' or ptr_arr(current_reg) + in_num_bits >= BUS_WIDTH) then
            out_valid            <= '1';
            current_reg          <= next_reg;
            prev_reg             <= current_reg;
            ptr_arr(current_reg) <= 0;
            if (in_last = '0') then
              ptr_arr(next_reg) <= ptr_arr(current_reg) + in_num_bits - BUS_WIDTH;
            else
              ptr_arr(next_reg) <= 0;
            end if;
          else
            out_valid            <= '0';
            ptr_arr(current_reg) <= ptr_arr(current_reg) + in_num_bits;
          end if;
        else
          out_valid <= '0';
        end if;
        out_last <= in_last;
      end if;
    end if;
  end process;

  -- Endianness conversion
  process (data_regs, prev_reg)
    constant NUM_BYTES : integer := BUS_WIDTH/8;
    variable NEW_INDEX : integer;

    -- Simplifies dealing with data_regs range running in the opposite direction
    variable data      : std_logic_vector(BUS_WIDTH-1 downto 0);
  begin
    data := data_regs(prev_reg);
    if (LITTLE_ENDIAN) then
      for i in 0 to NUM_BYTES - 1 loop
        NEW_INDEX                                  := NUM_BYTES - 1 - i;
        out_data(8*NEW_INDEX+7 downto 8*NEW_INDEX) <= data(8*i+7 downto 8*i);
      end loop;
    else
      out_data <= data;
    end if;
  end process;

end rtl;
