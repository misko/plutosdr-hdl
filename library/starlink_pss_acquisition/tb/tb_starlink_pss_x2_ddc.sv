`timescale 1ns/1ps

module tb_starlink_pss_x2_ddc #(
  parameter integer EDGE_UPPER = 1
);

  localparam integer INPUT_COUNT = 500;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg input_gap = 1'b0;
  reg signed [15:0] input_i = 16'sd0;
  reg signed [15:0] input_q = 16'sd0;
  reg [63:0] input_index = 64'd0;

  wire output_enable;
  wire output_valid;
  wire output_gap;
  wire signed [15:0] output_i;
  wire signed [15:0] output_q;
  wire [63:0] output_index;
  wire [31:0] accepted_sample_count;
  wire [31:0] emitted_sample_count;
  wire [31:0] discontinuity_count;
  wire [31:0] saturation_event_count;

  reg [96:0] input_memory [0:INPUT_COUNT-1];
  reg [96:0] expected_memory [0:249];
  reg [31:0] summary_memory [0:3];

  starlink_pss_x2_ddc #(
    .EDGE_UPPER (EDGE_UPPER)
  ) dut (
    .clk                    (clk),
    .resetn                 (resetn),
    .enable                 (enable),
    .flush                  (flush),
    .input_valid            (input_valid),
    .input_gap              (input_gap),
    .input_i                (input_i),
    .input_q                (input_q),
    .input_index            (input_index),
    .output_enable          (output_enable),
    .output_valid           (output_valid),
    .output_gap             (output_gap),
    .output_i               (output_i),
    .output_q               (output_q),
    .output_index           (output_index),
    .accepted_sample_count  (accepted_sample_count),
    .emitted_sample_count   (emitted_sample_count),
    .discontinuity_count    (discontinuity_count),
    .saturation_event_count (saturation_event_count)
  );

  integer observed_outputs = 0;
  always @(negedge clk) begin
    if (resetn && output_valid) begin
      if (observed_outputs >= summary_memory[0])
        $fatal(1, "unexpected extra DDC output %0d", observed_outputs);
      if ({output_gap, output_index, output_q, output_i} !==
          expected_memory[observed_outputs]) begin
        $display("DDC mismatch edge_upper=%0d output=%0d", EDGE_UPPER,
                 observed_outputs);
        $display("expected=%025x", expected_memory[observed_outputs]);
        $display("actual  =%025x",
                 {output_gap, output_index, output_q, output_i});
        $fatal(1, "DDC output mismatch");
      end
      observed_outputs = observed_outputs + 1;
    end
  end

  integer input_number;
  initial begin
    $readmemh("build/ddc_input.mem", input_memory);
    if (EDGE_UPPER) begin
      $readmemh("build/ddc_upper_expected.mem", expected_memory);
      $readmemh("build/ddc_upper_summary.mem", summary_memory);
    end else begin
      $readmemh("build/ddc_lower_expected.mem", expected_memory);
      $readmemh("build/ddc_lower_summary.mem", summary_memory);
    end

    repeat (6) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;
    #1;
    if (!output_enable)
      $fatal(1, "enabled DDC did not advertise output enable");

    for (input_number = 0; input_number < INPUT_COUNT;
         input_number = input_number + 1) begin
      // Irregular clock-level spacing proves that FIR history advances only
      // on accepted samples, while absolute mixer phase follows source index.
      if ((input_number % 11) == 3 || (input_number % 17) == 8) begin
        @(negedge clk);
        input_valid = 1'b0;
      end
      @(negedge clk);
      input_valid = 1'b1;
      input_gap = input_memory[input_number][96];
      input_index = input_memory[input_number][95:32];
      input_q = input_memory[input_number][31:16];
      input_i = input_memory[input_number][15:0];
    end
    @(negedge clk);
    input_valid = 1'b0;
    input_gap = 1'b0;
    repeat (12) @(negedge clk);

    if (observed_outputs != summary_memory[0] ||
        emitted_sample_count != summary_memory[0])
      $fatal(1, "DDC output count got %0d/%0d expected %0d",
             observed_outputs, emitted_sample_count, summary_memory[0]);
    if (accepted_sample_count != summary_memory[1])
      $fatal(1, "DDC accepted count got %0d expected %0d",
             accepted_sample_count, summary_memory[1]);
    if (discontinuity_count != summary_memory[2])
      $fatal(1, "DDC discontinuity count got %0d expected %0d",
             discontinuity_count, summary_memory[2]);
    if (saturation_event_count != summary_memory[3])
      $fatal(1, "DDC saturation count got %0d expected %0d",
             saturation_event_count, summary_memory[3]);

    @(negedge clk);
    enable = 1'b0;
    @(posedge clk);
    #1;
    if (output_enable || output_valid)
      $fatal(1, "disabled DDC did not fail closed");

    $display("STARLINK_PSS_X2_DDC_PASS edge_upper=%0d inputs=%0d outputs=%0d discontinuities=%0d saturations=%0d",
             EDGE_UPPER, accepted_sample_count, emitted_sample_count,
             discontinuity_count, saturation_event_count);
    $finish;
  end

endmodule
