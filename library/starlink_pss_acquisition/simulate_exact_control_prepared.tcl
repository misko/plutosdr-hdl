# Future actual-core execution entry. OFFLINE preparation does not source this.
# Requires separate authorization; no synthesis/place/route or production use.
# BEGIN EXACT_CONTROL_RECEIPTS
proc exact_verify_receipts {log registered distributed scratch extras} {
  set lines [regexp -all -inline -line {^EXACT_CONTROL_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} { error "expected exactly one candidate terminal" }
  set pattern {^EXACT_CONTROL_ACTUAL_PASS registered=([01]) distributed=([01]) scratch=([01]) extra=([01]) checks=([0-9]+) active=([0-9]+) consumed=([0-9]+) private_differences=([0-9]+) final_fault_edges=([0-9]+) owned_stalls=([0-9]+) reset_owned_edges=([0-9]+) independent_actual_core=1$}
  if {![regexp $pattern [lindex $lines 0] unused r d s e checks active consumed differences final_faults stalls resets]} {
    error "malformed candidate settings/count receipt"
  }
  if {$r != $registered || $d != $distributed || $s != $scratch || $e != $extras} {
    error "candidate receipt does not match explicit run settings"
  }
  if {$checks <= 0 || $active <= 0 || $consumed <= 0} {
    error "candidate active/public/identity coverage missing"
  }
  set extra_lines [regexp -all -inline -line {^EXACT_CONTROL_EXTRA_EPOCHS_PASS[^\n]*$} $log]
  if {$extras} {
    # Candidate and independently driven reference each execute/assert their
    # own four extra epochs before printing this exact receipt. The candidate
    # cannot finish until reference_done; neither bench shares these counters.
    if {$final_faults < 2 || $stalls < 3 || [llength $extra_lines] != 2} {
      error "extra epoch active evidence or independent receipt missing"
    }
    foreach line $extra_lines {
      if {$line ne "EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=2 healthy_recoveries=4"} {
        error "extra epoch counts differ from frozen expectations"
      }
    }
  } elseif {[llength $extra_lines] != 0} {
    error "extra epochs ran without explicit selection"
  }
  return "EXACT_CONTROL_RECEIPTS_VERIFIED"
}
# END EXACT_CONTROL_RECEIPTS
if {$argc != 1} { error "expected unique PREPARED_OUTPUT directory" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set output_dir [file normalize [lindex $argv 0]]
set source_dir [file join $output_dir frozen_sources]
set project_dir [file join $output_dir project]
if {[file exists $project_dir]} { error "refusing to overwrite/retry actual evidence" }
set old_directory [pwd]
cd $output_dir
exec sha256sum -c SHA256SUMS --quiet
source settings.tcl
cd $old_directory
if {[llength $exact_generics] != 6} { error "unexpected option inventory" }
foreach key {REGISTERED_SCHEDULING DISTRIBUTED_FAST_FAULT PRIVATE_NEXT_START_SCRATCH EXACT_EXTRA_EPOCHS} {
  set found [lsearch -all -inline -glob $exact_generics ${key}=*]
  if {[llength $found] != 1 || [lindex $found 0] ni [list ${key}=0 ${key}=1]} {
    error "invalid explicit option $key"
  }
}
if {[lsearch -exact $exact_generics FAST_MHZ=175] < 0 ||
    [lsearch -exact $exact_generics QUICK_MUTATION=0] < 0} { error "clock/stimulus gate changed" }
set registered [expr {[lsearch -exact $exact_generics REGISTERED_SCHEDULING=1] >= 0}]
set distributed [expr {[lsearch -exact $exact_generics DISTRIBUTED_FAST_FAULT=1] >= 0}]
set scratch [expr {[lsearch -exact $exact_generics PRIVATE_NEXT_START_SCRATCH=1] >= 0}]
set extras [expr {[lsearch -exact $exact_generics EXACT_EXTRA_EPOCHS=1] >= 0}]
set project_name exact_control_actual
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
add_files -fileset sim_1 -norecurse [glob [file join $source_dir *.v] [file join $source_dir *.sv]]
add_files -fileset sim_1 -norecurse [glob [file join $source_dir *.mem]]
set_property include_dirs [list $source_dir] [get_filesets sim_1]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_fft_bank_owned_slice [get_filesets sim_1]
set_property generic $exact_generics [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
set logfile [file join $simulation_dir simulate.log]
set channel [open $logfile r]; set log [read $channel]; close $channel
if {[regexp -nocase {fatal:|error:} $log]} { error "actual shadow failed; retain $logfile" }
puts [exact_verify_receipts $log $registered $distributed $scratch $extras]
foreach marker {FFT_BANK_OWNED_SLICE_PASS HELD_PHASE_INPUT_PASS HELD_PREFLIGHT_ACTUAL_PASS
    BALANCED_IDENTITY_ACTUAL_PASS PAYLOAD_BUBBLES_ACTUAL_PASS FORWARD_RETIREMENT_ACTUAL_PASS
    EXACT_CONTROL_ACTUAL_PASS} {
  if {[string first $marker $log] < 0} { error "missing terminal marker $marker" }
}
if {$registered} {
  foreach marker {REGISTERED_SCHEDULING_PASS PREFLIGHT_REASON_SPLIT_PASS} {
    if {[string first $marker $log] < 0} { error "missing registered marker $marker" }
  }
}
if {[lsearch -exact $exact_generics EXACT_EXTRA_EPOCHS=1] >= 0 &&
    [string first EXACT_CONTROL_EXTRA_EPOCHS_PASS $log] < 0} { error "extra epochs did not finish" }
set candidate_csv [file join $simulation_dir fft_bank_owned_trace.csv]
set reference_csv [file join $simulation_dir exact_control_reference_trace.csv]
exec cmp $candidate_csv $reference_csv
# Original complete stimulus CSVs, not a retuned expected trace. Extra epochs
# have separate files and cannot dilute either full original CSV comparison.
set expected_csv [expr {$registered ?
  "25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122" :
  "b0d60e80101b34ff163b85ef7547814e0403561b315f975eb38a98817b7eb84d"}]
if {[lindex [exec sha256sum $candidate_csv] 0] ne $expected_csv} { error "original full CSV changed" }
cd $output_dir
exec sha256sum -c SHA256SUMS --quiet
cd $old_directory
close_project
puts "EXACT_CONTROL_ACTUAL_FROZEN_PAIR_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM"
