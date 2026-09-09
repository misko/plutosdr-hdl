`timescale 1ns/1ps

// Core-only simulation: no PSMA tickets, IIO, upstream health, or RF claim.
module tb_starlink_pss_phase_map_stop #(
  parameter integer BINS = 8,
  parameter integer FRAMES = 4
);
  localparam integer PW = $clog2(BINS);
  localparam integer FW = $clog2(FRAMES);
  localparam integer TOTAL = BINS * FRAMES;
  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, acquisition_enable = 0, score_valid = 0;
  reg [63:0] score_start_index = 0;
  reg [PW-1:0] score_phase = 0;
  reg [7:0] score_value = 0;
  reg stream_discontinuity = 0, stop_request = 0;
  reg map_read_request = 0, map_read_bank = 0, map_release = 0, map_release_bank = 0;
  reg [PW-1:0] map_read_index = 0;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0, map_generation_1;
  wire [63:0] map_start_index_0, map_start_index_1;
  wire map_read_valid, map_read_error;
  wire [15:0] map_read_data;
  wire [31:0] accepted_score_count, discarded_score_count, discontinuity_abort_count;
  wire [31:0] map_publish_count, map_overrun_count, score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count, map_read_error_count, map_release_error_count;
  wire stop_pending, stop_ack, stop_done, stop_complete, stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;

  starlink_pss_phase_map #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(PW), .TILE_FRAMES(FRAMES),
    .TILE_FRAME_WIDTH(FW), .MAP_SEGMENT_ADDRESS_WIDTH(PW),
    .MAP_SEGMENT_COUNT(1), .MAP_SEGMENT_INDEX_WIDTH(1), .ENABLE_BOUNDARY_STOP(1)
  ) dut (.*);

  task automatic fail(input string message);
    $display("MAP_STOP_FAIL bins=%0d frames=%0d %s", BINS, FRAMES, message);
    $fatal(1);
  endtask

  // Independent publication-edge scoreboard. A ready bank may legally be
  // released on the ack edge; current ready alone cannot prove publication.
  reg committed = 0, prior_done = 0, prior_ack = 0;
  reg [31:0] committed_generation = 0;
  reg [63:0] committed_start = 0;
  reg [160:0] held_tuple = 0;
  integer ack_count = 0;
  always @(posedge clk) begin
    if (!resetn) begin
      committed = 0;
      committed_generation = 0;
      committed_start = 0;
    end else if (dut.publish_pending) begin
      committed = 1;
      committed_generation = dut.publish_bank ? map_generation_1 : map_generation_0;
      committed_start = dut.publish_bank ? map_start_index_1 : map_start_index_0;
    end
  end
  always @(negedge clk) begin
    if (!resetn) begin
      prior_done = 0;
      prior_ack = 0;
      ack_count = 0;
    end else begin
      if (stop_ack) begin
        ack_count = ack_count + 1;
        if (prior_ack || !stop_done || stop_pending || dut.update_pending ||
            dut.write_pending || dut.publish_pending || dut.state == 2 || dut.state == 3)
          fail("ack precedes empty publication pipeline or repeats");
        if (stop_has_map !== committed || (committed &&
            (stop_generation !== committed_generation || stop_start_index !== committed_start)))
          fail("terminal metadata does not refer to an actual publication");
      end
      if (prior_done && stop_done &&
          held_tuple !== {stop_has_map, stop_generation, stop_start_index, stop_end_index})
        fail("valid terminal tuple changed after publication/release/late fault");
      held_tuple = {stop_has_map, stop_generation, stop_start_index, stop_end_index};
      prior_done = stop_done;
      prior_ack = stop_ack;
    end
  end

  task automatic beat(input bit valid, input [63:0] index,
                      input integer phase, input bit request, input bit gap);
    @(negedge clk);
    score_valid = valid;
    score_start_index = index;
    score_phase = phase;
    score_value = (phase + 1);
    stop_request = request;
    stream_discontinuity = gap;
    @(posedge clk); #1;
  endtask
  task automatic idle(input integer count);
    for (integer j = 0; j < count; j = j + 1)
      beat(0, 0, 0, 0, 0);
  endtask
  task automatic boot(input bit wait_for_bank);
    @(negedge clk);
    resetn = 0;
    acquisition_enable = 0;
    score_valid = 0;
    stream_discontinuity = 0;
    stop_request = 0;
    map_read_request = 0;
    map_release = 0;
    repeat (3) @(negedge clk);
    resetn = 1;
    acquisition_enable = 1;
    if (wait_for_bank) idle(BINS + 4);
  endtask
  task automatic terminal(input bit healthy, input bit complete,
                          input integer generation, input [63:0] start_index);
    integer attempts;
    attempts = 0;
    while (!stop_done && attempts < TOTAL + 20) begin
      idle(1);
      attempts = attempts + 1;
    end
    idle(1);
    if (!stop_done || stop_pending || stop_failed !== !healthy ||
        stop_complete !== complete || ack_count != 1)
      fail("wrong terminal status");
    if (stop_generation !== generation || stop_has_map !== (generation != 0))
      fail("wrong terminal generation/history");
    if (generation != 0 && (stop_start_index !== start_index ||
        stop_end_index !== start_index + TOTAL))
      fail("wrong exact candidate interval");
    if (generation == 0 && (stop_start_index != 0 || stop_end_index != 0))
      fail("empty observation fabricated source support");
  endtask
  task automatic healthy_counters(input integer count);
    if (accepted_score_count != count || discarded_score_count != 0 ||
        discontinuity_abort_count != 0 || map_overrun_count != 0 ||
        score_protocol_error_count != 0 || map_arithmetic_overflow_count != 0 ||
        map_read_error_count != 0 || map_release_error_count != 0)
      fail("healthy stop changed real loss/error counters");
  endtask
  task automatic read_bin(input bit bank, input integer phase);
    @(negedge clk);
    score_valid = 0;
    stop_request = 0;
    map_read_request = 1;
    map_read_bank = bank;
    map_read_index = phase;
    @(negedge clk);
    map_read_request = 0;
    @(posedge clk); #1;
    if (!map_read_valid || map_read_error || map_read_data != FRAMES * (phase + 1))
      fail("complete bank changed or read failed across fence");
  endtask
  task automatic release_bank(input bit bank);
    @(negedge clk);
    score_valid = 0;
    stop_request = 0;
    map_release = 1;
    map_release_bank = bank;
    @(negedge clk);
    map_release = 0;
  endtask
  task automatic tile(input [63:0] start_index, input integer stop_position);
    for (integer j = 0; j < TOTAL; j = j + 1)
      beat(1, start_index + j, j % BINS, j == stop_position, 0);
  endtask

  integer cut, offset, fault;
  reg [63:0] base;
  initial begin
    // WAIT_BANK while RAM clear walkers are still active.
    boot(0);
    beat(1, 1000, 0, 1, 0);
    terminal(1, 1, 0, 0);
    healthy_counters(0);

    // Disabled requests have no acceptance/ack, and a new pulse on rearm
    // creates a fresh core operation rather than reviving the old terminal.
    acquisition_enable = 0;
    idle(2);
    beat(0, 0, 0, 1, 0);
    idle(2);
    if (ack_count != 1 || stop_pending) fail("disabled request was accepted");
    acquisition_enable = 1;
    beat(1, 1010, 0, 1, 0);
    idle(4);
    if (!stop_done || stop_failed || !stop_complete || stop_has_map || ack_count != 2)
      fail("same-edge rearm/request admitted a score or lost the new operation");

    // Every position, including simultaneous first score and DRAIN's next
    // tile phase zero. The discarded post-boundary scores must not count.
    for (cut = 0; cut <= TOTAL; cut = cut + 1) begin
      boot(1);
      for (integer j = 0; j <= TOTAL; j = j + 1)
        beat(1, 1000 + j, j % BINS, j == cut, 0);
      terminal(1, 1, cut == 0 ? 0 : 1, 1000);
      healthy_counters(cut == 0 ? 0 : TOTAL);
      if (cut != 0)
        for (integer j = 0; j < BINS; j = j + 1) read_bin(0, j);
      // Repeated requests in the parked state do not restart or re-ack.
      beat(1, 9000, 0, 1, 0);
      idle(3);
      if (ack_count != 1) fail("parked request acknowledged twice");
    end

    // Request on the registered write/publication edge and just after it.
    for (offset = 1; offset <= 3; offset = offset + 1) begin
      boot(1);
      tile(2000, -1);
      idle(offset);
      beat(1, 2000 + TOTAL, 0, 1, 0);
      terminal(1, 1, 1, 2000);
      healthy_counters(TOTAL);
    end

    // Both banks ready at completion; read bank zero during pending FILL.
    boot(1);
    tile(3000, -1);
    idle(3);
    beat(1, 3000 + TOTAL, 0, 0, 0);
    beat(1, 3001 + TOTAL, 1, 1, 0);
    read_bin(0, 0);
    for (integer j = 2; j < TOTAL; j = j + 1)
      beat(1, 3000 + TOTAL + j, j % BINS, 0, 0);
    terminal(1, 1, 2, 3000 + TOTAL);
    if (map_ready_mask != 3) fail("stop erased one of two ready banks");
    for (integer j = 0; j < BINS; j = j + 1) begin
      read_bin(0, j);
      read_bin(1, j);
    end
    release_bank(0);
    release_bank(1);
    idle(BINS + 3);
    terminal(1, 1, 2, 3000 + TOTAL);
    healthy_counters(2 * TOTAL);

    // Release and clear the old bank while the stopped-on-request tile is
    // still filling: it must never become a new reservation after the fence.
    boot(1);
    tile(4500, -1);
    idle(3);
    beat(1, 4500 + TOTAL, 0, 0, 0);
    beat(1, 4501 + TOTAL, 1, 1, 0);
    release_bank(0);
    idle(BINS + 2);
    for (integer j = 2; j < TOTAL; j = j + 1)
      beat(1, 4500 + TOTAL + j, j % BINS, 0, 0);
    terminal(1, 1, 2, 4500 + TOTAL);
    if (map_ready_mask != 2) fail("pending release prevented final publication");
    read_bin(1, BINS - 1);
    release_bank(1);
    idle(BINS + 3);
    healthy_counters(2 * TOTAL);

    // A new enable epoch invalidates the old tuple and can reuse released RAM.
    acquisition_enable = 0;
    idle(2);
    acquisition_enable = 1;
    idle(3);
    if (stop_done || stop_pending || stop_failed) fail("enable edge did not rearm");
    tile(6000, 1);
    idle(5);
    if (!stop_done || stop_generation != 3 || stop_start_index != 6000 ||
        stop_end_index != 6000 + TOTAL || ack_count != 2)
      fail("rearmed acquisition did not produce the new terminal map");

    // Request after a previous publication was released before any request.
    boot(1);
    tile(7000, -1);
    idle(3);
    release_bank(0);
    idle(BINS + 2);
    beat(0, 0, 0, 1, 0);
    terminal(1, 1, 1, 7000);

    // Release the last ready bank on the acknowledgment clock itself.
    boot(1);
    tile(8000, 1);
    idle(2);
    @(negedge clk);
    score_valid = 0;
    map_release = 1;
    map_release_bank = 0;
    @(posedge clk); #1;
    if (!stop_ack || map_ready_mask != 0) fail("release/ack coincidence was not exercised");
    @(negedge clk); map_release = 0;
    terminal(1, 1, 1, 8000);
    healthy_counters(TOTAL);

    // Quiet score gaps are not discontinuities and cannot manufacture done.
    boot(1);
    beat(1, 9000, 0, 0, 0);
    beat(0, 0, 0, 1, 0);
    idle(100);
    beat(0, 0, 0, 1, 0);
    idle(2);
    if (!stop_pending || stop_done || stop_failed) fail("stalled FILL invented a terminal");
    acquisition_enable = 0;
    terminal(0, 0, 0, 0);
    if (discontinuity_abort_count != 1 || !stop_failure_reason[3])
      fail("explicit pending abort lost its real counter/reason");

    // Explicit disable at DRAIN still publishes the already-complete tile,
    // but cannot be passed off as a healthy requested graceful lifecycle.
    boot(1);
    tile(9500, 1);
    acquisition_enable = 0;
    terminal(0, 1, 1, 9500);
    if (discontinuity_abort_count != 0 || !stop_failure_reason[3] || map_ready_mask != 1)
      fail("DRAIN disable lost publication or invented a partial-tile abort");

    // Bad phase, index, and explicit discontinuity on the final candidate.
    for (fault = 0; fault < 3; fault = fault + 1) begin
      boot(1);
      for (integer j = 0; j < TOTAL - 1; j = j + 1)
        beat(1, 10000 + j, j % BINS, j == 1, 0);
      beat(1, 10000 + TOTAL - 1 + (fault == 1),
           fault == 0 ? 0 : BINS - 1, 0, fault == 2);
      terminal(0, 0, 0, 0);
      if (discontinuity_abort_count != 1 ||
          score_protocol_error_count != (fault == 2 ? 0 : 1))
        fail("failed final candidate hid real abort/protocol accounting");
    end

    // Failed partial map retains earlier complete history, but not COMPLETE.
    boot(1);
    tile(11000, -1);
    idle(3);
    release_bank(0);
    beat(1, 11000 + TOTAL, 0, 1, 0); // Request before any next-tile admission.
    terminal(1, 1, 1, 11000);
    acquisition_enable = 0;
    idle(2);
    acquisition_enable = 1;
    idle(BINS + 3);
    beat(1, 12000, 0, 0, 0);
    beat(1, 12001, 1, 1, 0);
    beat(0, 0, 0, 0, 1);
    idle(5);
    if (!stop_done || stop_complete || !stop_failed || !stop_has_map ||
        stop_generation != 1 || stop_start_index != 11000 || discontinuity_abort_count != 1)
      fail("partial abort lost history or claimed a complete boundary");

    // A fault on the exact ack edge takes precedence; after-ack faults stay
    // visible without destroying retained coordinates or published RAM.
    for (fault = 0; fault < 3; fault = fault + 1) begin
      boot(1);
      tile(13000, 1);
      idle(2);
      if (fault == 0) beat(0, 0, 0, 0, 1);
      else begin
        @(negedge clk);
        score_valid = 0;
        if (fault == 1) begin map_read_request = 1; map_read_bank = 1; end
        else begin map_release = 1; map_release_bank = 1; end
        @(posedge clk); #1;
      end
      if (!stop_ack || !stop_failed || !stop_complete)
        fail("ack edge concealed a simultaneous fault");
      @(negedge clk);
      map_read_request = 0;
      map_release = 0;
      idle(3);
      terminal(0, 1, 1, 13000);
    end
    for (fault = 0; fault < 3; fault = fault + 1) begin
      boot(1);
      tile(14000, 1);
      terminal(1, 1, 1, 14000);
      if (fault == 0) beat(0, 0, 0, 0, 1);
      else if (fault == 1) begin
        @(negedge clk); map_read_request = 1; map_read_bank = 1;
        @(negedge clk); map_read_request = 0;
      end else begin
        release_bank(0);
        release_bank(0); // Now invalid: do not hide this late local fault.
      end
      idle(2);
      terminal(0, 1, 1, 14000);
      if (fault == 1 && map_read_error_count != 1) fail("late read failure was hidden");
      if (fault == 2 && map_release_error_count != 1) fail("late release failure was hidden");
    end

    // A representable maximum end, followed by exact-end and in-tile wrap.
    boot(1);
    base = 64'hffffffffffffffff - TOTAL;
    tile(base, 1);
    terminal(1, 1, 1, base);
    for (offset = 0; offset < 2; offset = offset + 1) begin
      boot(1);
      base = offset == 0 ? (64'hffffffffffffffff - TOTAL + 1) :
                           (64'hffffffffffffffff - TOTAL / 2);
      tile(base, 1);
      idle(5);
      if (!stop_done || !stop_failed || !stop_failure_reason[4] ||
          stop_start_index != base || stop_end_index != 0)
        fail("unrepresentable candidate end was reported as valid");
    end

    // Saturated generation is conservatively unqualified, not a unique ID.
    boot(1);
    @(negedge clk); dut.map_publish_count = 32'hfffffffe;
    tile(15000, 1);
    idle(5);
    if (!stop_done || !stop_failed || !stop_failure_reason[5] ||
        stop_generation != 32'hffffffff)
      fail("saturated generation was accepted as unique");

    // Legacy disable still aborts; a later stop must not forgive that history.
    boot(1);
    beat(1, 16000, 0, 0, 0);
    acquisition_enable = 0;
    idle(3);
    if (discontinuity_abort_count != 1) fail("ordinary disable stopped counting abort");
    acquisition_enable = 1;
    idle(BINS + 3);
    beat(0, 0, 0, 1, 0);
    terminal(0, 1, 0, 0);
    $display("MAP_STOP_PASS bins=%0d frames=%0d cuts=%0d core_only=1 no_radio_claim=1",
             BINS, FRAMES, TOTAL + 1);
    $finish;
  end
  initial begin #2000000; fail("bounded test timeout"); end
endmodule

// Compile alongside the unmodified legacy testbench, selecting both roots.
// All new ports are omitted there: X/Z must not leak into default-disabled
// admission or the existing RAM pipeline.
module legacy_map_stop_monitor;
  initial begin
    #1;
    if (tb_starlink_pss_phase_map.dut.stop_request !== 1'bz)
      $fatal(1, "legacy fixture did not omit the new input");
    #19; force tb_starlink_pss_phase_map.dut.stop_request = 1'bx;
    #500; force tb_starlink_pss_phase_map.dut.stop_request = 1'b1;
    #500; release tb_starlink_pss_phase_map.dut.stop_request;
    $display("LEGACY_STOP_INERT_PASS omitted_z=1 forced_x=1 forced_one=1");
  end
  always @(negedge tb_starlink_pss_phase_map.clk) begin
    if (tb_starlink_pss_phase_map.resetn &&
        (tb_starlink_pss_phase_map.dut.stop_hold !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_pending !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_ack !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_done !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_failed !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_complete !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_failure_reason !== 6'd0 ||
         tb_starlink_pss_phase_map.dut.stop_has_map !== 1'b0 ||
         tb_starlink_pss_phase_map.dut.stop_generation !== 32'd0 ||
         tb_starlink_pss_phase_map.dut.stop_start_index !== 64'd0 ||
         tb_starlink_pss_phase_map.dut.stop_end_index !== 64'd0))
      $fatal(1, "default-disabled omitted stop input changed legacy behavior");
  end
endmodule
