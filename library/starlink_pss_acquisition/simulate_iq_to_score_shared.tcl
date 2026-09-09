# Complete coarse pipeline with the actual 100/200/100 MHz transform island.
# Numerical and canonical 15 MS/s capacity evidence, not receiver fit/deployment.
# Usage: ... -tclargs OUTPUT numeric VECTORS | OUTPUT capacity ?64|4096? ?nominal|bursty-stalled?
if {$argc < 2 || $argc > 4} { error "expected OUTPUT numeric VECTORS or OUTPUT capacity ?64|4096? ?nominal|bursty-stalled?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set mode [lindex $argv 1]
if {$mode ni {capacity numeric} || ($mode eq "numeric" && $argc != 3)} {
  error "numeric mode requires vectors; capacity does not"
}
set capacity_blocks 64
if {$mode eq "capacity" && $argc >= 3} { set capacity_blocks [lindex $argv 2] }
if {$capacity_blocks ni {64 4096}} { error "capacity supports 64 or 4096 blocks" }
set capacity_profile nominal
if {$mode eq "capacity" && $argc == 4} { set capacity_profile [lindex $argv 3] }
if {$capacity_profile ni {nominal bursty-stalled}} { error "unknown capacity profile" }
if {[file exists $output_dir]} { error "refusing to overwrite pipeline evidence" }
file mkdir $output_dir
set bench_name tb_starlink_pss_iq_to_score_xfft
if {$mode eq "capacity"} { append bench_name _longrun }
set channel [open [file join $script_dir tb ${bench_name}.sv] r]
set bench [read $channel]
close $channel
regsub {\mstarlink_pss_iq_to_score\M} $bench starlink_pss_iq_to_score_shared bench
set bench [string map [list \
  {always #5 clk = ~clk;} {always #5 clk = ~clk;
  reg fft_clk = 0;
  reg fft_resetn = 1;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end} \
  {dut (} {dut (
    .fft_clk(fft_clk), .fft_resetn(fft_resetn),} \
  {dut.forward_adapter.protocol_fault} {dut.transform_service.adapter.protocol_fault} \
] $bench]
if {$mode eq "capacity"} {
  set bench [string map [list \
    {        $finish;} {        $fatal(1, "shared pipeline fault");} \
    {localparam integer BLOCK_COUNT = 64;} "localparam integer BLOCK_COUNT = $capacity_blocks;" \
    {cycle_count > 1000000} {cycle_count > BLOCK_COUNT * 4000 + 100000} \
  ] $bench]
} else {
  # The global latch persists while leaf faults are cleared by the common
  # quarantine reset. Allow the explicit cross-clock reset/fault synchronizers;
  # do not require a reset leaf's transient diagnostic to remain asserted.
  set bench [string map [list \
    {repeat (2) @(posedge clk);} {repeat (12) @(posedge clk);} \
    {if (!forward_fft_fault || !detector_fault || score_valid)} \
    {if (!detector_fault || score_valid)} \
  ] $bench]
  set reset_test {
    expected_fault_window = 1;
    fft_resetn = 0;
    repeat (12) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("independent FFT reset did not quarantine acquisition");
    fft_resetn = 1;
    repeat (12) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("FFT reset quarantine cleared without explicit recovery");
    enable = 0;
    repeat (12) @(negedge clk);
    enable = 1;
    repeat (12) @(negedge clk);
    expected_fault_window = 0;
    if (detector_fault || score_valid)
      fail("FFT reset recovery failed");
    $display("SHARED_PIPELINE_FFT_RESET_PASS sticky_quarantine=1 explicit_recovery=1");
  }
  set marker {    $display("IQ_TO_SCORE_XFFT_PASS}
  if {[string first $marker $bench] < 0} { error "missing positive numeric verdict anchor" }
  set bench [string map [list $marker "$reset_test\n$marker"] $bench]
}
set bench_path [file join $output_dir ${bench_name}.sv]
set channel [open $bench_path w]
puts $channel "// GENERATED: actual slow 100 / FFT 200 MHz composition; nominal ADC 15 MS/s."
puts $channel $bench
close $channel

set project_name iq_to_score_shared
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name starlink_pss_fft512_bfp18
set_property -dict [list \
  CONFIG.channels {1} CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {200} CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {40} CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} CONFIG.input_width {18} CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} CONFIG.xk_index {true} CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips starlink_pss_fft512_bfp18]
generate_target all [get_ips starlink_pss_fft512_bfp18]
set channel [open [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18 synth starlink_pss_fft512_bfp18.vhd] r]
set wrapper [read $channel]
close $channel
if {![regexp {C_ARCH => 1,} $wrapper]} { error "must retain radix-4 burst arithmetic" }
foreach name {
  starlink_pss_overlap_scheduler starlink_pss_energy_cache starlink_pss_xfft_block_adapter
  starlink_pss_kernel_rom starlink_pss_forward_kernel_join starlink_pss_spectrum_product
  starlink_pss_transform_fifo starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo
  starlink_pss_energy_join starlink_pss_score_prepare starlink_pss_score_divider
  starlink_pss_score_divider_radix4 starlink_pss_score_lanes starlink_pss_candidate_score_path
  starlink_pss_block_mailbox starlink_pss_shared_xfft_service starlink_pss_iq_to_score_shared
} { add_files -norecurse [file join $script_dir ${name}.v] }
add_files -fileset sim_1 -norecurse $bench_path
add_files -fileset sim_1 -norecurse [file join $script_dir tb upper_edge_pss_kernel_q17.mem]
if {$mode eq "numeric"} {
  set vector_dir [file normalize [lindex $argv 2]]
  foreach name {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents scores_u8} {
    if {![file isfile [file join $vector_dir ${name}.mem]]} { error "missing vector $name" }
    add_files -fileset sim_1 -norecurse [file join $vector_dir ${name}.mem]
  }
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
if {$mode eq "capacity" && $capacity_profile eq "bursty-stalled"} {
  set_property generic {SOURCE_BURST_MODE=1 SCORE_STALL_MODE=1} [get_filesets sim_1]
}
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
puts "IQ_TO_SCORE_SHARED_SIMULATION_COMPLETE REQUIRE_BENCH_PASS mode=$mode slow_mhz=100 fft_mhz=200 source_msps=15 RECEIVER_UNQUALIFIED"
