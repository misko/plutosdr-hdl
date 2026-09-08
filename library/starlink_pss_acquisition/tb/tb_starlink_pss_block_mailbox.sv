`timescale 1ns/1ps
module tb_starlink_pss_block_mailbox;
  parameter integer ADDRESS_WIDTH = 9;
  parameter integer METADATA_WIDTH = 70;
  parameter integer RESET_RELEASE_EXTERNAL = 0;
  parameter integer INPUT_RELEASE_EXTRA_CYCLES = 0;
  parameter integer OUTPUT_RELEASE_EXTRA_CYCLES = 0;
  parameter real INPUT_HALF_NS = 5.0;
  parameter real OUTPUT_HALF_NS = 2.5;
  parameter real OUTPUT_PHASE_NS = 0.7;
  localparam integer DEPTH = 1 << ADDRESS_WIDTH;
  reg input_clk = 0, output_clk = 0;
  reg input_resetn = 0, output_resetn = 0;
  reg input_valid = 0, output_ready = 0;
  wire input_ready, input_fault, output_valid, output_last;
  reg [35:0] input_data = 0;
  reg [ADDRESS_WIDTH-1:0] input_position = 0;
  reg input_last = 0;
  reg [METADATA_WIDTH-1:0] input_metadata = 0;
  wire [35:0] output_data;
  wire [ADDRESS_WIDTH-1:0] output_position;
  wire [METADATA_WIDTH-1:0] output_metadata;
  integer output_cycles = 0, received = 0, checked_blocks = 0;
  integer expected_block = 1, expected_position = 0;
  integer block_number, index_number, fault_kind, snapshot;
  reg check_outputs = 1, drain_enable = 0;
  reg held = 0;
  reg [METADATA_WIDTH+35:0] held_value;
  reg [ADDRESS_WIDTH-1:0] held_position;
  reg held_last;

  always #(INPUT_HALF_NS) input_clk = !input_clk;
  initial begin
    #(OUTPUT_PHASE_NS);
    forever #(OUTPUT_HALF_NS) output_clk = !output_clk;
  end
  // Model the service's single local release pair, including independent
  // raw reset assertion and optional additional release skew in either clock.
  reg [1+INPUT_RELEASE_EXTRA_CYCLES:0] raw_in_to_in = 0, raw_out_to_in = 0;
  reg [1+OUTPUT_RELEASE_EXTRA_CYCLES:0] raw_in_to_out = 0, raw_out_to_out = 0;
  always @(posedge input_clk or negedge input_resetn)
    if (!input_resetn) raw_in_to_in <= 0;
    else raw_in_to_in <= (raw_in_to_in << 1) | 1'b1;
  always @(posedge input_clk or negedge output_resetn)
    if (!output_resetn) raw_out_to_in <= 0;
    else raw_out_to_in <= (raw_out_to_in << 1) | 1'b1;
  always @(posedge output_clk or negedge input_resetn)
    if (!input_resetn) raw_in_to_out <= 0;
    else raw_in_to_out <= (raw_in_to_out << 1) | 1'b1;
  always @(posedge output_clk or negedge output_resetn)
    if (!output_resetn) raw_out_to_out <= 0;
    else raw_out_to_out <= (raw_out_to_out << 1) | 1'b1;
  wire local_input_resetn = raw_in_to_in[1+INPUT_RELEASE_EXTRA_CYCLES] &&
                           raw_out_to_in[1+INPUT_RELEASE_EXTRA_CYCLES];
  wire local_output_resetn = raw_in_to_out[1+OUTPUT_RELEASE_EXTRA_CYCLES] &&
                            raw_out_to_out[1+OUTPUT_RELEASE_EXTRA_CYCLES];
  starlink_pss_block_mailbox #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH), .METADATA_WIDTH(METADATA_WIDTH),
    .RESET_RELEASE_EXTERNAL(RESET_RELEASE_EXTERNAL)
  ) dut (
    .input_resetn(RESET_RELEASE_EXTERNAL ? local_input_resetn : input_resetn),
    .output_resetn(RESET_RELEASE_EXTERNAL ? local_output_resetn : output_resetn), .*
  );

  function automatic [35:0] payload(input integer block_id, input integer position);
    payload = 36'hb12345678 ^ (block_id * 65537) ^ (position * 131);
  endfunction
  function automatic [METADATA_WIDTH-1:0] metadata(input integer block_id);
    begin
      metadata = 70'h25_123456789abcdef0 ^ (block_id * 7919);
      metadata[METADATA_WIDTH-1 -: 6] = block_id[5:0];
    end
  endfunction

  always @(posedge input_clk) begin
    if (dut.in_running && dut.metadata_load !==
        (dut.input_accept && dut.input_framing_valid && dut.write_position == 0))
      $fatal(1, "first-word metadata gate differs from original framing predicate");
  end

  always @(negedge output_clk) begin
    output_ready = drain_enable && (output_cycles % 17 != 3) &&
                   (output_cycles % 17 != 4) && (output_cycles % 11 != 8);
  end
  always @(posedge output_clk) begin
    output_cycles = output_cycles + 1;
    if (output_cycles > 500000) $fatal(1, "mailbox watchdog");
    if (!input_resetn || !output_resetn) held = 0;
    else begin
      if (held && (!output_valid || {output_metadata, output_data} !== held_value ||
                   output_position !== held_position || output_last !== held_last))
        $fatal(1, "stalled mailbox output changed");
      held = output_valid && !output_ready;
      held_value = {output_metadata, output_data};
      held_position = output_position;
      held_last = output_last;
      if (output_valid && output_ready && check_outputs) begin
        if (output_data !== payload(expected_block, expected_position) ||
            output_metadata !== metadata(expected_block) ||
            output_position !== expected_position ||
            output_last !== (expected_position == DEPTH-1))
          $fatal(1, "mailbox mismatch block=%0d position=%0d got=%h metadata=%h",
                 expected_block, expected_position, output_data, output_metadata);
        received = received + 1;
        if (expected_position == DEPTH-1) begin
          expected_position = 0;
          expected_block = expected_block + 1;
          checked_blocks = checked_blocks + 1;
        end else expected_position = expected_position + 1;
      end
    end
  end

  task automatic beat(input integer block_id, input integer position,
                      input integer supplied_position, input bit supplied_last,
                      input bit wrong_metadata);
    begin
      @(negedge input_clk);
      input_valid = 1;
      input_data = payload(block_id, position);
      input_metadata = metadata(block_id);
      if (wrong_metadata) input_metadata[METADATA_WIDTH-1] = !input_metadata[METADATA_WIDTH-1];
      input_position = supplied_position;
      input_last = supplied_last;
      @(posedge input_clk);
      while (!input_ready) @(posedge input_clk);
    end
  endtask
  task automatic stop_input;
    begin @(negedge input_clk); input_valid = 0; end
  endtask
  task automatic send_block(input integer block_id);
    integer position;
    begin
      for (position = 0; position < DEPTH; position = position + 1) begin
        if ((position + block_id) % 31 == 7) begin
          stop_input();
          repeat (3) @(negedge input_clk);
        end
        beat(block_id, position, position, position == DEPTH-1, 0);
      end
      stop_input();
    end
  endtask
  task automatic reset_one(input bit source_side);
    begin
      stop_input();
      drain_enable = 0;
      #1.1;
      if (source_side) input_resetn = 0;
      else output_resetn = 0;
      repeat (8) @(negedge input_clk);
      repeat (8) @(negedge output_clk);
      if (input_ready || output_valid) $fatal(1, "reset did not close both domains");
      if (source_side) input_resetn = 1;
      else output_resetn = 1;
      repeat (8) @(negedge input_clk);
      repeat (8) @(negedge output_clk);
      if (!input_ready || input_fault || output_valid) $fatal(1, "reset left stale work");
    end
  endtask
  task automatic wait_received(input integer count);
    begin
      while (received < count) @(negedge output_clk);
      repeat (8) @(negedge input_clk);
      repeat (8) @(negedge output_clk);
      if (received != count || !input_ready || output_valid || input_fault)
        $fatal(1, "mailbox did not drain/release exactly");
    end
  endtask

  initial begin
    repeat (8) @(negedge input_clk);
    input_resetn = 1;
    output_resetn = 1;
    // Partial input must never publish, even if the reader is ready.
    drain_enable = 1;
    for (index_number = 0; index_number < DEPTH-1; index_number = index_number + 1)
      beat(1, index_number, index_number, 0, 0);
    stop_input();
    repeat (20) @(negedge output_clk);
    if (output_valid || received) $fatal(1, "partial block escaped");
    drain_enable = 0;
    beat(1, DEPTH-1, DEPTH-1, 1, 0);
    stop_input();
    repeat (20) @(negedge output_clk);
    if (!output_valid || input_ready) $fatal(1, "complete block ownership missing");
    // Perturb all producer wires while the consumer is stalled; no ownership.
    input_metadata = ~input_metadata;
    input_data = ~input_data;
    repeat (20) @(negedge input_clk);
    drain_enable = 1;
    wait_received(DEPTH);
    for (block_number = 2; block_number <= 12; block_number = block_number + 1)
      send_block(block_number);
    wait_received(12 * DEPTH);

    // Invalid first index, early TLAST, missing final TLAST, changed metadata.
    for (fault_kind = 0; fault_kind < 4; fault_kind = fault_kind + 1) begin
      snapshot = received;
      if (fault_kind == 0) beat(99, 0, 1, 0, 0);
      else if (fault_kind == 1) begin
        beat(99, 0, 0, 0, 0);
        beat(99, 1, 1, 1, 0);
      end else if (fault_kind == 2) begin
        for (index_number = 0; index_number < DEPTH; index_number = index_number + 1)
          beat(99, index_number, index_number, 0, 0);
      end else begin
        beat(99, 0, 0, 0, 0);
        beat(99, 1, 1, 0, 1);
      end
      stop_input();
      repeat (20) @(negedge output_clk);
      if (!input_fault || input_ready || output_valid || received != snapshot)
        $fatal(1, "malformed block was not quarantined kind=%0d", fault_kind);
      reset_one(fault_kind % 2);
      drain_enable = 1;
    end

    // Purge partially written and fully committed-but-stalled blocks using
    // either reset alone. A new epoch must never inherit RAM or toggle state.
    for (fault_kind = 0; fault_kind < 6; fault_kind = fault_kind + 1) begin : reset_cases
      drain_enable = 0;
      if (fault_kind < 2) begin
        beat(99, 0, 0, 0, 0);
        beat(99, 1, 1, 0, 0);
      end else if (fault_kind < 4) send_block(99);
      else begin
        check_outputs = 0;
        send_block(99);
        drain_enable = 1;
        wait (output_valid && output_position == DEPTH/2);
        drain_enable = 0;
      end
      reset_one(fault_kind % 2);
      check_outputs = 1;
      expected_block = 100 + fault_kind;
      expected_position = 0;
      snapshot = received;
      drain_enable = 1;
      send_block(expected_block);
      wait_received(snapshot + DEPTH);
    end
    $display("BLOCK_MAILBOX_PASS depth=%0d blocks=%0d words=%0d input_half=%0.2f output_half=%0.2f framing_faults=4 independent_resets=10 mid_read_resets=2 external_reset=%0d release_skew_in=%0d release_skew_out=%0d",
             DEPTH, checked_blocks, received, INPUT_HALF_NS, OUTPUT_HALF_NS,
             RESET_RELEASE_EXTERNAL, INPUT_RELEASE_EXTRA_CYCLES, OUTPUT_RELEASE_EXTRA_CYCLES);
    $finish(0);
  end
endmodule
