# Validate the monitor-specific CDC contract in a routed Pluto checkpoint.
# Usage:
#   vivado -mode batch -source validate_routed.tcl \
#     -tclargs /path/system_top_routed.dcp /path/report-directory

if {$argc != 2} {
  error "expected routed checkpoint and report directory"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
open_checkpoint $checkpoint

set monitor_glob "*starlink_pss_candidate_monitor/inst/i_event_cdc"
set mailbox_cells [get_cells -quiet -hier -filter "IS_SEQUENTIAL && (
  NAME =~ ${monitor_glob}/mailbox_event_count_reg* ||
  NAME =~ ${monitor_glob}/mailbox_sample_index_reg* ||
  NAME =~ ${monitor_glob}/mailbox_metric_num_reg* ||
  NAME =~ ${monitor_glob}/mailbox_metric_den_reg*
)"]
set snapshot_cells [get_cells -quiet -hier -filter "IS_SEQUENTIAL && (
  NAME =~ ${monitor_glob}/snapshot_event_count_reg* ||
  NAME =~ ${monitor_glob}/snapshot_sample_index_reg* ||
  NAME =~ ${monitor_glob}/snapshot_metric_num_reg* ||
  NAME =~ ${monitor_glob}/snapshot_metric_den_reg*
)"]
set synchronizer_cells [get_cells -quiet -hier -filter "
  NAME =~ ${monitor_glob}/request_sync_1_reg ||
  NAME =~ ${monitor_glob}/request_sync_2_reg ||
  NAME =~ ${monitor_glob}/acknowledge_sync_1_reg ||
  NAME =~ ${monitor_glob}/acknowledge_sync_2_reg
"]

if {[llength $mailbox_cells] != 293} {
  error "expected 293 mailbox source registers, got [llength $mailbox_cells]"
}
if {[llength $snapshot_cells] != 293} {
  error "expected 293 snapshot registers, got [llength $snapshot_cells]"
}
if {[llength $synchronizer_cells] != 4} {
  error "expected four toggle synchronizer registers, got [llength $synchronizer_cells]"
}
foreach cell $synchronizer_cells {
  if {![get_property ASYNC_REG $cell]} {
    error "missing ASYNC_REG on $cell"
  }
}

set mailbox_path [get_timing_paths -quiet -delay_type max -max_paths 1 \
  -from $mailbox_cells -to $snapshot_cells]
if {[llength $mailbox_path] != 1} {
  error "mailbox max-delay path is missing"
}
set mailbox_slack [get_property SLACK $mailbox_path]
if {$mailbox_slack < 0.0} {
  error "mailbox max-delay constraint failed with slack $mailbox_slack ns"
}

report_timing -delay_type max -max_paths 20 -nworst 1 \
  -from $mailbox_cells -to $snapshot_cells \
  -file [file join $report_dir starlink_pss_mailbox_timing.rpt]
set monitor_event_cdc_cells [get_cells -quiet -hier -filter \
  "NAME =~ ${monitor_glob}"]
if {[llength $monitor_event_cdc_cells] != 1} {
  error "expected one monitor event-CDC hierarchy, got [llength $monitor_event_cdc_cells]"
}
set bus_skew_report [report_bus_skew -warn_on_violation \
  -cells $monitor_event_cdc_cells -return_string]
set bus_skew_report_file [open \
  [file join $report_dir starlink_pss_bus_skew.rpt] w]
puts -nonewline $bus_skew_report_file $bus_skew_report
close $bus_skew_report_file
set bus_skew_violated_count [regexp -all {Slack \(VIOLATED\)} $bus_skew_report]
set bus_skew_met_count [regexp -all {Slack \(MET\)} $bus_skew_report]
if {$bus_skew_violated_count != 0} {
  error "routed design contains $bus_skew_violated_count violated bus-skew constraints"
}
if {$bus_skew_met_count != 1} {
  error "expected exactly one met monitor bus-skew constraint, got $bus_skew_met_count"
}
if {![regexp {starlink_pss_candidate_monitor.*mailbox_} $bus_skew_report]} {
  error "monitor mailbox bus-skew constraint is absent from the routed report"
}
set cdc_report_path [file join $report_dir starlink_pss_cdc.rpt]
report_cdc -details -file $cdc_report_path

set cdc_report_file [open $cdc_report_path r]
set cdc_report [read $cdc_report_file]
close $cdc_report_file
set monitor_critical_count [regexp -all -line \
  {CDC-[0-9]+[ \t]+Critical.*starlink_pss_candidate_monitor} $cdc_report]
set monitor_payload_count [regexp -all -line \
  {CDC-15[ \t]+Warning.*starlink_pss_candidate_monitor.*mailbox_.*snapshot_} \
  $cdc_report]
set monitor_toggle_count [regexp -all -line \
  {CDC-3[ \t]+Info.*starlink_pss_candidate_monitor.*_toggle_reg.*_sync_1_reg} \
  $cdc_report]
if {$monitor_critical_count != 0} {
  error "monitor introduced $monitor_critical_count Critical CDC rows"
}
if {$monitor_payload_count != 293} {
  error "expected 293 monitor CDC-15 payload rows, got $monitor_payload_count"
}
if {$monitor_toggle_count != 2} {
  error "expected two monitor CDC-3 toggle rows, got $monitor_toggle_count"
}

set summary [open [file join $report_dir starlink_pss_cdc_summary.txt] w]
puts $summary "mailbox_source_registers=[llength $mailbox_cells]"
puts $summary "snapshot_registers=[llength $snapshot_cells]"
puts $summary "toggle_synchronizer_registers=[llength $synchronizer_cells]"
puts $summary "mailbox_max_delay_slack_ns=$mailbox_slack"
puts $summary "met_bus_skew_constraints=$bus_skew_met_count"
puts $summary "violated_bus_skew_constraints=$bus_skew_violated_count"
puts $summary "monitor_critical_cdc_rows=$monitor_critical_count"
puts $summary "monitor_payload_cdc15_rows=$monitor_payload_count"
puts $summary "monitor_toggle_cdc3_rows=$monitor_toggle_count"
close $summary

puts "STARLINK_PSS_CDC_PASS mailbox_max_delay_slack_ns=$mailbox_slack"
close_design
