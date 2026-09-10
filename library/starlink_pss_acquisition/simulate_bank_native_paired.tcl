# Actual-core, additive public-native-AXI + bank PSMA/PIL1 static-anchor smoke.
# Args: NEW_OUTPUT ORIGINAL_SCORE_VECTORS ORIGINAL_PILOT_ORACLE NATIVE_ORACLE 175|200 ?447|520?
# STARLINK_NATIVE_PYTHON must name an absolute Python with repo dependencies.
if {$argc ni {5 6}} { error "expected NEW_OUTPUT SCORE_VECTORS PILOT_ORACLE NATIVE_ORACLE FAST_MHZ ?447|520?" }
if {[lindex $argv 4] ni {175 200}} { error "native paired clock must be literal175 or200" }
set native_profile 447
if {$argc == 6} { set native_profile [lindex $argv 5] }
if {$native_profile ni {447 520}} { error "native anchor must be literal447 or520" }
set native_expected_lag [expr {$native_profile == 520 ? -17 : 0}]
# Resolve every caller-relative path before the independent Python subprocess
# changes cwd. Output and all three input roots keep the caller's coordinates.
for {set native_arg 0} {$native_arg < 4} {incr native_arg} {
  lset argv $native_arg [file normalize [lindex $argv $native_arg]]
}
set native_dir [file normalize [lindex $argv 3]]
set native_script_dir [file dirname [file normalize [info script]]]
set native_fw [file normalize [file join $native_script_dir ../../..]]
# Deterministic project-local import closure for python -m below. The package
# initializers import more than the four direct arithmetic modules. Preserve
# distinct encoded paths (not two colliding __init__.py basenames). This is a
# future-runner provenance addition, not a rewrite of completed v1 inventories.
set native_python_relatives {
  tests/__init__.py tests/starlink_oracle/__init__.py
  tests/starlink_oracle/acquisition.py tests/starlink_oracle/bank_native_paired.py
  tests/starlink_oracle/ddc.py tests/starlink_oracle/fixed.py
  tests/starlink_oracle/numerology.py tests/starlink_oracle/search.py
  tests/starlink_oracle/waveforms.py tests/starlink_oracle/xfft_bitacc.py
}
foreach relative $native_python_relatives {
  if {![file isfile [file join $native_fw $relative]]} {
    error "missing native Python runtime dependency: $relative"
  }
}
source [file join $native_script_dir prepare_bank_native_paired.tcl]
if {[file exists [lindex $argv 0]]} { error "refusing to overwrite native paired evidence" }
if {![info exists ::env(STARLINK_NATIVE_PYTHON)] ||
    [file pathtype $::env(STARLINK_NATIVE_PYTHON)] ne "absolute" ||
    ![file executable $::env(STARLINK_NATIVE_PYTHON)]} {
  error "native oracle needs absolute executable STARLINK_NATIVE_PYTHON"
}
set native_python $::env(STARLINK_NATIVE_PYTHON)
set native_cwd [pwd]
cd $native_fw
set native_failed [catch {
  exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH $native_python \
    -m tests.starlink_oracle.bank_native_paired [lindex $argv 2] $native_dir --verify --anchor $native_profile
} native_receipt]
cd $native_cwd
if {$native_failed} { error "independent native oracle rejected: $native_receipt" }
if {$native_receipt ne "BANK_NATIVE_ORACLE_VERIFIED source=4096 taps=66 packet_words=26 anchor=$native_profile winner_lag=$native_expected_lag"} {
  error "native oracle verification lacks exact receipt"
}
set argv [list [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] 447x2 1 [lindex $argv 4]]
set argc 6
set channel [open [file join $native_script_dir simulate_paired_realtime_psma_stop.tcl] r]
set native_runner [read $channel]; close $channel
set native_runner [native_replace_once $native_runner {set input_paths [list [info script]} {
set native_rtl_paths {}
foreach name {starlink_pss_async_fifo starlink_sat_add48 starlink_pss_candidate_scheduler
    starlink_pss_capture_bridge starlink_pss_sliding_correlator starlink_pss_tracking_core
    starlink_pss_exact_reducer starlink_pss_exact_track_reducer starlink_pss_result_store
    starlink_pss_reduced_tracking_core} {
  lappend native_rtl_paths [file normalize [file join $script_dir ../starlink_pss_raw_correlator ${name}.v]]
}
foreach relative {../common/ad_mem.v ../common/up_axi.v
    ../axi_starlink_pss_tracker/axi_starlink_pss_tracker.v
    ../axi_starlink_pss_tracker/starlink_pss_injection_mux.v} {
  lappend native_rtl_paths [file normalize [file join $script_dir $relative]]
}
set input_paths [list [info script] \
  [file join $script_dir simulate_paired_realtime_psma_stop.tcl] \
  [file join $script_dir prepare_bank_native_paired.tcl] \
  [file join $script_dir tb bank_native_paired_checks.svh] \
  [file join $native_fw tests test_starlink_bank_native_paired.py] \
  [file join $native_fw tests starlink_oracle bank_native_paired.py] \
  [file join $native_fw tests starlink_oracle fixed.py] \
  [file join $native_fw tests starlink_oracle numerology.py] \
  [file join $native_fw tests starlink_oracle waveforms.py]}]
set native_runner [native_replace_once $native_runner {foreach path $input_paths {
  if {![file isfile $path]} { error "missing paired simulation source $path" }
}} {
foreach path $native_rtl_paths { lappend input_paths $path }
foreach name {native_coefficients_q15.mem native_expected_packet.mem native_oracle.json} {
  lappend input_paths [file join $native_dir $name]
}
lappend vector_names native_coefficients_q15.mem native_expected_packet.mem
foreach path $input_paths {
  if {![file isfile $path]} { error "missing paired simulation source $path" }
}}]
set native_runner [native_replace_once $native_runner {foreach path $input_paths { file copy $path $source_dir }} {
foreach path $input_paths { file copy $path $source_dir }
set native_runtime_manifest {}
foreach relative $native_python_relatives {
  set encoded "python_runtime__[string map {/ __} $relative]"
  file copy [file join $native_fw $relative] [file join $source_dir $encoded]
  append native_runtime_manifest "$relative $encoded\n"
}
set channel [open [file join $source_dir python_runtime_inventory.txt] w]
puts -nonewline $channel $native_runtime_manifest
close $channel
set channel [open [file join $source_dir ${bench_name}.sv] r]
set native_bench [read $channel]; close $channel
set channel [open [file join $source_dir bank_native_paired_checks.svh] r]
set native_checks [read $channel]; close $channel
set bench_name tb_starlink_bank_native_paired
set channel [open [file join $source_dir ${bench_name}.sv] w]
puts -nonewline $channel [prepare_native_paired_bench $native_bench $native_checks]
close $channel}]
set native_runner [native_replace_once $native_runner {sample_clock_ns=10 sample_phase_ns=2.1} {sample_clock_MHz=15 sample_phase_ns=2.1}]
set native_runner [native_replace_once $native_runner {scope=actual_digital_shell_cdc_canonical_real_fft_psma_and_pilot} {scope=actual_original15_source_public_native_AXI_bank_PSMA_PIL1_static_anchor}]
set native_runner [native_replace_once $native_runner {ADC_format_DMA_IIO_fine_production_geometry_duration_physical_RF_qualified=false} {ADC_format_DMA_IIO_causal_fine_production_geometry_duration_physical_RF_qualified=false}]
set native_runner [native_replace_once $native_runner {test_only_geometry=$selected_geometry outer_index_bits=15 score_fixture_unchanged=true} {test_only_geometry=$selected_geometry outer_index_bits=15 score_fixture_unchanged=true native_anchor=$native_profile native_expected_lag=$native_expected_lag}]
set native_runner [native_replace_once $native_runner {FAST_MHZ=$fast_mhz" [get_filesets sim_1]} {FAST_MHZ=$fast_mhz NATIVE_OFFSET=$native_profile" [get_filesets sim_1]}]
set native_runner [native_replace_once $native_runner {set project_name paired_realtime_psma_stop} {
set native_frozen_names [lsort [glob [file join $source_dir *]]]
set native_frozen_hashes [exec sha256sum {*}$native_frozen_names]
set_param general.maxThreads 2
set project_name bank_native_paired}]
set native_runner [native_replace_once $native_runner {add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]} {
foreach path $native_rtl_paths { add_files -norecurse [file join $source_dir [file tail $path]] }
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]}]
set native_runner [native_replace_once $native_runner {close_project
puts "PAIRED_REALTIME_PSMA_STOP_SIMULATION_VERIFIED} {
native_verify_outputs $simulation_dir $source_dir $fast_mhz $native_profile
if {[lsort [glob [file join $source_dir *]]] ne $native_frozen_names ||
    [exec sha256sum {*}$native_frozen_names] ne $native_frozen_hashes} {
  error "native frozen source inventory/hash changed during execution"
}
close_project
puts "PAIRED_REALTIME_PSMA_STOP_SIMULATION_VERIFIED}]

proc native_verify_outputs {simulation_dir source_dir fast_mhz {anchor 447}} {
  if {$anchor ni {447 520} || $fast_mhz ni {175 200}} { error "invalid native receipt profile" }
  set log_path [file join $simulation_dir simulate.log]
  set channel [open $log_path r]; set log [read $channel]; close $channel
  # This exact historical successful fault test remains mandatory in the
  # original verifier. No prefix exemption may hide a later failing suffix.
  foreach line [split $log "\n"] {
    if {$line eq {PAIRED_LATE_FAULT_PASS actual_invalid_release=1 failed_joint_health=1 terminal_coordinates_retained=1 pilot_bytes_preserved=1}} { continue }
    if {[regexp -nocase {(^|[ \t:])([A-Z][A-Z0-9_]*_)?(FAIL|FAULT|FATAL|ERROR)([: \t_]|$)} $line]} {
      error "native paired log contains failure evidence: $line"
    }
  }
  require_realtime_probe_pass $log_path [list \
    {BANK_NATIVE_EXACT_PASS packets=1 public_reads=52 capture_words=130 taps=66 qualified_lags=61 retained_across_stop=1 injection=0 timestamp_equals_index=1} \
    "BANK_NATIVE_PAIRED_PASS source_msps=15 fast_mhz=$fast_mhz anchor=$anchor source_words=4096 scores=894 map_words=447 pilot_bytes=2048 STATIC_ANCHOR_NOT_CAUSAL_NO_RF_PHYSICAL"] BANK_NATIVE_PACKET_WORD 52
  set channel [open [file join $source_dir native_expected_packet.mem] r]
  set packet [split [string trim [read $channel]] "\n"]; close $channel
  set rows [regexp -all -inline -line {^BANK_NATIVE_PACKET_WORD pass=([01]) word=([0-9]+) data=([0-9a-f]{8})$} $log]
  if {[llength $rows] != 52 * 4} { error "native packet inventory malformed" }
  for {set n 0} {$n < 52} {incr n} {
    set row [lrange $rows [expr {$n * 4}] [expr {$n * 4 + 3}]]
    if {[lindex $row 1] != $n / 26 || [lindex $row 2] != $n % 26 ||
        [lindex $row 3] ne [lindex $packet [expr {$n % 26}]]} { error "native packet exact ordered inventory mismatch" }
  }
  if {[regexp -all -line {^BANK_NATIVE_ADMISSION } $log] != 1 ||
      ![regexp -line {^BANK_NATIVE_ADMISSION index=([0-9]+) capture_start=([0-9]+) lead=([0-9]+) deadline=([0-9]+)$} $log all index start lead deadline] ||
      $start != 8589934576 + $anchor - 32 || $deadline != 8589934704 || $index < 8589934592 ||
      $index > $deadline || $lead < 64 || $lead != $start - $index - 1} {
    error "native admission receipt does not attest exact safe source lead"
  }
  if {[regexp -all -line {^BANK_NATIVE_OVERLAP } $log] != 1 ||
      ![regexp -line {^BANK_NATIVE_OVERLAP capture_fft_fast_cycles=([0-9]+) compute_coarse_pilot_accepts=([0-9]+)$} $log all capture compute] ||
      $capture < 1 || $compute < 1} { error "native positive concurrency witness missing" }
  puts "BANK_NATIVE_PAIRED_SIMULATION_VERIFIED fast_mhz=$fast_mhz anchor=$anchor native_packets=1 native_public_words=52 pilot_bytes=2048 static_anchor_only=1"
}
eval $native_runner
