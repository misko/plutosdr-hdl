# Separately reviewed actual launch ONLY: NEW_RUN FROZEN_BUNDLE PYTHON BUNDLE_SHA.
# Fixed healthy60upper, ideal60/100/175 clocks, native264, PIL1,447x2. No MMCM.
if {$argc != 4} { error "expected NEW_RUN FROZEN_BUNDLE PYTHON BUNDLE_SHA; no alternate rate/geometry" }
if {[version -short] ne "2022.2"} { error "requires Vivado2022.2" }
proc paired60_no_symlink {path} {
  set cursor $path
  while {$cursor ne [file dirname $cursor]} {
    if {[file exists $cursor] && [file type $cursor] eq "link"} { error "symlink input/output parent forbidden" }
    set cursor [file dirname $cursor]
  }
}
foreach path [lrange $argv 0 1] { paired60_no_symlink $path }
set output_dir [file normalize [lindex $argv 0]]
set prepared [file normalize [lindex $argv 1]]
set python [file normalize [lindex $argv 2]]
set expected_sha [lindex $argv 3]
proc paired60_python {python args} {
  # Sanitize independent Python only. Vivado retains its required SuSE path.
  return [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH $python -B {*}$args]
}
if {[file exists $output_dir]} { error "refusing to overwrite simulation evidence" }
if {![file executable $python]} { error "explicit executable Python required" }
if {![regexp {^[0-9a-f]{64}$} $expected_sha]} { error "external reviewed bundle SHA required" }
set verifier [file join $prepared source_snapshot tools prepare_starlink_high_rate60_harness.py]
puts [paired60_python $python $verifier verify $prepared --expected-bundle-sha $expected_sha]
set own_name hdl/library/starlink_pss_acquisition/simulate_high_rate60_bank_native_paired.tcl
set channel [open [info script] rb]; set live_entry [read $channel]; close $channel
set channel [open [file join $prepared source_snapshot $own_name] rb]; set frozen_entry [read $channel]; close $channel
if {$live_entry ne $frozen_entry} { error "runner differs from frozen reviewed source" }
file mkdir $output_dir
file copy $prepared [file join $output_dir inputs]
set inputs [file join $output_dir inputs]
set source_root [file join $inputs source_snapshot]
set acq [file join $source_root hdl library starlink_pss_acquisition]
set vectors [file join $inputs vectors]
set verifier [file join $source_root tools prepare_starlink_high_rate60_harness.py]
set channel [open [file join $output_dir before_integrity.txt] w]
puts $channel [paired60_python $python $verifier verify $inputs --expected-bundle-sha $expected_sha]
close $channel
set run_code [catch {
  set_param general.maxThreads 2
  source [file join $acq create_shared_realtime_xfft_ip.tcl]
  set project_name high_rate60_bank_native_paired
  set project_dir [file join $output_dir project]
  create_project $project_name $project_dir -part xc7z010clg400-1
  set_property target_language Verilog [current_project]
  set_property simulator_language Mixed [current_project]
  set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
  pss_create_shared_realtime_xfft_ip $wrapper_path
  foreach directory [glob -type d [file join $source_root hdl library *]] {
    foreach path [glob -nocomplain [file join $directory *.v]] { add_files -norecurse $path }
  }
  set bench tb_starlink_pss_60_bank_native_paired
  add_files -fileset sim_1 -norecurse [file join $acq tb ${bench}.sv]
  set_property include_dirs [list [file join $acq tb]] [get_filesets sim_1]
  foreach path [glob [file join $vectors *.mem]] { add_files -fileset sim_1 -norecurse $path }
  foreach name {pilot_mixer_q16.mem pilot_halfband2_q17.mem pilot_fir3_q17.mem} {
    add_files -fileset sim_1 -norecurse [file join $acq $name]
  }
  add_files -fileset sim_1 -norecurse [file join $acq tb upper_edge_pss60_x4_ddc_kernel_q17.mem]
  set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
  set_property top $bench [get_filesets sim_1]
  set_property xsim.simulate.runtime {all} [get_filesets sim_1]
  set channel [open [file join $output_dir generated_ip.txt] w]
  puts $channel [exec sha256sum $wrapper_path]; close $channel
  launch_simulation -simset sim_1 -mode behavioral
  close_sim
  set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
  set result [paired60_python $python $verifier result $simulation_dir $inputs --expected-bundle-sha $expected_sha]
  close_project
} run_error run_options]
set integrity_code [catch {paired60_python $python $verifier verify $inputs --expected-bundle-sha $expected_sha} integrity_result]
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
puts "HIGH_RATE60_SIMULATION_VERIFIED ideal_bank175=1 native264=1 pilot512=1 static_known_center_not_RF=1"
