library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

entity ccsds123_ip_top is
  generic (
    PIPELINES     : integer := 1;
    LITTLE_ENDIAN : boolean := true;
    COL_ORIENTED  : boolean := false;
    REDUCED       : boolean := false;
    OMEGA         : integer := 19;
    D             : integer := 16;
    P             : integer := 1;
    R             : integer := 64;
    TINC_LOG      : integer := 4;
    V_MIN         : integer := -6;
    V_MAX         : integer := 9;
    UMAX          : integer := 9;
    KZ_PRIME      : integer := 8;
    COUNTER_SIZE  : integer := 8;
    INITIAL_COUNT : integer := 6;
    NX            : integer := 500;
    NY            : integer := 500;
    NZ            : integer := 100
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Input AXI Stream
    s_axis_tdata  : in  std_logic_vector(PIPELINES*D-1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;

    -- Output AXI Stream
    m_axis_tdata  : out std_logic_vector(63 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic
    );
end ccsds123_ip_top;

architecture rtl of ccsds123_ip_top is
  component axis_data_fifo_0
    port (
      s_axis_aresetn     : in  std_logic;
      s_axis_aclk        : in  std_logic;
      s_axis_tvalid      : in  std_logic;
      s_axis_tready      : out std_logic;
      s_axis_tdata       : in  std_logic_vector(63 downto 0);
      m_axis_tvalid      : out std_logic;
      m_axis_tready      : in  std_logic;
      m_axis_tdata       : out std_logic_vector(63 downto 0);
      m_axis_tlast       : out std_logic;
      axis_data_count    : out std_logic_vector(31 downto 0);
      axis_wr_data_count : out std_logic_vector(31 downto 0);
      axis_rd_data_count : out std_logic_vector(31 downto 0)
      );
  end component;

  signal core_ready : std_logic;
  signal out_ready  : std_logic;

  signal from_core_tdata  : std_logic_vector(63 downto 0);
  signal from_core_tvalid : std_logic;
  signal from_core_tlast  : std_logic;

  signal axis_data_count : std_logic_vector(31 downto 0);

  constant C_FIFO_SIZE : integer := 128;
  constant C_FIFO_MAX  : integer := C_FIFO_SIZE - 16;
begin

  i_core : entity work.ccsds123_top
    generic map (
      PIPELINES     => PIPELINES,
      LITTLE_ENDIAN => LITTLE_ENDIAN,
      COL_ORIENTED  => COL_ORIENTED,
      REDUCED       => REDUCED,
      OMEGA         => OMEGA,
      D             => D,
      P             => P,
      R             => R,
      TINC_LOG      => TINC_LOG,
      V_MIN         => V_MIN,
      V_MAX         => V_MAX,
      UMAX          => UMAX,
      KZ_PRIME      => KZ_PRIME,
      COUNTER_SIZE  => COUNTER_SIZE,
      INITIAL_COUNT => INITIAL_COUNT,
      BUS_WIDTH     => 64,
      NX            => NX,
      NY            => NY,
      NZ            => NZ)
    port map (
      clk        => clk,
      aresetn    => aresetn,
      in_tdata   => s_axis_tdata,
      in_tvalid  => s_axis_tvalid,
      in_tready  => core_ready,
      out_tdata  => from_core_tdata,
      out_tvalid => from_core_tvalid,
      out_tlast  => from_core_tlast);

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        out_ready <= '0';
      else
        if (to_integer(unsigned(axis_data_count)) <= C_FIFO_MAX) then
          out_ready <= '1';
        else
          out_ready <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Input stream is only ready when enough space in FIFO for whatever is
  -- currently inside the core, and the core itself is ready
  s_axis_tready <= out_ready and core_ready;

  i_fifo : axis_data_fifo_0
    port map (
      s_axis_aresetn     => aresetn,
      s_axis_aclk        => clk,
      s_axis_tvalid      => from_core_tvalid,
      s_axis_tready      => open,
      s_axis_tdata       => from_core_tdata,
      s_axis_tlast       => from_core_tlast,
      m_axis_tvalid      => m_axis_tvalid,
      m_axis_tready      => m_axis_tready,
      m_axis_tdata       => m_axis_tdata,
      m_axis_tlast       => m_axis_tlast,
      axis_data_count    => axis_data_count,
      axis_wr_data_count => open,
      axis_rd_data_count => open);
end rtl;
