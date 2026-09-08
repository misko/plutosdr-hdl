# Inspect the saved implementation with its OWN constraints. Never reapply
# clocks, waive paths, or treat a synthesized checkpoint as a routed receiver.
# Produces diagnostic evidence; not a standalone deployment authorization.
if {$argc != 2} { error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY" }
set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite checkpoint evidence" }
file mkdir $output_dir
cd $output_dir
open_checkpoint $checkpoint
source [file join $script_dir shared_xfft_impl_gate.tcl]
report_utilization -hierarchical -hierarchical_depth 12 -file utilization.rpt
report_control_sets -verbose -file control_sets.rpt
report_timing_summary -report_unconstrained -delay_type min_max -max_paths 25 -file timing.rpt
report_bus_skew -file bus_skew.rpt
report_route_status -file route_status.rpt
report_methodology -file methodology.rpt
check_timing -verbose -file check_timing.rpt
set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing timing evidence" }
set channel [open summary.txt w]
puts $channel "checkpoint=$checkpoint"
puts $channel "checkpoint_sha256=[exec sha256sum $checkpoint]"
puts $channel "setup_wns_ns=[get_property SLACK $setup]"
puts $channel "hold_whs_ns=[get_property SLACK $hold]"
puts $channel "hardware_qualified=false"
puts $channel "scope=diagnostics_only_review_all_route_timing_CDC_methodology_reports"
# Record the actual read/write widths, collision modes and clocks of the FIFO
# primitive. RTL read-first equivalence alone does not establish its mapping.
set pacer [get_cells -quiet -hier -filter \
  {NAME =~ */starlink_pilot_capture/inst/ddc/pacer_memory/* && REF_NAME == RAMB18E1}]
foreach property {READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B WRITE_MODE_A WRITE_MODE_B DOA_REG DOB_REG} {
  puts $channel "pilot_pacer_$property=[get_property $property $pacer]"
}
close $channel
puts "SHARED_RECEIVER_CHECKPOINT_AUDIT_WRITTEN_NOT_DEPLOYMENT_QUALIFICATION"
close_design
