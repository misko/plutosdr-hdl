# Compare actual synthesized BRAM primitives against the pinned old RTL.
# This proves functional storage behavior, not placement/timing or RF.
if {$argc != 2} { error "expected COMPARISON_DIRECTORY NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set comparison [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
if {[file exists $output]} { error "output must be new" }
foreach name {scope.txt baseline.v candidate.v candidate_netlist.v} {
  if {![file isfile [file join $comparison $name]]} { error "missing comparison input $name" }
}
set channel [open [file join $comparison scope.txt] r]
set comparison_scope [read $channel]
close $channel
if {[llength [lsearch -all -exact [split $comparison_scope "\n"] \
    {FIFO_STORAGE_COMPARISON_FINISHED hardware_qualified=false}]] != 1} {
  error "synthesis comparison incomplete"
}
set baseline_hash 21740ca5d282ee1aea6b302692ffe3d4d96df1bfacd805d570fec4cea65f6db5
if {[lindex [exec sha256sum [file join $comparison baseline.v]] 0] ne $baseline_hash} {
  error "baseline source mismatch"
}
set candidate_hash [lindex [exec sha256sum [file join $comparison candidate.v]] 0]
if {$candidate_hash ne [lindex [exec sha256sum [file join $source_dir starlink_pss_transform_fifo.v]] 0]} {
  error "candidate source changed since synthesis"
}
set candidate_netlist_hash [lindex [exec sha256sum [file join $comparison candidate_netlist.v]] 0]
foreach {label value} [list candidate_source_sha256 $candidate_hash \
    candidate_netlist_sha256 $candidate_netlist_hash baseline_source_sha256 $baseline_hash] {
  if {[llength [lsearch -all -exact [split $comparison_scope "\n"] "$label=$value"]] != 1} {
    error "synthesis receipt does not bind $label"
  }
}
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach path [list [info script] [file join $comparison candidate_netlist.v] \
    [file join $comparison scope.txt] [file join $comparison candidate.v] \
    [file join $source_dir verify_realtime_probe_result.tcl] \
    [file join $source_dir tb tb_starlink_pss_transform_fifo.sv] \
    [file join $source_dir tb tb_starlink_pss_transform_fifo_storage.sv]] {
  file copy $path $frozen
}
set channel [open [file join $comparison baseline.v] r]
set baseline [read $channel]
close $channel
set channel [open [file join $frozen golden.v] w]
puts -nonewline $channel [string map \
  [list {module starlink_pss_transform_fifo #(} {module starlink_pss_transform_fifo_golden #(}] $baseline]
close $channel
set receipt [open [file join $output scope.txt] w]
puts $receipt "scope=default_depth4_actual_synthesized_BRAM_public_cycle_equivalence_to_pinned_RTL"
puts $receipt "no_full_receiver_fit_timing_or_hardware_qualification=true"
puts $receipt "baseline_source_sha256=$baseline_hash"
puts $receipt "candidate_source_sha256=$candidate_hash"
puts $receipt "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]]]"
close $receipt
source [file join $frozen verify_realtime_probe_result.tcl]
set project_dir [file join $output project]
create_project fifo_storage $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [file join $frozen candidate_netlist.v]
foreach name {golden.v tb_starlink_pss_transform_fifo.sv tb_starlink_pss_transform_fifo_storage.sv} {
  add_files -fileset sim_1 -norecurse [file join $frozen $name]
}
set_property verilog_define FIFO_STORAGE_SYNTH_NETLIST [get_filesets sim_1]
set_property top tb_starlink_pss_transform_fifo_storage [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
file mkdir [file join $project_dir fifo_storage.sim sim_1 behav xsim build]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log_path [file join $project_dir fifo_storage.sim sim_1 behav xsim simulate.log]
require_realtime_probe_pass $log_path [list \
  {FIFO_STORAGE_EQUIVALENCE_WITNESS checked_cycles=512} \
  {TRANSFORM_FIFO_PASS words=512 depth=4 stalls=1 malformed=1 identity=1 flush=1}] \
  FIFO_STORAGE_EQUIVALENCE_WITNESS 1
close_project
puts "FIFO_STORAGE_ACTUAL_BRAM_SIMULATION_VERIFIED no_receiver_physical_claim=1"
