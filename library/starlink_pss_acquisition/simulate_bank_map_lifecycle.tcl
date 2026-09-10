# Actual bank-owned FFT -> reduced phase map -> native synchronous PSMA.
# Usage: vivado -mode batch -source simulate_bank_map_lifecycle.tcl \
#        -tclargs NEW_OUTPUT EXISTING_NUMERIC_VECTOR_DIRECTORY ?FAST_MHZ=175|200?
if {$argc ni {2 3}} { error "expected NEW_OUTPUT EXISTING_NUMERIC_VECTOR_DIRECTORY ?FAST_MHZ=175|200?" }
set use_bank_owned_xfft 1
set fast_mhz 175
if {$argc == 3} {
  set fast_mhz [lindex $argv 2]
  if {$fast_mhz ni {175 200}} { error "bank lifecycle probe requires FAST_MHZ=175|200" }
}
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite lifecycle evidence" }
set rtl_names {
  starlink_pss_overlap_scheduler starlink_pss_energy_cache starlink_pss_xfft_block_adapter
  starlink_pss_kernel_rom starlink_pss_forward_kernel_join starlink_pss_spectrum_product
  starlink_pss_transform_fifo starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo
  starlink_pss_energy_join starlink_pss_score_prepare starlink_pss_score_divider
  starlink_pss_score_divider_radix4 starlink_pss_score_lanes starlink_pss_candidate_score_path
  starlink_pss_iq_to_score starlink_pss_block_mailbox starlink_pss_shared_xfft_service
  starlink_pss_iq_to_score_shared starlink_pss_shared_realtime_xfft_service
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_score_phase_tagger starlink_pss_phase_map_bank starlink_pss_phase_map
  starlink_pss_acquisition_health starlink_pss_iq_to_phase_map
}
set bench_name tb_starlink_pss_bank_map_lifecycle
if {$use_bank_owned_xfft} {
  lappend rtl_names starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
}
set input_paths [list [info script] [file join $script_dir create_shared_realtime_xfft_ip.tcl] \
  [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir tb ${bench_name}.sv] \
  [file join $script_dir tb upper_edge_pss_kernel_q17.mem]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach relative {../axi_starlink_pss_acquisition/axi_starlink_pss_phase_map_sync.v \
                  ../axi_starlink_pss_phase_map/starlink_pss_axi_lite.v} {
  lappend input_paths [file normalize [file join $script_dir $relative]]
}
# Retain all seven original fixtures. Every visible score, including valid
# faulted prefixes, is checked; retained intermediates are not re-compared.
set vector_geometry {samples_ci16 1406 8 forward_q17 1536 9 product_q17 1536 9
  inverse_q17 1536 9 forward_exponents 3 2 inverse_exponents 3 2 scores_u8 1341 2}
set vector_names {}
foreach {name rows width} $vector_geometry {
  set path [file join $vector_dir ${name}.mem]
  if {![file isfile $path]} { error "missing vector $name" }
  set channel [open $path r]
  set data [split [string trim [read $channel]] "\n"]
  close $channel
  if {[llength $data] != $rows} { error "unexpected vector row count $name" }
  foreach row $data {
    if {![regexp "^\[0-9a-fA-F\]{$width}$" [string trim $row]]} {
      error "malformed vector row $name"
    }
  }
  lappend input_paths $path
  lappend vector_names ${name}.mem
}
foreach path $input_paths {
  if {![file isfile $path]} { error "missing lifecycle simulation source $path" }
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_bank_owned_fft_psma_map_lifecycle_reduced_447x2"
puts $channel "slow_clock_MHz=100 fast_clock_MHz=$fast_mhz fft_phase_ns=1.3 source_msps=15 use_bank_owned_xfft=$use_bank_owned_xfft"
puts $channel "fixture_samples=1406 fixture_scores=1341 compared_scores=every_visible_prefix complete_map_words=447"
puts $channel "retained_intermediates_not_compared_by_this_bench=true"
puts $channel "source_bounded_three_blocks_no_canonical_tap_pilot_dma_or_native_fine=true"
puts $channel "local_faults_model_current_domain_visibility_separate_from_remote_raw_event=true"
puts $channel "complete_healthy_publications_retained_with_failed_terminal_health=true"
puts $channel "host=[exec uname -a]"
puts $channel "production_geometry_duration_physical_timing_RF_qualified=false"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "working_tree_status=[exec git -C $script_dir status --short]"
puts $channel "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $source_dir *]]]]"
close $channel

set_param general.maxThreads 2
set project_name bank_map_lifecycle
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper_path
foreach name [concat $rtl_names {axi_starlink_pss_phase_map_sync starlink_pss_axi_lite}] {
  add_files -norecurse [file join $source_dir ${name}.v]
}
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]
foreach name [concat $vector_names {upper_edge_pss_kernel_q17.mem}] {
  add_files -fileset sim_1 -norecurse [file join $source_dir $name]
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
set_property generic "FAST_MHZ=$fast_mhz" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel "generated_wrapper_sha256=[exec sha256sum $wrapper_path]"
close $channel
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log_path [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $log_path r]; set transcript [read $channel]; close $channel
if {[regexp -line {^BANK_MAP_LIFECYCLE_(FAIL|FAULT) } $transcript]} {
  error "lifecycle bench reported a failed assertion; inspect $log_path"
}
require_realtime_probe_pass $log_path [list \
  {BANK_MAP_LIFECYCLE_CASE healthy_reenable=1 external_reset_between=0 tickets=2 exact_scores=1788 exact_map_words=894} \
  {BANK_MAP_LIFECYCLE_CASE post_fault_epoch_reset_replay=1 exact_scores=894 exact_map_words=447} \
  "BANK_MAP_LIFECYCLE_PASS cases=8 actual_core=1 source_mhz=15 slow_mhz=100 fft_mhz=$fast_mhz REDUCED_GEOMETRY_NO_PAIRED_FINE_CAPACITY_OR_RF_CLAIM" \
] BANK_MAP_LIFECYCLE_CASE 8
# Variable numeric prefixes/timestamps still require each distinct case once.
foreach case_pattern {
  {^BANK_MAP_LIFECYCLE_CASE retained_map_partial_fault=1 }
  {^BANK_MAP_LIFECYCLE_CASE independent_fft_reset=1 }
  {^BANK_MAP_LIFECYCLE_CASE local_boundary=0 completed=0 }
  {^BANK_MAP_LIFECYCLE_CASE local_boundary=1 completed=1 }
  {^BANK_MAP_LIFECYCLE_CASE local_boundary=2 completed=1 }
  {^BANK_MAP_LIFECYCLE_CASE remote_boundary=1 }
} {
  if {[regexp -all -line $case_pattern $transcript] != 1} {
    error "lifecycle case identity missing or duplicated"
  }
}
close_project
puts "BANK_MAP_LIFECYCLE_SIMULATION_VERIFIED reduced_geometry_only=1"

