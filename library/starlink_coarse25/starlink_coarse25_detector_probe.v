// Registered-boundary full coarse detector probe. Not a deployable RX interface.
module starlink_coarse25_detector_probe (
  input wire clk,
  output reg [181:0] observed
);
  reg [2:0] startup = 0;
  reg [5:0] cadence = 0;
  reg [63:0] index = 0;
  reg [15:0] noise_i = 16'h6139;
  reg [15:0] noise_q = 16'h1235;
  wire reset = startup != 7;
  wire valid = cadence == 39;
  wire initializing,fault,cv,detected;
  wire [63:0] first;
  wire [13:0] phase,n;
  wire [14:0] peak;
  wire [27:0] sum;
  wire [42:0] sumsq;
  always @(posedge clk) begin
    if (startup != 7) startup <= startup + 1'b1;
    if (reset) begin cadence <= 0; index <= 0; end
    else begin
      cadence <= valid ? 0 : cadence + 1'b1;
      if (valid) index <= index + 1'b1;
    end
    noise_i <= {noise_i[14:0],noise_i[15]^noise_i[13]^noise_i[12]^noise_i[10]};
    noise_q <= {noise_q[14:0],noise_q[15]^noise_q[14]^noise_q[12]^noise_q[3]};
    observed <= {initializing,fault,cv,detected,first,phase,peak,sum,sumsq,n};
  end
  (* dont_touch="yes" *) starlink_coarse25_detector dut (
    .clk(clk),.reset(reset),.sample_valid(valid),.sample_i(noise_i),.sample_q(noise_q),
    .sample_index(index),.initializing(initializing),.fault(fault),
    .candidate_valid(cv),.detected(detected),.candidate_map_first_index(first),
    .candidate_phase(phase),.candidate_peak(peak),.candidate_background_sum(sum),
    .candidate_background_sumsq(sumsq),.candidate_background_count(n)
  );
endmodule
