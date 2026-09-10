# One source-frozen actual campaign. This file is not invoked during preparation.
if {$argc != 4} { error "expected BUNDLE PYTHON EXTERNAL_MANIFEST_SHA NEW_OUTPUT" }
lassign $argv bundle python expected output
foreach requested [list $bundle $python $output [info script]] {
  set p $requested
  if {[file pathtype $p] ne "absolute"} { error "absolute paths required" }
  while {1} {
    if {![catch {file type $p} kind] && $kind eq "link"} { error "symlink path forbidden" }
    set parent [file dirname $p]
    if {$parent eq $p} { break }
    set p $parent
  }
}
set bundle [file normalize $bundle]
set output [file normalize $output]
set source_dir [file join $bundle source_snapshot]
set runner [file join $source_dir hdl library starlink_pss_acquisition retained_summary_actual simulate_retained_summary_actual.tcl]
if {[file normalize [info script]] ne $runner} { error "only exact frozen runner" }
if {[version -short] ne "2022.2"} { error "Vivado 2022.2 required" }
if {![file executable $python]} { error "explicit executable Python required" }
if {$python ne "/home/mouse9911/.local/share/uv/python/cpython-3.11.16-linux-x86_64-gnu/bin/python3.11" ||
    [lindex [exec sha256sum $python] 0] ne "2874a0b9344d06b7767aebb1e6e25a759ffcbdb544e99400ecc74dc6092d1174"} {
  error "tested resolved Python identity required"
}
if {[file exists $output]} { error "one-shot output already exists" }
set_param general.maxThreads 2
set py [list env -u PYTHONHOME -u PYTHONPATH -u PYTHONOPTIMIZE -u LD_LIBRARY_PATH $python -B \
  [file join $source_dir tools prepare_starlink_retained_summary_actual.py]]
exec {*}$py stage $bundle --output $output --expected $expected --authorize-actual
set inputs [file join $output inputs]
set project [file join $output project]
set wrapper ""
set generated_before ""
set result_json ""
set status [catch {
  create_project retained_output_actual $project -part xc7z010clg400-1
  set_property target_language Verilog [current_project]
  set_property simulator_language Mixed [current_project]
  source [file join $inputs source_snapshot hdl library starlink_pss_acquisition retained_output_actual reference create_shared_realtime_xfft_ip.tcl]
  set wrapper [file join $project retained_output_actual.gen sources_1 ip starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
  pss_create_shared_realtime_xfft_ip $wrapper
  set generated_before [exec sha256sum $wrapper]
  set f [open [file join $output generated_ip_before.txt] {WRONLY CREAT EXCL}]
  puts $f $generated_before; close $f
  source [file join $inputs profile.tcl]
  foreach name $compiled_names {
    set compiled_file [file join $inputs $name]
    if {[file extension $compiled_file] ni {.v .sv}} { error "unexpected compiled HDL extension" }
    add_files -fileset sim_1 -norecurse $compiled_file
    set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] $compiled_file]
  }
  foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $inputs $name] }
  set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
  set_property top tb [get_filesets sim_1]
  set_property xsim.simulate.runtime all [get_filesets sim_1]
  set_property xsim.simulate.custom_tcl [file join $inputs source_snapshot hdl library starlink_pss_acquisition retained_output_actual run_retained_output_actual.tcl] [get_filesets sim_1]
  launch_simulation -simset sim_1 -mode behavioral
  close_sim
  set result_json [exec {*}$py results $output --expected $expected]
  close_project
} result options]
# Failure must not skip either source-copy verification or generated-IP receipt.
set ip_status [catch {
  set f [open [file join $output generated_ip_after.txt] {WRONLY CREAT EXCL}]
  if {$wrapper ne "" && [file isfile $wrapper]} {
    set generated_after [exec sha256sum $wrapper]
    puts $f $generated_after
    if {$generated_before eq "" || $generated_before ne $generated_after} { close $f; error "generated IP missing-before/changed" }
  } else {
    puts $f "not_generated"
    if {$generated_before ne ""} { close $f; error "generated IP vanished" }
  }
  close $f
} ip_result ip_options]
set after_status [catch {exec {*}$py after $bundle --output $output --expected $expected} after_result after_options]
set f [open [file join $output run_outcome.txt] {WRONLY CREAT EXCL}]
puts $f "run_status=$status\nrun_result=$result\nrun_options=$options"
puts $f "ip_status=$ip_status\nip_result=$ip_result\nip_options=$ip_options"
puts $f "after_status=$after_status\nafter_result=$after_result\nafter_options=$after_options"
close $f
if {$status} { return -options $options $result }
if {$ip_status} { return -options $ip_options $ip_result }
if {$after_status} { return -options $after_options $after_result }
set f [open [file join $output results.json] {WRONLY CREAT EXCL}]
puts $f $result_json;close $f
puts "RETAINED_SUMMARY_ACTUAL_VERIFIED_SEVEN_CONTEXTS_NO_CONTINUOUS_OR_PHYSICAL_CLAIM"
