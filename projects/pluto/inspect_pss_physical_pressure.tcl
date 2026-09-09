# Read-only pressure/timing inventory of a caller-pinned receiver checkpoint.
# Saved pre-route estimates must never be called routed timing qualification.
# No source, constraint, optimization, placement or checkpoint writes.
if {$argc != 4} { error "expected CHECKPOINT NEW_OUTPUT HDL_COMMIT CHECKPOINT_SHA256" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set revision [lindex $argv 2]
set digest [lindex $argv 3]
if {![regexp {^[0-9a-f]{40}$} $revision] || ![regexp {^[0-9a-f]{64}$} $digest]} {
  error "full revision and checkpoint hash required"
}
if {![file isfile $checkpoint] || [file exists $output]} { error "existing checkpoint and new output required" }
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "checkpoint SHA256 mismatch" }
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {[exec git -C $repo rev-parse "${revision}^{commit}"] ne $revision} { error "revision did not resolve" }
file mkdir $output
file copy [info script] [file join $output inspection_source.tcl]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} { error "wrong receiver part" }
foreach label {starlink_pss_acquisition starlink_pss_tracker starlink_pilot_capture starlink_pilot_dma} {
  set cell [get_cells -quiet -hier -filter "NAME =~ */$label/inst"]
  if {[llength $cell] != 1} { error "expected one complete receiver component: $label" }
}
set report [open [file join $output scope.txt] w]
puts $report "scope=read_only_physical_pressure_inventory_not_deployment_qualification"
puts $report "caller_attested_source_revision=$revision source_association_not_derived_from_checkpoint=1"
puts $report "checkpoint_sha256=$digest"
puts $report "routed_fully=[report_route_status -boolean_check ROUTED_FULLY]"
puts $report "routing_errors=[report_route_status -boolean_check ERRORS_IN_ROUTES]"
puts $report "hardware_timing_CDC_qualified=false"
foreach clock_name {clk_fpga_0 clk_fpga_1 rx_clk} expected_period {10.0 5.0 16.270} {
  set clock [get_clocks -quiet $clock_name]
  if {[llength $clock] != 1 || abs([get_property PERIOD $clock] - $expected_period) > 0.001} {
    error "unexpected receiver clock: $clock_name expected_period_ns=$expected_period"
  }
  set paths [get_timing_paths -quiet -group $clock_name -delay_type max -max_paths 30 -nworst 1]
  if {![llength $paths]} { error "missing timed endpoints for $clock_name" }
  puts $report "clock=$clock_name period_ns=[get_property PERIOD $clock] reported_paths=[llength $paths]"
  foreach path $paths {
    puts $report "slack_ns=[get_property SLACK $path] requirement_ns=[get_property REQUIREMENT $path] source=[get_property STARTPOINT_PIN $path] destination=[get_property ENDPOINT_PIN $path]"
  }
  report_timing -group $clock_name -delay_type max -max_paths 30 -nworst 1 \
    -file [file join $output ${clock_name}_timing.rpt]
}
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
  -file [file join $output timing_summary.rpt]
report_utilization -hierarchical -hierarchical_depth 12 -file [file join $output hierarchy.rpt]
report_utilization -file [file join $output utilization.rpt]
report_control_sets -verbose -file [file join $output control_sets.rpt]
# Vivado 2022.2's optional report_qor_suggestions crashes on this saved design.
# Keep the independent timing/control-set evidence; do not retry that engine or
# treat an incomplete report as proof. No optimization suggestions are applied.
report_route_status -file [file join $output route_status.rpt]
report_clocks -file [file join $output clocks.rpt]
check_timing -verbose -file [file join $output check_timing.rpt]
help report_high_fanout_nets
help report_design_analysis
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "checkpoint changed during inspection" }
puts $report "PHYSICAL_PRESSURE_INSPECTED hardware_timing_CDC_qualified=false"
close $report
close_design
puts "PHYSICAL_PRESSURE_INSPECTED hardware_timing_CDC_qualified=false"
