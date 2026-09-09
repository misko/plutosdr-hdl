# Read-only structural diagnosis of an already synthesized full receiver.
# A missing combinational dependency is NOT a timing or functional proof.
if {$argc != 2} { error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "retirement audit requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {![file isfile $checkpoint]} { error "missing input checkpoint" }
if {[file exists $output_dir]} { error "refusing to overwrite retirement evidence" }
file mkdir $output_dir
file copy [file normalize [info script]] [file join $output_dir audit_source.tcl]
cd $output_dir
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} {
  error "retirement audit requires the complete xc7z010 receiver"
}
set sources [get_cells -quiet -hier -regexp \
  {.*transform_service/adapter/expected_input_position_reg\[[0-9]+\]$}]
set address_pins [get_pins -quiet -hier -regexp \
  {.*transform_service/input_mailbox/read_address_reg\[[0-9]+\]/(CE|D)$}]
set memory_pins [get_pins -quiet -hier -regexp \
  {.*transform_service/input_mailbox/payload_memory_reg[^/]*/ENARDEN$}]
if {[llength $sources] != 9 || [llength $address_pins] != 18 || ![llength $memory_pins]} {
  error "missing expected input-position/address/BRAM endpoints; do not infer isolation"
}
set source_names [get_property NAME $sources]
set endpoints [concat $address_pins $memory_pins]
set report [open fanin.txt w]
puts $report "checkpoint=$checkpoint"
puts $report "checkpoint_sha256=[exec sha256sum $checkpoint]"
puts $report "scope=structural_combinational_fanin_not_path_sensitization_or_timing_closure"
puts $report "hardware_qualified=false"
puts $report "input_position_registers=[llength $sources]"
puts $report "address_control_pins=[llength $address_pins]"
puts $report "memory_enable_pins=[llength $memory_pins]"
set dependent_endpoints 0
foreach endpoint [lsort $endpoints] {
  set startpoints [all_fanin -flat -startpoints_only -only_cells -to $endpoint]
  set names [lsort -unique [get_property NAME $startpoints]]
  set metadata_sources {}
  foreach name $source_names {
    if {[lsearch -exact $names $name] >= 0} { lappend metadata_sources $name }
  }
  if {[llength $metadata_sources]} { incr dependent_endpoints }
  puts $report "endpoint=$endpoint input_position_sources=[llength $metadata_sources]"
  foreach name $names { puts $report "  startpoint=$name" }
}
puts $report "input_position_dependent_endpoints=$dependent_endpoints"
close $report
# Retain constrained paths when present, but never add or relax constraints.
# In a synthesis DCP the board clocks may be absent: the structural inventory
# remains usable, while timing still requires the constrained full route.
report_timing -from $sources -to $endpoints -max_paths 25 -nworst 1 \
  -file input_position_paths.rpt
puts "SHARED_INPUT_RETIREMENT_AUDIT_FINISHED dependent_endpoints=$dependent_endpoints hardware_qualified=false"
close_design
