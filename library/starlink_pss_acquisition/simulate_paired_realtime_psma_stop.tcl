proc pss_verify_paired_outputs {simulation_dir expected_binary {map_bins 447} {bank_owned 0} {fast_mhz 200}} {
  if {$map_bins ni {447 343}} { error "invalid paired verifier geometry" }
  if {$bank_owned ni {0 1} || $fast_mhz ni {175 200} || (!$bank_owned && $fast_mhz != 200)} {
    error "invalid paired verifier engine/clock"
  }
  set tile_scores [expr {$map_bins * 2}]
  set log_path [file join $simulation_dir simulate.log]
  if {![file isfile $log_path]} { error "missing paired simulation log" }
  set channel [open $log_path r]
  set log_text [read $channel]
  close $channel
  if {[regexp -nocase -line {^[ \t]*PAIRED_REALTIME_PSMA_STOP_FAIL([ \t]|$)} $log_text]} {
    error "paired simulation contains FAIL evidence"
  }
  require_realtime_probe_pass $log_path [list \
    {PAIRED_PREROLL_PASS real_shell=1 real_cdc=1 real_canonical=1 samples=768 empty_ticket=1 explicit_configuration_pause=1} \
    "PAIRED_MAP_PILOT_PASS exact_scores=$tile_scores exact_map_words=$map_bins exact_pilot_words=512 exact_bytes=2048 shared_support_envelope=959 pilot_after_stop=1 healthy_snapshot=1" \
    {PAIRED_LATE_FAULT_PASS actual_invalid_release=1 failed_joint_health=1 terminal_coordinates_retained=1 pilot_bytes_preserved=1} \
    "PAIRED_REALTIME_PSMA_STOP_PASS source_words=4096 pilot_words=512 map_words=$map_bins NO_ADC_DMA_IIO_FINE_PRODUCTION_OR_PHYSICAL_CLAIM" \
  ] PAIRED_PILOT_WORD 512
  if {$map_bins == 343} {
    require_realtime_probe_pass $log_path [list \
      {PAIRED_RESIDUE_PASS selected_scores=686 map_words=343 residue=239 post_fence_tail_not_map_admission=1} \
    ] PAIRED_STOP_TAIL 1
  }
  if {$bank_owned} {
    require_realtime_probe_pass $log_path [list \
      "PAIRED_BANK_PASS map_bins=$map_bins selected_scores=$tile_scores exact_pilot_bytes=2048 fast_mhz=$fast_mhz TEST_ONLY_SELECTOR_NOT_RECEIVER"] PAIRED_BANK_PASS 1
  }
  set actual_binary [file join $simulation_dir paired_pilot_actual.ci16]
  if {![file isfile $actual_binary] || [file size $actual_binary] != 2048} {
    error "actual pilot AXIS sink byte count mismatch"
  }
  set channel [open $actual_binary rb]
  set actual_pilot_bytes [read $channel]
  close $channel
  set channel [open $expected_binary rb]
  set expected_pilot_bytes [read $channel]
  close $channel
  if {$actual_pilot_bytes ne $expected_pilot_bytes} { error "actual pilot AXIS bytes differ from independent oracle" }
}
# Actual digital CI16 shell/CDC -> canonical tap -> real FFT/PSMA and PIL1.
# Default447x2 or explicit343x2 residue239 map; explicit configuration pause; no DMA/IIO/ADC/RF claim.
# Usage: vivado -mode batch -source simulate_paired_realtime_psma_stop.tcl \
#        -tclargs NEW_OUTPUT EXISTING_SCORE_VECTORS EXISTING_PILOT_ORACLE ?343x2|447x2?
if {$argc ni {3 4 6}} { error "expected NEW_OUTPUT EXISTING_SCORE_VECTORS EXISTING_PILOT_ORACLE ?343x2|447x2? ?BANK_OWNED=1 FAST_MHZ=175|200?" }
set selected_geometry 447x2
set use_bank_owned_xfft 0
set fast_mhz 200
if {$argc >= 4} { set selected_geometry [lindex $argv 3] }
if {$argc == 6} {
  set use_bank_owned_xfft [lindex $argv 4]
  set fast_mhz [lindex $argv 5]
  if {$use_bank_owned_xfft ne "1" || $fast_mhz ni {175 200}} {
    error "paired bank probe requires BANK_OWNED=1 FAST_MHZ=175|200"
  }
}
if {$selected_geometry ni {447x2 343x2}} { error "paired geometry must be literal447x2 or343x2" }
set map_bins [expr {$selected_geometry eq "343x2" ? 343 : 447}]
set tile_scores [expr {$map_bins * 2}]
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set pilot_dir [file normalize [lindex $argv 2]]
if {[file exists $output_dir]} { error "refusing to overwrite paired evidence" }
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
  starlink_pss_acquisition_health starlink_pss_iq_to_phase_map starlink_pss_sample_cdc
  starlink_pilot_ddc starlink_pilot_halfband2 starlink_pilot_fir3
}
set bench_name tb_starlink_pss_paired_realtime_psma_stop
if {$use_bank_owned_xfft} {
  lappend rtl_names starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
}
set input_paths [list [info script] [file join $script_dir create_shared_realtime_xfft_ip.tcl] \
  [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir tb ${bench_name}.sv] \
  [file join $script_dir tb upper_edge_pss_kernel_q17.mem] \
  [file normalize [file join $script_dir ../../../tests/test_starlink_paired_realtime_psma_stop_policy.py]] \
  [file normalize [file join $script_dir ../../../tests/starlink_oracle/pilot_ddc.py]]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach relative {../axi_starlink_pss_acquisition/axi_starlink_pss_acquisition.v \
                  ../axi_starlink_pss_acquisition/axi_starlink_pss_phase_map_sync.v \
                  ../axi_starlink_pss_phase_map/starlink_pss_axi_lite.v \
                  ../axi_starlink_pilot_capture/axi_starlink_pilot_capture.v} {
  lappend input_paths [file normalize [file join $script_dir $relative]]
}
set filter_names {pilot_mixer_q16.mem pilot_halfband2_q17.mem pilot_fir3_q17.mem}
foreach name $filter_names { lappend input_paths [file join $script_dir $name] }
set vector_geometry {samples_ci16 1406 8 forward_q17 1536 9 product_q17 1536 9
  inverse_q17 1536 9 forward_exponents 3 2 inverse_exponents 3 2 scores_u8 1341 2}
set pilot_geometry {paired_source_ci16 4096 8 paired_pilot_ci16 512 8
  paired_pilot_newest 512 16 paired_metadata 10 16}
set vector_names {}
foreach {directory geometry} [list $vector_dir $vector_geometry $pilot_dir $pilot_geometry] {
  foreach {name rows width} $geometry {
    set path [file join $directory ${name}.mem]
    if {![file isfile $path]} { error "missing vector $name" }
    if {[file size $path] > $rows * ($width + 2)} { error "oversize vector $name" }
    set channel [open $path r]
    set data [split [string trim [read $channel]] "\n"]
    close $channel
    if {[llength $data] != $rows} { error "unexpected vector row count $name" }
    foreach row $data {
      if {![regexp "^\[0-9a-fA-F\]{$width}$" [string trim $row]]} {
        error "malformed vector row $name"
      }
    }
    set vector_data($name) $data
    lappend input_paths $path
    lappend vector_names ${name}.mem
  }
}
# The same source actually feeds both branches: never compare scores from a
# different sample file. Original seven score goldens are preserved unchanged.
for {set n 0} {$n < 1406} {incr n} {
  if {![string equal -nocase [lindex $vector_data(samples_ci16) $n] \
      [lindex $vector_data(paired_source_ci16) [expr {$n + 768}]]]} {
    error "paired source vector differs from original numeric fixture"
  }
}
set first [expr {(1 << 33) - 16}]
set first_newest [expr {(($first - 768 + 538 + 5) / 6) * 6}]
set last_newest [expr {$first_newest + 6 * 511}]
set unsupported [expr {($first_newest - (($first - 768 + 5) / 6) * 6) / 6}]
set expected_metadata [list $first [expr {$first - 768}] $first_newest $last_newest \
  $unsupported [expr {$unsupported + 512}] [expr {$first_newest - 269}] \
  [expr {$last_newest - 269}] [expr {$first_newest - 538}] [expr {$last_newest + 1}]]
for {set n 0} {$n < 10} {incr n} {
  scan [lindex $vector_data(paired_metadata) $n] %llx actual
  if {$actual != [lindex $expected_metadata $n]} { error "incorrect paired metadata vector" }
}
for {set n 0} {$n < 512} {incr n} {
  scan [lindex $vector_data(paired_pilot_newest) $n] %llx actual
  if {$actual != $first_newest + 6 * $n} { error "incorrect paired index vector" }
}
set expected_binary [file join $pilot_dir paired_pilot_expected.ci16]
set oracle_manifest [file join $pilot_dir paired_oracle.json]
if {![file isfile $expected_binary] || [file size $expected_binary] != 2048 ||
    ![file isfile $oracle_manifest] || [file size $oracle_manifest] > 16384} {
  error "missing or invalid bounded pilot oracle vector receipt"
}
lappend input_paths $expected_binary $oracle_manifest
set channel [open $oracle_manifest r]
set oracle_text [read $channel]
close $channel
set oracle_geometry [regexp -all -inline {"selected_map_geometry": "([0-9]+x[0-9]+)"} $oracle_text]
if {[llength $oracle_geometry] == 0 && $selected_geometry eq "447x2"} {
  # Preserve replay of original default-only pilot manifests.
  set oracle_geometry [list legacy_default 447x2]
}
if {[llength $oracle_geometry] != 2 || [lindex $oracle_geometry 1] ne $selected_geometry} {
  error "pilot oracle vector receipt geometry differs from selected geometry"
}
foreach path $input_paths {
  if {![file isfile $path]} { error "missing paired simulation source $path" }
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_digital_shell_cdc_canonical_real_fft_psma_and_pilot"
puts $channel "processing_clock_MHz=100 fast_clock_MHz=$fast_mhz fft_phase_ns=1.3 sample_clock_ns=10 sample_phase_ns=2.1 source_msps=15 use_bank_owned_xfft=$use_bank_owned_xfft"
puts $channel "bank_selector_is_test_only_child_defparam_not_AXI_receiver_profile=true"
puts $channel "test_only_geometry=$selected_geometry outer_index_bits=15 score_fixture_unchanged=true"
puts $channel "selected_score_prefix=$tile_scores fft_stride=447 tile_end_residue=[expr {$tile_scores % 447}] production_tile_end_residue=[expr {1280000 % 447}]"
puts $channel "residue_scope=matching_block_residue_is_not_production_geometry_or_duration_qualification"
puts $channel "preroll_samples=768 source_words=4096 pilot_words=512 pilot_axis_bytes=2048"
puts $channel "empty_stop_then_pilot_preroll_configuration_pause_then_enable_without_flush=true"
puts $channel "startup_prerequisite=two_real_contiguous_inactive_bootstrap_beats_then_canonical_gap_zero_before_ARM"
puts $channel "pilot_expected_is_independent_integer_oracle_not_RTL=true"
puts $channel "ADC_format_DMA_IIO_fine_production_geometry_duration_physical_RF_qualified=false"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "working_tree_status=[exec git -C $script_dir status --short]"
puts $channel "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $source_dir *]]]]"
close $channel
set project_name paired_realtime_psma_stop
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper_path
foreach name [concat $rtl_names {axi_starlink_pss_acquisition axi_starlink_pss_phase_map_sync \
    starlink_pss_axi_lite axi_starlink_pilot_capture}] {
  add_files -norecurse [file join $source_dir ${name}.v]
}
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]
foreach name [concat $vector_names $filter_names {upper_edge_pss_kernel_q17.mem}] {
  add_files -fileset sim_1 -norecurse [file join $source_dir $name]
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
set_property generic "MAP_BINS=$map_bins USE_BANK_OWNED_XFFT=$use_bank_owned_xfft FAST_MHZ=$fast_mhz" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel "generated_wrapper_sha256=[exec sha256sum $wrapper_path]"
close $channel
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
pss_verify_paired_outputs $simulation_dir [file join $source_dir paired_pilot_expected.ci16] $map_bins $use_bank_owned_xfft $fast_mhz
close_project
puts "PAIRED_REALTIME_PSMA_STOP_SIMULATION_VERIFIED exact_axis_bytes=2048 reduced_geometry_only=1"
puts "PAIRED_GEOMETRY_VERIFIED map_bins=$map_bins map_frames=2 selected_scores=$tile_scores residue=[expr {$tile_scores % 447}]"
