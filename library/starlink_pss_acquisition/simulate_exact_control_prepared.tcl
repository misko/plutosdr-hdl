# Future actual-core execution entry. OFFLINE preparation does not source this.
# Requires separate authorization; no synthesis/place/route or production use.
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
