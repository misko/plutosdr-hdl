# Additive fixed30-upper ideal175 cases, selected ONLY by a reviewed bundle.
# healthy343: native132 success; late447: expected native-command rejection.
# No default/rate/runtime/old447 helper edits. Separate actual authorization.
# Usage: NEW_RUN FROZEN_CASE_BUNDLE PYTHON_EXECUTABLE
if {$argc != 3} { error "expected NEW_RUN FROZEN_CASE_BUNDLE PYTHON_EXECUTABLE; no alternate rate/geometry/clock" }
if {[version -short] ne "2022.2"} { error "requires Vivado2022.2" }
set output_dir [file normalize [lindex $argv 0]]
set prepared [file normalize [lindex $argv 1]]
set python [file normalize [lindex $argv 2]]
proc case_python {python args} {
  return [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH $python -B {*}$args]
}
if {[file exists $output_dir]} { error "refusing to overwrite simulation evidence" }
if {![file executable $python]} { error "explicit executable Python required" }
set verifier [file join $prepared source_snapshot tools prepare_starlink_high_rate_cases.py]
puts [case_python $python $verifier verify $prepared]
set own_name hdl/library/starlink_pss_acquisition/simulate_high_rate_bank_native_cases.tcl
set channel [open [info script] rb]; set live_entry [read $channel]; close $channel
set channel [open [file join $prepared source_snapshot $own_name] rb]; set frozen_entry [read $channel]; close $channel
if {$live_entry ne $frozen_entry} { error "runner differs from frozen reviewed source" }
file mkdir $output_dir
file copy $prepared [file join $output_dir inputs]
set inputs [file join $output_dir inputs]
set source_root [file join $inputs base source_snapshot]
set acq [file join $source_root hdl library starlink_pss_acquisition]
set vectors [file join $inputs base vectors]
set generated [file join $inputs generated]
set case_tb [file join $inputs source_snapshot hdl library starlink_pss_acquisition tb]
set verifier [file join $inputs source_snapshot tools prepare_starlink_high_rate_cases.py]
set channel [open [file join $output_dir prelaunch_receipt.txt] w]
puts $channel [case_python $python $verifier verify $inputs]
puts $channel "scope=frozen_context_specific30upper_bank175_native132_PIL1_static_known_center"
puts $channel "original=8205 prime=2 continuation=4096 preroll_raw=1549 preroll_canonical=768 pilot=512"
puts $channel "runtime_and_original447_bundle_unchanged=true actual_physical_radio_DMA_IIO_causal=false"
close $channel
set run_code [catch {
set_param general.maxThreads 2
source [file join $acq create_shared_realtime_xfft_ip.tcl]
set project_name high_rate_bank_native_case
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper_path
# Runtime closure comes ONLY from the byte-identical accepted447 base bundle.
foreach directory [glob -type d [file join $source_root hdl library *]] {
  foreach path [glob -nocomplain [file join $directory *.v]] { add_files -norecurse $path }
}
set bench tb_starlink_high_rate30_case
add_files -fileset sim_1 -norecurse [file join $generated ${bench}.sv]
set_property include_dirs [list $generated $case_tb [file join $acq tb]] [get_filesets sim_1]
foreach path [glob [file join $vectors *.mem]] { add_files -fileset sim_1 -norecurse $path }
foreach name {pilot_mixer_q16.mem pilot_halfband2_q17.mem pilot_fir3_q17.mem} {
  add_files -fileset sim_1 -norecurse [file join $acq $name]
}
add_files -fileset sim_1 -norecurse [file join $acq tb upper_edge_pss30_x2_ddc_kernel_q17.mem]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel [exec sha256sum $wrapper_path]; close $channel
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
foreach name {native_all_raw_tuples.json pilot_expected.ci16} {
  file copy [file join $vectors $name] [file join $simulation_dir $name]
}
set result [case_python $python $verifier result $inputs --simulation $simulation_dir]
close_project
} run_error run_options]
# Preserve the original failure while still verifying sources after it.
set integrity_code [catch {case_python $python $verifier verify $inputs} integrity_result]
set channel [open [file join $output_dir after_integrity.txt] w]
puts $channel "integrity_exit=$integrity_code"; puts $channel $integrity_result; close $channel
set channel [open [file join $output_dir run_status.txt] w]
puts $channel "run_tcl_exit=$run_code integrity_exit=$integrity_code"; puts $channel $run_error; close $channel
if {$run_code} {
  catch {close_project}
  return -options $run_options $run_error
}
if {$integrity_code} { error "post-run frozen source verification failed: $integrity_result" }
set channel [open [file join $output_dir terminal_receipt.json] w]
puts $channel $result; close $channel
puts "HIGH_RATE30_CASE_SIMULATION_VERIFIED context_specific_outcome=1 actual_bank175=1 pilot512=1 static_not_RF=1"
