# Read-only DCP inspection. Never change constraints, placement, routing or DCP.
if {$argc != 3} { error "expected CHECKPOINT EXPECTED_SHA256 NEW_OUTPUT" }
set checkpoint [file normalize [lindex $argv 0]]
set expected_hash [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {![regexp {^[0-9a-f]{64}$} $expected_hash]} { error "invalid expected hash" }
if {![file isfile $checkpoint] || [file exists $output_dir]} { error "missing checkpoint or occupied output" }
set before [exec sha256sum $checkpoint]
if {[lindex $before 0] ne $expected_hash} { error "checkpoint hash mismatch" }
file mkdir $output_dir
set_param general.maxThreads 2
open_checkpoint $checkpoint
set out [open [file join $output_dir inventory.txt] w]
puts $out "scope=read_only_isolated_product_checkpoint_not_receiver"
puts $out "checkpoint_sha256=$expected_hash"
puts $out "part=[get_property PART [current_design]]"
puts $out "clock_period_ns=[get_property PERIOD [get_clocks product_clk]]"
set dsps [lsort [get_cells -hier -filter {REF_NAME == DSP48E1}]]
puts $out "dsp_count=[llength $dsps]"
foreach cell $dsps {
  set row [list DSP $cell]
  foreach property {AREG BREG MREG PREG CREG ACASCREG BCASCREG} {
    lappend row $property [get_property $property $cell]
  }
  puts $out [join $row " "]
}
set registers [all_registers]
foreach {mode label} {max setup min hold} {
  set paths [get_timing_paths -quiet -from $registers -to $registers -delay_type $mode -max_paths 1]
  if {[llength $paths] != 1} { error "missing internal $label path" }
  puts $out "register_to_register_${label}_slack_ns=[get_property SLACK $paths]"
  report_timing -from $registers -to $registers -delay_type $mode -max_paths 10 \
    -path_type full_clock_expanded -file [file join $output_dir internal_${label}.rpt]
}
set failed [get_timing_paths -quiet -delay_type min -slack_lesser_than 0 -nworst 1 -max_paths 10000]
set rows [open [file join $output_dir failing_hold_endpoints.tsv] w]
puts $rows "startpoint\tendpoint\tslack_ns\tstart_is_top_port"
set port_count 0
foreach path $failed {
  set start [get_property STARTPOINT_PIN $path]
  set end [get_property ENDPOINT_PIN $path]
  # Top-level ports have no hierarchy separator; register clock pins do.
  set is_port [expr {[string first / $start] < 0}]
  if {$is_port} { incr port_count }
  puts $rows "$start\t$end\t[get_property SLACK $path]\t$is_port"
}
close $rows
puts $out "failing_hold_endpoints=[llength $failed]"
puts $out "failing_hold_from_top_ports=$port_count"
close $out
close_design
if {[exec sha256sum $checkpoint] ne $before} { error "checkpoint changed during audit" }
puts "ROUND_CHECKPOINT_READ_ONLY_AUDIT_COMPLETE failing_hold=[llength $failed] port_startpoints=$port_count"
