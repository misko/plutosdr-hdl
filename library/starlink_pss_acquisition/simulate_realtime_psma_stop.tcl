# Actual shared realtime FFT -> reduced phase map -> native synchronous PSMA.
# Usage: vivado -mode batch -source simulate_realtime_psma_stop.tcl \
#        -tclargs NEW_OUTPUT EXISTING_NUMERIC_VECTOR_DIRECTORY
if {$argc != 2} { error "expected NEW_OUTPUT EXISTING_NUMERIC_VECTOR_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite stop evidence" }
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
set bench_name tb_starlink_pss_realtime_psma_stop
set input_paths [list [info script] [file join $script_dir create_shared_realtime_xfft_ip.tcl] \
  [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir tb ${bench_name}.sv] \
  [file join $script_dir tb upper_edge_pss_kernel_q17.mem]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach relative {../axi_starlink_pss_acquisition/axi_starlink_pss_phase_map_sync.v \
                  ../axi_starlink_pss_phase_map/starlink_pss_axi_lite.v} {
  lappend input_paths [file normalize [file join $script_dir $relative]]
}
# All seven original fixtures are retained. This bench consumes the input and
# first 894 scores; it does not claim to compare all retained intermediates.
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
  if {![file isfile $path]} { error "missing stop simulation source $path" }
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_realtime_fft_psma_boundary_stop_reduced_447x2"
puts $channel "slow_clock_ns=10 fft_clock_ns=5 fft_phase_ns=1.3 source_msps=15"
puts $channel "fixture_samples=1406 fixture_scores=1341 compared_score_prefix=894 exact_map_words=447"
puts $channel "retained_intermediates_not_compared_by_this_bench=true"
puts $channel "source_continuation_is_stimulus_not_canonical_tap_or_pilot_dma=true"
puts $channel "production_geometry_duration_physical_timing_RF_qualified=false"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "working_tree_status=[exec git -C $script_dir status --short]"
puts $channel "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $source_dir *]]]]"
close $channel

set project_name realtime_psma_stop
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
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel "generated_wrapper_sha256=[exec sha256sum $wrapper_path]"
close $channel
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log_path [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
require_realtime_probe_pass $log_path [list \
  {REALTIME_PSMA_STOP_HEALTHY_PASS exact_scores=894 exact_map_words=447 actual_third_block_pending=1 source_continues=1 coarse_flush=0 tail_health_clean=1 reduced_geometry_only=1} \
  {REALTIME_PSMA_STOP_LATE_BRIDGE_PASS actual_invalid_release=1 stable_terminal_tuple=1 failed_receipt=1} \
  {REALTIME_PSMA_STOP_LIVE_FAULT_PASS pending_stop=1 vendor_event_in_live_epoch=1 partial_abort=1 no_partial_publication=1 service_health_bit=14} \
  {REALTIME_PSMA_STOP_PASS healthy_maps=1 exact_map_words=447 fault_cases=2 source_mhz=15 slow_mhz=100 fft_mhz=200 NO_PILOT_DMA_PRODUCTION_CAPACITY_OR_PHYSICAL_CLAIM} \
] REALTIME_PSMA_STOP_ACK 2
close_project
puts "REALTIME_PSMA_STOP_SIMULATION_VERIFIED reduced_geometry_only=1"
