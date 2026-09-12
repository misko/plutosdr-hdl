// Registered-boundary route harness; not a radio top level.
module starlink_coarse25_datapath_probe (
  input wire clk,
  output reg [76:0] observed
);
  reg [2:0] startup = 0;
  reg [5:0] cadence = 0;
  reg [63:0] index = 0;
  reg [15:0] noise_i = 16'h6139;
  reg [15:0] noise_q = 16'h1235;
  wire reset = startup != 7;
  wire valid = cadence == 39;
  wire score_valid, denominator_zero, gap, mac_overrun, score_overrun;
  wire [7:0] score;
  wire [63:0] first;
  always @(posedge clk) begin
    if (startup != 7) startup <= startup + 1'b1;
    if (reset) begin cadence <= 0; index <= 0; end
    else begin
      cadence <= valid ? 0 : cadence + 1'b1;
      if (valid) index <= index + 1'b1;
    end
    noise_i <= {noise_i[14:0],noise_i[15]^noise_i[13]^noise_i[12]^noise_i[10]};
    noise_q <= {noise_q[14:0],noise_q[15]^noise_q[14]^noise_q[12]^noise_q[3]};
    observed <= {score_valid,denominator_zero,gap,mac_overrun,score_overrun,score,first};
  end
  (* dont_touch = "yes" *) starlink_coarse25_datapath dut (
    .clk(clk), .reset(reset), .sample_valid(valid), .sample_i(noise_i), .sample_q(noise_q),
    .sample_index(index), .score_valid(score_valid), .score(score), .score_first_index(first),
    .denominator_zero(denominator_zero), .gap(gap), .mac_overrun(mac_overrun),
    .score_overrun(score_overrun)
  );
endmodule
