# Produce hierarchy and packing diagnostics from an experimental RX-only PSS
# global-synthesis checkpoint without modifying the implementation project.
# Usage: vivado -mode batch -source report_starlink_synth.tcl -tclargs \
#   /absolute/path/system_top.dcp /absolute/path/output-directory

if {$argc != 2} {
  error "expected one synthesis checkpoint and one output directory"
}
if {[version -short] ne "2022.2"} {
  error "synthesis diagnostics require Vivado 2022.2, got [version -short]"
}

set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
file mkdir $output_dir
open_checkpoint $checkpoint

report_utilization -hierarchical -hierarchical_depth 8 \
  -file [file join $output_dir hierarchical_utilization.rpt]
report_control_sets -verbose \
  -file [file join $output_dir control_sets.rpt]

set tracker [get_cells -quiet -hier -filter {
  NAME =~ *starlink_pss_tracker/inst
}]
set acquisition [get_cells -quiet -hier -filter {
  NAME =~ *starlink_pss_acquisition/inst
}]
foreach {label cells} [list tracker $tracker acquisition $acquisition] {
  if {[llength $cells] != 1} {
    error "expected one $label hierarchy, got [llength $cells]"
  }
  report_utilization -cells $cells -hierarchical -hierarchical_depth 8 \
    -file [file join $output_dir ${label}_utilization.rpt]
  report_control_sets -cells $cells -verbose \
    -file [file join $output_dir ${label}_control_sets.rpt]
}

report_qor_suggestions \
  -file [file join $output_dir qor_suggestions.rpt]

set telemetry_ramb18 [get_cells -quiet -hier -filter {
  NAME =~ *starlink_pss_tracker/inst/i_telemetry_memory/* &&
  REF_NAME == RAMB18E1
}]
set summary [open [file join $output_dir summary.txt] w]
puts $summary "telemetry_ramb18e1=[llength $telemetry_ramb18]"
puts $summary "tracker_cells=[llength $tracker]"
puts $summary "acquisition_cells=[llength $acquisition]"
close $summary
puts "STARLINK_SYNTH_REPORT_PASS telemetry_ramb18e1=[llength $telemetry_ramb18]"
close_design
