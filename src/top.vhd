library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.common.all;

entity ccsds123_top is
  generic (
    PIPELINES     : integer := 1;
    LITTLE_ENDIAN : boolean := true;
    COL_ORIENTED  : boolean := false;
    REDUCED       : boolean := false;
    OMEGA         : integer := 19;
    D             : integer := 16;
    P             : integer := 3;
    R             : integer := 64;
    TINC_LOG      : integer := 4;
    V_MIN         : integer := -6;
    V_MAX         : integer := 9;
    UMAX          : integer := 9;
    KZ_PRIME      : integer := 8;
    COUNTER_SIZE  : integer := 8;
    INITIAL_COUNT : integer := 6;
    BUS_WIDTH     : integer := 64;
    NX            : integer := 500;
    NY            : integer := 500;
    NZ            : integer := 10
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Input AXI stream
    in_tdata  : in  std_logic_vector(PIPELINES * D-1 downto 0);
    in_tvalid : in  std_logic;
    in_tready : out std_logic;

    out_tdata  : out std_logic_vector(BUS_WIDTH-1 downto 0);
    out_tvalid : out std_logic;
    out_tlast  : out std_logic
    );
end ccsds123_top;

architecture rtl of ccsds123_top is
  function CZ return integer is
  begin
    if (REDUCED) then
      return P;
    else
      return P + 3;
    end if;
  end function CZ;

  signal in_handshake : std_logic;
  signal in_ready     : std_logic;

  signal from_ctrl_ctrl    : ctrl_t;
  signal from_ctrl_z_block : integer range 0 to NZ/PIPELINES-1;

  signal w_update_wr : std_logic_vector(PIPELINES-1 downto 0);
  signal weights_wr  : signed(PIPELINES*CZ*(OMEGA+3)-1 downto 0);
  signal weights_rd  : std_logic_vector(PIPELINES*CZ*(OMEGA+3)-1 downto 0);

  signal pipeline_out_valid    : std_logic_vector(PIPELINES-1 downto 0);
  signal pipeline_out_last     : std_logic_vector(PIPELINES-1 downto 0);
  signal pipeline_out_data     : std_logic_vector(PIPELINES*(UMAX + D)-1 downto 0);
  signal pipeline_out_num_bits : unsigned(PIPELINES*len2bits(UMAX + D) - 1 downto 0);

  signal combiner_over_threshold : std_logic;

  type central_diff_arr_t is array (0 to PIPELINES-1) of signed(D+2 downto 0);
  type central_diff_zb_arr_t is array (0 to PIPELINES-1) of integer range 0 to NZ/PIPELINES-1;
  signal central_diff_valid    : std_logic_vector(PIPELINES-1 downto 0);
  signal central_diff_zb       : central_diff_zb_arr_t;
  signal central_diffs_vec     : signed(PIPELINES*(D+3)-1 downto 0);
  signal central_diff          : central_diff_arr_t;
  signal from_local_diff_store : signed(P*(D+3)-1 downto 0);

  signal prev_s_reg : std_logic_vector(D-1 downto 0);
