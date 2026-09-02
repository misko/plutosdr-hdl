// Strict AXI4-Stream boundary for one generated 512-point Xilinx XFFT core.
//
// The adapter deliberately does not instantiate vendor IP.  It owns reset
// stretching, the one-time transform-direction configuration, one-block
// lifecycle, scheduler-side and XFFT-side framing checks, block identity, and
// block-exponent qualification.  A malformed transaction is consumed where
// possible, never published, and latches protocol_fault until an explicit
// common flush resets both this adapter and the generated core.

`timescale 1ns/1ps

module starlink_pss_xfft_block_adapter #(
  parameter integer FORWARD_TRANSFORM = 1
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [23:0]      input_i,
  input  wire signed [23:0]      input_q,
  input  wire [8:0]              input_position,
  input  wire [63:0]             input_block_start_index,
  input  wire                    input_last,

  output wire                    output_valid,
  input  wire                    output_ready,
  output wire signed [23:0]      output_i,
  output wire signed [23:0]      output_q,
  output wire [8:0]              output_position,
  output wire [4:0]              output_block_exponent,
  output wire [63:0]             output_block_start_index,
  output wire                    output_last,

  output wire                    core_aresetn,
  output wire [7:0]              core_config_tdata,
  output wire                    core_config_tvalid,
  input  wire                    core_config_tready,
  output wire [47:0]             core_input_tdata,
  output wire                    core_input_tvalid,
  input  wire                    core_input_tready,
  output wire                    core_input_tlast,
  input  wire [47:0]             core_output_tdata,
  input  wire [23:0]             core_output_tuser,
  input  wire                    core_output_tvalid,
  output wire                    core_output_tready,
  input  wire                    core_output_tlast,
  input  wire [7:0]              core_status_tdata,
  input  wire                    core_status_tvalid,
  output wire                    core_status_tready,
  input  wire                    core_event_frame_started,
  input  wire                    core_event_tlast_unexpected,
  input  wire                    core_event_tlast_missing,
  input  wire                    core_event_status_channel_halt,
  input  wire                    core_event_data_in_channel_halt,
  input  wire                    core_event_data_out_channel_halt,

  output reg                     configured_pulse,
  output reg                     input_block_complete_pulse,
  output reg                     output_block_complete_pulse,
  output reg                     protocol_error_pulse,
  output reg                     input_framing_error_pulse,
  output reg                     output_metadata_error_pulse,
  output reg                     status_error_pulse,
  output reg                     core_tlast_error_pulse,
  output reg                     core_data_in_halt_pulse,
  output reg                     core_data_out_halt_pulse,
  output reg                     protocol_fault
);

  reg [1:0] reset_release_count;
  reg configured;
  reg block_inflight;
  reg input_in_progress;
  reg [8:0] expected_input_position;
  reg [8:0] expected_output_position;
  reg [63:0] active_block_start_index;
  reg frame_started_seen;
  reg status_seen;
  reg [4:0] status_block_exponent;
  reg output_exponent_seen;
  reg [4:0] active_output_exponent;

  wire adapter_released;
  wire input_slot_available;
  wire input_metadata_valid;
  wire input_accept;
  wire input_start_accept;
  wire input_framing_error_now;
  wire status_accept;
  wire status_or_padding_error_now;
  wire effective_status_seen;
  wire [4:0] effective_status_exponent;
  wire frame_started_error_now;
  wire core_tlast_error_now;
  wire hard_core_error_now;
  wire output_check_enabled;
  wire output_metadata_valid;
  wire output_metadata_error_now;
  wire fault_event_now;
  wire core_output_accept;

  initial begin
    if (FORWARD_TRANSFORM != 0 && FORWARD_TRANSFORM != 1)
      $fatal(1, "FORWARD_TRANSFORM must be zero or one");
  end

  assign adapter_released = resetn && !flush &&
                            (reset_release_count == 2);
  assign core_aresetn = adapter_released;

  assign core_config_tdata = {7'b0, FORWARD_TRANSFORM[0]};
  assign core_config_tvalid = adapter_released && !configured &&
                              !protocol_fault;

  assign input_slot_available = !block_inflight || input_in_progress;
  assign input_metadata_valid =
    input_position == expected_input_position &&
    input_last == (expected_input_position == 9'd511) &&
    (!block_inflight ||
     input_block_start_index == active_block_start_index);
  assign input_ready = adapter_released && configured && !protocol_fault &&
                       input_slot_available &&
                       (input_metadata_valid ? core_input_tready : 1'b1);
  assign input_accept = input_valid && input_ready;
  assign input_start_accept = input_accept &&
                              expected_input_position == 0 &&
                              !block_inflight;
  assign input_framing_error_now = input_accept && !input_metadata_valid;

  assign core_input_tdata = {input_q, input_i};
  assign core_input_tvalid = input_valid && input_ready &&
                             input_metadata_valid;
  assign core_input_tlast = input_last;

  // The block-floating status is documented to appear at frame start.  Keep
  // TREADY asserted whenever the core is released, capture it independently,
  // and hold data output if the status has not arrived yet.
  assign core_status_tready = adapter_released;
  assign status_accept = core_status_tvalid && core_status_tready;
  assign status_or_padding_error_now = status_accept &&
    (!block_inflight || status_seen || core_status_tdata[7:5] != 0);
  assign effective_status_seen = status_seen ||
                                 (status_accept &&
                                  !status_or_padding_error_now);
  assign effective_status_exponent = status_seen ?
    status_block_exponent : core_status_tdata[4:0];

  assign frame_started_error_now = core_event_frame_started &&
    !(input_start_accept || (block_inflight && !frame_started_seen));
  assign core_tlast_error_now = core_event_tlast_unexpected ||
                                core_event_tlast_missing;
  assign hard_core_error_now = frame_started_error_now ||
                               core_tlast_error_now ||
                               core_event_status_channel_halt;

  assign output_check_enabled = core_output_tvalid &&
                                effective_status_seen;
  assign output_metadata_valid = block_inflight && !input_in_progress &&
    (frame_started_seen || core_event_frame_started) &&
    core_output_tuser[15:9] == 0 && core_output_tuser[23:21] == 0 &&
    core_output_tuser[8:0] == expected_output_position &&
    core_output_tlast == (expected_output_position == 9'd511) &&
    core_output_tuser[20:16] == effective_status_exponent &&
    (!output_exponent_seen ||
     core_output_tuser[20:16] == active_output_exponent);
  assign output_metadata_error_now = output_check_enabled &&
                                     !output_metadata_valid;
  assign fault_event_now = input_framing_error_now ||
                           status_or_padding_error_now ||
                           hard_core_error_now ||
                           output_metadata_error_now;

  // With one block in flight, application input and XFFT output can never
  // handshake in the same lifecycle phase.  Only faults that can coincide
  // with an output beat participate in this same-cycle publication gate;
  // input framing still latches protocol_fault before any output phase opens.
  assign output_valid = adapter_released && configured && !protocol_fault &&
                        !status_or_padding_error_now &&
                        !core_event_status_channel_halt &&
                        !output_metadata_error_now && output_check_enabled;
  assign core_output_tready = adapter_released &&
    (protocol_fault ? 1'b1 :
     (effective_status_seen ? output_ready : 1'b0));
  assign core_output_accept = core_output_tvalid && core_output_tready;

  assign output_i = core_output_tdata[23:0];
  assign output_q = core_output_tdata[47:24];
  assign output_position = core_output_tuser[8:0];
  assign output_block_exponent = core_output_tuser[20:16];
  assign output_block_start_index = active_block_start_index;
  assign output_last = core_output_tlast;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      reset_release_count <= 0;
      configured <= 1'b0;
      block_inflight <= 1'b0;
      input_in_progress <= 1'b0;
      expected_input_position <= 0;
      expected_output_position <= 0;
      active_block_start_index <= 0;
      frame_started_seen <= 1'b0;
      status_seen <= 1'b0;
      status_block_exponent <= 0;
      output_exponent_seen <= 1'b0;
      active_output_exponent <= 0;
      configured_pulse <= 1'b0;
      input_block_complete_pulse <= 1'b0;
      output_block_complete_pulse <= 1'b0;
      protocol_error_pulse <= 1'b0;
      input_framing_error_pulse <= 1'b0;
      output_metadata_error_pulse <= 1'b0;
      status_error_pulse <= 1'b0;
      core_tlast_error_pulse <= 1'b0;
      core_data_in_halt_pulse <= 1'b0;
      core_data_out_halt_pulse <= 1'b0;
      protocol_fault <= 1'b0;
    end else begin
      configured_pulse <= 1'b0;
      input_block_complete_pulse <= 1'b0;
      output_block_complete_pulse <= 1'b0;
      protocol_error_pulse <= 1'b0;
      input_framing_error_pulse <= 1'b0;
      output_metadata_error_pulse <= 1'b0;
      status_error_pulse <= 1'b0;
      core_tlast_error_pulse <= 1'b0;
      core_data_in_halt_pulse <= core_event_data_in_channel_halt;
      core_data_out_halt_pulse <= core_event_data_out_channel_halt;

      if (reset_release_count != 2)
        reset_release_count <= reset_release_count + 1'b1;

      if (core_config_tvalid && core_config_tready) begin
        configured <= 1'b1;
        configured_pulse <= 1'b1;
      end

      if (input_accept && input_metadata_valid) begin
        if (!block_inflight) begin
          block_inflight <= 1'b1;
          input_in_progress <= 1'b1;
          active_block_start_index <= input_block_start_index;
          frame_started_seen <= 1'b0;
          status_seen <= 1'b0;
          output_exponent_seen <= 1'b0;
          expected_output_position <= 0;
        end

        if (expected_input_position == 9'd511) begin
          expected_input_position <= 0;
          input_in_progress <= 1'b0;
          input_block_complete_pulse <= 1'b1;
        end else begin
          expected_input_position <= expected_input_position + 1'b1;
        end
      end

      if (core_event_frame_started && !frame_started_error_now)
        frame_started_seen <= 1'b1;

      if (status_accept && !status_or_padding_error_now) begin
        status_seen <= 1'b1;
        status_block_exponent <= core_status_tdata[4:0];
      end

      if (core_output_accept && !fault_event_now && !protocol_fault) begin
        if (!output_exponent_seen) begin
          output_exponent_seen <= 1'b1;
          active_output_exponent <= core_output_tuser[20:16];
        end

        if (expected_output_position == 9'd511) begin
          expected_output_position <= 0;
          block_inflight <= 1'b0;
          frame_started_seen <= 1'b0;
          status_seen <= 1'b0;
          output_exponent_seen <= 1'b0;
          output_block_complete_pulse <= 1'b1;
        end else begin
          expected_output_position <= expected_output_position + 1'b1;
        end
      end

      if (fault_event_now && !protocol_fault) begin
        protocol_fault <= 1'b1;
        protocol_error_pulse <= 1'b1;
        input_framing_error_pulse <= input_framing_error_now;
        output_metadata_error_pulse <= output_metadata_error_now;
        status_error_pulse <= status_or_padding_error_now ||
                              core_event_status_channel_halt;
        core_tlast_error_pulse <= core_tlast_error_now;
      end
    end
  end

endmodule
