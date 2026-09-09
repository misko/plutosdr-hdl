# Read-only endpoint audit of a caller-attested completed realtime receiver DCP.
# It never applies constraints, optimizes, places, routes, or writes a checkpoint.
# Timing failures are measurements, not reasons to alter or waive the saved design.
if {$argc != 4} {
  error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY HDL_COMMIT CHECKPOINT_SHA256"
}
if {[version -short] ne "2022.2"} { error "routed audit requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set source_revision [lindex $argv 2]
set expected_sha256 [lindex $argv 3]
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {![regexp {^[0-9a-f]{40}$} $source_revision]} { error "full immutable HDL commit required" }
if {![regexp {^[0-9a-f]{64}$} $expected_sha256]} { error "checkpoint SHA256 required" }
if {![file isfile $checkpoint]} { error "missing checkpoint" }
if {[file exists $output_dir]} { error "refusing to overwrite routed audit evidence" }
set actual_sha256 [lindex [exec sha256sum $checkpoint] 0]
if {$actual_sha256 ne $expected_sha256} { error "checkpoint SHA256 mismatch" }
if {[exec git -C $repo rev-parse "${source_revision}^{commit}"] ne $source_revision} {
  error "source commit did not resolve exactly"
}
set source_files {
  library/starlink_pss_acquisition/starlink_pss_shared_realtime_xfft_service.v
  library/starlink_pss_acquisition/starlink_pss_realtime_input_guard.v
  library/starlink_pss_acquisition/starlink_pss_realtime_result_guard.v
  library/starlink_pss_acquisition/starlink_pss_block_mailbox.v
}
set frozen_sources {}
foreach source_file $source_files {
  lappend frozen_sources [exec git -C $repo show "${source_revision}:$source_file"]
}
file mkdir $output_dir
file copy [file normalize [info script]] [file join $output_dir audit_source.tcl]
foreach source_file $source_files source_text $frozen_sources {
  set channel [open [file join $output_dir [file tail $source_file]] w]
  puts $channel $source_text
  close $channel
}
cd $output_dir
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} {
  error "expected the complete xc7z010 receiver"
}
proc audit_one {pattern} {
  set cells [get_cells -quiet -hier -regexp $pattern]
  if {[llength $cells] != 1} { error "expected exactly one endpoint: $pattern got [llength $cells]" }
  return $cells
}
proc audit_period {cells expected} {
  set clocks [get_clocks -quiet -of_objects \
    [get_pins -of_objects $cells -filter {REF_PIN_NAME == C}]]
  if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - $expected) > 0.001} {
    error "wrong actual clock for $cells: expected $expected ns, found $clocks"
  }
}
set core [audit_one {.*transform_service/shared_xfft$}]
if {![string match *starlink_pss_fft512_bfp18_rt_candidate* \
    "[get_property REF_NAME $core] [get_property ORIG_REF_NAME $core]"]} {
  error "expected the explicitly selected realtime generated core"
}
audit_one {.*starlink_pss_tracker/inst$}
audit_one {.*starlink_pilot_capture/inst$}
audit_one {.*starlink_pilot_dma/inst$}
set report [open summary.txt w]
puts $report "scope=read_only_saved_constraints_endpoint_timing_and_CDC_not_deployment_qualification"
puts $report "checkpoint=$checkpoint"
puts $report "checkpoint_sha256=$actual_sha256"
puts $report "hdl_source_revision=$source_revision"
puts $report "source_association=caller_attested_build_provenance_not_derived_from_checkpoint"
puts $report "hardware_qualified=false"
puts $report "category\tmatched_sources\tmatched_destinations\treported_paths\tworst_slack_ns\trequirement_ns"
proc audit_paths {label sources destinations {required_period {}}} {
  if {![llength $destinations] || ($label eq "vendor_internal" && ![llength $sources])} {
    error "empty endpoint inventory for $label"
  }
  set arguments [list -quiet -delay_type max -to $destinations -max_paths 10 -nworst 1]
  if {[llength $sources]} { lappend arguments -from $sources }
  set paths [get_timing_paths {*}$arguments]
  if {![llength $paths]} { error "no timed paths for $label; do not infer a pass" }
  if {$required_period ne {}} {
    foreach path $paths {
      if {abs([get_property REQUIREMENT $path] - $required_period) > 0.001} {
        error "unexpected or waived timing requirement for $label"
      }
    }
  }
  set worst [lindex $paths 0]
  puts $::report "$label\t[llength $sources]\t[llength $destinations]\t[llength $paths]\t[get_property SLACK $worst]\t[get_property REQUIREMENT $worst]"
  foreach path $paths {
    puts $::report "  source=[get_property STARTPOINT_PIN $path] destination=[get_property ENDPOINT_PIN $path] slack_ns=[get_property SLACK $path] requirement_ns=[get_property REQUIREMENT $path]"
  }
  report_timing {*}$arguments -file "${label}.rpt"
}
set core_registers [get_cells -quiet -hier -filter \
  {IS_SEQUENTIAL && NAME =~ *transform_service/shared_xfft/*}]
audit_paths vendor_internal $core_registers $core_registers 5.0
set return_registers [get_cells -quiet -hier -regexp \
  {.*transform_service/result_guard/return_(valid|last|data|position|exponent)_reg(\[[0-9]+\])?$}]
audit_paths return_slot {} $return_registers 5.0
set publish [audit_one {.*transform_service/output_mailbox/request_toggle_reg$}]
audit_period $publish 5.0
audit_paths output_publication {} $publish 5.0
set output_fault [audit_one {.*transform_service/output_mailbox/input_fault_reg$}]
audit_paths output_mailbox_fault {} $output_fault 5.0
set output_payload [get_cells -quiet -hier -filter \
  {NAME =~ *transform_service/output_mailbox/* && (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1)}]
if {![llength $output_payload]} { error "output mailbox payload RAM is missing" }
set payload_control [get_pins -quiet -of_objects $output_payload \
  -filter {REF_PIN_NAME =~ WE* || REF_PIN_NAME =~ EN*}]
audit_paths output_mailbox_payload_control {} $payload_control
set fault_source [audit_one {.*transform_service/input_mailbox/input_fault_reg$}]
set fault_first [audit_one {.*transform_service/input_fault_fast_sync_reg\[0\]$}]
set fault_second [audit_one {.*transform_service/input_fault_fast_sync_reg\[1\]$}]
audit_period $fault_source 10.0
audit_period $fault_first 5.0
audit_period $fault_second 5.0
foreach flop [concat $fault_first $fault_second] {
  if {![get_property ASYNC_REG $flop]} { error "sticky fault synchronizer is not marked ASYNC_REG" }
}
audit_paths sticky_fault_crossing $fault_source $fault_first 5.0
audit_paths sticky_fault_second_stage $fault_first $fault_second 5.0
# Inspect, but never set or reload, the checkpoint's own constraints.
report_clocks -file clocks.rpt
report_exceptions -file exceptions.rpt
report_exceptions -ignored -file ignored_exceptions.rpt
report_cdc -details -file cdc.rpt
report_utilization -file utilization.rpt
report_route_status -file route_status.rpt
check_timing -verbose -file check_timing.rpt
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_sha256} {
  error "input checkpoint changed during the read-only audit"
}
puts $report "SHARED_REALTIME_ROUTED_AUDIT_FINISHED hardware_qualified=false"
close $report
puts "SHARED_REALTIME_ROUTED_AUDIT_FINISHED hardware_qualified=false"
close_design
