# Fail-closed, test-only adaptation. Legacy bench and product RTL are unchanged.
proc native_replace_once {value old replacement} {
  if {[string first $old $value] < 0 || [string first $old $value] != [string last $old $value]} {
    error "native anchor missing or duplicated: $old"
  }
  return [string map [list $old $replacement] $value]
}
proc prepare_native_paired_bench {bench checks} {
  foreach {old replacement} {
    {module tb_starlink_pss_paired_realtime_psma_stop #(} {module tb_starlink_bank_native_paired #(}
    {initial begin #2.1; forever #5 sample_clk = !sample_clk; end}
    {initial begin #2.1; forever #(500.0 / 15) sample_clk = !sample_clk; end}
    {wire pilot_ready = (cycles % 97) >= 8;}
    {reg pilot_ready = 0; always @(negedge clk) pilot_ready = (cycles % 97) >= 8;}
    {reg [7:0] awaddr [0:1], araddr [0:1];} {reg [7:0] awaddr [0:2], araddr [0:2];}
    {reg [31:0] wdata [0:1];} {reg [31:0] wdata [0:2];}
    {reg [1:0] awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;}
    {reg [2:0] awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;}
    {wire [1:0] awready, wready, bvalid, arready, rvalid;}
    {wire [2:0] awready, wready, bvalid, arready, rvalid;}
    {wire [1:0] bresp [0:1], rresp [0:1];} {wire [1:0] bresp [0:2], rresp [0:2];}
    {wire [31:0] rdata [0:1];} {wire [31:0] rdata [0:2];}
    {for (n = 0; n < 2; n = n + 1) begin awaddr[n]} {for (n = 0; n < 3; n = n + 1) begin awaddr[n]}
    {.sample_strobe(sample_strobe), .sample_enable(1'b1), .sample_gap(1'b0),}
    {.sample_strobe(sample_strobe), .sample_enable(source_enable), .sample_gap(1'b0),}
    {    repeat (500) @(negedge clk);}
    {    repeat (500) @(negedge clk); configure_native();}
    {    fork
      source_range(768, SOURCE_COUNT - 768);}
    {    fork
      run_native_command();
      source_range(768, SOURCE_COUNT - 768);}
    {    healthy(); $fclose(sink_fd);}
    {    healthy(); verify_native_terminal(); $fclose(sink_fd);}
  } {
    set bench [native_replace_once $bench $old $replacement]
  }
  set old {    integer sent;
    sent = 0;
    while (!sent) begin
      @(negedge sample_clk); sample_strobe = 0; input_phase = input_phase + 15;
      if (input_phase >= 100) begin
        input_phase = input_phase - 100;
        sample_strobe = 1; sample_index = index; sample_data = value; sent = 1;
      end
    end}
  set bench [native_replace_once $bench $old {
    @(negedge sample_clk); source_enable = 1;
    sample_strobe = 1; sample_index = index; sample_data = value;}]
  # Both intentional pauses precede native admission or follow its completed
  # window. Do not reinterpret idle valid cycles while a native request owns it.
  if {[regexp -all {    @\(negedge sample_clk\); sample_strobe = 0;} $bench] != 2} {
    error "native source-pause inventory changed"
  }
  set bench [string map [list {    @(negedge sample_clk); sample_strobe = 0;} \
    {    @(negedge sample_clk); sample_strobe = 0; source_enable = 0;}] $bench]
  return [native_replace_once $bench {endmodule} "$checks\nendmodule"]
}
