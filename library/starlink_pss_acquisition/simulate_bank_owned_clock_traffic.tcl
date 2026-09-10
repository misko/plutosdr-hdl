# Actual generated MMCM + unchanged complete bank-owned coarse numerical traffic.
# This additive runner never modifies existing benches, RTL, vectors or profiles.
if {$argc != 2} { error "expected NEW_OUTPUT EXISTING_NUMERIC_VECTORS" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set out [file normalize [lindex $argv 0]]
set vectors [file normalize [lindex $argv 1]]
if {[file exists $out]} { error "refusing to overwrite clock traffic evidence" }
set rtl_names {starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_block_mailbox starlink_pss_forward_kernel_join starlink_pss_kernel_rom
  starlink_pss_spectrum_product starlink_pss_overlap_scheduler starlink_pss_energy_cache
  starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo starlink_pss_energy_join
  starlink_pss_score_prepare starlink_pss_score_divider starlink_pss_score_divider_radix4
  starlink_pss_score_lanes starlink_pss_candidate_score_path}
set paths [list [info script]]
foreach name $rtl_names { lappend paths [file join $script_dir ${name}.v] }
foreach name {create_shared_realtime_xfft_ip.tcl create_bank_owned_clock_ip.tcl verify_realtime_probe_result.tcl} {
  lappend paths [file join $script_dir $name]
}
set bench tb_starlink_pss_bank_clock_traffic
foreach name [list ${bench}.sv upper_edge_pss_kernel_q17.mem] {
  lappend paths [file join $script_dir tb $name]
}
lappend paths [file normalize [file join $script_dir ../../../tests/test_starlink_bank_clock_traffic_policy.py]]
set vector_geometry {samples_ci16 1406 8 forward_q17 1536 9 product_q17 1536 9
  inverse_q17 1536 9 forward_exponents 3 2 inverse_exponents 3 2 scores_u8 1341 2}
set vector_names {}
foreach {name rows width} $vector_geometry {
  set path [file join $vectors ${name}.mem]
  if {![file isfile $path]} { error "missing vector $name" }
  if {[file size $path] > $rows * ($width + 2)} { error "oversize vector $name" }
  set channel [open $path r]
  set data [split [string trim [read $channel]] "\n"]
  close $channel
  if {[llength $data] != $rows} { error "unexpected vector row count $name" }
  foreach row $data {
    if {![regexp "^\[0-9a-fA-F\]{$width}$" [string trim $row]]} { error "malformed vector row $name" }
  }
  lappend paths $path
  lappend vector_names ${name}.mem
}
foreach path $paths { if {![file isfile $path]} { error "missing clock traffic source $path" } }
set frozen [file join $out frozen_sources]
file mkdir $frozen
foreach path $paths { file copy $path $frozen }
foreach helper {create_shared_realtime_xfft_ip create_bank_owned_clock_ip verify_realtime_probe_result} {
  source [file join $frozen ${helper}.tcl]
}
set receipt [open [file join $out scope.txt] w]
puts $receipt "scope=actual_generated_MMCM_complete_bank_coarse_numeric_active_resets"
puts $receipt "input_clock_MHz=100 nominal_output_MHz=175 source_msps=15 average_period_tolerance_ns=0.005"
puts $receipt "fixture_samples=1406 fixture_scores=1341 all_visible_score_and_transform_prefixes_compared=true"
puts $receipt "healthy_exact_epochs=5 mmcm_active_resets=3 manual_fft_only_reset=1"
puts $receipt "prompt_closure_observation_ns=0.002 measured_from_observed_fft_epoch_fall_not_raw_MMCM_reset=true"
puts $receipt "outer_fault_bound_ns=10.0021 sticky_while_enable_held_through_relock=true explicit_recovery=enable_cycle"
puts $receipt "not_input_clock_loss_detection_not_physical_timing_not_receiver_pilot_fine_RF=true"
puts $receipt "host=[exec uname -a]"
puts $receipt "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $receipt "working_tree_status=[exec git -C $script_dir status --short]"
puts $receipt "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]]]"
close $receipt
set_param general.maxThreads 2
set project_name bank_clock_traffic
set project_dir [file join $out project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set gen [file join $project_dir ${project_name}.gen sources_1 ip]
set clock_files [pss_create_bank_owned_clock_ip [file join $gen starlink_bank_clock175_candidate]]
set fft_wrapper [file join $gen starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $fft_wrapper
foreach name $rtl_names { add_files -norecurse [file join $frozen ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $frozen ${bench}.sv]
foreach name [concat $vector_names {upper_edge_pss_kernel_q17.mem}] {
  add_files -fileset sim_1 -norecurse [file join $frozen $name]
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set receipt [open [file join $out generated_ip.txt] w]
puts $receipt "generated_ip_hashes=[exec sha256sum {*}$clock_files $fft_wrapper]"
close $receipt
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $log r]; set transcript [read $channel]; close $channel
if {[regexp -nocase -line {^[ \t]*BANK_CLOCK_TRAFFIC_(FAIL|FAULT)([ \t]|$)} $transcript]} {
  error "clock traffic assertion failed"
}
set markers [list {BANK_CLOCK_TRAFFIC_PASS exact_epochs=5 exact_full_scores=6705 reset_cases=4 mmcm_active_resets=3 manual_fft_only_resets=1 measured_edges=5120 ACTUAL_IP_NO_INPUT_CLOCK_LOSS_RECEIVER_PHYSICAL_OR_RF_CLAIM}]
require_realtime_probe_pass $log $markers BANK_CLOCK_TRAFFIC_EXACT 5
require_realtime_probe_pass $log $markers BANK_CLOCK_TRAFFIC_RESET 4
require_realtime_probe_pass $log $markers BANK_CLOCK_TRAFFIC_TOTAL 1
foreach epoch {1 3 5 7 9} {
  if {[regexp -all -line "^BANK_CLOCK_TRAFFIC_EXACT epoch=$epoch scores=1341 forward=1536 product=1536 inverse=1536 " $transcript] != 1} {
    error "exact healthy replay epoch missing, duplicated or wrong counts"
  }
}
foreach kind {0 1 2 3} {
  if {[regexp -all -line "^BANK_CLOCK_TRAFFIC_RESET kind=$kind " $transcript] != 1} {
    error "active reset kind missing or duplicated"
  }
}
close_project
puts "BANK_CLOCK_TRAFFIC_ACTUAL_IP_VERIFIED_NO_PHYSICAL_CLAIM"
