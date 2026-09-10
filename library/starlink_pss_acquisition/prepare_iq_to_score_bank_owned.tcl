# Pure, fail-closed mechanical adaptation of the existing independent benches.
# tclsh-callable: no Vivado commands or simulator-only source dependencies.
proc bank_replace_once {value old replacement} {
  if {[string first $old $value] < 0 || [string first $old $value] != [string last $old $value]} {
    error "bench anchor missing or duplicated: $old"
  }
  return [string map [list $old $replacement] $value]
}
proc prepare_bank_owned_bench {bench mode} {
  if {$mode ni {numeric capacity}} { error "unsupported bank-owned bench mode" }
  set bench [bank_replace_once $bench {`timescale 1ns/1ps} {`timescale 1ns/1fs}]
  set bench [bank_replace_once $bench {starlink_pss_iq_to_score dut (} {starlink_pss_iq_to_score_bank_owned dut (
    .fft_clk(fft_clk), .fft_resetn(fft_resetn),}]
  set bench [bank_replace_once $bench {  always #5 clk = ~clk;} {
  parameter integer FAST_MHZ = 200;
  reg fft_clk = 0;
  reg fft_resetn = 1;
  initial begin #1.3; forever #(500.0 / FAST_MHZ) fft_clk = !fft_clk; end
  always #5 clk = ~clk;
}]
  # Relocate BOTH actual acceptance monitors, not only their signal names.
  set first [string first {      if (dut.forward_output_valid} $bench]
  set last [string first {      if (dut.inverse_output_valid} $bench]
  if {$first < 0 || $last <= $first} { error "fast monitor boundaries missing" }
  set fast [string range $bench $first [expr {$last - 1}]]
  set bench [string replace $bench $first [expr {$last - 1}] {}]
  set fast [string map {
    dut.forward_output_valid dut.island.joiner.input_valid
    dut.forward_output_ready dut.island.joiner.input_ready
    dut.forward_output_q dut.island.return_data[35:18]
    dut.forward_output_i dut.island.return_data[17:0]
    dut.forward_output_position dut.island.return_position
    dut.forward_output_exponent dut.island.return_metadata[4:0]
    dut.forward_output_last dut.island.return_last
    dut.forward_output_block_start dut.island.return_metadata[73:10]
    dut.product_output_valid dut.island.product.input_valid_UNUSED
    dut.product_output_ready dut.island.product_bank_ready
    dut.product_output_q dut.island.product_q
    dut.product_output_i dut.island.product_i
    dut.product_output_bin_index dut.island.product_position
    dut.product_output_exponent dut.island.product_exponent
    dut.product_output_last dut.island.product_last
    dut.product_output_block_start dut.island.product_start
    dut.product_output_overflow dut.island.product_overflow
    block_number fast_block_number
    block_position fast_block_position
  } $fast]
  set fast [string map {dut.island.product.input_valid_UNUSED {dut.island.product_valid && !dut.island.fast_fault}} $fast]
  set fast_header {  integer fast_block_number, fast_block_position;
  always @(posedge fft_clk) begin
    if (resetn && enable}
  if {$mode eq "numeric"} { append fast_header { && !expected_fault_window} }
  append fast_header ") begin\n$fast    end\n  end\n"
  set bench [bank_replace_once $bench {endmodule} "$fast_header\nendmodule"]
  if {$mode eq "numeric"} {
    set bench [bank_replace_once $bench {      $fatal(1);} {      $fatal(1, "bank-owned numeric assertion failed");}]
    set bench [bank_replace_once $bench {    if (resetn && enable) begin} {    if (resetn && enable && !expected_fault_window) begin}]
    set bench [bank_replace_once $bench {dut.inverse_output_position !== block_position[8:0] ||} {dut.inverse_forward_exponent !== expected_forward_exponents[block_number] ||
            dut.inverse_output_position !== block_position[8:0] ||}]
    set first [string first {    // Prove that a real generated-core event} $bench]
    set last [string first {    $display("IQ_TO_SCORE_XFFT_PASS} $bench]
    if {$first < 0 || $last <= $first} { error "numeric fault boundaries missing" }
    set bench [string replace $bench $first [expr {$last - 1}] "    run_bank_fault_scenarios();\n\n"]
    set bench [bank_replace_once $bench {  always #5 clk = ~clk;} {  `include "bank_owned_iq_fault_scenarios.svh"
  always #5 clk = ~clk;}]
  } else {
    set bench [bank_replace_once $bench {  localparam integer BLOCK_COUNT = 64;} {  parameter integer CAPACITY_BLOCKS = 64;
  localparam integer BLOCK_COUNT = CAPACITY_BLOCKS;
  initial if (CAPACITY_BLOCKS != 64 && CAPACITY_BLOCKS != 4096)
    $fatal(1, "capacity bench supports only 64 or 4096 blocks");}]
    set bench [bank_replace_once $bench {cycle_count > 1000000} {cycle_count > BLOCK_COUNT * 4000 + 100000}]
    set bench [bank_replace_once $bench {  always #5 clk = ~clk;} {  `include "bank_owned_iq_capacity_checks.svh"
  always #5 clk = ~clk;}]
    set bench [bank_replace_once $bench {  wire score_ready = !SCORE_STALL_MODE || cycle_count % 97 >= 3;} {  reg score_ready = 1;
  always @(negedge clk) score_ready = !SCORE_STALL_MODE || cycle_count % 97 >= 3;}]
    set bench [bank_replace_once $bench {        $finish;} {        $fatal(1, "bank-owned continuous pipeline fault");}]
    set bench [bank_replace_once $bench {      if (dut.transform_fifo.stored_count > maximum_transform_fifo)
        maximum_transform_fifo = dut.transform_fifo.stored_count;} {      // The removed transform FIFO is not modeled as an existing buffer.
      // The RTL has exactly source/product/egress 512-word owned banks.}]
    set bench [bank_replace_once $bench {        maximum_transform_fifo > dut.transform_fifo.FIFO_DEPTH ||
} {}]
    set bench [string map {maximum_transform_fifo removed_transform_fifo transform_fifo_max removed_transform_fifo} $bench]
    set bench [bank_replace_once $bench {    $display("IQ_TO_SCORE_XFFT_LONGRUN_PASS} {    if (cap_forward_words != BLOCK_COUNT * 512 || cap_product_words != BLOCK_COUNT * 512 ||
        cap_inverse_words != BLOCK_COUNT * 512)
      report_and_fail("independent_frame_counter_totals");
    $display("BANK_IQ_CAPACITY_METADATA_PASS blocks=%0d forward=%0d product=%0d inverse=%0d admission_interval_fast_min=%0d admission_interval_fast_max=%0d capture_next_epoch_words=%0d three_epoch_overlap_words=%0d",
      BLOCK_COUNT, cap_forward_words, cap_product_words, cap_inverse_words,
      cap_min_interval, cap_max_interval, cap_overlap_capture, cap_three_epoch_overlap);
    if (BLOCK_COUNT == 64)
      $display("BANK_IQ_CAPACITY_COMPLETE blocks=64 samples=28673 scores=28608");
    else
      $display("BANK_IQ_CAPACITY_COMPLETE blocks=4096 samples=1830977 scores=1830912");
    $display("IQ_TO_SCORE_XFFT_LONGRUN_PASS}]
  }
  return $bench
}
