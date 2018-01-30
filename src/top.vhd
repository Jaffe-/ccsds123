library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity ccsds123_top is
  generic (
    COL_ORIENTED : boolean := false;
    OMEGA        : integer := 8;
    CZ           : integer := 4;
    D            : integer := 8;
    P            : integer := 1;
    R            : integer := 32;
    NX           : integer := 500;
    NY           : integer := 500;
    NZ           : integer := 100
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Input AXI stream
    s_axis_tdata  : in  std_logic_vector(D-1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;

    res       : out signed(D downto 0);
    res_valid : out std_logic
    );
end ccsds123_top;

architecture rtl of ccsds123_top is
  signal in_handshake : std_logic;
  signal in_ready     : std_logic;

  signal from_ctrl_ctrl : ctrl_t;
  signal from_ctrl_z    : integer range 0 to NZ-1;
  signal from_ctrl_t    : integer range 0 to NX*NY-1;

  signal s_ne : std_logic_vector(D-1 downto 0);
  signal s_n  : std_logic_vector(D-1 downto 0);
  signal s_nw : std_logic_vector(D-1 downto 0);
  signal s_w  : std_logic_vector(D-1 downto 0);

  signal from_local_diff_ctrl   : ctrl_t;
  signal from_local_diff_valid  : std_logic;
  signal from_local_diff_z      : integer range 0 to NZ-1;
  signal from_local_diff_t      : integer range 0 to NX*NY-1;
  signal from_local_diff_s      : signed(D-1 downto 0);
  signal from_local_diff_locsum : signed(D+2 downto 0);
  signal d_c                    : signed(D+2 downto 0);
  signal d_n                    : signed(D+2 downto 0);
  signal d_nw                   : signed(D+2 downto 0);
  signal d_w                    : signed(D+2 downto 0);

  signal local_diffs      : signed(CZ*(D+3)-1 downto 0);
  signal weights          : signed(CZ*(OMEGA+3)-1 downto 0);
  signal pred_d_c         : signed(D+3+OMEGA+3-1 downto 0);
  signal from_dot_valid   : std_logic;
  signal from_dot_ctrl    : ctrl_t;
  signal from_dot_s       : from_local_diff_s'subtype;
  signal from_dot_locsum  : from_local_diff_locsum'subtype;
  signal from_dot_z       : from_local_diff_z'subtype;
  signal from_dot_t       : from_local_diff_t'subtype;
  signal from_dot_weights : weights'subtype;
  signal from_dot_diffs   : local_diffs'subtype;

  signal from_pred_valid   : std_logic;
  signal from_pred_pred_s  : signed(D downto 0);
  signal from_pred_ctrl    : ctrl_t;
  signal from_pred_s       : from_local_diff_s'subtype;
  signal from_pred_z       : from_local_diff_z'subtype;
  signal from_pred_t       : from_local_diff_t'subtype;
  signal from_pred_weights : weights'subtype;
  signal from_pred_diffs   : local_diffs'subtype;

  signal from_w_update_valid   : std_logic;
  signal from_w_update_z       : from_local_diff_z'subtype;
  signal from_w_update_weights : weights'subtype;
begin
  in_ready      <= '1';                 -- for now
  in_handshake  <= s_axis_tvalid and in_ready;
  s_axis_tready <= in_ready;

  i_control : entity work.control
    generic map (
      NX => NX,
      NY => NY,
      NZ => NZ,
      D  => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      tick => in_handshake,

      out_ctrl => from_ctrl_ctrl,
      out_z    => from_ctrl_z,
      out_t    => from_ctrl_t);

  i_sample_store : entity work.sample_store
    generic map (
      D  => D,
      NX => NX,
      NZ => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_sample => s_axis_tdata,
      in_valid  => in_handshake,

      out_s_ne => s_ne,
      out_s_n  => s_n,
      out_s_nw => s_nw,
      out_s_w  => s_w);

  i_local_diff : entity work.local_diff
    generic map (
      COL_ORIENTED => COL_ORIENTED,
      NX           => NX,
      NY           => NY,
      NZ           => NZ,
      CZ           => CZ,
      D            => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      s_cur    => signed(s_axis_tdata),
      s_ne     => signed(s_ne),
      s_n      => signed(s_n),
      s_nw     => signed(s_nw),
      s_w      => signed(s_w),
      in_valid => in_handshake,
      in_ctrl  => from_ctrl_ctrl,
      in_t     => from_ctrl_t,
      in_z     => from_ctrl_z,

      local_sum => from_local_diff_locsum,
      d_c       => d_c,
      d_n       => local_diffs((D+3)*(P+3)-1 downto (D+3)*(P+2)),
      d_nw      => local_diffs((D+3)*(P+2)-1 downto (D+3)*(P+1)),
      d_w       => local_diffs((D+3)*(P+1)-1 downto (D+3)*P),
      out_valid => from_local_diff_valid,
      out_ctrl  => from_local_diff_ctrl,
      out_t     => from_local_diff_t,
      out_z     => from_local_diff_z,
      out_s     => from_local_diff_s);

  i_local_diff_store : entity work.local_diff_store
    generic map (
      NZ => NZ,
      P  => P,
      D  => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr            => from_local_diff_valid,
      wr_local_diff => d_c,
      z             => from_local_diff_z,

      local_diffs => local_diffs((D+3)*P-1 downto 0));

  i_weight_store : entity work.weight_store
    generic map (
      OMEGA => OMEGA,
      CZ    => CZ,
      NZ    => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr        => from_w_update_valid,
      wr_z      => from_w_update_z,
      wr_weight => from_w_update_weights,

      rd        => in_handshake,
      rd_z      => from_ctrl_z,
      rd_weight => weights);

  i_dot : entity work.dot_product
    generic map (
      N      => CZ,
      A_SIZE => D+3,
      B_SIZE => OMEGA+3,
      NX     => NX,
      NY     => NY,
      NZ     => NZ,
      D      => D,
      CZ     => CZ,
      OMEGA  => OMEGA)
    port map (
      clk     => clk,
      aresetn => aresetn,

      a       => local_diffs,
      a_valid => from_local_diff_valid,
      b       => weights,
      b_valid => '1',
      s       => pred_d_c,
      s_valid => from_dot_valid,

      in_locsum  => from_local_diff_locsum,
      in_ctrl    => from_local_diff_ctrl,
      in_z       => from_local_diff_z,
      in_t       => from_local_diff_t,
      in_s       => from_local_diff_s,
      in_weights => weights,
      in_diffs   => local_diffs,

      out_locsum  => from_dot_locsum,
      out_ctrl    => from_dot_ctrl,
      out_z       => from_dot_z,
      out_t       => from_dot_t,
      out_s       => from_dot_s,
      out_weights => from_dot_weights,
      out_diffs   => from_dot_diffs);

  i_predictor : entity work.predictor
    generic map (
      NX    => NX,
      NY    => NY,
      NZ    => NZ,
      D     => D,
      R     => R,
      OMEGA => OMEGA,
      P     => P,
      CZ    => CZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_valid => from_dot_valid,
      in_d_c   => pred_d_c,

      in_locsum  => from_dot_locsum,
      in_z       => from_dot_z,
      in_t       => from_dot_t,
      in_s       => from_dot_s,
      in_ctrl    => from_dot_ctrl,
      in_weights => from_dot_weights,
      in_diffs   => from_dot_diffs,

      out_valid   => from_pred_valid,
      out_pred_s  => from_pred_pred_s,
      out_z       => from_pred_z,
      out_t       => from_pred_t,
      out_s       => from_pred_s,
      out_ctrl    => from_pred_ctrl,
      out_weights => from_pred_weights,
      out_diffs   => from_pred_diffs);

  res       <= from_pred_pred_s;
  res_valid <= from_pred_valid;

  i_weight_update : entity work.weight_update
    generic map (
      NX    => NX,
      NY    => NY,
      NZ    => NZ,
      OMEGA => OMEGA,
      D     => D,
      R     => R,
      CZ    => CZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_ctrl    => from_pred_ctrl,
      in_t       => from_pred_t,
      in_z       => from_pred_z,
      in_s       => from_pred_s,
      in_pred_s  => from_pred_pred_s,
      in_diffs   => from_pred_diffs,
      in_valid   => from_pred_valid,
      in_weights => from_pred_weights,

      out_valid   => from_w_update_valid,
      out_z       => from_w_update_z,
      out_weights => from_w_update_weights);
end rtl;
