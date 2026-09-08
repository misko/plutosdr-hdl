// SPDX-License-Identifier: GPL-2.0
// Combinational equivalence of the factored gate on the actual adapter. No
// vendor FFT model or reachable-state assumption is needed for this check.
`timescale 1ns/1ps
module tb_starlink_pss_xfft_output_gate;
  parameter integer CHECK_IDENTITY = 1;
  reg resetn, flush, input_valid, input_last, output_ready;
  reg [8:0] input_position;
  reg [63:0] input_block_start_index;
  reg core_input_tready, core_output_tvalid, core_output_tlast;
  reg [23:0] core_output_tuser;
  reg [7:0] core_status_tdata;
  reg core_status_tvalid, core_event_frame_started;
  reg core_event_tlast_unexpected, core_event_tlast_missing;
  reg core_event_status_channel_halt;
  starlink_pss_xfft_block_adapter #(
    .DATA_WIDTH(18), .CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY)
  ) dut (
    .clk(1'b0), .resetn(resetn), .flush(flush),
    .input_valid(input_valid), .input_i(18'sd0), .input_q(18'sd0),
    .input_position(input_position), .input_last(input_last),
    .input_block_start_index(input_block_start_index), .output_ready(output_ready),
    .core_config_tready(1'b1), .core_input_tready(core_input_tready),
    .core_output_tdata(48'd0), .core_output_tuser(core_output_tuser),
    .core_output_tvalid(core_output_tvalid), .core_output_tlast(core_output_tlast),
    .core_status_tdata(core_status_tdata), .core_status_tvalid(core_status_tvalid),
    .core_event_frame_started(core_event_frame_started),
    .core_event_tlast_unexpected(core_event_tlast_unexpected),
    .core_event_tlast_missing(core_event_tlast_missing),
    .core_event_status_channel_halt(core_event_status_channel_halt),
    .core_event_data_in_channel_halt(1'b0), .core_event_data_out_channel_halt(1'b0)
  );
  integer mask, geometry, checked = 0;
  integer allowed = 0, denied = 0;
  reg old_gate;
  initial begin
    for (geometry = 0; geometry < 4; geometry = geometry + 1) begin
      for (mask = 0; mask < 131072; mask = mask + 1) begin
        resetn = mask[0]; flush = mask[1];
        dut.reset_release_count = 2;
        dut.configured = mask[2]; dut.protocol_fault = mask[3];
        dut.block_inflight = mask[4]; dut.input_in_progress = mask[5];
        dut.status_seen = mask[6]; dut.frame_started_seen = mask[7];
        core_output_tvalid = mask[8]; output_ready = mask[9];
        core_status_tvalid = mask[10]; core_event_frame_started = mask[11];
        core_event_tlast_unexpected = mask[12]; core_event_tlast_missing = mask[13];
        core_event_status_channel_halt = mask[14];
        input_valid = mask[15]; core_input_tready = mask[16];
        dut.expected_input_position = geometry == 0 ? 0 : 511;
        input_position = geometry == 2 ? 17 : dut.expected_input_position;
        input_last = geometry == 3 ? 0 : (dut.expected_input_position == 511);
        dut.active_block_start_index = 64'h123456789abcdef0;
        input_block_start_index = geometry == 1 ? 0 : dut.active_block_start_index;
        dut.expected_output_position = geometry == 0 ? 0 : 511;
        dut.status_block_exponent = 5;
        dut.output_exponent_seen = 1;
        dut.active_output_exponent = 5;
        core_output_tuser = {3'd0, 5'd5, 7'd0, dut.expected_output_position};
        core_output_tlast = dut.expected_output_position == 511;
        core_status_tdata = 8'd5;
        // Include bad output framing/exponent/padding as well as both ends
        // of a well-formed frame. Such outputs must never advance state.
        if (geometry == 2) core_output_tlast = !core_output_tlast;
        if (geometry == 3) begin
          core_output_tuser[20:16] = 6;
          core_status_tdata[7:5] = 3'b001;
        end
        #1;
        old_gate = dut.core_output_accept && !dut.fault_event_now && !dut.protocol_fault;
        if (dut.output_state_advance !== old_gate)
          $fatal(1, "output gate changed identity=%0d geometry=%0d mask=%0h old=%b new=%b",
                 CHECK_IDENTITY, geometry, mask, old_gate, dut.output_state_advance);
        if (old_gate) allowed = allowed + 1;
        else denied = denied + 1;
        checked = checked + 1;
      end
    end
    if (!allowed || !denied) $fatal(1, "vacuous output gate check");
    $display("XFFT_OUTPUT_GATE_EQUIVALENCE_PASS identity=%0d checked=%0d allowed=%0d denied=%0d",
             CHECK_IDENTITY, checked, allowed, denied);
    $finish;
  end
endmodule
