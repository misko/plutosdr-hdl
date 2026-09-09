# Public-interface comparison of the two caller-pinned synthesized pilot cores.
# Only module-name collision adapters are permitted; original files are retained.
if {$argc != 4} { error "expected MEASUREMENT NEW_OUTPUT BASELINE_SHA256 REPLICATED_SHA256" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set measurement [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set expected_hashes [lrange $argv 2 3]
if {[file exists $output]} { error "output must be new" }
foreach mode {baseline replicated} digest $expected_hashes {
  set netlist [file join $measurement ${mode}_netlist.v]
  if {![regexp {^[0-9a-f]{64}$} $digest] || ![file isfile $netlist] ||
      [lindex [exec sha256sum $netlist] 0] ne $digest} { error "netlist identity mismatch" }
}
set handle [open [file join $measurement scope.txt] r]
set scope [read $handle]
close $handle
if {[lsearch -exact [split $scope "\n"] \
    {PILOT_SNAPSHOT_FANOUT_MEASURED receiver_timing_and_hardware_qualified=false}] < 0} {
  error "measurement did not complete"
}
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach file [list [info script] [file join $measurement scope.txt] \
    [file join $source_dir tb tb_pilot_snapshot_replication.sv]] { file copy $file $frozen }
set marker "`ifndef GLBL\n"
foreach mode {baseline replicated} {
  set input [file join $measurement ${mode}_netlist.v]
  file copy $input $frozen
  set handle [open $input r]
  set original [read $handle]
  close $handle
  set split_at [string first $marker $original]
  if {$split_at < 0 || $split_at != [string last $marker $original]} { error "unexpected global startup layout" }
  set globals [string range $original $split_at end]
  if {$mode eq "baseline"} {
    set common_globals $globals
    set handle [open [file join $frozen common_glbl.v] w]
    puts -nonewline $handle $globals
    close $handle
  } elseif {$globals ne $common_globals} { error "different global startup definitions" }
  set logic [string range $original 0 [expr {$split_at - 1}]]
  if {![regexp {module starlink_pilot_pacer_memory} $logic]} { error "missing retained pacer module" }
  set unique_name pilot_snapshot_${mode}_pacer
  set adapted [string map [list starlink_pilot_pacer_memory $unique_name] $logic]
  if {"[string map [list $unique_name starlink_pilot_pacer_memory] $adapted]$globals" ne $original} {
    error "name-only netlist adaptation changed contents"
  }
  set handle [open [file join $frozen ${mode}_simulation.v] w]
  puts -nonewline $handle $adapted
  close $handle
}
set source_hashes [exec sha256sum {*}[lsort [glob [file join $frozen *]]]]
set report [open [file join $output scope.txt] w]
puts $report "scope=two_actual_synthesized_pilot_cores_public_functional_comparison"
puts $report "netlist_hashes=$expected_hashes"
puts $report "adapters=unique_pacer_module_names_and_one_identical_global_startup_definition"
puts $report "source_hashes=$source_hashes"
flush $report
set project_dir [file join $output project]
create_project snapshot_compare $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
foreach file {baseline_simulation.v replicated_simulation.v common_glbl.v tb_pilot_snapshot_replication.sv} {
  add_files -fileset sim_1 -norecurse [file join $frozen $file]
}
set_property top tb_pilot_snapshot_replication [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log [file join $project_dir snapshot_compare.sim sim_1 behav xsim simulate.log]
file copy $log [file join $output simulation.log]
set handle [open $log r]
set result [read $handle]
close $handle
if {[regexp -nocase -line {^[ \t]*(fatal|error)(:|[ \t])} $result] ||
    [string first PILOT_SNAPSHOT_EQ_FAIL $result] >= 0 ||
    [regexp -all {PILOT_SNAPSHOT_EQ_PASS cycles=[0-9]+ snapshots=12 reads=[0-9]+ pilot_samples=[0-9]+ no_receiver_timing_or_hardware_claim=1} $result] != 1} {
  error "actual netlist simulation lacks a clean terminal bench result"
}
if {[exec sha256sum {*}[lsort [glob [file join $frozen *]]]] ne $source_hashes} { error "frozen simulation inputs changed" }
foreach mode {baseline replicated} digest $expected_hashes {
  if {[lindex [exec sha256sum [file join $measurement ${mode}_netlist.v]] 0] ne $digest} { error "original netlist changed" }
}
puts $report "simulation_log_sha256=[lindex [exec sha256sum $log] 0]"
puts $report "PILOT_SNAPSHOT_NETLIST_EQUIVALENCE_TESTED receiver_timing_and_hardware_qualified=false"
close $report
close_project
puts "PILOT_SNAPSHOT_NETLIST_EQUIVALENCE_TESTED receiver_timing_and_hardware_qualified=false"
