// EXPERIMENT: unbackpressured synchronous canonical input -> six-port history
// -> exact 66-tap MAC. No normalizer, ADC CDC, phase-map or receiver wrapper.
// Bank order: source15 upper/lower, source30 upper/lower, source60 upper/lower.
// Every fence discards pending outputs and seeds a new segment with any input
// beat on that edge. Timestamps are stored, never reconstructed from latency.
`timescale 1ns/1ps
module starlink_pss_direct_feeder #(
  parameter COEFFICIENT_FILE = "direct_groups_q15.mem"
) (
  input wire clk, input wire resetn, input wire flush,
  input wire sample_valid, input wire sample_gap,
  input wire signed [15:0] sample_i, input wire signed [15:0] sample_q,
  input wire [63:0] sample_timestamp,
  input wire config_valid, input wire [2:0] config_bank,
  output wire config_accepted, output wire config_rejected,
  output reg identity_exhausted,
  output wire segment_fence, output wire expiry_now, output wire gap_now,
  output wire output_valid, input wire output_ready,
  output wire signed [39:0] output_i, output wire signed [39:0] output_q,
  output wire [63:0] output_timestamp,
  output wire [31:0] output_identity,
  output reg [31:0] accepted_samples, output reg [31:0] emitted_results,
  output reg [31:0] expiry_events, output reg [31:0] gap_events
);
  // 16-bit sequence differences remain unambiguous: expiry fences at 128,
  // long before half-range. Sequential operation is valid across seq wrap.
  reg [15:0] write_sequence, next_start;
  reg [3:0] issue_group;
  reg [2:0] active_bank;
  reg [28:0] generation;
  reg have_timestamp;
  reg [63:0] expected_timestamp;
  wire [2:0] selected_bank = config_accepted ? config_bank : active_bank;
  wire [2:0] selected_stride = selected_bank < 2 ? 3'd1 :
                               selected_bank < 4 ? 3'd2 : 3'd4;
  wire [15:0] pending_span = write_sequence - next_start;
  wire intentional_fence = flush || config_accepted;
  assign config_accepted = resetn && config_valid && config_bank < 6 &&
                           !identity_exhausted && generation != 29'h1fffffff;
  assign config_rejected = resetn && config_valid && !config_accepted;
  // An explicit upstream gap remains a real counted fault even if a config
  // or flush deliberately invalidates old timestamp-stride expectations.
  assign gap_now = resetn && (sample_gap || (!intentional_fence &&
                   !identity_exhausted && sample_valid && have_timestamp &&
                   sample_timestamp != expected_timestamp));
  // Conservative lifetime: retain every sample in a job until all its reads
  // have been issued. Never permit simultaneous overwrite of retained data.
  assign expiry_now = resetn && !identity_exhausted && !intentional_fence && !gap_now &&
                      sample_valid && pending_span >= 16'd128;
  assign segment_fence = resetn && (identity_exhausted || intentional_fence || gap_now || expiry_now);
  wire [6:0] write_address = segment_fence ? 7'd0 : write_sequence[6:0];
  wire [6:0] group_offset = {issue_group, 2'b00} + {1'b0, issue_group, 1'b0};
  wire [6:0] read_base = next_start[6:0] + group_offset;
  wire [6:0] coefficient_address = active_bank * 7'd11 + issue_group;
  reg read_valid, read_first, read_last;
  reg [31:0] read_identity;
  reg [63:0] read_timestamp;
  wire mac_ready, mac_valid;
  wire read_stage_ready = !read_valid || mac_ready;
  wire read_enable = resetn && !segment_fence && read_stage_ready &&
                     pending_span >= 16'd66;
  wire [95:0] read_i, read_q, coefficient_i, coefficient_q;
  (* rom_style = "distributed" *) reg [191:0] coefficient_rom [0:65];
  reg [191:0] coefficient_read;
  (* ram_style = "block" *) reg [63:0] timestamp_memory [0:127];
  initial $readmemh(COEFFICIENT_FILE, coefficient_rom, 0, 65);

  genvar lane;
  generate for (lane=0; lane<6; lane=lane+1) begin : history
    (* ram_style = "block" *) reg [31:0] samples [0:127];
    reg [31:0] sample_read;
    wire [6:0] read_address = read_base + lane;
    always @(posedge clk) begin
      if (resetn && sample_valid)
        samples[write_address] <= {sample_q, sample_i};
      if (read_enable)
        sample_read <= samples[read_address];
    end
    assign read_i[lane*16 +: 16] = sample_read[15:0];
    assign read_q[lane*16 +: 16] = sample_read[31:16];
    assign coefficient_i[lane*16 +: 16] = coefficient_read[lane*32 +: 16];
    assign coefficient_q[lane*16 +: 16] = coefficient_read[lane*32+16 +: 16];
  end endgenerate
  always @(posedge clk) begin
    if (resetn && sample_valid)
      timestamp_memory[write_address] <= sample_timestamp;
    if (read_enable) begin
      read_timestamp <= timestamp_memory[next_start[6:0]];
      coefficient_read <= coefficient_rom[coefficient_address];
    end
  end
  assign output_valid = resetn && !segment_fence && mac_valid;
  starlink_pss_direct_mac6 mac (
    .clk(clk), .resetn(resetn), .flush(segment_fence),
    .input_valid(read_valid), .input_ready(mac_ready),
    .input_first(read_first), .input_last(read_last),
    .input_i(read_i), .input_q(read_q),
    .coefficient_i(coefficient_i), .coefficient_q(coefficient_q),
    .input_timestamp(read_timestamp), .input_epoch(read_identity),
    .output_valid(mac_valid), .output_ready(output_ready && !segment_fence),
    .output_i(output_i), .output_q(output_q),
    .output_timestamp(output_timestamp), .output_epoch(output_identity)
  );
  always @(posedge clk) begin
    if (!resetn) begin
      write_sequence <= 0; next_start <= 0; issue_group <= 0;
      read_valid <= 0; have_timestamp <= 0; expected_timestamp <= 0;
      active_bank <= 0; generation <= 0;
      identity_exhausted <= 0;
      accepted_samples <= 0; emitted_results <= 0;
      expiry_events <= 0; gap_events <= 0;
    end else begin
      if (sample_valid && accepted_samples != 32'hffffffff)
        accepted_samples <= accepted_samples + 1'b1;
      if (output_valid && output_ready && emitted_results != 32'hffffffff)
        emitted_results <= emitted_results + 1'b1;
      if (expiry_now && expiry_events != 32'hffffffff)
        expiry_events <= expiry_events + 1'b1;
      if (gap_now && gap_events != 32'hffffffff)
        gap_events <= gap_events + 1'b1;
      if (config_accepted) active_bank <= config_bank;
      if (sample_valid) begin
        expected_timestamp <= sample_timestamp + selected_stride;
        have_timestamp <= 1;
      end
      if (segment_fence) begin
        // Refuse generation aliasing. A new external reset/session identity
        // is required after exhausting the 29-bit local generation space.
        if (generation == 29'h1fffffff) identity_exhausted <= 1;
        else generation <= generation + 1'b1;
        write_sequence <= sample_valid ? 16'd1 : 16'd0;
        next_start <= 0; issue_group <= 0; read_valid <= 0;
        have_timestamp <= sample_valid;
      end else begin
        if (sample_valid) write_sequence <= write_sequence + 1'b1;
        if (read_stage_ready) read_valid <= read_enable;
        if (read_enable) begin
          read_first <= issue_group == 0;
          read_last <= issue_group == 10;
          read_identity <= {generation, active_bank};
          if (issue_group == 10) begin
            issue_group <= 0;
            next_start <= next_start + 1'b1;
          end else issue_group <= issue_group + 1'b1;
        end
      end
    end
  end
endmodule
