// -----------------------------------------------------------------------------
// starlink_pss_event_cdc.v
//
// Loss-accounting, bundled-data clock-domain crossing for diagnostic candidate
// events.  The ADC side holds every mailbox word stable until the CPU side has
// captured it and returned the matching acknowledgement toggle.  Events that
// arrive while a transfer is outstanding are coalesced into the latest event,
// but the 64-bit event count records every event.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module starlink_pss_event_cdc (
  input  wire          adc_clk,
  input  wire          adc_reset,

  input  wire          candidate_valid,
  input  wire [63:0]   candidate_sample_index,
  input  wire [82:0]   candidate_metric_num,
  input  wire [81:0]   candidate_metric_den,

  input  wire          cpu_clk,
  input  wire          cpu_resetn,

  output reg  [31:0]   snapshot_generation,
  output reg  [63:0]   snapshot_event_count,
  output reg  [63:0]   snapshot_sample_index,
  output reg  [82:0]   snapshot_metric_num,
  output reg  [81:0]   snapshot_metric_den
);

  reg [63:0] event_count_adc;

  // The pending registers retain the newest event observed while the mailbox
  // is busy.  Intermediate payloads may be coalesced, but their events are not
  // lost from event_count_adc.
  reg          pending_valid;
  reg [63:0]   pending_event_count;
  reg [63:0]   pending_sample_index;
  reg [82:0]   pending_metric_num;
  reg [81:0]   pending_metric_den;

  // Bundled-data mailbox.  These words do not change from request_toggle until
  // the acknowledgement has returned through two ADC-clock synchronizers.
  reg [63:0]   mailbox_event_count;
  reg [63:0]   mailbox_sample_index;
  reg [82:0]   mailbox_metric_num;
  reg [81:0]   mailbox_metric_den;
  reg          request_toggle;

  reg          acknowledge_toggle;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg          acknowledge_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg          acknowledge_sync_2;

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg          request_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg          request_sync_2;

  wire mailbox_idle = (acknowledge_sync_2 == request_toggle);

  // Return-path synchronizer.
  always @(posedge adc_clk or posedge adc_reset) begin
    if (adc_reset) begin
      acknowledge_sync_1 <= 1'b0;
      acknowledge_sync_2 <= 1'b0;
    end else begin
      acknowledge_sync_1 <= acknowledge_toggle;
      acknowledge_sync_2 <= acknowledge_sync_1;
    end
  end

  // Source-side event accounting and mailbox launch.
  always @(posedge adc_clk or posedge adc_reset) begin
    if (adc_reset) begin
      event_count_adc          <= 64'd0;
      pending_valid            <= 1'b0;
      pending_event_count      <= 64'd0;
      pending_sample_index     <= 64'd0;
      pending_metric_num       <= 83'd0;
      pending_metric_den       <= 82'd0;
      mailbox_event_count      <= 64'd0;
      mailbox_sample_index     <= 64'd0;
      mailbox_metric_num       <= 83'd0;
      mailbox_metric_den       <= 82'd0;
      request_toggle           <= 1'b0;
    end else if (candidate_valid) begin
      event_count_adc <= event_count_adc + 1'b1;

      if (mailbox_idle) begin
        // A new event supersedes any older coalesced event because its count
        // includes every event through this payload.
        mailbox_event_count  <= event_count_adc + 1'b1;
        mailbox_sample_index <= candidate_sample_index;
        mailbox_metric_num   <= candidate_metric_num;
        mailbox_metric_den   <= candidate_metric_den;
        request_toggle       <= ~request_toggle;
        pending_valid        <= 1'b0;
      end else begin
        pending_event_count  <= event_count_adc + 1'b1;
        pending_sample_index <= candidate_sample_index;
        pending_metric_num   <= candidate_metric_num;
        pending_metric_den   <= candidate_metric_den;
        pending_valid        <= 1'b1;
      end
    end else if (mailbox_idle && pending_valid) begin
      mailbox_event_count  <= pending_event_count;
      mailbox_sample_index <= pending_sample_index;
      mailbox_metric_num   <= pending_metric_num;
      mailbox_metric_den   <= pending_metric_den;
      request_toggle       <= ~request_toggle;
      pending_valid        <= 1'b0;
    end
  end

  // Forward-path synchronizer and atomic CPU-domain capture.  The request
  // takes two CPU clocks to arrive, while the payload has already been stable
  // since before the first synchronizer sampled the toggle.
  always @(posedge cpu_clk or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      request_sync_1 <= 1'b0;
      request_sync_2 <= 1'b0;
    end else begin
      request_sync_1 <= request_toggle;
      request_sync_2 <= request_sync_1;
    end
  end

  always @(posedge cpu_clk or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      acknowledge_toggle     <= 1'b0;
      snapshot_generation    <= 32'd0;
      snapshot_event_count   <= 64'd0;
      snapshot_sample_index  <= 64'd0;
      snapshot_metric_num    <= 83'd0;
      snapshot_metric_den    <= 82'd0;
    end else if (request_sync_2 != acknowledge_toggle) begin
      snapshot_event_count   <= mailbox_event_count;
      snapshot_sample_index  <= mailbox_sample_index;
      snapshot_metric_num    <= mailbox_metric_num;
      snapshot_metric_den    <= mailbox_metric_den;
      snapshot_generation    <= snapshot_generation + 1'b1;
      acknowledge_toggle     <= request_sync_2;
    end
  end

endmodule
