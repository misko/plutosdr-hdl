# Idealized throughput/numerical experiment, NOT a receiver implementation.
# Replay the historical one-XFFT composition with current arithmetic leaves at
# 100/200 MHz and a true 15 MS/s input. The ENTIRE simulated composition uses
# this clock, so passing does not qualify an FFT-only CDC island, full design
# timing, pilot DMA, or hardware. Never substitute this for the dual-core top.
# Usage: vivado ... -tclargs OUTPUT capacity|numeric MHZ ?VECTOR_DIRECTORY?
if {$argc < 3 || $argc > 4} { error "expected OUTPUT capacity|numeric MHZ ?VECTORS?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set mode [lindex $argv 1]
set clock_mhz [lindex $argv 2]
if {$mode ni {capacity numeric} || $clock_mhz ni {100 200}} { error "unsupported probe" }
if {($mode eq "numeric") != ($argc == 4)} { error "numeric mode requires vectors only" }
if {[file exists $output_dir]} { error "refusing to overwrite existing probe evidence" }
file mkdir $output_dir
set historical_commit [exec git -C $script_dir rev-parse 592a736f^{commit}]
set composition [exec git -C $script_dir show \
  ${historical_commit}:library/starlink_pss_acquisition/starlink_pss_iq_to_score.v]
if {[regexp -all {starlink_pss_fft512_bfp18[ \t]+shared_xfft[ \t]+\(} $composition] != 1} {
  error "historical composition must instantiate exactly one shared generated FFT"
}
set generated_top [file join $output_dir historical_shared_iq_to_score.v]
set channel [open $generated_top w]
puts $channel "// GENERATED DIAGNOSTIC ONLY: historical header throughput claim is NOT evidence."
puts $channel $composition
close $channel

set bench_name tb_starlink_pss_iq_to_score_xfft
if {$mode eq "capacity"} { append bench_name _longrun }
set channel [open [file join $script_dir tb ${bench_name}.sv] r]
set bench [read $channel]
close $channel
foreach {old replacement} [list \
  {always #5 clk = ~clk;} "always #[expr {500.0 / $clock_mhz}] clk = ~clk;" \
  {cadence_phase >= 100} "cadence_phase >= $clock_mhz" \
  {cadence_phase - 100} "cadence_phase - $clock_mhz"] {
  if {[string first $old $bench] < 0} { error "missing expected bench anchor: $old" }
  set bench [string map [list $old $replacement] $bench]
}
# The old capacity diagnostic uses finish for failures. Make this experiment
# fail at the simulator boundary as well as requiring an explicit PASS marker.
if {$mode eq "capacity"} {
  set bench [string map [list {        $finish;} {        $fatal(1, "shared service fault");}] $bench]
}
set timing_monitor {
  integer shared_probe_start = -1;
  integer shared_probe_jobs = 0;
  integer shared_probe_max_service_cycles = 0;
  always @(posedge clk) begin
    if (resetn && enable) begin
      if (dut.scheduler_fft_valid && dut.scheduler_fft_ready &&
          dut.scheduler_fft_position == 0)
        shared_probe_start = cycle_count;
      if (dut.intermediate_release && shared_probe_start >= 0) begin
        shared_probe_jobs = shared_probe_jobs + 1;
        if (cycle_count - shared_probe_start > shared_probe_max_service_cycles)
          shared_probe_max_service_cycles = cycle_count - shared_probe_start;
        if (shared_probe_jobs <= 4 || shared_probe_jobs == BLOCK_COUNT)
          $display("SHARED_XFFT_SERVICE jobs=%0d forward_through_inverse_cycles=%0d maximum=%0d",
                   shared_probe_jobs, cycle_count - shared_probe_start,
                   shared_probe_max_service_cycles);
        shared_probe_start = -1;
      end
    end
  end
}
set bench [string map [list endmodule "$timing_monitor\nendmodule"] $bench]
set generated_bench [file join $output_dir ${bench_name}.sv]
set channel [open $generated_bench w]
puts $channel $bench
close $channel
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=idealized_whole_composition_fast_clock_NOT_FFT_CDC_or_receiver"
puts $channel "historical_composition_commit=$historical_commit"
puts $channel "current_hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "clock_mhz=$clock_mhz"
puts $channel "canonical_source_hz=15000000"
puts $channel "source_sha256=[exec sha256sum $generated_top $generated_bench]"
puts $channel "whole_receiver_qualified=false"
close $channel

set project_name shared_xfft_service
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name starlink_pss_fft512_bfp18
set_property -dict [list \
  CONFIG.channels {1} CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency $clock_mhz CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput [expr {$clock_mhz / 5}] \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} CONFIG.input_width {18} \
  CONFIG.phase_factor_width {16} CONFIG.scaling_options {block_floating_point} \
  CONFIG.rounding_modes {convergent_rounding} CONFIG.aresetn {true} \
  CONFIG.xk_index {true} CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} CONFIG.butterfly_type {use_xtremedsp_slices} \
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
  starlink_pss_xfft_intermediate_buffer starlink_pss_ifft_qualifier
  starlink_pss_raw_result_fifo starlink_pss_energy_join starlink_pss_score_prepare
  starlink_pss_score_divider starlink_pss_score_divider_radix4 starlink_pss_score_lanes
  starlink_pss_candidate_score_path
} { add_files -norecurse [file join $script_dir ${name}.v] }
add_files -norecurse $generated_top
add_files -fileset sim_1 -norecurse $generated_bench
add_files -fileset sim_1 -norecurse [file join $script_dir tb upper_edge_pss_kernel_q17.mem]
if {$mode eq "numeric"} {
  set vector_dir [file normalize [lindex $argv 3]]
  foreach name {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents scores_u8} {
    if {![file isfile [file join $vector_dir ${name}.mem]]} { error "missing vector $name" }
    add_files -fileset sim_1 -norecurse [file join $vector_dir ${name}.mem]
  }
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
puts "SHARED_XFFT_SERVICE_SIMULATION_COMPLETE REQUIRE_BENCH_PASS mode=$mode clock_mhz=$clock_mhz RECEIVER_UNQUALIFIED"
