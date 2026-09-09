# Vivado 2022.2 behavioral gate for the shared real XFFT through the phase map.
# Usage: vivado -mode batch -source simulate_iq_to_phase_map_xfft.tcl \
#        -tclargs OUTPUT VECTOR_DIRECTORY ?USE_SHARED_XFFT=0|1? ?USE_REALTIME_XFFT=0|1?

if {$argc < 2 || $argc > 4} {
  error "expected output and vector directories, optional USE_SHARED_XFFT=0|1 USE_REALTIME_XFFT=0|1"
}
set use_shared_xfft 0
set use_realtime_xfft 0
if {$argc >= 3} { set use_shared_xfft [lindex $argv 2] }
if {$argc == 4} { set use_realtime_xfft [lindex $argv 3] }
if {$use_shared_xfft ni {0 1}} { error "USE_SHARED_XFFT must be 0 or 1" }
if {$use_realtime_xfft ni {0 1}} { error "USE_REALTIME_XFFT must be 0 or 1" }
if {$use_realtime_xfft && !$use_shared_xfft} {
  error "realtime phase-map simulation requires explicit shared composition"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set project_dir [file join $output_dir project]
set project_name starlink_pss_iq_to_phase_map_xfft_sim
if {$use_shared_xfft && [file exists $output_dir]} { error "refusing to overwrite shared map evidence" }

set vector_names {
  samples_ci16.mem
  forward_q17.mem
  product_q17.mem
  inverse_q17.mem
  forward_exponents.mem
  inverse_exponents.mem
  scores_u8.mem
}
foreach required_file $vector_names {
  if {![file isfile [file join $vector_dir $required_file]]} {
    error "missing replay vector $required_file"
  }
}

set rtl_sources {
  starlink_pss_overlap_scheduler.v starlink_pss_energy_cache.v
  starlink_pss_xfft_block_adapter.v starlink_pss_kernel_rom.v
  starlink_pss_forward_kernel_join.v starlink_pss_spectrum_product.v
  starlink_pss_transform_fifo.v starlink_pss_ifft_qualifier.v
  starlink_pss_raw_result_fifo.v starlink_pss_energy_join.v
  starlink_pss_score_prepare.v starlink_pss_score_divider.v
  starlink_pss_score_divider_radix4.v starlink_pss_score_lanes.v
  starlink_pss_candidate_score_path.v starlink_pss_iq_to_score.v
  starlink_pss_iq_to_score_shared.v starlink_pss_shared_xfft_service.v
  starlink_pss_block_mailbox.v starlink_pss_score_phase_tagger.v
  starlink_pss_phase_map_bank.v starlink_pss_phase_map.v
  starlink_pss_acquisition_health.v starlink_pss_iq_to_phase_map.v
}
set bench_path [file join $script_dir tb tb_starlink_pss_iq_to_phase_map_xfft.sv]
set kernel_path [file join $script_dir tb upper_edge_pss_kernel_q17.mem]
set source_dir $script_dir
if {$use_realtime_xfft} {
  lappend rtl_sources starlink_pss_shared_realtime_xfft_service.v \
    starlink_pss_realtime_input_guard.v starlink_pss_realtime_result_guard.v
}
if {$use_shared_xfft} {
  set helpers {verify_realtime_probe_result.tcl}
  if {$use_realtime_xfft} { lappend helpers create_shared_realtime_xfft_ip.tcl }
  foreach name [concat $rtl_sources $helpers] {
    if {![file isfile [file join $script_dir $name]]} { error "missing shared phase-map source $name" }
  }
  foreach path [list $bench_path $kernel_path] {
    if {![file isfile $path]} { error "missing realtime phase-map fixture $path" }
  }
}
file mkdir $output_dir
if {$use_shared_xfft} {
  set source_dir [file join $output_dir frozen_sources]
  file mkdir $source_dir
  file copy [info script] [file join $source_dir probe_runner.tcl]
  foreach name [concat $rtl_sources $helpers] {
    file copy [file join $script_dir $name] $source_dir
  }
  foreach path [list $bench_path $kernel_path] { file copy $path $source_dir }
  foreach name $vector_names { file copy [file join $vector_dir $name] $source_dir }
  set bench_path [file join $source_dir [file tail $bench_path]]
  set kernel_path [file join $source_dir [file tail $kernel_path]]
  set vector_dir $source_dir
  if {$use_realtime_xfft} { source [file join $source_dir create_shared_realtime_xfft_ip.tcl] }
  source [file join $source_dir verify_realtime_probe_result.tcl]
}

create_project -force $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

if {$use_realtime_xfft} {
  set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
    starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
  pss_create_shared_realtime_xfft_ip $wrapper_path
} else {
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name starlink_pss_fft512_bfp18
set_property -dict [list \
  CONFIG.channels {1} \
  CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {100} \
  CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {20} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {18} \
  CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} \
  CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} \
  CONFIG.xk_index {true} \
  CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} \
  CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips starlink_pss_fft512_bfp18]
