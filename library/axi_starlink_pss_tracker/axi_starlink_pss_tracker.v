// SPDX-License-Identifier: GPL-2.0
//
// AXI4-Lite boundary for the experimental rate-scalable exact TRACK_ONE pipeline.
// Software loads one full-rate CI16 coefficient bank, submits future candidate
// centers, and reads one atomic 26-word normalized-winner packet.  This block
// is host-driven; it does not turn the older repeated-delay diagnostic into an
// exact-match claim or attempt to capture already-past candidate windows.

`timescale 1ns/1ps

module axi_starlink_pss_tracker #(
  parameter integer RATE_MSPS = 15,
  parameter integer COMMAND_FIFO_ADDRESS_WIDTH = 3,
  parameter [63:0] MINIMUM_LEAD_SAMPLES =
      64'd64 * (RATE_MSPS / 15),
  parameter integer ENABLE_INJECTION = 1
) (
  input  wire                 sample_clk,
  input  wire                 sample_reset,
  input  wire signed [15:0]   sample_i,
  input  wire signed [15:0]   sample_q,
  input  wire                 sample_strobe,
  input  wire                 sample_enable,
  input  wire [63:0]          sample_index,
  input  wire [63:0]          sample_timestamp,
  output wire signed [15:0]   selected_sample_i,
  output wire signed [15:0]   selected_sample_q,
  output wire                 selected_sample_strobe,
  output wire                 selected_sample_enable,
  output wire [63:0]          selected_sample_index,
  output wire [63:0]          selected_sample_timestamp,
  output wire                 selected_sample_injected,

  output wire                 irq,

  input  wire                 s_axi_aclk,
  input  wire                 s_axi_aresetn,
  input  wire                 s_axi_awvalid,
  input  wire [7:0]           s_axi_awaddr,
  output wire                 s_axi_awready,
  input  wire                 s_axi_wvalid,
  input  wire [31:0]          s_axi_wdata,
  input  wire [3:0]           s_axi_wstrb,
  output wire                 s_axi_wready,
  output wire                 s_axi_bvalid,
  output wire [1:0]           s_axi_bresp,
  input  wire                 s_axi_bready,
  input  wire                 s_axi_arvalid,
  input  wire [7:0]           s_axi_araddr,
  output wire                 s_axi_arready,
  output wire                 s_axi_rvalid,
  output wire [1:0]           s_axi_rresp,
  output wire [31:0]          s_axi_rdata,
  input  wire                 s_axi_rready,
  input  wire [2:0]           s_axi_awprot,
  input  wire [2:0]           s_axi_arprot
);

  localparam [31:0] IDENTIFICATION = 32'h5053_5354; // ASCII "PSST".
  localparam integer RATE_MULTIPLIER = RATE_MSPS / 15;
  localparam integer COEFFICIENT_COUNT = 66 * RATE_MULTIPLIER;
  localparam integer CAPTURE_COUNT = 130 * RATE_MULTIPLIER;
  localparam integer QUALIFIED_LAG_COUNT = 60 * RATE_MULTIPLIER + 1;
  localparam integer COEFFICIENT_COUNT_WIDTH =
      $clog2(COEFFICIENT_COUNT + 1);
  localparam integer STATUS_PADDING_WIDTH =
      32 - (12 + COMMAND_FIFO_ADDRESS_WIDTH + COEFFICIENT_COUNT_WIDTH);
  // ABI 1.2 and its byte-field geometry remain bit-for-bit stable at 15 MS/s.
  // Higher-rate ABI 1.3 uses marker 1 followed by 8/10/9-bit lag/capture/tap
  // fields, which represent all planned 30/60 MS/s geometries without loss.
  localparam [31:0] VERSION = (RATE_MSPS == 15) ?
      32'h0001_0002 : 32'h0001_0003;
  localparam [31:0] GEOMETRY = (RATE_MSPS == 15) ?
      {8'd0, 8'd61, 8'd130, 8'd66} :
      {5'd1, QUALIFIED_LAG_COUNT[7:0], CAPTURE_COUNT[9:0],
       COEFFICIENT_COUNT[8:0]};
  localparam [31:0] CAPABILITIES = ENABLE_INJECTION ?
      32'h0000_003d : 32'h0000_001d;

  localparam [5:0] REG_IDENTIFICATION = 6'h00; // 0x00
  localparam [5:0] REG_VERSION = 6'h01; // 0x04
  localparam [5:0] REG_RATE_MSPS = 6'h02; // 0x08
  localparam [5:0] REG_GEOMETRY = 6'h03; // 0x0c
  localparam [5:0] REG_CAPABILITIES = 6'h04; // 0x10
  localparam [5:0] REG_STATUS = 6'h05; // 0x14
  localparam [5:0] REG_CURRENT_INDEX_LO = 6'h06; // 0x18
  localparam [5:0] REG_CURRENT_INDEX_HI = 6'h07; // 0x1c
  localparam [5:0] REG_CANDIDATE_REQUEST = 6'h08; // 0x20
  localparam [5:0] REG_CANDIDATE_CENTER_LO = 6'h09; // 0x24
  localparam [5:0] REG_CANDIDATE_CENTER_HI = 6'h0a; // 0x28
  localparam [5:0] REG_CANDIDATE_TIMESTAMP_LO = 6'h0b; // 0x2c
  localparam [5:0] REG_CANDIDATE_TIMESTAMP_HI = 6'h0c; // 0x30
  localparam [5:0] REG_CANDIDATE_CONTROL = 6'h0d; // 0x34
  localparam [5:0] REG_CANDIDATE_COMMAND_OVERRUN = 6'h0e; // 0x38
  localparam [5:0] REG_COEFFICIENT_WRITE_OVERRUN = 6'h0f; // 0x3c
  localparam [5:0] REG_COEFFICIENT_DATA = 6'h10; // 0x40
  localparam [5:0] REG_COEFFICIENT_CONTROL = 6'h11; // 0x44
  localparam [5:0] REG_COEFFICIENT_GENERATION = 6'h12; // 0x48
  localparam [5:0] REG_ACTIVE_COEFFICIENT_GENERATION = 6'h13; // 0x4c
  localparam [5:0] REG_RESULT_WORD_INDEX = 6'h14; // 0x50
  localparam [5:0] REG_RESULT_WORD_DATA = 6'h15; // 0x54
  localparam [5:0] REG_RESULT_CONTROL = 6'h16; // 0x58
  localparam [5:0] REG_RESULT_STATUS = 6'h17; // 0x5c
  localparam [5:0] REG_ACTIVE_ENERGY_LO = 6'h18; // 0x60
  localparam [5:0] REG_ACTIVE_ENERGY_HI = 6'h19; // 0x64
  localparam [5:0] REG_TELEMETRY_CONTROL = 6'h1a; // 0x68
  localparam [5:0] REG_TELEMETRY_STATUS = 6'h1b; // 0x6c
  localparam [5:0] REG_TELEMETRY_GENERATION = 6'h1c; // 0x70

  localparam [5:0] REG_QUEUE_OVERRUN = 6'h20; // 0x80
  localparam [5:0] REG_ADMITTED = 6'h21; // 0x84
  localparam [5:0] REG_COMPLETED_CAPTURE = 6'h22; // 0x88
  localparam [5:0] REG_REJECTED = 6'h23; // 0x8c
  localparam [5:0] REG_LATE = 6'h24; // 0x90
  localparam [5:0] REG_DUPLICATE = 6'h25; // 0x94
  localparam [5:0] REG_OVERLAP = 6'h26; // 0x98
  localparam [5:0] REG_ABORTED = 6'h27; // 0x9c
  localparam [5:0] REG_VALID_GAP_ABORT = 6'h28; // 0xa0
  localparam [5:0] REG_INDEX_JUMP_ABORT = 6'h29; // 0xa4
  localparam [5:0] REG_TIMESTAMP_ABORT = 6'h2a; // 0xa8
  localparam [5:0] REG_CAPTURE_PUBLISHED = 6'h2b; // 0xac
  localparam [5:0] REG_CAPTURE_ABORT_DISCARD = 6'h2c; // 0xb0
  localparam [5:0] REG_CAPTURE_BUFFER_OVERRUN = 6'h2d; // 0xb4
  localparam [5:0] REG_CAPTURE_PROTOCOL_ERROR = 6'h2e; // 0xb8
  localparam [5:0] REG_ENGINE_CONSUMED = 6'h2f; // 0xbc
  localparam [5:0] REG_CORRELATOR_BOUND_ERROR = 6'h30; // 0xc0
  localparam [5:0] REG_REDUCER_PROCESSED = 6'h31; // 0xc4
  localparam [5:0] REG_REDUCER_EMITTED = 6'h32; // 0xc8
  localparam [5:0] REG_REDUCER_INVALID = 6'h33; // 0xcc
  localparam [5:0] REG_REDUCER_BOUND_ERROR = 6'h34; // 0xd0
  localparam [5:0] REG_REDUCER_PROTOCOL_ERROR = 6'h35; // 0xd4
  localparam [5:0] REG_RESULT_PUBLISHED = 6'h36; // 0xd8
  localparam [5:0] REG_RESULT_OVERRUN = 6'h37; // 0xdc
  localparam [5:0] REG_RESULT_CONSUMED = 6'h38; // 0xe0
  localparam [5:0] REG_INJECTION_DATA = 6'h39; // 0xe4
  localparam [5:0] REG_INJECTION_CONTROL = 6'h3a; // 0xe8
  localparam [5:0] REG_INJECTION_START_LO = 6'h3b; // 0xec
  localparam [5:0] REG_INJECTION_START_HI = 6'h3c; // 0xf0
  localparam [5:0] REG_INJECTION_GENERATION = 6'h3d; // 0xf4
  localparam [5:0] REG_INJECTION_STATUS = 6'h3e; // 0xf8
  localparam [5:0] REG_INJECTION_LAST_GENERATION = 6'h3f; // 0xfc

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  function automatic [63:0] binary_to_gray_64;
    input [63:0] value;
    begin
      binary_to_gray_64 = (value >> 1) ^ value;
    end
  endfunction

  function automatic [63:0] gray_to_binary_64;
    input [63:0] value;
    reg [63:0] prefix;
    begin
      // Parallel-prefix XOR avoids the long shared chain produced by a
      // bit-at-a-time Gray decoder.  For a 64-bit word this has six explicit
      // logic stages, independent of the requested output bit.
      prefix = value;
      prefix = prefix ^ (prefix >> 1);
      prefix = prefix ^ (prefix >> 2);
      prefix = prefix ^ (prefix >> 4);
      prefix = prefix ^ (prefix >> 8);
      prefix = prefix ^ (prefix >> 16);
      prefix = prefix ^ (prefix >> 32);
      gray_to_binary_64 = prefix;
    end
  endfunction

  generate
    if ((RATE_MSPS != 15) && (RATE_MSPS != 30) &&
        (RATE_MSPS != 60)) begin : g_invalid_rate
      initial $fatal(1, "tracker RATE_MSPS must be 15, 30, or 60");
    end
    if ((RATE_MSPS != 15) && (ENABLE_INJECTION != 0)) begin : g_invalid_injection_rate
      initial $fatal(1, "fixture injection is qualified only at 15 MS/s");
    end
    if (STATUS_PADDING_WIDTH < 0) begin : g_invalid_status_width
      initial $fatal(1, "tracker status fields exceed 32 bits");
    end
    if (ENABLE_INJECTION != 0 && ENABLE_INJECTION != 1) begin : g_invalid_injection
      initial $fatal(1, "ENABLE_INJECTION must be 0 or 1");
    end
  endgenerate

  // AXI reset establishes the common asynchronous epoch without placing
  // combinational logic ahead of an asynchronous reset pin.  The sample reset
  // is local/synchronous to sample_clk and is separately synchronized into
  // AXI; while asserted it holds both sides of every FIFO in reset.
  wire reset_epoch_async_n = s_axi_aresetn;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] control_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_reset_control_sync;

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      control_reset_sync <= 2'b00;
    else
      control_reset_sync <= {control_reset_sync[0], 1'b1};
  end

  always @(posedge sample_clk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      sample_reset_sync <= 2'b00;
    else
      sample_reset_sync <= {sample_reset_sync[0], 1'b1};
  end

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      sample_reset_control_sync <= 2'b11;
    else
      sample_reset_control_sync <= {
        sample_reset_control_sync[0], sample_reset
      };
  end

  wire core_control_resetn =
      control_reset_sync[1] && !sample_reset_control_sync[1];
  wire core_engine_resetn = core_control_resetn;
  wire core_sample_resetn = sample_reset_sync[1] && !sample_reset;

  // Gray synchronization gives software a coherent, near-current scheduling
  // reference.  The hardware stream advances by exactly one per accepted beat;
  // discontinuities reset the complete IP epoch before normal operation.
  reg [63:0] sample_index_gray;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] sample_index_gray_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] sample_index_gray_sync_2;

  always @(posedge sample_clk) begin
    if (!core_sample_resetn)
      sample_index_gray <= 64'd0;
    else if (selected_sample_enable && selected_sample_strobe)
      sample_index_gray <= binary_to_gray_64(selected_sample_index);
  end

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      sample_index_gray_sync_1 <= 64'd0;
      sample_index_gray_sync_2 <= 64'd0;
    end else begin
      sample_index_gray_sync_1 <= sample_index_gray;
      sample_index_gray_sync_2 <= sample_index_gray_sync_1;
    end
  end

  wire [63:0] current_sample_index =
      gray_to_binary_64(sample_index_gray_sync_2);

  reg injection_fixture_clear;
  reg injection_fixture_write;
  reg [31:0] injection_fixture_write_data;
  reg injection_fixture_commit;
  reg injection_arm;
  reg [63:0] injection_start_stage;
  reg [31:0] injection_generation_stage;
  wire injection_fixture_write_ready;
  wire injection_arm_ready;
  wire [31:0] injection_status;
  wire [31:0] injection_last_completed_generation;

  generate
    if (ENABLE_INJECTION) begin : g_injection
      starlink_pss_injection_mux #(
        .SAMPLE_COUNT             (130),
        .MINIMUM_ARM_LEAD_SAMPLES (64'd64)
      ) i_injection_mux (
        .control_clk                       (s_axi_aclk),
        .control_resetn                    (core_control_resetn),
        .fixture_clear                     (injection_fixture_clear),
        .fixture_write                     (injection_fixture_write),
        .fixture_write_data                (injection_fixture_write_data),
        .fixture_commit                    (injection_fixture_commit),
        .fixture_generation_stage          (injection_generation_stage),
        .arm                               (injection_arm),
        .arm_start_stage                   (injection_start_stage),
        .control_current_index             (current_sample_index),
        .fixture_write_ready               (injection_fixture_write_ready),
        .arm_ready                         (injection_arm_ready),
        .status                            (injection_status),
        .last_completed_generation         (injection_last_completed_generation),
        .sample_clk                        (sample_clk),
        .sample_resetn                     (core_sample_resetn),
        .source_sample_i                   (sample_i),
        .source_sample_q                   (sample_q),
        .source_sample_strobe              (sample_strobe),
        .source_sample_enable              (sample_enable),
        .source_sample_index               (sample_index),
        .source_sample_timestamp           (sample_timestamp),
        .selected_sample_i                 (selected_sample_i),
        .selected_sample_q                 (selected_sample_q),
        .selected_sample_strobe            (selected_sample_strobe),
        .selected_sample_enable            (selected_sample_enable),
        .selected_sample_index             (selected_sample_index),
        .selected_sample_timestamp         (selected_sample_timestamp),
        .selected_sample_injected          (selected_sample_injected)
      );
    end else begin : g_direct_sample_path
      assign injection_fixture_write_ready = 1'b0;
      assign injection_arm_ready = 1'b0;
      assign injection_status = 32'd0;
      assign injection_last_completed_generation = 32'd0;
      assign selected_sample_i = sample_i;
      assign selected_sample_q = sample_q;
      assign selected_sample_strobe = sample_strobe;
      assign selected_sample_enable = sample_enable;
      assign selected_sample_index = sample_index;
      assign selected_sample_timestamp = sample_timestamp;
      assign selected_sample_injected = 1'b0;
    end
  endgenerate

  wire up_wreq;
  wire [5:0] up_waddr;
  wire [31:0] up_wdata;
  wire up_rreq;
  wire [5:0] up_raddr;
  reg up_wack;
  reg up_rack;
  reg [31:0] up_rdata;

  reg [31:0] candidate_request_stage;
  reg [63:0] candidate_center_stage;
  reg [63:0] candidate_timestamp_stage;
  reg candidate_command_pending;
  reg [31:0] candidate_pending_request;
  reg [63:0] candidate_pending_center;
  reg [63:0] candidate_pending_timestamp;
  reg [31:0] candidate_command_overrun_count;

  reg coefficient_push_pending;
  reg signed [15:0] coefficient_pending_i;
  reg signed [15:0] coefficient_pending_q;
  reg coefficient_clear_pending;
  reg coefficient_clear;
  reg coefficient_commit_pending;
  reg [31:0] coefficient_generation_stage;
  reg [31:0] coefficient_write_overrun_count;

  reg [4:0] result_word_index;
  reg result_word_read;
  reg result_read_pending;
  reg telemetry_read_pending;
  reg register_read_pending;
  reg [2:0] register_read_bank_select;
  reg [31:0] register_read_bank_0;
  reg [31:0] register_read_bank_1;
  reg [31:0] register_read_bank_2;
  reg [31:0] register_read_bank_3;
  reg [31:0] register_read_bank_4;
  reg [31:0] register_read_bank_5;
  reg [31:0] register_read_bank_6;
  reg [31:0] register_read_bank_7;
  reg result_release;
  reg [63:0] current_index_snapshot;

  wire candidate_submit_ready;
  wire candidate_submit_accepted;
  wire [COMMAND_FIFO_ADDRESS_WIDTH-1:0] candidate_queue_room;
  wire [31:0] queue_overrun_count;
  wire coefficient_ready;
  wire coefficient_commit_ready;
  wire coefficient_commit_accepted;
  wire coefficient_commit_rejected;
  wire active_coefficient_valid;
  wire [31:0] active_coefficient_generation;
  wire signed [47:0] active_coefficient_energy;
  wire [COEFFICIENT_COUNT_WIDTH-1:0] shadow_coefficient_count;
  wire configuration_idle;
  wire result_available;
  wire result_bank;
  wire result_word_valid;
  wire [31:0] result_word_data;
  wire candidate_pending;
  wire capture_active;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] candidate_pending_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] capture_active_sync;
  wire [31:0] admitted_count;
  wire [31:0] completed_capture_count;
  wire [31:0] rejected_count;
  wire [31:0] late_count;
  wire [31:0] duplicate_count;
  wire [31:0] overlap_count;
  wire [31:0] aborted_count;
  wire [31:0] valid_gap_abort_count;
  wire [31:0] index_jump_abort_count;
  wire [31:0] timestamp_abort_count;
  wire [1:0] capture_bank_free;
  wire [31:0] capture_published_count;
  wire [31:0] capture_abort_discard_count;
  wire [31:0] capture_buffer_overrun_count;
  wire [31:0] capture_protocol_error_count;
  wire [31:0] engine_consumed_count;
  wire [31:0] correlator_bound_error_count;
  wire [31:0] reducer_processed_job_count;
  wire [31:0] reducer_emitted_result_count;
  wire [31:0] reducer_invalid_tuple_count;
  wire [31:0] reducer_bound_error_count;
  wire [31:0] reducer_protocol_error_count;
  wire [1:0] result_bank_free;
  wire [31:0] result_published_count;
  wire [31:0] result_overrun_count;
  wire [31:0] result_consumed_count;

  // Atomic sample-domain telemetry mailbox.  A request first blocks new
  // candidate submission and waits until the command FIFO and capture state
  // are empty.  The fourteen counters are then stable while sample_clk writes
  // them sequentially into a small true dual-clock RAM.  A toggle
  // acknowledgement publishes the complete bank to AXI only after the final
  // word is written.  This preserves the one-edge atomic meaning of the old
  // wide mailbox without 1,344 payload and synchronizer flip-flops.
  localparam integer TELEMETRY_COUNTERS = 14;
  localparam [COMMAND_FIFO_ADDRESS_WIDTH-1:0] COMMAND_FIFO_CAPACITY =
      {COMMAND_FIFO_ADDRESS_WIDTH{1'b1}};
  reg telemetry_request_toggle;
  reg telemetry_request_issued;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] telemetry_request_sync;
  reg telemetry_request_seen;
  reg telemetry_ack_toggle;
  reg telemetry_capture_active;
  reg [3:0] telemetry_write_index;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] telemetry_ack_sync;
  reg telemetry_ack_seen;
  reg telemetry_busy;
  reg telemetry_valid;
  reg [2:0] telemetry_idle_count;
  reg [31:0] telemetry_generation;
  wire [31:0] telemetry_memory_read_data;

  wire telemetry_request = up_wreq &&
      (up_waddr == REG_TELEMETRY_CONTROL) && up_wdata[0];
  wire telemetry_pipeline_idle =
      (candidate_queue_room == COMMAND_FIFO_CAPACITY) &&
      !candidate_pending_sync[1] && !capture_active_sync[1];

  reg [31:0] telemetry_write_data;
  always @(*) begin
    case (telemetry_write_index)
      4'd0: telemetry_write_data = admitted_count;
      4'd1: telemetry_write_data = completed_capture_count;
      4'd2: telemetry_write_data = rejected_count;
      4'd3: telemetry_write_data = late_count;
      4'd4: telemetry_write_data = duplicate_count;
      4'd5: telemetry_write_data = overlap_count;
      4'd6: telemetry_write_data = aborted_count;
      4'd7: telemetry_write_data = valid_gap_abort_count;
      4'd8: telemetry_write_data = index_jump_abort_count;
      4'd9: telemetry_write_data = timestamp_abort_count;
      4'd10: telemetry_write_data = capture_published_count;
      4'd11: telemetry_write_data = capture_abort_discard_count;
      4'd12: telemetry_write_data = capture_buffer_overrun_count;
      4'd13: telemetry_write_data = capture_protocol_error_count;
      default: telemetry_write_data = 32'd0;
    endcase
  end

  wire telemetry_word_addressed =
      (up_raddr >= REG_ADMITTED) &&
      (up_raddr <= REG_CAPTURE_PROTOCOL_ERROR);
  wire telemetry_memory_read =
      up_rreq && !register_read_pending && !result_read_pending &&
      !telemetry_read_pending && telemetry_word_addressed;

  ad_mem #(
    .DATA_WIDTH    (32),
    .ADDRESS_WIDTH (4)
  ) i_telemetry_memory (
    .clka  (sample_clk),
    .wea   (telemetry_capture_active),
    .addra (telemetry_write_index),
    .dina  (telemetry_write_data),
    .clkb  (s_axi_aclk),
    .reb   (telemetry_memory_read),
    .addrb (up_raddr[3:0] - REG_ADMITTED[3:0]),
    .doutb (telemetry_memory_read_data)
  );

  always @(posedge sample_clk) begin
    if (!core_sample_resetn) begin
      telemetry_request_sync <= 2'b00;
      telemetry_request_seen <= 1'b0;
      telemetry_ack_toggle <= 1'b0;
      telemetry_capture_active <= 1'b0;
      telemetry_write_index <= 4'd0;
    end else begin
      telemetry_request_sync <= {
        telemetry_request_sync[0], telemetry_request_toggle
      };
      if (telemetry_request_sync[1] != telemetry_request_seen) begin
        telemetry_request_seen <= telemetry_request_sync[1];
        telemetry_capture_active <= 1'b1;
        telemetry_write_index <= 4'd0;
      end else if (telemetry_capture_active) begin
        if (telemetry_write_index == TELEMETRY_COUNTERS - 1) begin
          telemetry_capture_active <= 1'b0;
          telemetry_ack_toggle <= telemetry_request_seen;
        end else begin
          telemetry_write_index <= telemetry_write_index + 1'b1;
        end
      end
    end
  end

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      telemetry_ack_sync <= 2'b00;
    end else begin
      telemetry_ack_sync <= {telemetry_ack_sync[0], telemetry_ack_toggle};
    end
  end

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      telemetry_request_toggle <= 1'b0;
      telemetry_request_issued <= 1'b0;
      telemetry_ack_seen <= 1'b0;
      telemetry_busy <= 1'b0;
      telemetry_valid <= 1'b0;
      telemetry_idle_count <= 3'd0;
      telemetry_generation <= 32'd0;
    end else begin
      if (telemetry_request && !telemetry_busy) begin
        telemetry_busy <= 1'b1;
        telemetry_valid <= 1'b0;
        telemetry_request_issued <= 1'b0;
        telemetry_idle_count <= 3'd0;
      end
      if (telemetry_busy && !telemetry_request_issued) begin
        if (!telemetry_pipeline_idle) begin
          telemetry_idle_count <= 3'd0;
        end else if (telemetry_idle_count == 3'd3) begin
          // Four consecutive control-clock observations cover the independent
          // two-stage FIFO-pointer and scheduler-status CDC latencies.
          telemetry_request_toggle <= ~telemetry_request_toggle;
          telemetry_request_issued <= 1'b1;
          telemetry_idle_count <= 3'd0;
        end else begin
          telemetry_idle_count <= telemetry_idle_count + 1'b1;
        end
      end
      if (telemetry_busy && telemetry_request_issued &&
          (telemetry_ack_sync[1] != telemetry_ack_seen)) begin
        telemetry_ack_seen <= telemetry_ack_sync[1];
        telemetry_request_issued <= 1'b0;
        telemetry_busy <= 1'b0;
        telemetry_valid <= 1'b1;
        telemetry_idle_count <= 3'd0;
        telemetry_generation <= increment_saturating_32(
            telemetry_generation);
      end
    end
  end

  wire candidate_command_handshake =
      candidate_command_pending && candidate_submit_ready && !telemetry_busy;
  wire coefficient_push_handshake =
      coefficient_push_pending && !coefficient_clear_pending &&
      coefficient_ready;
  // Ready intentionally falls while clear is asserted, so clear must be a
  // registered one-cycle command after idle has been observed.  A direct
  // combinational ready -> clear -> ready path would oscillate in simulation
  // and would not describe safe hardware.
  wire coefficient_clear_can_issue =
      coefficient_clear_pending && configuration_idle;
  wire coefficient_commit =
      coefficient_commit_pending && !coefficient_clear_pending &&
      !coefficient_push_pending && coefficient_commit_ready;

  // These are the only live sample-domain status bits exposed to AXI.  Wider
  // diagnostics are available only through the atomic mailbox above.
  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      candidate_pending_sync <= 2'b00;
      capture_active_sync <= 2'b00;
    end else begin
      candidate_pending_sync <= {candidate_pending_sync[0], candidate_pending};
      capture_active_sync <= {capture_active_sync[0], capture_active};
    end
  end

  wire [31:0] status_word = {
    {STATUS_PADDING_WIDTH{1'b0}},
    candidate_pending_sync[1],
    capture_active_sync[1],
    candidate_queue_room,
    result_bank_free,
    shadow_coefficient_count,
    irq,
    result_available,
    coefficient_commit_ready,
    coefficient_ready,
    active_coefficient_valid,
    candidate_command_pending,
    candidate_submit_ready,
    core_control_resetn
  };

  // The read map is split into eight banks and pipelined across two AXI-clock
  // cycles.  Each source therefore drives at most one 8:1 mux before a bank
  // register, followed by one 8:1 bank mux.  This avoids placing every status
  // and counter bit behind one device-wide combinational read tree.
  function automatic [31:0] read_bank_0_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_0_value = IDENTIFICATION;
        3'd1: read_bank_0_value = VERSION;
        3'd2: read_bank_0_value = RATE_MSPS;
        3'd3: read_bank_0_value = GEOMETRY;
        3'd4: read_bank_0_value = CAPABILITIES;
        3'd5: read_bank_0_value = status_word;
        3'd6: read_bank_0_value = current_sample_index[31:0];
        3'd7: read_bank_0_value = current_index_snapshot[63:32];
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_1_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_1_value = candidate_request_stage;
        3'd1: read_bank_1_value = candidate_center_stage[31:0];
        3'd2: read_bank_1_value = candidate_center_stage[63:32];
        3'd3: read_bank_1_value = candidate_timestamp_stage[31:0];
        3'd4: read_bank_1_value = candidate_timestamp_stage[63:32];
        3'd5: read_bank_1_value = 32'd0;
        3'd6: read_bank_1_value = candidate_command_overrun_count;
        3'd7: read_bank_1_value = coefficient_write_overrun_count;
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_2_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_2_value = 32'd0;
        3'd1: read_bank_2_value = 32'd0;
        3'd2: read_bank_2_value = coefficient_generation_stage;
        3'd3: read_bank_2_value = active_coefficient_generation;
        3'd4: read_bank_2_value = {27'd0, result_word_index};
        3'd5: read_bank_2_value = 32'd0; // Synchronous result RAM is separate.
        3'd6: read_bank_2_value = 32'd0;
        3'd7: read_bank_2_value = {
          3'd0, 5'd26, 22'd0, result_bank, result_available
        };
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_3_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_3_value = active_coefficient_energy[31:0];
        3'd1: read_bank_3_value = {
          {16{active_coefficient_energy[47]}},
          active_coefficient_energy[47:32]
        };
        3'd2: read_bank_3_value = 32'd0;
        3'd3: read_bank_3_value = {
          30'd0, telemetry_busy, telemetry_valid
        };
        3'd4: read_bank_3_value = telemetry_generation;
        default: read_bank_3_value = 32'd0;
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_4_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_4_value = queue_overrun_count;
        default: read_bank_4_value = 32'd0;
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_5_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_5_value = 32'd0;
        3'd1: read_bank_5_value = 32'd0;
        3'd2: read_bank_5_value = 32'd0;
        3'd3: read_bank_5_value = 32'd0;
        3'd4: read_bank_5_value = 32'd0;
        3'd5: read_bank_5_value = 32'd0;
        3'd6: read_bank_5_value = 32'd0;
        3'd7: read_bank_5_value = engine_consumed_count;
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_6_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_6_value = correlator_bound_error_count;
        3'd1: read_bank_6_value = reducer_processed_job_count;
        3'd2: read_bank_6_value = reducer_emitted_result_count;
        3'd3: read_bank_6_value = reducer_invalid_tuple_count;
        3'd4: read_bank_6_value = reducer_bound_error_count;
        3'd5: read_bank_6_value = reducer_protocol_error_count;
        3'd6: read_bank_6_value = result_published_count;
        3'd7: read_bank_6_value = result_overrun_count;
      endcase
    end
  endfunction

  function automatic [31:0] read_bank_7_value;
    input [2:0] slot;
    begin
      case (slot)
        3'd0: read_bank_7_value = result_consumed_count;
        3'd1: read_bank_7_value = 32'd0;
        3'd2: read_bank_7_value = 32'd0;
        3'd3: read_bank_7_value = ENABLE_INJECTION ?
            injection_start_stage[31:0] : 32'd0;
        3'd4: read_bank_7_value = ENABLE_INJECTION ?
            injection_start_stage[63:32] : 32'd0;
        3'd5: read_bank_7_value = ENABLE_INJECTION ?
            injection_generation_stage : 32'd0;
        3'd6: read_bank_7_value = injection_status;
        3'd7: read_bank_7_value = injection_last_completed_generation;
      endcase
    end
  endfunction

  assign irq = result_available;

  // Only the reset synchronizer flops use asynchronous assertion.  All AXI
  // state consumes their synchronized output as an ordinary synchronous
  // reset, avoiding a high-fanout generated asynchronous reset tree.
  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      up_wack <= 1'b0;
      up_rack <= 1'b0;
      up_rdata <= 32'd0;
      candidate_request_stage <= 32'd0;
      candidate_center_stage <= 64'd0;
      candidate_timestamp_stage <= 64'd0;
      candidate_command_pending <= 1'b0;
      candidate_pending_request <= 32'd0;
      candidate_pending_center <= 64'd0;
      candidate_pending_timestamp <= 64'd0;
      candidate_command_overrun_count <= 32'd0;
      coefficient_push_pending <= 1'b0;
      coefficient_pending_i <= 16'sd0;
      coefficient_pending_q <= 16'sd0;
      coefficient_clear_pending <= 1'b0;
      coefficient_clear <= 1'b0;
      coefficient_commit_pending <= 1'b0;
      coefficient_generation_stage <= 32'd0;
      coefficient_write_overrun_count <= 32'd0;
      result_word_index <= 5'd0;
      result_word_read <= 1'b0;
      result_read_pending <= 1'b0;
      telemetry_read_pending <= 1'b0;
      register_read_pending <= 1'b0;
      register_read_bank_select <= 3'd0;
      register_read_bank_0 <= 32'd0;
      register_read_bank_1 <= 32'd0;
      register_read_bank_2 <= 32'd0;
      register_read_bank_3 <= 32'd0;
      register_read_bank_4 <= 32'd0;
      register_read_bank_5 <= 32'd0;
      register_read_bank_6 <= 32'd0;
      register_read_bank_7 <= 32'd0;
      result_release <= 1'b0;
      current_index_snapshot <= 64'd0;
      injection_fixture_clear <= 1'b0;
      injection_fixture_write <= 1'b0;
      injection_fixture_write_data <= 32'd0;
      injection_fixture_commit <= 1'b0;
      injection_arm <= 1'b0;
      injection_start_stage <= 64'd0;
      injection_generation_stage <= 32'd0;
    end else begin
      up_wack <= up_wreq;
      up_rack <= 1'b0;
      up_rdata <= 32'd0;
      result_word_read <= 1'b0;
      result_release <= 1'b0;
      coefficient_clear <= 1'b0;
      injection_fixture_clear <= 1'b0;
      injection_fixture_write <= 1'b0;
      injection_fixture_commit <= 1'b0;
      injection_arm <= 1'b0;

      if (candidate_command_handshake)
        candidate_command_pending <= 1'b0;

      if (coefficient_push_handshake)
        coefficient_push_pending <= 1'b0;
      if (coefficient_clear_can_issue) begin
        coefficient_clear_pending <= 1'b0;
        coefficient_clear <= 1'b1;
      end
      if (coefficient_commit)
        coefficient_commit_pending <= 1'b0;

      if (up_wreq) begin
        case (up_waddr)
          REG_CANDIDATE_REQUEST:
            candidate_request_stage <= up_wdata;
          REG_CANDIDATE_CENTER_LO:
            candidate_center_stage[31:0] <= up_wdata;
          REG_CANDIDATE_CENTER_HI:
            candidate_center_stage[63:32] <= up_wdata;
          REG_CANDIDATE_TIMESTAMP_LO:
            candidate_timestamp_stage[31:0] <= up_wdata;
          REG_CANDIDATE_TIMESTAMP_HI:
            candidate_timestamp_stage[63:32] <= up_wdata;
          REG_CANDIDATE_CONTROL: begin
            if (up_wdata[0]) begin
              if (!candidate_command_pending ||
                  candidate_command_handshake) begin
                candidate_pending_request <= candidate_request_stage;
                candidate_pending_center <= candidate_center_stage;
                candidate_pending_timestamp <= candidate_timestamp_stage;
                candidate_command_pending <= 1'b1;
              end else begin
                candidate_command_overrun_count <= increment_saturating_32(
                    candidate_command_overrun_count);
              end
            end
          end
          REG_COEFFICIENT_DATA: begin
            if (!coefficient_push_pending || coefficient_push_handshake) begin
              coefficient_pending_i <= up_wdata[15:0];
              coefficient_pending_q <= up_wdata[31:16];
              coefficient_push_pending <= 1'b1;
            end else begin
              coefficient_write_overrun_count <= increment_saturating_32(
                  coefficient_write_overrun_count);
            end
          end
          REG_COEFFICIENT_CONTROL: begin
            if (up_wdata[0]) begin
              coefficient_clear_pending <= 1'b1;
              coefficient_push_pending <= 1'b0;
              coefficient_commit_pending <= 1'b0;
            end else if (up_wdata[1]) begin
              coefficient_commit_pending <= 1'b1;
            end
          end
          REG_COEFFICIENT_GENERATION:
            coefficient_generation_stage <= up_wdata;
          REG_RESULT_WORD_INDEX:
            result_word_index <= (up_wdata[4:0] < 5'd26) ?
                up_wdata[4:0] : 5'd25;
          REG_RESULT_CONTROL: begin
            if (up_wdata[0])
              result_release <= 1'b1;
          end
          REG_INJECTION_DATA: begin
            if (ENABLE_INJECTION) begin
              injection_fixture_write_data <= up_wdata;
              injection_fixture_write <= 1'b1;
            end
          end
          REG_INJECTION_CONTROL: begin
            if (ENABLE_INJECTION) begin
              injection_fixture_clear <= up_wdata[0];
              injection_fixture_commit <= up_wdata[1];
              injection_arm <= up_wdata[2];
            end
          end
          REG_INJECTION_START_LO: begin
            if (ENABLE_INJECTION)
              injection_start_stage[31:0] <= up_wdata;
          end
          REG_INJECTION_START_HI: begin
            if (ENABLE_INJECTION)
              injection_start_stage[63:32] <= up_wdata;
          end
          REG_INJECTION_GENERATION: begin
            if (ENABLE_INJECTION)
              injection_generation_stage <= up_wdata;
          end
          default: begin
          end
        endcase
      end

      if (register_read_pending) begin
        case (register_read_bank_select)
          3'd0: up_rdata <= register_read_bank_0;
          3'd1: up_rdata <= register_read_bank_1;
          3'd2: up_rdata <= register_read_bank_2;
          3'd3: up_rdata <= register_read_bank_3;
          3'd4: up_rdata <= register_read_bank_4;
          3'd5: up_rdata <= register_read_bank_5;
          3'd6: up_rdata <= register_read_bank_6;
          3'd7: up_rdata <= register_read_bank_7;
        endcase
        up_rack <= 1'b1;
        register_read_pending <= 1'b0;
      end

      if (telemetry_read_pending) begin
        up_rdata <= telemetry_valid ? telemetry_memory_read_data : 32'd0;
        up_rack <= 1'b1;
        telemetry_read_pending <= 1'b0;
      end

      if (up_rreq && !register_read_pending && !result_read_pending &&
          !telemetry_read_pending) begin
        if (up_raddr == REG_RESULT_WORD_DATA) begin
          result_word_read <= 1'b1;
          result_read_pending <= 1'b1;
        end else if (telemetry_word_addressed) begin
          telemetry_read_pending <= 1'b1;
        end else begin
          register_read_bank_select <= up_raddr[5:3];
          register_read_bank_0 <= read_bank_0_value(up_raddr[2:0]);
          register_read_bank_1 <= read_bank_1_value(up_raddr[2:0]);
          register_read_bank_2 <= read_bank_2_value(up_raddr[2:0]);
          register_read_bank_3 <= read_bank_3_value(up_raddr[2:0]);
          register_read_bank_4 <= read_bank_4_value(up_raddr[2:0]);
          register_read_bank_5 <= read_bank_5_value(up_raddr[2:0]);
          register_read_bank_6 <= read_bank_6_value(up_raddr[2:0]);
          register_read_bank_7 <= read_bank_7_value(up_raddr[2:0]);
          register_read_pending <= 1'b1;
          if (up_raddr == REG_CURRENT_INDEX_LO)
            current_index_snapshot <= current_sample_index;
        end
      end

      if (result_word_valid) begin
        up_rdata <= result_word_data;
        up_rack <= 1'b1;
        result_read_pending <= 1'b0;
      end
    end
  end

  starlink_pss_reduced_tracking_core #(
    .RATE_MULTIPLIER           (RATE_MULTIPLIER),
    .COMMAND_FIFO_ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH),
    .MINIMUM_LEAD_SAMPLES       (MINIMUM_LEAD_SAMPLES)
  ) i_core (
    .i_control_clk                     (s_axi_aclk),
    .i_sample_clk                      (sample_clk),
    .i_engine_clk                      (s_axi_aclk),
    .i_control_resetn                  (core_control_resetn),
    .i_sample_resetn                   (core_sample_resetn),
    .i_engine_resetn                   (core_engine_resetn),
    .i_candidate_submit                (candidate_command_pending &&
                                        !telemetry_busy),
    .i_candidate_request_id            (candidate_pending_request),
    .i_candidate_center_index          (candidate_pending_center),
    .i_candidate_center_timestamp      (candidate_pending_timestamp),
    .o_candidate_submit_ready          (candidate_submit_ready),
    .o_candidate_submit_accepted       (candidate_submit_accepted),
    .o_candidate_queue_room            (candidate_queue_room),
    .o_queue_overrun_count             (queue_overrun_count),
    .i_sample_enable                   (selected_sample_enable),
    .i_sample_valid                    (selected_sample_strobe),
    .i_sample_index                    (selected_sample_index),
    .i_sample_timestamp                (selected_sample_timestamp),
    .i_sample_i                        (selected_sample_i),
    .i_sample_q                        (selected_sample_q),
    .i_coefficient_clear               (coefficient_clear),
    .i_coefficient_valid               (coefficient_push_pending &&
                                        !coefficient_clear_pending),
    .o_coefficient_ready               (coefficient_ready),
    .i_coefficient_i                   (coefficient_pending_i),
    .i_coefficient_q                   (coefficient_pending_q),
    .i_coefficient_commit              (coefficient_commit),
    .o_coefficient_commit_ready        (coefficient_commit_ready),
    .i_coefficient_generation          (coefficient_generation_stage),
    .o_coefficient_commit_accepted     (coefficient_commit_accepted),
    .o_coefficient_commit_rejected     (coefficient_commit_rejected),
    .o_active_coefficient_valid        (active_coefficient_valid),
    .o_active_coefficient_generation   (active_coefficient_generation),
    .o_active_coefficient_energy       (active_coefficient_energy),
    .o_shadow_coefficient_count        (shadow_coefficient_count),
    .o_configuration_idle              (configuration_idle),
    .o_result_available                (result_available),
    .o_result_bank                     (result_bank),
    .i_result_word_index               (result_word_index),
    .i_result_word_read                (result_word_read),
    .o_result_word_valid               (result_word_valid),
    .o_result_word_data                (result_word_data),
    .i_result_release                  (result_release),
    .o_candidate_pending               (candidate_pending),
    .o_capture_active                  (capture_active),
    .o_admitted_count                  (admitted_count),
    .o_completed_capture_count         (completed_capture_count),
    .o_rejected_count                  (rejected_count),
    .o_late_count                      (late_count),
    .o_duplicate_count                 (duplicate_count),
    .o_overlap_count                   (overlap_count),
    .o_aborted_count                   (aborted_count),
    .o_valid_gap_abort_count           (valid_gap_abort_count),
    .o_index_jump_abort_count          (index_jump_abort_count),
    .o_timestamp_abort_count           (timestamp_abort_count),
    .o_capture_bank_free               (capture_bank_free),
    .o_capture_published_count         (capture_published_count),
    .o_capture_abort_discard_count     (capture_abort_discard_count),
    .o_capture_buffer_overrun_count    (capture_buffer_overrun_count),
    .o_capture_protocol_error_count    (capture_protocol_error_count),
    .o_engine_consumed_count           (engine_consumed_count),
    .o_correlator_bound_error_count    (correlator_bound_error_count),
    .o_reducer_processed_job_count     (reducer_processed_job_count),
    .o_reducer_emitted_result_count    (reducer_emitted_result_count),
    .o_reducer_invalid_tuple_count     (reducer_invalid_tuple_count),
    .o_reducer_bound_error_count       (reducer_bound_error_count),
    .o_reducer_protocol_error_count    (reducer_protocol_error_count),
    .o_result_bank_free                (result_bank_free),
    .o_result_published_count          (result_published_count),
    .o_result_overrun_count            (result_overrun_count),
    .o_result_consumed_count           (result_consumed_count)
  );

  wire unused_axi_fields = ^{s_axi_wstrb, s_axi_awprot, s_axi_arprot,
                             candidate_submit_accepted,
                             coefficient_commit_accepted,
                             coefficient_commit_rejected,
                             injection_fixture_write_ready,
                             injection_arm_ready,
                             selected_sample_injected};

  up_axi #(
    .AXI_ADDRESS_WIDTH (8)
  ) i_up_axi (
    .up_rstn           (core_control_resetn),
    .up_clk            (s_axi_aclk),
    .up_axi_awvalid    (s_axi_awvalid),
    .up_axi_awaddr     (s_axi_awaddr),
    .up_axi_awready    (s_axi_awready),
    .up_axi_wvalid     (s_axi_wvalid),
    .up_axi_wdata      (s_axi_wdata),
    .up_axi_wstrb      (s_axi_wstrb),
    .up_axi_wready     (s_axi_wready),
    .up_axi_bvalid     (s_axi_bvalid),
    .up_axi_bresp      (s_axi_bresp),
    .up_axi_bready     (s_axi_bready),
    .up_axi_arvalid    (s_axi_arvalid),
    .up_axi_araddr     (s_axi_araddr),
    .up_axi_arready    (s_axi_arready),
    .up_axi_rvalid     (s_axi_rvalid),
    .up_axi_rresp      (s_axi_rresp),
    .up_axi_rdata      (s_axi_rdata),
    .up_axi_rready     (s_axi_rready),
    .up_wreq           (up_wreq),
    .up_waddr          (up_waddr),
    .up_wdata          (up_wdata),
    .up_wack           (up_wack),
    .up_rreq           (up_rreq),
    .up_raddr          (up_raddr),
    .up_rdata          (up_rdata),
    .up_rack           (up_rack)
  );

endmodule
