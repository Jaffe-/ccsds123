library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.synth_params.all;

entity ccsds123_synth_top is
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Input AXI stream
    s_axis_tdata  : in  std_logic_vector(PIPELINES*D-1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;

    m_axis_tdata  : out std_logic_vector(BUS_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tlast  : out std_logic;
    m_axis_tready : in  std_logic
    );
end ccsds123_synth_top;

architecture rtl of ccsds123_synth_top is
begin
  ccsds123_top_1: entity work.ccsds123_top
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
      BUS_WIDTH     => BUS_WIDTH,
      NX            => NX,
      NY            => NY,
      NZ            => NZ,
      ISUNSIGNED    => ISUNSIGNED)
    port map (
      clk           => clk,
      aresetn       => aresetn,
      s_axis_tdata  => s_axis_tdata,
      s_axis_tvalid => s_axis_tvalid,
      s_axis_tready => s_axis_tready,
      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tlast  => m_axis_tlast,
      m_axis_tready => m_axis_tready);
end architecture rtl;
