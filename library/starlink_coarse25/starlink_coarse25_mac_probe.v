// Route-only harness: registered stimulus and sink make MAC boundary paths
// routable. This is not an RX interface, RF fixture, or deployable top level.
module starlink_coarse25_mac_probe (
  input wire clk,
  output reg [176:0] observed
);
  reg [2:0] startup = 0;
  reg [5:0] cadence = 0;
  reg [63:0] index = 0;
  reg [15:0] noise_i = 16'h6139;
  reg [15:0] noise_q = 16'h1235;
  wire reset = startup != 7;
  wire valid = cadence == 39;
  wire result_valid, gap, overrun;
  wire signed [36:0] re, im;
  wire [35:0] energy;
  wire [63:0] first_index;
  always @(posedge clk) begin
    if (startup != 7) startup <= startup + 1'b1;
    if (reset) begin
      cadence <= 0;
      index <= 0;
    end else begin
      cadence <= valid ? 0 : cadence + 1'b1;
      if (valid) index <= index + 1'b1;
    end
    noise_i <= {noise_i[14:0],noise_i[15]^noise_i[13]^noise_i[12]^noise_i[10]};
    noise_q <= {noise_q[14:0],noise_q[15]^noise_q[14]^noise_q[12]^noise_q[3]};
    observed <= {result_valid,gap,overrun,first_index,re,im,energy};
  end
  (* dont_touch = "yes" *) starlink_coarse25_mac dut (
    .clk(clk), .reset(reset), .sample_valid(valid), .sample_i(noise_i),
    .sample_q(noise_q), .sample_index(index), .result_valid(result_valid),
    .result_re(re), .result_im(im), .result_energy(energy),
    .result_first_index(first_index), .gap(gap), .overrun(overrun)
  );
endmodule
