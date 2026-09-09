# Complete coarse pipeline with the actual 100/200/100 MHz transform island.
# Numerical and canonical 15 MS/s capacity evidence, not receiver fit/deployment.
# Usage: ... -tclargs OUTPUT numeric VECTORS ?USE_REALTIME_XFFT=0|1?
#     or OUTPUT capacity ?64|4096? ?nominal|bursty-stalled? ?USE_REALTIME_XFFT=0|1?
if {$argc < 2 || $argc > 5} { error "expected OUTPUT numeric VECTORS ?USE_REALTIME_XFFT? or OUTPUT capacity ?64|4096? ?nominal|bursty-stalled? ?USE_REALTIME_XFFT?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set mode [lindex $argv 1]
if {$mode ni {capacity numeric} || ($mode eq "numeric" && $argc ni {3 4})} {
  error "numeric mode requires vectors; capacity does not"
}
set capacity_blocks 64
if {$mode eq "capacity" && $argc >= 3} { set capacity_blocks [lindex $argv 2] }
if {$capacity_blocks ni {64 4096}} { error "capacity supports 64 or 4096 blocks" }
set capacity_profile nominal
if {$mode eq "capacity" && $argc >= 4} { set capacity_profile [lindex $argv 3] }
if {$capacity_profile ni {nominal bursty-stalled}} { error "unknown capacity profile" }
set use_realtime_xfft 0
if {$mode eq "numeric" && $argc == 4} { set use_realtime_xfft [lindex $argv 3] }
if {$mode eq "capacity" && $argc == 5} { set use_realtime_xfft [lindex $argv 4] }
if {$use_realtime_xfft ni {0 1}} { error "USE_REALTIME_XFFT must be 0 or 1" }
if {[file exists $output_dir]} { error "refusing to overwrite pipeline evidence" }
set bench_name tb_starlink_pss_iq_to_score_xfft
if {$mode eq "capacity"} { append bench_name _longrun }
set rtl_names {
  starlink_pss_overlap_scheduler starlink_pss_energy_cache starlink_pss_xfft_block_adapter
  starlink_pss_kernel_rom starlink_pss_forward_kernel_join starlink_pss_spectrum_product
  starlink_pss_transform_fifo starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo
  starlink_pss_energy_join starlink_pss_score_prepare starlink_pss_score_divider
  starlink_pss_score_divider_radix4 starlink_pss_score_lanes starlink_pss_candidate_score_path
  starlink_pss_block_mailbox starlink_pss_shared_xfft_service starlink_pss_iq_to_score_shared
  starlink_pss_shared_realtime_xfft_service starlink_pss_realtime_input_guard
  starlink_pss_realtime_result_guard
}
set input_paths [list [info script] [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir tb ${bench_name}.sv] [file join $script_dir tb upper_edge_pss_kernel_q17.mem]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
set vector_names {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents scores_u8}
if {$mode eq "numeric"} {
  set vector_dir [file normalize [lindex $argv 2]]
  foreach name $vector_names {
    set path [file join $vector_dir ${name}.mem]
    if {![file isfile $path]} { error "missing vector $name" }
    lappend input_paths $path
  }
}
foreach path $input_paths {
  if {![file isfile $path]} { error "missing pipeline source $path" }
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $source_dir ${bench_name}.sv] r]
set bench [read $channel]
close $channel
regsub {\mstarlink_pss_iq_to_score\M} $bench starlink_pss_iq_to_score_shared bench
if {$use_realtime_xfft} {
  set fault_path dut.realtime_transform.transform_service.input_guard.protocol_fault
} else {
  set fault_path dut.nonrealtime_transform.transform_service.adapter.protocol_fault
}
set bench [string map [list \
  {always #5 clk = ~clk;} {always #5 clk = ~clk;
  reg fft_clk = 0;
  reg fft_resetn = 1;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end} \
  {starlink_pss_iq_to_score_shared } "starlink_pss_iq_to_score_shared #(.USE_REALTIME_XFFT($use_realtime_xfft)) " \
  {dut (} {dut (
    .fft_clk(fft_clk), .fft_resetn(fft_resetn),} \
  {dut.forward_adapter.protocol_fault} $fault_path \
] $bench]
if {$mode eq "capacity"} {
  set bench [string map [list \
    {        $finish;} {        $fatal(1, "shared pipeline fault");} \
    {localparam integer BLOCK_COUNT = 64;} "localparam integer BLOCK_COUNT = $capacity_blocks;" \
    {cycle_count > 1000000} {cycle_count > BLOCK_COUNT * 4000 + 100000} \
  ] $bench]
  set marker {    $display("IQ_TO_SCORE_XFFT_LONGRUN_PASS}
  set terminal_marker "SHARED_PIPELINE_CAPACITY_CERTIFIED blocks=$capacity_blocks profile=$capacity_profile realtime=$use_realtime_xfft COUNTS_ORDER_BACKLOG_NOT_NUMERICS"
  if {[string first $marker $bench] < 0} { error "missing capacity verdict anchor" }
  set bench [string map [list $marker "    \$display(\"$terminal_marker\");\n$marker"] $bench]
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
  set terminal_marker "SHARED_PIPELINE_NUMERIC_CERTIFIED scores=1341 realtime=$use_realtime_xfft"
  set bench [string map [list $marker "    \$display(\"$terminal_marker\");\n$marker"] $bench]
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
set module_name starlink_pss_fft512_bfp18
set throttle nonrealtime
if {$use_realtime_xfft} {
  set module_name starlink_pss_fft512_bfp18_rt_candidate
  set throttle realtime
}
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name $module_name
set_property -dict [list \
  CONFIG.channels {1} CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {200} CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {40} CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} CONFIG.input_width {18} CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} CONFIG.xk_index {true} CONFIG.throttle_scheme $throttle \
  CONFIG.output_ordering {natural_order} CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips $module_name]
generate_target all [get_ips $module_name]
set channel [open [file join $project_dir ${project_name}.gen sources_1 ip \
  $module_name synth ${module_name}.vhd] r]
set wrapper [read $channel]
close $channel
set required_generics {
  C_S_AXIS_CONFIG_TDATA_WIDTH 8 C_S_AXIS_DATA_TDATA_WIDTH 48
  C_M_AXIS_DATA_TDATA_WIDTH 48 C_M_AXIS_DATA_TUSER_WIDTH 24 C_M_AXIS_STATUS_TDATA_WIDTH 8
  C_CHANNELS 1 C_NFFT_MAX 9 C_ARCH 1 C_HAS_NFFT 0
  C_USE_FLT_PT 0 C_INPUT_WIDTH 18 C_TWIDDLE_WIDTH 16 C_OUTPUT_WIDTH 18
  C_HAS_SCALING 1 C_HAS_BFP 1 C_HAS_ROUNDING 1 C_HAS_ACLKEN 0 C_HAS_ARESETN 1
  C_HAS_OVFLO 0 C_HAS_NATURAL_INPUT 1 C_HAS_NATURAL_OUTPUT 1 C_HAS_CYCLIC_PREFIX 0
  C_HAS_XK_INDEX 1 C_DATA_MEM_TYPE 1 C_TWIDDLE_MEM_TYPE 1 C_BRAM_STAGES 0
  C_REORDER_MEM_TYPE 1 C_USE_HYBRID_RAM 0 C_OPTIMIZE_GOAL 0 C_CMPY_TYPE 1 C_BFLY_TYPE 1
}
lappend required_generics C_THROTTLE_SCHEME [expr {$use_realtime_xfft ? 0 : 1}]
foreach {name value} $required_generics {
  if {![regexp "${name} => ${value}(,|\n)" $wrapper]} { error "unexpected generated generic $name" }
}
foreach name $rtl_names { add_files -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse $bench_path
add_files -fileset sim_1 -norecurse [file join $source_dir upper_edge_pss_kernel_q17.mem]
if {$mode eq "numeric"} {
  foreach name $vector_names {
    add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem]
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
set log_path [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
if {$mode eq "capacity"} {
  require_realtime_probe_pass $log_path [list $terminal_marker] IQ_TO_SCORE_XFFT_LONGRUN_PROGRESS $capacity_blocks
} else {
  require_realtime_probe_pass $log_path [list $terminal_marker \
    {SHARED_PIPELINE_FFT_RESET_PASS sticky_quarantine=1 explicit_recovery=1}] IQ_TO_SCORE_XFFT_PASS 1
}
close_project
puts "IQ_TO_SCORE_SHARED_SIMULATION_VERIFIED mode=$mode realtime=$use_realtime_xfft slow_mhz=100 fft_mhz=200 source_msps=15 RECEIVER_UNQUALIFIED"
