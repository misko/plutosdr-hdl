# Source-frozen actual vendor FFT launch. Preparation is a separate offline step.
if {$argc != 2} { error "expected PREPARED_OUTPUT ABSOLUTE_PYTHON" }
set output_dir [file normalize [lindex $argv 0]]
set python [file normalize [lindex $argv 1]]
set source_dir [file dirname [file normalize [info script]]]
if {$source_dir ne [file join $output_dir frozen_sources]} { error "launch only the frozen runner" }
if {![file executable $python]} { error "explicit repository Python required" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set project_dir [file join $output_dir project]
if {[file exists $project_dir] || [file exists [file join $output_dir launch_started.txt]]} {
  error "refusing actual launch restart or overwrite"
}
# Uses the frozen standalone helper: no mutable repository/package import.
set python_command [list env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH $python -B \
  [file join $source_dir bank_arithmetic_actual.py]]
exec {*}$python_command verify $output_dir > [file join $output_dir preflight.json]
source [file join $source_dir profile.tcl]
if {$R != 1 || [list $B $O] ni {{0 0} {1 1}} || $fast_mhz ni {175 200}} { error "undeclared matrix" }
set source_hashes_before [exec sha256sum {*}[lsort [glob [file join $source_dir *]]] [file join $output_dir manifest.json]]
set run_status [catch {
set channel [open [file join $output_dir launch_started.txt] {WRONLY CREAT EXCL}]
puts $channel "actual_fft=true R=$R B=$B O=$O frequency=$fast_mhz no_restart=true"; close $channel
set project_name fft_bank_arithmetic_actual
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
set wrapper_hash [lindex [exec sha256sum $wrapper] 0]
set channel [open [file join $output_dir generated_ip_before.txt] w]
puts $channel [exec sha256sum $wrapper]; close $channel
foreach name $compiled_names { add_files -fileset sim_1 -norecurse [file join $source_dir $name] }
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir $name] }
set_property include_dirs [list $source_dir] [get_filesets sim_1]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_bank_arithmetic_actual [get_filesets sim_1]
set_property generic [list FAST_MHZ=$fast_mhz R=$R B=$B O=$O] [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property xsim.simulate.custom_tcl [file join $source_dir simulate_bank_arithmetic_diagnostics.tcl] [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
if {[lindex [exec sha256sum $wrapper] 0] ne $wrapper_hash} { error "generated FFT wrapper changed during run" }
set channel [open [file join $output_dir generated_ip_after.txt] w]
puts $channel [exec sha256sum $wrapper]; close $channel
set result_json [exec {*}$python_command results $output_dir]
close_project
} run_result run_options]
# Always independently verify after the run body, including project/IP/launch,
# result parsing and close errors. Do not let either error hide the other.
set after_status [catch {
  set source_hashes_after [exec sha256sum {*}[lsort [glob [file join $source_dir *]]] [file join $output_dir manifest.json]]
  if {$source_hashes_before ne $source_hashes_after} { error "after-run frozen inventory/source/manifest changed" }
  exec {*}$python_command verify $output_dir > [file join $output_dir postflight.json]
} after_result after_options]
set channel [open [file join $output_dir run_outcome.txt] w]
puts $channel "run_status=$run_status\nrun_result=$run_result\nrun_options=$run_options"
puts $channel "after_status=$after_status\nafter_result=$after_result\nafter_options=$after_options"
close $channel
if {$run_status} { return -options $run_options $run_result }
if {$after_status} { return -options $after_options $after_result }
set channel [open [file join $output_dir results.json] {WRONLY CREAT EXCL}]
puts $channel $result_json; close $channel
puts "BANK_ARITHMETIC_ACTUAL_CORE_VERIFIED_NO_SCORER_RTL_PHYSICAL_OR_RF_CLAIM"
