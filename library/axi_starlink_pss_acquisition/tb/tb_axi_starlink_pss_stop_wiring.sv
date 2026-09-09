`timescale 1ns/1ps

// Real acquisition shell/CDC/IQ-to-map/phase tagger/map/control composition.
// Only the FFT score producer is replaced by a declared toy-score fixture.
// This proves stop/tap wiring, not FFT performance, PIL1 capture, or RF truth.
module tb_axi_starlink_pss_stop_wiring;
  reg clk = 0, resetn = 0;
  always #5 clk = !clk;
  reg source_running = 0, sample_strobe = 0;
  wire sample_enable = 1'b1, sample_gap = 1'b0, pilot_enable = 1'b1;
  wire signed [15:0] sample_i = 16'sd7, sample_q = -16'sd3;
  reg [63:0] sample_index = 0;
  integer source_phase = 0;
  reg [63:0] next_source_index = 64'h100000000;
  wire canonical_valid, canonical_gap, canonical_flush, irq;
  wire signed [15:0] canonical_i, canonical_q;
  wire [63:0] canonical_index;
  reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
  reg [7:0] s_axi_awaddr = 0, s_axi_araddr = 0;
  reg [31:0] s_axi_wdata = 0;
  reg [3:0] s_axi_wstrb = 0;
  wire s_axi_awready, s_axi_wready, s_axi_bvalid;
  wire [1:0] s_axi_bresp, s_axi_rresp;
  reg s_axi_arvalid = 0, s_axi_rready = 0;
  wire s_axi_arready, s_axi_rvalid;
  wire [31:0] s_axi_rdata;
  integer canonical_count = 0, flush_count = 0;
  reg have_canonical = 0;
  reg [63:0] previous_canonical_index = 0;

  axi_starlink_pss_acquisition #(
    .ENABLE_PILOT_TAP(1), .USE_SHARED_XFFT(1), .ENABLE_BOUNDARY_STOP(1)
  ) dut (.sample_clk(clk), .fft_clk(clk), .fft_resetn(resetn), .sample_reset(!resetn),
         .s_axi_aclk(clk), .s_axi_aresetn(resetn), .s_axi_awprot(3'd0), .s_axi_arprot(3'd0), .*);

  task automatic fail(input string message);
    $display("PSMA_STOP_WIRING_FAIL %s", message);
    $fatal(1);
  endtask
  always @(negedge clk) begin
    sample_strobe = 0;
    if (resetn && source_running) begin
      source_phase = (source_phase + 1) % 4;
      if (source_phase == 0) begin
        sample_strobe = 1;
        sample_index = next_source_index;
        next_source_index = next_source_index + 1;
      end
    end
  end
  always @(posedge clk) begin
    if (resetn && canonical_flush) flush_count = flush_count + 1;
    if (resetn && canonical_valid) begin
      // The real CDC intentionally gap-tags the first sample of its reset
      // epoch. Stop must preserve that marker and introduce no later gap.
      if (canonical_gap !== !have_canonical || canonical_i !== sample_i || canonical_q !== sample_q ||
          (have_canonical && canonical_index != previous_canonical_index + 1))
        fail("stop/control wiring disrupted canonical tap data or continuity");
      have_canonical = 1;
      previous_canonical_index = canonical_index;
      canonical_count = canonical_count + 1;
    end
  end
  task automatic axi_write(input [7:0] address, input [31:0] value);
    integer timeout;
    @(negedge clk);
    s_axi_awaddr = address; s_axi_wdata = value; s_axi_wstrb = 4'hf;
    s_axi_awvalid = 1; s_axi_wvalid = 1; s_axi_bready = 1;
    timeout = 0;
    while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
      @(posedge clk); timeout = timeout + 1;
    end
    if (timeout == 100) fail("AXI write address/data timeout");
    @(negedge clk); s_axi_awvalid = 0; s_axi_wvalid = 0;
    timeout = 0;
    while (!s_axi_bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_bresp != 0) fail("AXI write response failure");
    @(negedge clk); s_axi_bready = 0;
  endtask
  task automatic expect_register(input [7:0] address, input [31:0] expected);
    integer timeout;
    @(negedge clk); s_axi_araddr = address; s_axi_arvalid = 1; s_axi_rready = 1;
    timeout = 0;
    while (!s_axi_arready && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100) fail("AXI read address timeout");
    @(negedge clk); s_axi_arvalid = 0;
    timeout = 0;
    while (!s_axi_rvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_rresp != 0 || s_axi_rdata !== expected) begin
      $display("PSMA_STOP_WIRING_REGISTER address=%02h got=%08h expected=%08h",
               address, s_axi_rdata, expected);
      fail("AXI read response failure/mismatch");
    end
    @(negedge clk); s_axi_rready = 0;
  endtask
  task automatic expect_word(input integer index, input [31:0] expected);
    axi_write(8'hfc, index); expect_register(8'hfc, expected);
  endtask

  integer before_count;
  initial begin
    repeat (8) @(negedge clk);
    resetn = 1;
    repeat (20010) @(negedge clk);
    expect_register(8'h04, 32'h10006); expect_register(8'h10, 32'h33f);
    axi_write(8'h14, 1);
    axi_write(8'hf8, 1);
    expect_register(8'hf8, 1); expect_word(2, 6); expect_word(5, 0);
    if (dut.acquisition_enable || !dut.acquisition.phase_map.stop_done ||
        dut.discontinuity_abort_count != 0 || flush_count != 0)
      fail("empty stop did not traverse actual composition cleanly");
    source_running = 1;
    wait(canonical_count >= 100);
    if (!dut.conditioner_enable || dut.acquisition_enable || flush_count != 0)
      fail("successful stop disabled/flushed the independent pilot tap");

    axi_write(8'h14, 1);
    wait(dut.acquisition.phase_map.state == 2 && dut.accepted_score_count >= 2);
    axi_write(8'hf8, 2);
    expect_register(8'hf8, 2); expect_word(2, 32'h21);
    if (!dut.acquisition.phase_map.stop_pending || !dut.acquisition.stop_pending)
      fail("request was not delivered through real IQ-to-map wiring");
    axi_write(8'h14, 0);
    expect_word(2, 32'ha); expect_word(4, 2); expect_word(5, 0);
    if (dut.discontinuity_abort_count != 1 || dut.acquisition_enable || flush_count != 0)
      fail("real partial stop abort lost accounting or flushed the pilot");
    before_count = canonical_count;
    wait(canonical_count >= before_count + 100);
    if (!dut.conditioner_enable || canonical_count <= 200)
      fail("canonical input did not continue after the partial abort");

    // Deliberate legacy flush still reaches the canonical tap. No claim is
    // made that this explicit flush is suitable for a complete pilot receipt.
    axi_write(8'h14, 3);
    if (!dut.acquisition_enable || flush_count != 1)
      fail("CONTROL3 enable/flush semantics changed in the actual shell");
    axi_write(8'h14, 2);
    if (dut.acquisition_enable || flush_count != 2)
      fail("CONTROL2 disable/flush semantics changed in the actual shell");
    $display("PSMA_STOP_WIRING_PASS real_shell=1 real_iq_to_map=1 real_map=1 real_cdc=1 canonical_after_stop=1 fft_score_stub=1 no_pilot_capture_or_rf_claim=1");
    $finish;
  end
  initial begin #3000000; fail("bounded composition wiring timeout"); end
endmodule

// Interface-only toy score producer: all actual phase tagging, map RAM,
// stop logic, and acquisition health wiring above remain the real modules.
module starlink_pss_iq_to_score_shared #(
  parameter integer USE_REALTIME_XFFT = 0,
  parameter KERNEL_ROM_FILE = "",
  parameter [30:0] COEFFICIENT_ENERGY = 0
) (
  input wire clk, resetn, fft_clk, fft_resetn, enable, flush,
  input wire sample_valid, sample_gap,
  input wire signed [15:0] sample_i, sample_q,
  input wire [63:0] sample_index,
  output wire score_valid,
  input wire score_ready,
  output wire [7:0] score_value,
  output wire [63:0] score_start_index,
  output wire score_denominator_zero, detector_fault,
  output wire scheduler_gap_pulse, scheduler_index_error_pulse, scheduler_overflow_pulse,
  output wire forward_fft_fault, kernel_join_fault, product_overflow_fault, inverse_fft_fault,
  output wire forward_exponent_fault, candidate_path_fault,
  output wire [9:0] candidate_fifo_stored_count, candidate_fifo_maximum_stored_count
);
  assign score_valid = resetn && enable && !flush && sample_valid;
  assign score_value = sample_i[7:0];
  assign score_start_index = sample_index;
  assign scheduler_gap_pulse = enable && sample_gap;
  assign score_denominator_zero = 0;
  assign detector_fault = 0;
  assign scheduler_index_error_pulse = 0;
  assign scheduler_overflow_pulse = 0;
  assign forward_fft_fault = 0;
  assign kernel_join_fault = 0;
  assign product_overflow_fault = 0;
  assign inverse_fft_fault = 0;
  assign forward_exponent_fault = 0;
  assign candidate_path_fault = 0;
  assign candidate_fifo_stored_count = 0;
  assign candidate_fifo_maximum_stored_count = 0;
endmodule