generate_target all [get_ips starlink_pss_fft512_bfp18]

set wrappers [glob -nocomplain \
  [file join $project_dir ${project_name}.gen sources_1 ip \
    starlink_pss_fft512_bfp18 synth starlink_pss_fft512_bfp18.vhd]]
if {[llength $wrappers] != 1} {
  error "could not locate generated XFFT synthesis wrapper"
}
set wrapper_file [open [lindex $wrappers 0] r]
set wrapper_path [lindex $wrappers 0]
set wrapper_text [read $wrapper_file]
close $wrapper_file
if {![regexp {C_ARCH => 1,} $wrapper_text]} {
  error "20 MS/s automatic selection did not choose radix-4 burst C_ARCH=1"
}
}
foreach source_name $rtl_sources {
  add_files -norecurse [file join $source_dir $source_name]
}

add_files -fileset sim_1 -norecurse $bench_path
add_files -fileset sim_1 -norecurse $kernel_path
foreach vector_file $vector_names {
  add_files -fileset sim_1 -norecurse [file join $vector_dir $vector_file]
}
set_property file_type {Memory Initialization Files} \
  [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_iq_to_phase_map_xfft [get_filesets sim_1]
set_property generic "USE_SHARED_XFFT=$use_shared_xfft USE_REALTIME_XFFT=$use_realtime_xfft" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
if {$use_shared_xfft} {
  set channel [open [file join $output_dir scope.txt] w]
  puts $channel "scope=shared_phase_map_reduced_geometry_3x447_not_receiver"
  puts $channel "actual_clocks_ns=100MHz:10,200MHz:5 source_msps=15"
  puts $channel "use_shared_xfft=1 use_realtime_xfft=$use_realtime_xfft psma_health_service_bit=14"
  puts $channel "production_geometry_capacity_physical_timing_CDC_qualified=false"
  puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
  puts $channel "source_hashes=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper_path]"
  close $channel
}

launch_simulation -simset sim_1 -mode behavioral
close_sim
if {$use_shared_xfft} {
  set terminal_markers [list \
    {SHARED_PHASE_MAP_FAULT_PASS partial_tile_aborted=1 no_partial_publication=1 service_health_bit=14 detector_episodes=1}]
  if {$use_realtime_xfft} {
    lappend terminal_markers \
      {REALTIME_PHASE_MAP_PASS exact_scores=1341 exact_map_reads=447 reduced_geometry_only=1 CAPACITY_AND_PHYSICAL_UNQUALIFIED} \
      {REALTIME_PHASE_MAP_FAULT_PASS partial_tile_aborted=1 service_health_bit=14}
  }
  require_realtime_probe_pass [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log] \
    $terminal_markers \
    IQ_TO_PHASE_MAP_XFFT_PASS 1
}
close_project

puts "STARLINK_IQ_TO_PHASE_MAP_XFFT_SIMULATION_COMPLETE"
