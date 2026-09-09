# Bounded placement-only diagnostic from an immutable caller-attested DCP.
# The saved source checkpoint and all its timing constraints remain unchanged.
# A placed child is NOT fresh synthesis, routed timing, or deployment evidence.
if {$argc != 5} { error "expected CHECKPOINT NEW_OUTPUT HDL_COMMIT CHECKPOINT_SHA256 DIRECTIVE" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set revision [lindex $argv 2]
set digest [lindex $argv 3]
set directive [lindex $argv 4]
if {![regexp {^[0-9a-f]{40}$} $revision] || ![regexp {^[0-9a-f]{64}$} $digest]} {
  error "full revision and checkpoint hash required"
}
if {$directive ni {AltSpreadLogic_medium Explore}} { error "unsupported bounded placement policy" }
if {![file isfile $checkpoint] || [file exists $output]} { error "existing checkpoint and new output required" }
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "checkpoint SHA256 mismatch" }
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {[exec git -C $repo rev-parse "${revision}^{commit}"] ne $revision} { error "revision did not resolve" }
file mkdir $output
file copy [info script] [file join $output probe_source.tcl]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} { error "wrong receiver part" }
foreach label {starlink_pss_acquisition starlink_pss_tracker starlink_pilot_capture starlink_pilot_dma} {
  if {[llength [get_cells -quiet -hier -filter "NAME =~ */$label/inst"]] != 1} {
    error "expected complete receiver component: $label"
  }
}
foreach clock_name {clk_fpga_0 clk_fpga_1 rx_clk} expected_period {10.0 5.0 16.270} {
  set clock [get_clocks -quiet $clock_name]
  if {[llength $clock] != 1 || abs([get_property PERIOD $clock] - $expected_period) > 0.001} {
    error "unexpected saved receiver clock"
  }
}
set report [open [file join $output scope.txt] w]
puts $report "scope=placement_only_child_of_saved_optimized_checkpoint_not_fresh_receiver_qualification"
puts $report "caller_attested_source_revision=$revision source_association_not_derived_from_checkpoint=1"
puts $report "checkpoint_sha256=$digest directive=$directive"
puts $report "constraints_changed=0 hardware_qualified=0 routed_timing_qualified=0"
flush $report
set_param general.maxThreads 8
set failed [catch {place_design -directive $directive} message]
puts $report "placement_failed=$failed message=$message"
if {!$failed} {
  report_utilization -file [file join $output utilization.rpt]
  report_control_sets -verbose -file [file join $output control_sets.rpt]
  report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
    -file [file join $output pre_route_timing.rpt]
  report_route_status -file [file join $output route_status.rpt]
  write_checkpoint [file join $output placement_only.dcp]
  puts $report "child_checkpoint_sha256=[lindex [exec sha256sum [file join $output placement_only.dcp]] 0]"
}
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "source checkpoint changed during probe" }
puts $report "PLACEMENT_PROBE_FINISHED deployment_qualified=0"
close $report
close_design
if {$failed} { error "bounded placement diagnostic failed: $message" }
puts "PLACEMENT_PROBE_FINISHED deployment_qualified=0"
