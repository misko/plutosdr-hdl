`timescale 1ns/1fs

// Real digital CI16 shell/CDC/canonical tap, real shared XFFT/PSMA, real PIL1.
// Test-only447x2 default or explicit343x2 residue239 maps; pre-roll configuration pause is explicit. AXIS capture
// bytes are not DDR DMA completion, IIO receipt, ADC formatting or RF evidence.
module tb_starlink_pss_paired_realtime_psma_stop #(
  parameter integer MAP_BINS = 447,
  parameter integer USE_BANK_OWNED_XFFT = 0,
  parameter integer FAST_MHZ = 200
);
  localparam [63:0] FIRST = 64'h00000001fffffff0;
  localparam [63:0] PRE_FIRST = FIRST - 768;
  localparam integer TILE_SCORES = MAP_BINS * 2;
  localparam [63:0] MAP_END = FIRST + TILE_SCORES;
  localparam integer SOURCE_COUNT = 4096, PILOT_COUNT = 512, VISIT = 77;
  reg clk = 0, sample_clk = 0, fft_clk = 0, resetn = 0;
  always #5 clk = !clk;
  initial begin #2.1; forever #5 sample_clk = !sample_clk; end
  initial begin #1.3; forever #(500.0 / FAST_MHZ) fft_clk = !fft_clk; end
  reg sample_strobe = 0;
  reg [31:0] sample_data = 0;
  reg [63:0] sample_index = 0;
  wire canonical_valid, canonical_gap, canonical_flush, pilot_enable;
  wire signed [15:0] canonical_i, canonical_q;
  wire [63:0] canonical_index;
  wire pss_irq, pilot_irq, pilot_valid;
  wire [31:0] pilot_data;
  integer cycles = 0;
  wire pilot_ready = (cycles % 97) >= 8;
  reg [7:0] awaddr [0:1], araddr [0:1];
  reg [31:0] wdata [0:1];
  reg [1:0] awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  wire [1:0] awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp [0:1], rresp [0:1];
  wire [31:0] rdata [0:1];
  reg [31:0] source_words [0:SOURCE_COUNT-1];
  reg [31:0] pilot_words [0:PILOT_COUNT-1];
  reg [63:0] pilot_indexes [0:PILOT_COUNT-1];
  reg [63:0] metadata [0:9];
  reg [7:0] scores [0:1340];
  reg [31:0] snapshot [0:25];
  integer canonical_count = 0, input_phase = 0, score_count = 0;
  integer admitted_count = 0, delivered_count = 0, ddc_accepted_count = 0;
  integer pilot_at_stop = -1, canonical_at_stop = -1, ack_count = 0;
  integer sink_fd, map_count = 0, first_map_reads = 0;
  reg gap_seen = 0, pilot_armed = 0, expected_late_fault = 0;
  reg third_started = 0, third_returned = 0, second_started = 0, prior_stalled = 0;
  integer produced_at_ack = -1, candidate_fifo_at_ack = -1;
  integer bank_quiet_cycles = 0;
  reg inverse_busy_at_ack = 0;
  reg [31:0] held_data;
  reg [63:0] expected_canonical = PRE_FIRST - 2;

  axi_starlink_pss_acquisition #(
    .INPUT_RATE_MSPS(15), .ENABLE_PILOT_TAP(1), .USE_SHARED_XFFT(1),
    .USE_REALTIME_XFFT(1), .ENABLE_BOUNDARY_STOP(1)
  ) dut (
    .sample_clk(sample_clk), .sample_reset(!resetn), .fft_clk(fft_clk), .fft_resetn(resetn),
    .sample_strobe(sample_strobe), .sample_enable(1'b1), .sample_gap(1'b0),
    .sample_i(sample_data[15:0]), .sample_q(sample_data[31:16]), .sample_index(sample_index),
    .pilot_enable(pilot_enable), .canonical_valid(canonical_valid), .canonical_gap(canonical_gap),
    .canonical_flush(canonical_flush), .canonical_i(canonical_i), .canonical_q(canonical_q),
    .canonical_index(canonical_index), .irq(pss_irq),
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr[0]), .s_axi_awvalid(awvalid[0]), .s_axi_awready(awready[0]),
    .s_axi_wdata(wdata[0]), .s_axi_wstrb(4'hf), .s_axi_wvalid(wvalid[0]), .s_axi_wready(wready[0]),
    .s_axi_bvalid(bvalid[0]), .s_axi_bresp(bresp[0]), .s_axi_bready(bready[0]),
    .s_axi_araddr(araddr[0]), .s_axi_arvalid(arvalid[0]), .s_axi_arready(arready[0]),
    .s_axi_rvalid(rvalid[0]), .s_axi_rdata(rdata[0]), .s_axi_rresp(rresp[0]), .s_axi_rready(rready[0]),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0)
  );
  // Production shell has fixed map geometry. Override BOTH real child modules
  // in this bench only; keep15-bit outer index width so padding is exercised.
  defparam dut.acquisition.PHASE_BINS = MAP_BINS;
  // Test-only engine selector, like the reduced geometry below. No AXI
  // receiver parameter, packaged capability or board profile changes.
  defparam dut.acquisition.USE_BANK_OWNED_XFFT = USE_BANK_OWNED_XFFT;
  defparam dut.acquisition.TILE_FRAMES = 2;
  defparam dut.acquisition.MAP_SEGMENT_ADDRESS_WIDTH = 9;
  defparam dut.acquisition.MAP_SEGMENT_COUNT = 1;
  defparam dut.acquisition.MAP_SEGMENT_INDEX_WIDTH = 1;
  defparam dut.phase_map_control.PHASE_BINS = MAP_BINS;
  defparam dut.phase_map_control.TILE_FRAMES = 2;

  wire observed_third_inverse_final, observed_inverse_busy, observed_pipeline_active;
  generate if (USE_BANK_OWNED_XFFT) begin : engine_observer
    // Allow eight actual fast clocks after slow teardown, then require the
    // bank and vendor reset epoch to stay closed through the late-fault case.
    // This is a bounded digital witness, not physical reset/CDC signoff.
    always @(posedge fft_clk) begin
      #0.001;
      if (!resetn || ack_count < 2) bank_quiet_cycles = 0;
      else if (!observed_pipeline_active) begin
        bank_quiet_cycles = bank_quiet_cycles + 1;
        if (bank_quiet_cycles >= 8 &&
            (dut.acquisition.bank_transform.iq_to_score.island.fast_running !== 1'b0 ||
             dut.acquisition.bank_transform.iq_to_score.island.core_aresetn !== 1'b0 ||
             dut.acquisition.bank_transform.iq_to_score.island.config_valid !== 1'b0 ||
             dut.acquisition.bank_transform.iq_to_score.island.core_input_valid !== 1'b0 ||
             dut.acquisition.bank_transform.iq_to_score.island.core_output_valid !== 1'b0))
          fail("bank fast domain not quiescent after bounded local teardown");
      end else if (bank_quiet_cycles != 0)
        fail("bank pipeline reactivated after terminal teardown");
    end
    // Witness actual core consumption at fft_clk, not slow source-bank capture.
    always @(posedge fft_clk)
      if (!resetn) begin second_started = 0; third_started = 0; end
      else if (dut.acquisition.bank_transform.iq_to_score.island.core_input_valid &&
          dut.acquisition.bank_transform.iq_to_score.island.core_input_ready &&
          !dut.acquisition.bank_transform.iq_to_score.island.next_inverse &&
          dut.acquisition.bank_transform.iq_to_score.island.selected_position == 0) begin
        if (dut.acquisition.bank_transform.iq_to_score.island.engine_metadata[68:5] == FIRST + 447)
          second_started = 1;
        if (dut.acquisition.bank_transform.iq_to_score.island.engine_metadata[68:5] == FIRST + 894)
          third_started = 1;
      end
    assign observed_third_inverse_final = dut.acquisition.bank_transform.iq_to_score.inverse_output_valid &&
      dut.acquisition.bank_transform.iq_to_score.inverse_output_last &&
      dut.acquisition.bank_transform.iq_to_score.inverse_output_block_start == FIRST + 894;
    assign observed_inverse_busy = dut.acquisition.bank_transform.iq_to_score.island.result_busy &&
      dut.acquisition.bank_transform.iq_to_score.island.next_inverse;
    assign observed_pipeline_active = dut.acquisition.bank_transform.iq_to_score.pipeline_active;
  end else begin : engine_observer
    always @(posedge clk)
      if (!resetn) begin second_started = 0; third_started = 0; end
      else if (dut.acquisition.shared_transform.iq_to_score.shared_input_accept &&
          !dut.acquisition.shared_transform.iq_to_score.choose_inverse &&
          dut.acquisition.shared_transform.iq_to_score.scheduler_fft_position == 0) begin
        if (dut.acquisition.shared_transform.iq_to_score.scheduler_fft_block_start == FIRST + 447)
          second_started = 1;
        if (dut.acquisition.shared_transform.iq_to_score.scheduler_fft_block_start == FIRST + 894)
          third_started = 1;
      end
    assign observed_third_inverse_final = dut.acquisition.shared_transform.iq_to_score.inverse_output_accept &&
      dut.acquisition.shared_transform.iq_to_score.inverse_output_last &&
      dut.acquisition.shared_transform.iq_to_score.inverse_output_block_start == FIRST + 894;
    assign observed_inverse_busy = dut.acquisition.shared_transform.iq_to_score.inverse_busy;
    assign observed_pipeline_active = dut.acquisition.shared_transform.iq_to_score.pipeline_active;
  end endgenerate

  axi_starlink_pilot_capture #(.INPUT_RATE_MSPS(15)) pilot (
    .canonical_valid(canonical_valid), .canonical_gap(canonical_gap), .canonical_flush(canonical_flush),
    .canonical_i(canonical_i), .canonical_q(canonical_q), .canonical_index(canonical_index),
    .pilot_enable(pilot_enable), .m_axis_tvalid(pilot_valid), .m_axis_tdata(pilot_data),
    .m_axis_tready(pilot_ready), .irq(pilot_irq),
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr[1]), .s_axi_awvalid(awvalid[1]), .s_axi_awready(awready[1]),
    .s_axi_wdata(wdata[1]), .s_axi_wstrb(4'hf), .s_axi_wvalid(wvalid[1]), .s_axi_wready(wready[1]),
    .s_axi_bvalid(bvalid[1]), .s_axi_bresp(bresp[1]), .s_axi_bready(bready[1]),
    .s_axi_araddr(araddr[1]), .s_axi_arvalid(arvalid[1]), .s_axi_arready(arready[1]),
    .s_axi_rvalid(rvalid[1]), .s_axi_rdata(rdata[1]), .s_axi_rresp(rresp[1]), .s_axi_rready(rready[1]),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0)
  );

  task automatic fail(input string message);
    $display("PAIRED_REALTIME_PSMA_STOP_FAIL %s cycles=%0d canonical=%0d scores=%0d pilot=%0d health=%08h capture=%08h ddc=%02h",
      message, cycles, canonical_count, score_count, delivered_count,
      dut.detector_health_flags, pilot.faults, pilot.ddc_fault);
    $fatal(1, "paired full-shell check failed: %s", message);
    $finish; // Explicit fallback: do not rely on bare $fatal(1) in xsim.
  endtask
  task automatic write_reg(input integer port, input [7:0] address, input [31:0] value);
    integer timeout;
    @(negedge clk); awaddr[port] = address; wdata[port] = value;
    awvalid[port] = 1; wvalid[port] = 1; bready[port] = 1; timeout = 0;
    while (!(awready[port] && wready[port]) && timeout < 100) begin
      @(posedge clk); timeout = timeout + 1;
    end
    if (timeout == 100) fail("AXI address/data timeout");
    @(negedge clk); awvalid[port] = 0; wvalid[port] = 0; timeout = 0;
    while (!bvalid[port] && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || bresp[port] != 0) fail("AXI write response");
    @(negedge clk); bready[port] = 0;
  endtask
  task automatic read_reg(input integer port, input [7:0] address, output [31:0] value);
    integer timeout;
    @(negedge clk); araddr[port] = address; arvalid[port] = 1; rready[port] = 1; timeout = 0;
    while (!arready[port] && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100) fail("AXI read address timeout");
    @(negedge clk); arvalid[port] = 0; timeout = 0;
    while (!rvalid[port] && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || rresp[port] != 0) fail("AXI read response");
    value = rdata[port]; @(negedge clk); rready[port] = 0;
  endtask
  task automatic expect_reg(input integer port, input [7:0] address, input [31:0] expected);
    reg [31:0] value;
    read_reg(port, address, value);
    if (value !== expected) begin
      $display("PAIRED_REGISTER port=%0d address=%02h actual=%08h expected=%08h", port, address, value, expected);
      fail("register mismatch");
    end
  endtask
  task automatic expect_stop_word(input integer index, input [31:0] expected);
    write_reg(0, 8'hfc, index); expect_reg(0, 8'hfc, expected);
  endtask
  task automatic drive_word(input [63:0] index, input [31:0] value);
    integer sent;
    sent = 0;
    while (!sent) begin
      @(negedge sample_clk); sample_strobe = 0; input_phase = input_phase + 15;
      if (input_phase >= 100) begin
        input_phase = input_phase - 100;
        sample_strobe = 1; sample_index = index; sample_data = value; sent = 1;
      end
    end
  endtask
  task automatic source_range(input integer first, input integer count);
    integer index;
    for (index = first; index < first + count; index = index + 1)
      drive_word(PRE_FIRST + index, source_words[index]);
    @(negedge sample_clk); sample_strobe = 0;
  endtask
  task automatic healthy;
    if (dut.detector_health_flags || dut.discontinuity_abort_count || dut.discarded_score_count ||
        dut.map_overrun_count || dut.score_protocol_error_count || dut.map_arithmetic_overflow_count ||
        dut.map_read_error_count || dut.map_release_error_count || dut.ingress_overflow_sticky ||
        dut.ingress_dropped_sample_count || dut.phase_map_control.bridge_read_error_count ||
        (expected_late_fault ? dut.phase_map_control.bridge_release_error_count > 1 :
          dut.phase_map_control.bridge_release_error_count != 0) ||
        dut.phase_map_control.snapshot_request_overrun_count)
      fail("unexpected acquisition/map/bridge/CDC health");
    if (canonical_flush || pilot.faults || pilot.ddc_fault || pilot.ddc_clips || pilot_irq)
      fail("pilot or shared canonical flush fault");
  endtask

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (cycles > 160000) fail("bounded watchdog");
    if (resetn) begin
      healthy();
      if (expected_late_fault && (dut.acquisition_enable || observed_pipeline_active ||
          dut.acquisition.score_valid || dut.map_publish_count != 1 || dut.map_ready_mask ||
          pilot_enable || delivered_count != PILOT_COUNT || dut.accepted_score_count != TILE_SCORES))
        fail("late bridge fault reactivated or corrupted the stopped paired capture");
      if (canonical_valid) begin
        if (canonical_index !== expected_canonical || canonical_gap !== !gap_seen)
          fail("canonical ordinal or first-gap marker mismatch");
        if (canonical_count < 2) begin
          if ({canonical_q, canonical_i} !== canonical_count + 1 || pilot_enable || dut.acquisition_enable)
            fail("initial CDC gap was hidden or consumed by an armed engine");
          gap_seen = 1;
        end else if ({canonical_q, canonical_i} !== source_words[canonical_count-2])
          fail("canonical CI16 differs from independent common source");
        expected_canonical = expected_canonical + 1;
        canonical_count = canonical_count + 1;
      end
      if (pilot.ddc.accept) ddc_accepted_count = ddc_accepted_count + 1;
      if (pilot.push) begin
        if (admitted_count >= PILOT_COUNT || pilot.capture_data !== pilot_words[admitted_count] ||
            pilot.capture_index !== pilot_indexes[admitted_count] ||
            !pilot.capture_support || pilot.capture_visit !== VISIT)
          fail("admitted pilot IQ/index/history/visit mismatch");
        admitted_count = admitted_count + 1;
      end
      if (prior_stalled && (!pilot_valid || pilot_data !== held_data))
        fail("AXIS promise changed while stalled");
      prior_stalled = pilot_valid && !pilot_ready; held_data = pilot_data;
      if (pilot_valid && pilot_ready) begin
        if (delivered_count >= PILOT_COUNT || pilot_data !== pilot_words[delivered_count])
          fail("AXIS bytes differ from independent pilot oracle");
        $fwrite(sink_fd, "%c%c%c%c", pilot_data[7:0], pilot_data[15:8], pilot_data[23:16], pilot_data[31:24]);
        $display("PAIRED_PILOT_WORD ordinal=%0d newest=%016h word=%08h", delivered_count,
                 pilot_indexes[delivered_count], pilot_data);
        delivered_count = delivered_count + 1;
      end
      if (dut.acquisition.score_valid) begin
        // The map fence controls MAP admission, not the tagger's already
        // computed tail while map publication/ACK is retiring. Check every
        // observed score against the same oracle, distinguish prefix from tail.
        if (score_count >= (MAP_BINS == 447 ? 894 : 1341) ||
            dut.acquisition.score_value !== scores[score_count] ||
            dut.acquisition.score_start_index !== FIRST + score_count ||
            dut.acquisition.score_phase !== score_count % MAP_BINS || dut.acquisition.score_denominator_zero)
          fail("original frozen score/index/phase mismatch or post-fence score");
        score_count = score_count + 1;
      end
      if (dut.map_read_request && (dut.map_read_index[14:9] !== 0 || dut.map_read_index >= MAP_BINS))
        fail("outer15-bit map index was not correctly zero padded");
      if (observed_third_inverse_final)
        third_returned = 1;
      if (dut.stop_ack) begin
        ack_count = ack_count + 1;
        if (ack_count == 2) begin
          if (!pilot_enable || score_count < TILE_SCORES ||
              dut.accepted_score_count != TILE_SCORES || !second_started)
            fail("terminal lacked exact selected prefix or independently active pilot");
          if (MAP_BINS == 447 && (!third_started || third_returned || score_count != 894))
            fail("default terminal lacked original third-block work witness");
          produced_at_ack = score_count;
          candidate_fifo_at_ack = dut.candidate_fifo_stored_count;
          inverse_busy_at_ack = observed_inverse_busy;
          $display("PAIRED_STOP_TAIL map_bins=%0d selected_scores=%0d produced_scores=%0d residue=%0d second_started=%0d third_started=%0d third_returned=%0d candidate_fifo=%0d inverse_busy=%0d",
            MAP_BINS, TILE_SCORES, score_count, TILE_SCORES % 447, second_started,
            third_started, third_returned, candidate_fifo_at_ack, inverse_busy_at_ack);
          pilot_at_stop = delivered_count; canonical_at_stop = canonical_count;
        end
      end
    end
  end

  integer n;
  reg [31:0] value, generation;
  initial begin
    if (MAP_BINS != 447 && MAP_BINS != 343)
      fail("only default447x2 or explicit343x2 test geometry is admitted");
    if (MAP_BINS == 343 && TILE_SCORES % 447 != 1280000 % 447)
      fail("residue geometry no longer matches the production block-boundary residue");
    for (n = 0; n < 2; n = n + 1) begin awaddr[n] = 0; araddr[n] = 0; wdata[n] = 0; end
    $readmemh("paired_source_ci16.mem", source_words);
    $readmemh("paired_pilot_ci16.mem", pilot_words);
    $readmemh("paired_pilot_newest.mem", pilot_indexes);
    $readmemh("paired_metadata.mem", metadata);
    $readmemh("scores_u8.mem", scores);
    if (metadata[0] != FIRST || metadata[1] != PRE_FIRST || metadata[6] > FIRST ||
        metadata[7] + 1 < FIRST + 959 || metadata[8] > FIRST || metadata[9] < FIRST + 959)
      fail("independent support fixture does not contain complete selected-map FFT envelope");
    if (dut.acquisition.PHASE_BINS != MAP_BINS || dut.phase_map_control.PHASE_BINS != MAP_BINS ||
        dut.acquisition.TILE_FRAMES != 2 || dut.phase_map_control.TILE_FRAMES != 2 ||
        dut.acquisition.PHASE_INDEX_WIDTH != 15 || dut.phase_map_control.PHASE_INDEX_WIDTH != 15 ||
        dut.acquisition.phase_map.i_map_bank_0.DEPTH != MAP_BINS ||
        dut.acquisition.phase_map.i_map_bank_1.DEPTH != MAP_BINS)
      fail("test-only full-shell/control/actual-bank geometry inventory mismatch");
    sink_fd = $fopen("paired_pilot_actual.ci16", "wb");
    if (!sink_fd) fail("cannot open bounded AXIS sink");
    repeat (10) @(negedge clk); resetn = 1;
    repeat (500) @(negedge clk);
    drive_word(PRE_FIRST - 2, 32'h00000001);
    drive_word(PRE_FIRST - 1, 32'h00000002);
    @(negedge sample_clk); sample_strobe = 0;
    wait(canonical_count == 2); repeat (30) @(negedge clk);
    // Gap is held with the CDC payload even after VALID drops. Only a real
    // following clean beat, not waiting/masking, establishes this prerequisite.
    if (canonical_gap !== 0 || canonical_valid || dut.ingress_fifo_level)
      fail("startup did not establish a clean drained canonical payload before ARM");
    expect_reg(0, 8'h04, 32'h10006); expect_reg(0, 8'h08, MAP_BINS);
    expect_reg(0, 8'h0c, 32'h21002); expect_reg(0, 8'h10, 32'h33f);
    write_reg(0, 8'h14, 1);
    write_reg(1, 8'h08, 4); write_reg(1, 8'h20, VISIT);
    write_reg(1, 8'h9c, PILOT_COUNT); write_reg(1, 8'h08, 1); pilot_armed = 1;
    write_reg(0, 8'hf8, 1);
    wait(dut.phase_map_control.stop_terminal_valid); @(negedge clk);
    expect_stop_word(2, 6); expect_stop_word(4, 1); expect_stop_word(5, 0);
    if (ack_count != 1 || dut.acquisition_enable || !pilot_enable || score_count)
      fail("empty ticket did not preserve armed pilot");
    source_range(0, 768);
    wait(canonical_count == 770); repeat (2000) @(negedge clk);
    if (!pilot_enable || admitted_count < 1 || !dut.conditioner_enable || dut.ingress_fifo_level)
      fail("pilot prehistory or actual conditioner retention missing");
    $display("PAIRED_PREROLL_PASS real_shell=1 real_cdc=1 real_canonical=1 samples=768 empty_ticket=1 explicit_configuration_pause=1");
    write_reg(0, 8'h14, 1); // Enable only: never reset pilot filter history.
    repeat (20) @(negedge clk);
    fork
      source_range(768, SOURCE_COUNT - 768);
      begin
        wait(score_count >= 200); write_reg(0, 8'hf8, 2);
        wait(dut.phase_map_control.stop_terminal_valid); @(negedge clk);
        expect_stop_word(2, 32'h16); expect_stop_word(4, 2); expect_stop_word(5, 1);
        expect_stop_word(6, FIRST[31:0]); expect_stop_word(7, FIRST[63:32]);
        expect_stop_word(8, MAP_END[31:0]); expect_stop_word(9, MAP_END[63:32]); expect_stop_word(10, 0);
        if (ack_count != 2 || dut.acquisition_enable || !pss_irq || dut.map_ready_mask != 1 ||
            dut.map_publish_count != 1 || dut.accepted_score_count != TILE_SCORES ||
            dut.map_generation_0 != 1 || dut.map_start_index_0 != FIRST)
          fail("selected map terminal ownership/IRQ/count mismatch");
        write_reg(0, 8'h1c, 0); write_reg(0, 8'h20, 0);
        for (first_map_reads = 0; first_map_reads < MAP_BINS; first_map_reads = first_map_reads + 1) begin
          expect_reg(0, 8'h24, {24'd0, scores[first_map_reads]} + {24'd0, scores[first_map_reads + MAP_BINS]});
          map_count = map_count + 1;
        end
        write_reg(0, 8'h28, 1);
      end
    join
    wait(canonical_count == SOURCE_COUNT + 2);
    wait(!pilot_enable && delivered_count == PILOT_COUNT); repeat (100) @(negedge clk);
    if (pilot_at_stop < 1 || pilot_at_stop >= PILOT_COUNT || delivered_count <= pilot_at_stop + 32 ||
        canonical_count <= canonical_at_stop + 512 || score_count < TILE_SCORES || map_count != MAP_BINS ||
        dut.accepted_score_count != TILE_SCORES ||
        pss_irq || dut.map_ready_mask || dut.map_publish_count != 1 ||
        observed_pipeline_active)
      fail("source/pilot continuation or healthy coarse local shutdown not proven");
    expect_stop_word(2, 32'h16); expect_stop_word(4, 2); expect_stop_word(5, 1);
    expect_stop_word(6, FIRST[31:0]); expect_stop_word(7, FIRST[63:32]);
    expect_stop_word(8, MAP_END[31:0]); expect_stop_word(9, MAP_END[63:32]); expect_stop_word(10, 0);
    write_reg(1, 8'h08, 8); read_reg(1, 8'h98, generation);
    if (generation == 0) fail("no fresh PIL1 hardware snapshot");
    for (n = 0; n < 26; n = n + 1) read_reg(1, 8'h30 + 4*n, snapshot[n]);
    expect_reg(1, 8'h98, generation);
    if ({snapshot[1], snapshot[0]} !== metadata[2] || {snapshot[3], snapshot[2]} !== metadata[3] ||
        {snapshot[5], snapshot[4]} != PILOT_COUNT || {snapshot[7], snapshot[6]} != PILOT_COUNT ||
        {snapshot[9], snapshot[8]} !== metadata[4] || {snapshot[15], snapshot[14]} !== metadata[5] ||
        {snapshot[13], snapshot[12]} != ddc_accepted_count || snapshot[16] || snapshot[17][7:0] ||
        snapshot[18] || snapshot[19] != 24 || snapshot[20] != VISIT || snapshot[22] ||
        snapshot[23] || snapshot[24] || snapshot[25] || admitted_count != PILOT_COUNT)
      fail("final PIL1 snapshot accounting/metadata/health mismatch");
    $write("PAIRED_PIL1_SNAPSHOT generation=%0d raw_words=", generation);
    for (n = 0; n < 26; n = n + 1) $write(" %08x", snapshot[n]);
    $write("\n");
    healthy(); $fclose(sink_fd);
    $display("PAIRED_MAP_PILOT_PASS exact_scores=%0d exact_map_words=%0d exact_pilot_words=512 exact_bytes=2048 shared_support_envelope=959 pilot_after_stop=1 healthy_snapshot=1", TILE_SCORES, MAP_BINS);
    // Real bridge misuse AFTER successful drain must invalidate joint health;
    // neither the historical terminal nor the already captured pilot changes.
    expected_late_fault = 1;
    write_reg(0, 8'h28, 1); repeat (20) @(negedge clk);
    expect_stop_word(2, 32'h1e); expect_stop_word(4, 2); expect_stop_word(5, 1);
    expect_stop_word(6, FIRST[31:0]); expect_stop_word(7, FIRST[63:32]);
    expect_stop_word(8, MAP_END[31:0]); expect_stop_word(9, MAP_END[63:32]);
    write_reg(0, 8'hfc, 10); read_reg(0, 8'hfc, value);
    if (!value[2] || dut.phase_map_control.bridge_release_error_count != 1 || pilot.faults || pilot.ddc_fault ||
        pilot.delivered != PILOT_COUNT || dut.map_publish_count != 1)
      fail("late bridge failure lost evidence or corrupted independent pilot");
    $display("PAIRED_LATE_FAULT_PASS actual_invalid_release=1 failed_joint_health=1 terminal_coordinates_retained=1 pilot_bytes_preserved=1");
    if (MAP_BINS == 343)
      $display("PAIRED_RESIDUE_PASS selected_scores=686 map_words=343 residue=239 post_fence_tail_not_map_admission=1");
    $display("PAIRED_REALTIME_PSMA_STOP_PASS source_words=4096 pilot_words=512 map_words=%0d NO_ADC_DMA_IIO_FINE_PRODUCTION_OR_PHYSICAL_CLAIM", MAP_BINS);
    if (USE_BANK_OWNED_XFFT) begin
      if (bank_quiet_cycles < 32) fail("insufficient fast-clock teardown observations");
      $display("PAIRED_BANK_QUIESCENCE_PASS reset_held=1 minimum_fast_cycles=32 no_fast_restart=1");
      $display("PAIRED_BANK_PASS map_bins=%0d selected_scores=%0d exact_pilot_bytes=2048 fast_mhz=%0d TEST_ONLY_SELECTOR_NOT_RECEIVER", MAP_BINS, TILE_SCORES, FAST_MHZ);
    end
    $finish;
  end
endmodule
