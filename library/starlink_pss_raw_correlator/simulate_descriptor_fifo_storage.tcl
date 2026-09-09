# Actual optimized BRAM netlist vs frozen old RTL plus independent queue oracle.
# Clock simulation is NOT metastability, routed CDC, receiver fit or RF proof.
if {$argc != 2} { error "expected MEASUREMENT_DIRECTORY NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set measurement [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
if {[file exists $output]} { error "output must be new" }
set fifo_source [file join $measurement frozen_sources starlink_pss_async_fifo.v]
set netlist [file join $measurement block_netlist.v]
foreach path [list $fifo_source $netlist [file join $measurement scope.txt]] {
  if {![file isfile $path]} { error "missing measurement input $path" }
}
set baseline_hash a07f1bf38da80b3a0f125351af439af5b58aae1ab783597ba15086d40f3cbc0d
foreach path [list $fifo_source [file join $source_dir starlink_pss_async_fifo.v]] {
  if {[lindex [exec sha256sum $path] 0] ne $baseline_hash} { error "FIFO source differs from pinned measurement" }
}
set netlist_hash [lindex [exec sha256sum $netlist] 0]
set channel [open [file join $measurement scope.txt] r]
set measured_scope [read $channel]
close $channel
foreach required [list "block_netlist_sha256=$netlist_hash" \
    {DATA_WIDTH=161 ADDRESS_WIDTH=2 usable_entries=3} \
    {DESCRIPTOR_STORAGE_MEASURED equivalence_CDC_timing_receiver_fit_qualified=false}] {
  if {[llength [lsearch -all -exact [split $measured_scope "\n"] $required]] != 1} {
    error "measurement receipt missing or mismatched binding"
  }
}
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach path [list [info script] $fifo_source $netlist [file join $measurement scope.txt] \
    [file join $source_dir tb tb_starlink_pss_descriptor_storage.sv] \
    [file join $source_dir ../starlink_pss_acquisition/verify_realtime_probe_result.tcl]] {
  file copy $path $frozen
}
set channel [open $fifo_source r]
set baseline [read $channel]
close $channel
set channel [open [file join $frozen golden.v] w]
puts -nonewline $channel [string map \
  [list {module starlink_pss_async_fifo #(} {module starlink_pss_async_fifo_golden #(}] $baseline]
close $channel
set receipt [open [file join $output scope.txt] w]
puts $receipt "scope=actual_synthesized_descriptor_BRAM_public_equivalence_and_queue_oracle"
puts $receipt "physical_CDC_timing_full_receiver_and_hardware_qualified=false"
puts $receipt "baseline_source_sha256=$baseline_hash"
puts $receipt "netlist_sha256=$netlist_hash"
puts $receipt "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]]]"
flush $receipt
source [file join $frozen verify_realtime_probe_result.tcl]
set project_dir [file join $output project]
create_project descriptor_storage $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [file join $frozen block_netlist.v]
foreach name {golden.v tb_starlink_pss_descriptor_storage.sv} {
  add_files -fileset sim_1 -norecurse [file join $frozen $name]
}
set_property verilog_define DESCRIPTOR_SYNTH_NETLIST [get_filesets sim_1]
set_property top tb_starlink_pss_descriptor_storage [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach {write_half read_half read_first} {7 5 0 7 5 1 5 7 0 5 7 1 3 5 0 3 5 1} {
  set case_name w${write_half}_r${read_half}_release${read_first}
  set_property generic [list WRITE_HALF=$write_half READ_HALF=$read_half \
    RELEASE_READ_FIRST=$read_first] [get_filesets sim_1]
  launch_simulation -simset sim_1 -mode behavioral
  close_sim
  set log_path [file join $project_dir descriptor_storage.sim sim_1 behav xsim simulate.log]
  require_realtime_probe_pass $log_path [list \
    "DESCRIPTOR_CLOCK_CONFIG write_half=$write_half read_half=$read_half release_read_first=$read_first" \
    {DESCRIPTOR_STORAGE_WITNESS writes=195 reads=192 reset_discard=3 consumed_hold=12} \
    {DESCRIPTOR_STORAGE_PASS full=1 wrap=1 stalls=1 coordinated_reset=1 queue_oracle=1 public_equivalence=1}] \
    DESCRIPTOR_STORAGE_WITNESS 1
  file copy $log_path [file join $output ${case_name}.log]
  puts $receipt "verified_case=$case_name log_sha256=[lindex [exec sha256sum $log_path] 0]"
  flush $receipt
}
close_project
puts $receipt "DESCRIPTOR_ACTUAL_BRAM_SIMULATION_VERIFIED cases=6 hardware_qualified=false"
close $receipt
puts "DESCRIPTOR_ACTUAL_BRAM_SIMULATION_VERIFIED cases=6 hardware_qualified=false"
