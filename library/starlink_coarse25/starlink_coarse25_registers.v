// Latest-result mailbox with coherent explicit snapshots. Not a lossless queue.
// Sequence and fault counters saturate; saturation is an explicit invalid state.
module starlink_coarse25_registers #(
  parameter integer GROUPS = 29
) (
  input wire clk,
  input wire reset,
  input wire arithmetic_reset,
  input wire sample_valid,
  input wire signed [15:0] sample_i,
  input wire signed [15:0] sample_q,
  input wire [63:0] sample_index,
  input wire snapshot_request,
  input wire [5:0] read_address,
  output reg [31:0] read_data
);
  wire initializing, fault, candidate_valid, detected;
  wire [63:0] first;
  wire [13:0] phase, count;
  wire [14:0] peak;
  wire [27:0] sum;
  wire [42:0] sumsq;
  starlink_coarse25_detector #(.GROUPS(GROUPS)) core (
    .clk(clk), .reset(reset || arithmetic_reset),
    .sample_valid(sample_valid), .sample_i(sample_i), .sample_q(sample_q),
    .sample_index(sample_index), .initializing(initializing), .fault(fault),
    .candidate_valid(candidate_valid), .detected(detected),
    .candidate_map_first_index(first), .candidate_phase(phase), .candidate_peak(peak),
    .candidate_background_sum(sum), .candidate_background_sumsq(sumsq),
    .candidate_background_count(count)
  );
  reg [31:0] sequence_number, fault_count;
  reg valid, decision;
  reg [63:0] latest_first;
  reg [13:0] latest_phase, latest_count;
  reg [14:0] latest_peak;
  reg [27:0] latest_sum;
  reg [42:0] latest_sumsq;
  reg [31:0] snapshot [0:12];
  integer n;
  always @(posedge clk) begin
    if (reset) begin
      sequence_number <= 0; fault_count <= 0; valid <= 0; decision <= 0;
      latest_first <= 0; latest_phase <= 0; latest_count <= 0;
      latest_peak <= 0; latest_sum <= 0; latest_sumsq <= 0;
    end else begin
      if (fault && !arithmetic_reset && !(&fault_count)) fault_count <= fault_count + 1'b1;
      if (candidate_valid && !arithmetic_reset) begin
        if (!(&sequence_number)) sequence_number <= sequence_number + 1'b1;
        valid <= 1; decision <= detected; latest_first <= first;
        latest_phase <= phase; latest_count <= count; latest_peak <= peak;
        latest_sum <= sum; latest_sumsq <= sumsq;
      end
    end
    // Same pre-edge snapshot as the IQ capture counters and generation.
    if (reset) begin
      for (n = 0; n < 13; n = n + 1) snapshot[n] <= 0;
    end else if (snapshot_request) begin
      snapshot[0] <= sequence_number;
      snapshot[1] <= {27'd0, (&sequence_number) || (&fault_count),
                     arithmetic_reset, initializing, decision, valid};
      snapshot[2] <= latest_first[31:0]; snapshot[3] <= latest_first[63:32];
      snapshot[4] <= latest_phase; snapshot[5] <= latest_peak;
      snapshot[6] <= latest_sum;
      snapshot[7] <= latest_sumsq[31:0]; snapshot[8] <= latest_sumsq[42:32];
      snapshot[9] <= latest_count; snapshot[10] <= fault_count;
      snapshot[11] <= GROUPS * 10000;
      snapshot[12] <= 32'h00010010; // template profile 1, 16 taps
    end
  end
  always @* begin
    read_data = 0;
    if (read_address >= 6'h28 && read_address <= 6'h34)
      read_data = snapshot[read_address - 6'h28];
  end
endmodule
