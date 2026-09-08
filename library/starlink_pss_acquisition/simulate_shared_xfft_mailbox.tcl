# Actual two-clock transform service with frozen vectors; no receiver claims.
if {$argc < 2 || $argc > 3} { error "expected OUTPUT VECTOR_DIRECTORY ?MAIN_JOBS?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set main_jobs [expr {$argc == 3 ? [lindex $argv 2] : 6}]
if {$main_jobs ni {6 64}} { error "bounded replay supports 6 or 64 main jobs" }
if {[file exists $output_dir]} { error "refusing to overwrite replay evidence" }
set project_name shared_xfft_mailbox
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
foreach name {starlink_pss_block_mailbox starlink_pss_xfft_block_adapter starlink_pss_shared_xfft_service} {
  add_files -norecurse [file join $script_dir ${name}.v]
}
add_files -fileset sim_1 -norecurse [file join $script_dir tb tb_starlink_pss_shared_xfft_service.sv]
foreach name {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents} {
  if {![file isfile [file join $vector_dir ${name}.mem]]} { error "missing vector $name" }
  add_files -fileset sim_1 -norecurse [file join $vector_dir ${name}.mem]
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_shared_xfft_service [get_filesets sim_1]
set_property generic "MAIN_JOBS=$main_jobs" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
puts "SHARED_XFFT_MAILBOX_SIMULATION_COMPLETE REQUIRE_BENCH_PASS RECEIVER_UNQUALIFIED"
