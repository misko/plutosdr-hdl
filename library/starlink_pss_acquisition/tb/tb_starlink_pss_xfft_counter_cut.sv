`timescale 1ns/1ps
// Differential lifecycle test: the optimized private counter may differ only
// after a fault. Every external control, payload and completion remains equal.
module tb_starlink_pss_xfft_counter_cut;
  parameter integer CHECK_IDENTITY = 0;
  reg clk = 0, resetn = 0, flush = 0;
  always #5 clk = !clk;
  reg input_valid = 0, input_last = 0, output_ready = 1;
  reg signed [23:0] input_i = 0, input_q = 0;
  reg [8:0] input_position = 0;
  reg [63:0] input_block_start_index = 64'hf123456789abcdef;
  reg core_config_tready = 1, core_input_tready = 1;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = 0;
  reg core_output_tvalid = 0, core_output_tlast = 0;
  reg [7:0] core_status_tdata = 5;
  reg core_status_tvalid = 0, core_event_frame_started = 0;
  reg core_event_tlast_unexpected = 0, core_event_tlast_missing = 0;
  reg core_event_status_channel_halt = 0;
  reg core_event_data_in_channel_halt = 0, core_event_data_out_channel_halt = 0;
  wire [1:0] input_ready, output_valid, core_config_tvalid, core_output_tready;
  wire [1:0] protocol_fault, output_block_complete_pulse;
  wire [201:0] observable [0:1];
  integer cycles = 0, fault_cases = 0, speculative_advances = 0;
  integer healthy_advances = 0, completed_blocks = 0;
  integer kind, point, p;
  genvar mode;
  generate for (mode = 0; mode < 2; mode = mode + 1) begin : adapters
    wire signed [23:0] output_i, output_q;
    wire [8:0] output_position;
    wire [4:0] output_block_exponent;
    wire [63:0] output_block_start_index;
    wire output_last, core_aresetn, core_input_tvalid, core_input_tlast;
    wire [7:0] core_config_tdata;
    wire [47:0] core_input_tdata;
    wire core_status_tready, configured_pulse, input_block_complete_pulse;
    wire protocol_error_pulse, input_framing_error_pulse;
    wire output_metadata_error_pulse, status_error_pulse, core_tlast_error_pulse;
    wire core_data_in_halt_pulse, core_data_out_halt_pulse;
    starlink_pss_xfft_block_adapter #(
      .CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY), .RAW_OUTPUT_POSITION_ADVANCE(mode)
    ) dut (
      .clk(clk), .resetn(resetn), .flush(flush),
      .input_valid(input_valid), .input_ready(input_ready[mode]),
      .input_i(input_i), .input_q(input_q), .input_position(input_position),
      .input_block_start_index(input_block_start_index), .input_last(input_last),
      .output_valid(output_valid[mode]), .output_ready(output_ready),
      .output_i(output_i), .output_q(output_q), .output_position(output_position),
      .output_block_exponent(output_block_exponent),
      .output_block_start_index(output_block_start_index), .output_last(output_last),
      .core_aresetn(core_aresetn), .core_config_tdata(core_config_tdata),
      .core_config_tvalid(core_config_tvalid[mode]), .core_config_tready(core_config_tready),
      .core_input_tdata(core_input_tdata), .core_input_tvalid(core_input_tvalid),
      .core_input_tready(core_input_tready), .core_input_tlast(core_input_tlast),
      .core_output_tdata(core_output_tdata), .core_output_tuser(core_output_tuser),
      .core_output_tvalid(core_output_tvalid), .core_output_tready(core_output_tready[mode]),
      .core_output_tlast(core_output_tlast), .core_status_tdata(core_status_tdata),
      .core_status_tvalid(core_status_tvalid), .core_status_tready(core_status_tready),
      .core_event_frame_started(core_event_frame_started),
      .core_event_tlast_unexpected(core_event_tlast_unexpected),
      .core_event_tlast_missing(core_event_tlast_missing),
      .core_event_status_channel_halt(core_event_status_channel_halt),
      .core_event_data_in_channel_halt(core_event_data_in_channel_halt),
      .core_event_data_out_channel_halt(core_event_data_out_channel_halt),
      .configured_pulse(configured_pulse),
      .input_block_complete_pulse(input_block_complete_pulse),
      .output_block_complete_pulse(output_block_complete_pulse[mode]),
      .protocol_error_pulse(protocol_error_pulse),
      .input_framing_error_pulse(input_framing_error_pulse),
      .output_metadata_error_pulse(output_metadata_error_pulse),
      .status_error_pulse(status_error_pulse), .core_tlast_error_pulse(core_tlast_error_pulse),
      .core_data_in_halt_pulse(core_data_in_halt_pulse),
      .core_data_out_halt_pulse(core_data_out_halt_pulse), .protocol_fault(protocol_fault[mode])
    );
    assign observable[mode] = {
      input_ready[mode], output_valid[mode], output_i, output_q, output_position,
      output_block_exponent, output_block_start_index, output_last,
      core_aresetn, core_config_tdata, core_config_tvalid[mode], core_input_tdata,
      core_input_tvalid, core_input_tlast, core_output_tready[mode], core_status_tready,
      configured_pulse, input_block_complete_pulse, output_block_complete_pulse[mode],
      protocol_error_pulse, input_framing_error_pulse, output_metadata_error_pulse,
      status_error_pulse, core_tlast_error_pulse, core_data_in_halt_pulse,
      core_data_out_halt_pulse, protocol_fault[mode]
    };
  end endgenerate

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (cycles > 100000) $fatal(1, "counter differential watchdog");
    if (resetn && !flush) begin
      if (observable[0] !== observable[1])
        $fatal(1, "counter cut changed public interface cycle=%0d kind=%0d point=%0d", cycles, kind, point);
      if (!protocol_fault[1]) begin
        if (adapters[0].dut.expected_output_position !== adapters[1].dut.expected_output_position)
          $fatal(1, "private output position differs before fault quarantine");
        if (adapters[1].dut.output_position_advance && !adapters[1].dut.output_state_advance) begin
          if (!adapters[1].dut.fault_event_now)
            $fatal(1, "speculative counter advance lacks same-cycle fault");
          speculative_advances = speculative_advances + 1;
        end
        if (adapters[1].dut.output_state_advance) healthy_advances = healthy_advances + 1;
      end
      if (protocol_fault[1] && (output_valid[1] || output_block_complete_pulse[1]))
        $fatal(1, "faulted counter escaped publication/completion quarantine");
      if (output_block_complete_pulse[1]) completed_blocks = completed_blocks + 1;
    end
  end

  task automatic clear_events;
    begin
      core_event_frame_started = 0;
      core_event_tlast_unexpected = 0;
      core_event_tlast_missing = 0;
      core_event_status_channel_halt = 0;
      core_status_tvalid = 0;
    end
  endtask
  task automatic reset_epoch(input bit use_flush);
    begin
      @(negedge clk);
      input_valid = 0; core_output_tvalid = 0; output_ready = 1; clear_events();
      if (use_flush) flush = 1; else resetn = 0;
      repeat (3) @(negedge clk);
      flush = 0; resetn = 1;
      wait (core_config_tvalid[1]);
      @(negedge clk);
      if (protocol_fault != 0) $fatal(1, "counter reset did not recover");
    end
  endtask
  task automatic send_input_block;
    integer n;
    begin
      for (n = 0; n < 512; n = n + 1) begin
        @(negedge clk);
        input_valid = 1; input_position = n; input_last = n == 511;
        input_i = n; input_q = -n;
        core_event_frame_started = n == 0;
        @(posedge clk);
        while (!input_ready[1]) @(posedge clk);
      end
      @(negedge clk); input_valid = 0; clear_events();
      // Hold an early output until its matching status arrives.
      core_output_tvalid = 1; core_output_tlast = 0;
      core_output_tuser = {3'b0, 5'd5, 7'b0, 9'd0};
      repeat (2) @(negedge clk);
      if (core_output_tready != 0 || output_valid != 0)
        $fatal(1, "output escaped before status");
      core_output_tvalid = 0;
      core_status_tdata = 5; core_status_tvalid = 1;
      @(negedge clk); core_status_tvalid = 0;
    end
  endtask
  task automatic output_beat(input integer n, input integer corruption);
    begin
      @(negedge clk);
      core_output_tdata = {24'(1000+n), 24'(2000+n)};
      core_output_tuser = {3'b0, 5'd5, 7'b0, 9'(n)};
      core_output_tlast = n == 511; core_output_tvalid = 1;
      // Exercise backpressure before either a healthy or adversarial beat.
      if (n == 0 || n == 255 || n == 511) begin
        output_ready = 0;
        repeat (2) @(negedge clk);
        output_ready = 1;
      end
      case (corruption)
        0: core_output_tuser[8:0] = 9'(n+1);
        1: core_output_tlast = !core_output_tlast;
        2: core_output_tuser[20:16] = 6;
        3: core_output_tuser[23] = 1;
        4: core_event_tlast_missing = 1;
        5: core_event_status_channel_halt = 1;
        6: core_event_frame_started = 1;
        7: begin core_status_tvalid = 1; core_status_tdata = 5; end
        8: begin core_status_tvalid = 1; core_status_tdata = 8'he5; end
        9: core_event_tlast_unexpected = 1;
      endcase
      @(posedge clk);
      if (!core_output_tready[1]) $fatal(1, "active output beat not consumed");
      @(negedge clk); core_output_tvalid = 0; clear_events();
    end
  endtask
  initial begin
    reset_epoch(0);
    // Two healthy blocks without reset prove wrap/next-job invariants.
    repeat (2) begin
      send_input_block();
      for (p = 0; p < 512; p = p + 1) output_beat(p, -1);
      repeat (3) @(negedge clk);
    end
    for (kind = 0; kind < 10; kind = kind + 1) begin
      for (point = 0; point < 3; point = point + 1) begin
        reset_epoch((kind + point) % 2);
        send_input_block();
        for (p = 0; p < (point == 0 ? 0 : point == 1 ? 255 : 511); p = p + 1)
          output_beat(p, -1);
        output_beat(p, kind);
        if (protocol_fault != 2'b11 || output_block_complete_pulse != 0)
          $fatal(1, "malformed beat failed sticky quarantine kind=%0d point=%0d", kind, point);
        // Further apparently well-formed beats must not revive the epoch.
        output_beat(511, -1);
        repeat (3) @(negedge clk);
        fault_cases = fault_cases + 1;
      end
    end
    reset_epoch(1);
    send_input_block();
    for (p = 0; p < 512; p = p + 1) output_beat(p, -1);
    repeat (3) @(negedge clk);
    if (fault_cases != 30 || speculative_advances != 30 || completed_blocks != 3)
      $fatal(1, "counter differential coverage mismatch cases=%0d speculative=%0d blocks=%0d",
             fault_cases, speculative_advances, completed_blocks);
    $display("XFFT_COUNTER_CUT_PASS identity=%0d fault_cases=%0d speculative_advances=%0d healthy_advances=%0d completed_blocks=%0d public_interface_equivalent=1 healthy_shadow_counter=1",
             CHECK_IDENTITY, fault_cases, speculative_advances, healthy_advances, completed_blocks);
    $finish;
  end
endmodule
