library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use ieee.math_real.all;
use work.common.all;

entity ccsds123_top is
  generic (
    PIPELINES     : integer := 1;
    ON_THE_FLY    : boolean := true;
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
    NZ            : integer := 10;
    ISUNSIGNED    : boolean := true
    );
  port (
    clk     : in std_logic;
    aresetn : in std_logic;

    -- Input AXI stream
    s_axis_tdata  : in  std_logic_vector(PIPELINES * D-1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;

    m_axis_tdata  : out std_logic_vector(BUS_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tlast  : out std_logic;
    m_axis_tready : in  std_logic
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
  signal in_valid     : std_logic;
  signal in_data      : std_logic_vector(PIPELINES*D-1 downto 0);

  signal weights_wr      : std_logic_vector(PIPELINES-1 downto 0);
  signal weights_wr_data : signed(PIPELINES*CZ*(OMEGA+3)-1 downto 0);
  signal weights_rd_data : std_logic_vector(PIPELINES*CZ*(OMEGA+3)-1 downto 0);

  signal accumulator_wr      : std_logic_vector(PIPELINES-1 downto 0);
  signal accumulator_wr_data : std_logic_vector(PIPELINES*(D+COUNTER_SIZE)-1 downto 0);
  signal accumulator_rd      : std_logic_vector(PIPELINES-1 downto 0);
  signal accumulator_rd_data : std_logic_vector(PIPELINES*(D+COUNTER_SIZE)-1 downto 0);

  signal pipeline_last : std_logic_vector(PIPELINES-1 downto 0);
  signal last          : std_logic;

  signal pipeline_out_valid    : std_logic_vector(PIPELINES-1 downto 0);
  signal pipeline_out_last     : std_logic_vector(PIPELINES-1 downto 0);
  signal pipeline_out_data     : std_logic_vector(PIPELINES*(UMAX + D)-1 downto 0);
  signal pipeline_out_num_bits : unsigned(PIPELINES*num2bits(UMAX + D) - 1 downto 0);

  signal combiner_over_threshold : std_logic;

  type central_diff_arr_t is array (0 to PIPELINES-1) of signed(D+2 downto 0);
  signal central_diff_valid    : std_logic_vector(PIPELINES-1 downto 0);
  signal central_diffs_vec     : signed(PIPELINES*(D+3)-1 downto 0);
  signal central_diff          : central_diff_arr_t;
  signal from_local_diff_store : signed(P*(D+3)-1 downto 0);

  signal prev_s_reg : std_logic_vector(D-1 downto 0);

  signal to_pipeline_valid : std_logic_vector(PIPELINES-1 downto 0);

  -- Stall input if the pipeline is deeper than NZ, and we have filled up NZ
  -- components already
  --
  --  Local diff calculations: 3
  --  Dot product:             ceil(log2(CZ))
  --  Predictor:               2
  --  Weight update:           3
  --  Weight storage:          1
  constant C_INCL_PIPE_CTRL : boolean := not ON_THE_FLY and CZ > 0 and NZ/PIPELINES < DELAY_LOCAL_DIFF + delay_dot(CZ) + DELAY_PREDICTOR + DELAY_WEIGHT_UPDATE + 1;

  signal in_samples : std_logic_vector(D*PIPELINES-1 downto 0);

  signal from_sample_store_ne : std_logic_vector(PIPELINES*D-1 downto 0);
  signal from_sample_store_nw : std_logic_vector(PIPELINES*D-1 downto 0);
  signal from_sample_store_n  : std_logic_vector(PIPELINES*D-1 downto 0);
  signal from_sample_store_w  : std_logic_vector(PIPELINES*D-1 downto 0);
begin
  in_handshake  <= in_valid and in_ready;
  in_valid      <= s_axis_tvalid;
  in_data       <= s_axis_tdata;
  s_axis_tready <= in_ready;

  g_pipe_ctrl : if (C_INCL_PIPE_CTRL) generate
    signal count : integer range 0 to NZ;
  begin
    process (clk)
    begin
      if (rising_edge(clk)) then
        if (aresetn = '0') then
          count <= 0;
        else
          if (in_handshake = '1' and weights_wr(0) = '0') then
            count <= count + 1;
          elsif (weights_wr(0) = '1' and in_handshake = '0') then
            count <= count - 1;
          end if;
        end if;
      end if;
    end process;

    in_ready <= '1' when count < NZ/PIPELINES and combiner_over_threshold = '0' else '0';
  end generate g_pipe_ctrl;

  g_nopipe_ctrl : if (not C_INCL_PIPE_CTRL) generate
    in_ready <= '1' when ON_THE_FLY else not combiner_over_threshold;
  end generate g_nopipe_ctrl;

  last <= or_slv(pipeline_last);

  process (last, in_handshake)
  begin
    if (in_handshake = '1') then
      if (last = '0') then
        to_pipeline_valid <= (others => '1');
      else
        to_pipeline_valid <= (others => '0');
        for i in 0 to PIPELINES-1 loop
          if (NX*NY*NZ mod PIPELINES = 0 or i < NX*NY*NZ mod PIPELINES) then
            to_pipeline_valid(i) <= '1';
          end if;
        end loop;
      end if;
    else
      to_pipeline_valid <= (others => '0');
    end if;
  end process;

  -- Convert unsigned to signed if necessary
  g_signed_convert : if (ISUNSIGNED) generate
    process (in_data)
      variable sample : std_logic_vector(D-1 downto 0);
    begin
      for i in 0 to PIPELINES-1 loop
        sample                           := in_data((i+1)*D-1 downto i*D);
        sample(D-1)                      := not sample(D-1);
        in_samples((i+1)*D-1 downto i*D) <= sample;
      end loop;
    end process;
  end generate g_signed_convert;

  g_no_signed_convert : if (not ISUNSIGNED) generate
    in_samples <= in_data;
  end generate g_no_signed_convert;

  i_sample_store : entity work.sample_store
    generic map (
      PIPELINES => PIPELINES,
      D         => D,
      NX        => NX,
      NZ        => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_s     => in_samples,
      in_valid => in_handshake,

      out_s_ne => from_sample_store_ne,
      out_s_n  => from_sample_store_n,
      out_s_nw => from_sample_store_nw,
      out_s_w  => from_sample_store_w);

  i_weight_store : entity work.shared_store
    generic map (
      PIPELINES    => PIPELINES,
      DELAY        => DELAY_LOCAL_DIFF - 1,  -- read takes 1 cycle
      ELEMENT_SIZE => CZ*(OMEGA+3),
      ELEMENTS     => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr      => weights_wr(0),
      wr_data => std_logic_vector(weights_wr_data),

      rd      => in_handshake,
      rd_data => weights_rd_data
      );

  i_local_diff_store : entity work.local_diff_store
    generic map (
      PIPELINES => PIPELINES,
      P         => P,
      D         => D)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr            => central_diff_valid(0),
      wr_local_diff => central_diffs_vec,

      local_diffs => from_local_diff_store);

  i_accumulator_store : entity work.shared_store
    generic map (
      PIPELINES    => PIPELINES,
      DELAY        => 0,
      ELEMENT_SIZE => D+COUNTER_SIZE,
      ELEMENTS     => NZ)
    port map (
      clk     => clk,
      aresetn => aresetn,

      wr      => accumulator_wr(0),
      wr_data => accumulator_wr_data,

      rd      => accumulator_rd(0),
      rd_data => accumulator_rd_data
      );

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (aresetn = '0') then
        prev_s_reg <= (others => '0');
      elsif (in_handshake = '1') then
        prev_s_reg <= in_samples(PIPELINES*D-1 downto (PIPELINES-1)*D);
      end if;
    end if;
  end process;

  g_pipelines : for i in 0 to PIPELINES-1 generate
    signal prev_central_diffs : signed(P*(D+3)-1 downto 0);
    signal prev_s             : std_logic_vector(D-1 downto 0);
  begin

    -- Order in central difference store must be from most recent sample at
    -- index 0, so reorder it:
    central_diffs_vec((PIPELINES-i)*(D+3)-1 downto (PIPELINES-i-1)*(D+3)) <= central_diff(i);

    process (central_diff, from_local_diff_store, prev_s_reg, in_samples)
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
        prev_s <= in_samples(i*D-1 downto (i-1)*D);
      end if;
    end process;

    i_pipeline : entity work.pipeline_top
      generic map (
        PIPELINES      => PIPELINES,
        PIPELINE_INDEX => i,
        LITTLE_ENDIAN  => LITTLE_ENDIAN,
        COL_ORIENTED   => COL_ORIENTED,
        REDUCED        => REDUCED,
        OMEGA          => OMEGA,
        D              => D,
        P              => P,
        CZ             => CZ,
        R              => R,
        V_MIN          => V_MIN,
        V_MAX          => V_MAX,
        TINC_LOG       => TINC_LOG,
        UMAX           => UMAX,
        KZ_PRIME       => KZ_PRIME,
        COUNTER_SIZE   => COUNTER_SIZE,
        INITIAL_COUNT  => INITIAL_COUNT,
        NX             => NX,
        NY             => NY,
        NZ             => NZ
        )
      port map (
        clk     => clk,
        aresetn => aresetn,

        in_s           => in_samples((i+1)*D-1 downto i*D),
        in_s_ne        => from_sample_store_ne((i+1)*D-1 downto i*D),
        in_s_nw        => from_sample_store_nw((i+1)*D-1 downto i*D),
        in_s_n         => from_sample_store_n((i+1)*D-1 downto i*D),
        in_s_w         => from_sample_store_w((i+1)*D-1 downto i*D),
        in_prev_sample => prev_s,
        in_valid       => to_pipeline_valid(i),
        in_weights     => signed(weights_rd_data((i+1)*CZ*(OMEGA+3)-1 downto i*CZ*(OMEGA+3))),

        has_last_sample => pipeline_last(i),

        weights_wr      => weights_wr(i),
        weights_wr_data => weights_wr_data((i+1)*CZ*(OMEGA+3)-1 downto i*CZ*(OMEGA+3)),

        accumulator_wr      => accumulator_wr(i),
        accumulator_wr_data => accumulator_wr_data((i+1)*(D+COUNTER_SIZE)-1 downto i*(D+COUNTER_SIZE)),
        accumulator_rd      => accumulator_rd(i),
        accumulator_rd_data => accumulator_rd_data((i+1)*(D+COUNTER_SIZE)-1 downto i*(D+COUNTER_SIZE)),

        out_central_diff       => central_diff(i),
        out_central_diff_valid => central_diff_valid(i),
        in_prev_central_diffs  => prev_central_diffs,

        out_data     => pipeline_out_data((i+1)*(UMAX+D)-1 downto i*(UMAX+D)),
        out_num_bits => pipeline_out_num_bits((i+1)*num2bits(UMAX+D)-1 downto i*num2bits(UMAX+D)),
        out_valid    => pipeline_out_valid(i),
        out_last     => pipeline_out_last(i)
        );
  end generate g_pipelines;

  i_packer : entity work.packer
    generic map (
      BLOCK_SIZE        => BUS_WIDTH,
      N_WORDS           => PIPELINES,
      MAX_LENGTH        => UMAX + D,
      N_WORDS_PER_CHAIN => minimum(4, PIPELINES),
      LITTLE_ENDIAN     => LITTLE_ENDIAN)
    port map (
      clk     => clk,
      aresetn => aresetn,

      in_words   => pipeline_out_data,
      in_lengths => pipeline_out_num_bits,
      in_valid   => pipeline_out_valid(0),
      in_last    => or_slv(pipeline_out_last),

      out_data  => m_axis_tdata,
      out_valid => m_axis_tvalid,
      out_last  => m_axis_tlast,
      out_ready => m_axis_tready,

      over_threshold => combiner_over_threshold
      );

end rtl;
