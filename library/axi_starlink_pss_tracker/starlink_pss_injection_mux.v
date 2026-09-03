// SPDX-License-Identifier: GPL-2.0
//
// Deterministic accepted-sample injection boundary for the experimental
// Stage-15 tracker. A complete 130-word fixture is loaded and frozen in the
// AXI/control domain before a future absolute sample index is armed. The
// sample-domain mux replaces only I/Q; enable, strobe, index, and timestamp
// remain source-derived and are pipelined with the selected sample. The same
// selected outputs feed both the tracker and RX DMA fan-out.

`timescale 1ns/1ps

module starlink_pss_injection_mux #(
  parameter integer SAMPLE_COUNT = 130,
  parameter [63:0] MINIMUM_ARM_LEAD_SAMPLES = 64'd64
) (
  input  wire                 control_clk,
  input  wire                 control_resetn,
  input  wire                 fixture_clear,
  input  wire                 fixture_write,
  input  wire [31:0]          fixture_write_data,
  input  wire                 fixture_commit,
  input  wire [31:0]          fixture_generation_stage,
  input  wire                 arm,
  input  wire [63:0]          arm_start_stage,
  input  wire [63:0]          control_current_index,
  output wire                 fixture_write_ready,
  output wire                 arm_ready,
  output wire [31:0]          status,
  output reg  [31:0]          last_completed_generation,

  input  wire                 sample_clk,
  input  wire                 sample_resetn,
  input  wire signed [15:0]   source_sample_i,
  input  wire signed [15:0]   source_sample_q,
  input  wire                 source_sample_strobe,
  input  wire                 source_sample_enable,
  input  wire [63:0]          source_sample_index,
  input  wire [63:0]          source_sample_timestamp,
  output reg  signed [15:0]   selected_sample_i,
  output reg  signed [15:0]   selected_sample_q,
  output reg                  selected_sample_strobe,
  output reg                  selected_sample_enable,
  output reg  [63:0]          selected_sample_index,
  output reg  [63:0]          selected_sample_timestamp,
  output reg                  selected_sample_injected
);

  generate
    if (SAMPLE_COUNT != 130) begin : g_invalid_sample_count
      initial $fatal(1, "Stage-15 injection requires SAMPLE_COUNT=130");
    end
  endgenerate

  // A true dual-clock block RAM keeps the control write port and sample read
  // port explicit to the implementation tools. Writes are forbidden from
  // commit until the armed transaction has completed or failed.
  (* ram_style = "block" *)
  reg [31:0] fixture_memory [0:SAMPLE_COUNT-1];
  reg [7:0] fixture_count;
  reg fixture_valid;
  reg [31:0] fixture_generation;
  reg rejected_sticky;
  reg completed_sticky;
  reg mismatch_sticky;

  reg [63:0] arm_start_mailbox;
  reg arm_request_toggle;
  reg arm_validation_pending;
  reg [1:0] arm_validation_count;
  reg [63:0] arm_validation_start;
  reg arm_pending;
  reg arm_inflight;

  // Break the Gray-decoded current-index plus 64-bit lead comparison into
  // separate control-clock stages. The host polls arm_ready after staging the
  // start word; the full-width equality keeps that readiness bound to the
  // exact staged command rather than a previous start value.
  reg [63:0] control_current_index_stage;
  reg [63:0] arm_start_checked_stage;
  reg [63:0] arm_lead_difference_stage;
  reg arm_start_not_before_stage;
  reg arm_window_no_overflow_stage;

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] arm_ack_sync;
  reg arm_ack_seen;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] completion_sync;
  reg completion_seen;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] mismatch_sync;
  reg mismatch_seen;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_active_sync;

  wire command_onehot = fixture_clear ^ fixture_commit ^ arm;
  wire command_multiple =
      (fixture_clear && fixture_commit) ||
      (fixture_clear && arm) ||
      (fixture_commit && arm);
  wire accepted_sample_control_lead =
      arm_start_stage == arm_start_checked_stage &&
      arm_start_not_before_stage &&
      arm_lead_difference_stage >= MINIMUM_ARM_LEAD_SAMPLES &&
      arm_window_no_overflow_stage;

  assign fixture_write_ready =
      !fixture_valid && !arm_validation_pending && !arm_pending && !arm_inflight &&
      fixture_count < SAMPLE_COUNT;
  assign arm_ready =
      fixture_valid && !arm_validation_pending && !arm_pending && !arm_inflight &&
      accepted_sample_control_lead;
  assign status = {
    16'd0,
    fixture_count,
    arm_inflight,
    mismatch_sticky,
    rejected_sticky,
    completed_sticky,
    sample_active_sync[1],
    (arm_pending || arm_validation_pending),
    arm_ready,
    fixture_valid
  };

  always @(posedge control_clk) begin
    if (!control_resetn) begin
      fixture_count <= 8'd0;
      fixture_valid <= 1'b0;
      fixture_generation <= 32'd0;
      rejected_sticky <= 1'b0;
      completed_sticky <= 1'b0;
      mismatch_sticky <= 1'b0;
      last_completed_generation <= 32'd0;
      arm_start_mailbox <= 64'd0;
      arm_request_toggle <= 1'b0;
      arm_validation_pending <= 1'b0;
      arm_validation_count <= 2'd0;
      arm_validation_start <= 64'd0;
      arm_pending <= 1'b0;
      arm_inflight <= 1'b0;
      control_current_index_stage <= 64'd0;
      arm_start_checked_stage <= 64'd0;
      arm_lead_difference_stage <= 64'd0;
      arm_start_not_before_stage <= 1'b0;
      arm_window_no_overflow_stage <= 1'b0;
      arm_ack_sync <= 2'b00;
      arm_ack_seen <= 1'b0;
      completion_sync <= 2'b00;
      completion_seen <= 1'b0;
      mismatch_sync <= 2'b00;
      mismatch_seen <= 1'b0;
      sample_active_sync <= 2'b00;
    end else begin
      control_current_index_stage <= control_current_index;
      arm_start_checked_stage <= arm_start_stage;
      arm_lead_difference_stage <=
          arm_start_stage - control_current_index_stage;
      arm_start_not_before_stage <=
          arm_start_stage >= control_current_index_stage;
      arm_window_no_overflow_stage <=
          arm_start_stage <= 64'hffff_ffff_ffff_ffff - (SAMPLE_COUNT - 1);

      arm_ack_sync <= {arm_ack_sync[0], sample_arm_ack_toggle};
      completion_sync <= {completion_sync[0], sample_completion_toggle};
      mismatch_sync <= {mismatch_sync[0], sample_mismatch_toggle};
      sample_active_sync <= {sample_active_sync[0], sample_injection_active};

      if (arm_validation_pending) begin
        if (arm_validation_count != 2'd1) begin
          arm_validation_count <= arm_validation_count - 1'b1;
        end else begin
          arm_validation_pending <= 1'b0;
          arm_validation_count <= 2'd0;
          if (arm_start_stage == arm_validation_start &&
              accepted_sample_control_lead) begin
            arm_start_mailbox <= arm_validation_start;
            arm_request_toggle <= ~arm_request_toggle;
            arm_pending <= 1'b1;
            arm_inflight <= 1'b1;
            completed_sticky <= 1'b0;
            mismatch_sticky <= 1'b0;
          end else begin
            rejected_sticky <= 1'b1;
          end
        end
      end

      if (arm_ack_sync[1] != arm_ack_seen) begin
        arm_ack_seen <= arm_ack_sync[1];
        arm_pending <= 1'b0;
      end
      if (completion_sync[1] != completion_seen) begin
        completion_seen <= completion_sync[1];
        completed_sticky <= 1'b1;
        last_completed_generation <= fixture_generation;
        arm_inflight <= 1'b0;
      end
      if (mismatch_sync[1] != mismatch_seen) begin
        mismatch_seen <= mismatch_sync[1];
        mismatch_sticky <= 1'b1;
        arm_inflight <= 1'b0;
      end

      if (fixture_write) begin
        if (fixture_write_ready) begin
          fixture_memory[fixture_count] <= fixture_write_data;
          fixture_count <= fixture_count + 1'b1;
        end else begin
          rejected_sticky <= 1'b1;
        end
      end

      if ((fixture_clear || fixture_commit || arm) &&
          (!command_onehot || command_multiple)) begin
        rejected_sticky <= 1'b1;
      end else if (fixture_clear) begin
        if (!arm_validation_pending && !arm_pending && !arm_inflight) begin
          fixture_count <= 8'd0;
          fixture_valid <= 1'b0;
          fixture_generation <= 32'd0;
          rejected_sticky <= 1'b0;
          completed_sticky <= 1'b0;
          mismatch_sticky <= 1'b0;
          last_completed_generation <= 32'd0;
        end else begin
          rejected_sticky <= 1'b1;
        end
      end else if (fixture_commit) begin
        if (!fixture_valid && !arm_validation_pending &&
            !arm_pending && !arm_inflight &&
            fixture_count == SAMPLE_COUNT &&
            fixture_generation_stage != 32'd0) begin
          fixture_valid <= 1'b1;
          fixture_generation <= fixture_generation_stage;
        end else begin
          rejected_sticky <= 1'b1;
        end
      end else if (arm) begin
        if (fixture_valid && !arm_validation_pending &&
            !arm_pending && !arm_inflight) begin
          arm_validation_pending <= 1'b1;
          arm_validation_count <= 2'd2;
          arm_validation_start <= arm_start_stage;
        end else begin
          rejected_sticky <= 1'b1;
        end
      end
    end
  end

  // Immutable arm payload mailbox. The payload traverses two ordinary sample
  // registers; after the toggle arrives, two additional sample clocks settle
  // it before the armed state is exposed.
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] arm_request_sync;
  reg arm_request_seen;
  reg arm_request_pending_value;
  reg [1:0] arm_settle_count;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] arm_start_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] arm_start_sync_2;

  reg sample_arm_ack_toggle;
  reg sample_completion_toggle;
  reg sample_mismatch_toggle;
  reg sample_armed;
  reg sample_started;
  reg sample_injection_active;
  reg [63:0] sample_arm_start;
  reg [63:0] sample_expected_index;
  reg [7:0] sample_fixture_index;

  wire source_sample_accepted = source_sample_enable && source_sample_strobe;
  wire sample_index_matches =
      (!sample_started && source_sample_index == sample_arm_start) ||
      (sample_started && source_sample_index == sample_expected_index);
  wire inject_this_sample =
      sample_armed && source_sample_accepted && sample_index_matches;
  // Once the exact first index arrives, a local accepted-sample counter is
  // both the BRAM address and the completion bound. The full 64-bit expected
  // index still detects every source discontinuity; repeated 64-bit range
  // compares and a subtractor are unnecessary on the per-sample path.
  wire [7:0] fixture_read_index = sample_started ?
      sample_fixture_index : 8'd0;
  reg [31:0] fixture_read_word;
  reg signed [15:0] source_sample_i_stage;
  reg signed [15:0] source_sample_q_stage;
  reg source_sample_strobe_stage;
  reg source_sample_enable_stage;
  reg [63:0] source_sample_index_stage;
  reg [63:0] source_sample_timestamp_stage;
  reg selection_injected_stage;
  reg completion_pending_stage;

  always @(posedge sample_clk) begin
    if (!sample_resetn) begin
      arm_request_sync <= 2'b00;
      arm_request_seen <= 1'b0;
      arm_request_pending_value <= 1'b0;
      arm_settle_count <= 2'd0;
      arm_start_sync_1 <= 64'd0;
      arm_start_sync_2 <= 64'd0;
      sample_arm_ack_toggle <= 1'b0;
      sample_completion_toggle <= 1'b0;
      sample_mismatch_toggle <= 1'b0;
      sample_armed <= 1'b0;
      sample_started <= 1'b0;
      sample_injection_active <= 1'b0;
      sample_arm_start <= 64'd0;
      sample_expected_index <= 64'd0;
      sample_fixture_index <= 8'd0;
      fixture_read_word <= 32'd0;
      source_sample_i_stage <= 16'sd0;
      source_sample_q_stage <= 16'sd0;
      source_sample_strobe_stage <= 1'b0;
      source_sample_enable_stage <= 1'b0;
      source_sample_index_stage <= 64'd0;
      source_sample_timestamp_stage <= 64'd0;
      selection_injected_stage <= 1'b0;
      completion_pending_stage <= 1'b0;
      selected_sample_i <= 16'sd0;
      selected_sample_q <= 16'sd0;
      selected_sample_strobe <= 1'b0;
      selected_sample_enable <= 1'b0;
      selected_sample_index <= 64'd0;
      selected_sample_timestamp <= 64'd0;
      selected_sample_injected <= 1'b0;
    end else begin
      arm_request_sync <= {arm_request_sync[0], arm_request_toggle};
      arm_start_sync_1 <= arm_start_mailbox;
      arm_start_sync_2 <= arm_start_sync_1;

      fixture_read_word <= fixture_memory[fixture_read_index];
      source_sample_i_stage <= source_sample_i;
      source_sample_q_stage <= source_sample_q;
      source_sample_strobe_stage <= source_sample_strobe;
      source_sample_enable_stage <= source_sample_enable;
      source_sample_index_stage <= source_sample_index;
      source_sample_timestamp_stage <= source_sample_timestamp;
      selection_injected_stage <= inject_this_sample;
      completion_pending_stage <=
          inject_this_sample && fixture_read_index == SAMPLE_COUNT - 1;

      selected_sample_i <= selection_injected_stage ?
          $signed(fixture_read_word[15:0]) : source_sample_i_stage;
      selected_sample_q <= selection_injected_stage ?
          $signed(fixture_read_word[31:16]) : source_sample_q_stage;
      selected_sample_strobe <= source_sample_strobe_stage;
      selected_sample_enable <= source_sample_enable_stage;
      selected_sample_index <= source_sample_index_stage;
      selected_sample_timestamp <= source_sample_timestamp_stage;
      selected_sample_injected <= selection_injected_stage;

      if (completion_pending_stage) begin
        sample_injection_active <= 1'b0;
        sample_completion_toggle <= ~sample_completion_toggle;
      end

      if (arm_request_sync[1] != arm_request_seen &&
          arm_settle_count == 0 && !sample_armed) begin
        arm_request_seen <= arm_request_sync[1];
        arm_request_pending_value <= arm_request_sync[1];
        arm_settle_count <= 2'd2;
      end else if (arm_settle_count != 0) begin
        arm_settle_count <= arm_settle_count - 1'b1;
        if (arm_settle_count == 1) begin
          sample_arm_start <= arm_start_sync_2;
          sample_expected_index <= arm_start_sync_2;
          sample_fixture_index <= 8'd0;
          sample_armed <= 1'b1;
          sample_started <= 1'b0;
          sample_arm_ack_toggle <= arm_request_pending_value;
        end
      end

      if (sample_armed && source_sample_accepted) begin
        if (!sample_started && source_sample_index < sample_arm_start) begin
          sample_injection_active <= 1'b0;
        end else if (!sample_index_matches) begin
          sample_armed <= 1'b0;
          sample_started <= 1'b0;
          sample_injection_active <= 1'b0;
          sample_fixture_index <= 8'd0;
          sample_mismatch_toggle <= ~sample_mismatch_toggle;
        end else begin
          sample_started <= 1'b1;
          sample_injection_active <= 1'b1;
          sample_expected_index <= source_sample_index + 1'b1;
          if (fixture_read_index == SAMPLE_COUNT - 1) begin
            sample_armed <= 1'b0;
            sample_started <= 1'b0;
            sample_fixture_index <= 8'd0;
          end else begin
            sample_fixture_index <= fixture_read_index + 1'b1;
          end
        end
      end else if (!sample_armed) begin
        sample_injection_active <= 1'b0;
      end
    end
  end

endmodule