begin
  in_handshake <= in_tvalid and in_ready;
  in_tready    <= in_ready;

  i_control : entity work.control
    generic map (
      PIPELINES => PIPELINES,
      V_MIN     => V_MIN,
      V_MAX     => V_MAX,
      TINC_LOG  => TINC_LOG,
      NX        => NX,
      NY        => NY,
      NZ        => NZ,
      CZ        => CZ,
      D         => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      tick               => in_handshake,
      w_upd_handshake    => w_update_wr(0),
      ready              => in_ready,
      out_over_threshold => combiner_over_threshold,

      out_ctrl => from_ctrl_ctrl,
      out_z    => from_ctrl_z_block);

  i_weight_store : entity work.shared_store
    generic map (
      PIPELINES    => PIPELINES,
      DELAY        => 2,
      ELEMENT_SIZE => CZ*(OMEGA+3),
      ELEMENTS     => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr      => w_update_wr(0),
      wr_data => std_logic_vector(weights_wr),

      rd      => in_handshake,
      rd_data => weights_rd
      );

  i_local_diff_store : entity work.local_diff_store
    generic map (
      PIPELINES => PIPELINES,
      NZB       => NZ/PIPELINES,
      P         => P,
      D         => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr            => central_diff_valid(0),
      wr_local_diff => central_diffs_vec,
      zb            => central_diff_zb(0),

      local_diffs => from_local_diff_store);

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        prev_s_reg <= (others => '0');
      elsif (in_handshake = '1') then
        prev_s_reg <= in_tdata(PIPELINES*D-1 downto (PIPELINES-1)*D);
      end if;
    end if;
  end process;

  g_pipelines : for i in 0 to PIPELINES-1 generate
    signal from_ctrl_z        : integer range 0 to NZ-1;
    signal prev_central_diffs : signed(P*(D+3)-1 downto 0);
    signal prev_s             : std_logic_vector(D-1 downto 0);
  begin
    from_ctrl_z <= PIPELINES * from_ctrl_z_block + i;

    -- Order in central difference store must be from most recent sample at
    -- index 0, so reorder it:
    central_diffs_vec((PIPELINES-i)*(D+3)-1 downto (PIPELINES-i-1)*(D+3)) <= central_diff(i);

    process (central_diff, from_local_diff_store, prev_s_reg, in_tdata)
    begin
      for j in 0 to P-1 loop
        -- If j < i then we're going to take central differences from the other
        -- pipelines. Otherwise we must take from the local difference store.
        if (j < i) then
          prev_central_diffs((j+1)*(D+3)-1 downto j*(D+3)) <= central_diff(i-j-1);
        else
          prev_central_diffs((j+1)*(D+3)-1 downto j*(D+3)) <= from_local_diff_store((j-i+1)*(D+3)-1 downto (j-i)*(D+3));
        end if;
      end loop;

      if (i = 0) then
        prev_s <= prev_s_reg;
      else
        prev_s <= in_tdata(i*D-1 downto (i-1)*D);
      end if;
    end process;

    i_pipeline : entity work.pipeline_top
      generic map (
        PIPELINES     => PIPELINES,
        LITTLE_ENDIAN => LITTLE_ENDIAN,
        COL_ORIENTED  => COL_ORIENTED,
        REDUCED       => REDUCED,
        OMEGA         => OMEGA,
        D             => D,
        P             => P,
        CZ            => CZ,
        R             => R,
        V_MIN         => V_MIN,
        V_MAX         => V_MAX,
        UMAX          => UMAX,
        KZ_PRIME      => KZ_PRIME,
        COUNTER_SIZE  => COUNTER_SIZE,
        INITIAL_COUNT => INITIAL_COUNT,
        NX            => NX,
        NZ            => NZ
        )
      port map (
        clk     => clk,
        aresetn => aresetn,

        in_ctrl        => from_ctrl_ctrl,
        in_z           => from_ctrl_z,
        in_sample      => in_tdata((i+1)*D-1 downto i*D),
        in_prev_sample => prev_s,
        in_valid       => in_handshake,
        in_weights     => signed(weights_rd((i+1)*CZ*(OMEGA+3)-1 downto i*CZ*(OMEGA+3))),

        w_update_wr      => w_update_wr(i),
        w_update_weights => weights_wr((i+1)*CZ*(OMEGA+3)-1 downto i*CZ*(OMEGA+3)),

        out_central_diff       => central_diff(i),
        out_central_diff_valid => central_diff_valid(i),
        out_central_diff_zb    => central_diff_zb(i),
        in_prev_central_diffs  => prev_central_diffs,

        out_data     => pipeline_out_data((i+1)*(UMAX+D)-1 downto i*(UMAX+D)),
        out_num_bits => pipeline_out_num_bits((i+1)*len2bits(UMAX+D)-1 downto i*len2bits(UMAX+D)),
        out_valid    => pipeline_out_valid(i),
        out_last     => pipeline_out_last(i)
        );
  end generate g_pipelines;

  i_packer : entity work.combiner
    generic map (
      BLOCK_SIZE    => 64,
      N_WORDS       => PIPELINES,
      MAX_LENGTH    => UMAX + D,
      LITTLE_ENDIAN => LITTLE_ENDIAN)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_words   => pipeline_out_data,
      in_lengths => pipeline_out_num_bits,
      in_valid   => pipeline_out_valid(0),
      in_last    => pipeline_out_last(PIPELINES-1),

      out_data  => out_tdata,
      out_valid => out_tvalid,
      out_last  => out_tlast,

      over_threshold => combiner_over_threshold
      );

end rtl;
