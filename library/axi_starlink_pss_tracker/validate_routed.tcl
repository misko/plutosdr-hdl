# Validate the experimental Stage-15 tracker in a routed Pluto checkpoint.
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

set tracker_glob "*starlink_pss_tracker/inst"
set tracker_cell [get_cells -quiet -hier -filter "NAME =~ ${tracker_glob}"]
if {[llength $tracker_cell] != 1} {
  error "expected one Stage-15 tracker hierarchy, got [llength $tracker_cell]"
}

proc tracker_cells {tracker_glob suffix} {
  return [get_cells -quiet -hier -filter "NAME =~ ${tracker_glob}/${suffix}"]
}

foreach {label suffix expected} {
  control_reset_synchronizers "control_reset_sync_reg*" 2
  sample_reset_synchronizers "sample_reset_sync_reg*" 2
  sample_to_control_reset_synchronizers "sample_reset_control_sync_reg*" 2
  sample_index_source "sample_index_gray_reg*" 64
  sample_index_synchronizers "sample_index_gray_sync_*_reg*" 128
  telemetry_request_synchronizers "telemetry_request_sync_reg*" 2
  telemetry_ack_synchronizers "telemetry_ack_sync_reg*" 2
  telemetry_payload_source "telemetry_sample_payload_reg*" 448
  telemetry_payload_synchronizers "telemetry_payload_sync_*_reg*" 896
  telemetry_snapshot_registers "telemetry_snapshot_reg*" 448
  candidate_status_synchronizers "candidate_pending_sync_reg*" 2
  capture_status_synchronizers "capture_active_sync_reg*" 2
  candidate_pointer_synchronizers
    "i_core/i_raw_tracking_core/i_candidate_scheduler/i_command_fifo/*_sync_*_reg*" 16
  capture_pointer_synchronizers
    "i_core/i_raw_tracking_core/i_capture_bridge/i_descriptor_fifo/*_sync_*_reg*" 12
  capture_release_synchronizers
    "i_core/i_raw_tracking_core/i_capture_bridge/sample_release_toggle_sync_*_reg*" 4
  capture_descriptor_registers
    "i_core/i_raw_tracking_core/i_capture_bridge/i_descriptor_fifo/read_data_reg*" 161
} {
  set cells [tracker_cells $tracker_glob $suffix]
  if {[llength $cells] != $expected} {
    error "expected $expected $label, got [llength $cells]"
  }
  if {[string match "*synchronizers" $label]} {
    foreach cell $cells {
      if {![get_property ASYNC_REG $cell]} {
        error "missing ASYNC_REG on $cell"
      }
    }
  }
}

# The telemetry mailbox uses a stable bundled-data payload: exactly 448 source
# bits feed an ASYNC_REG two-stage destination bank, then a separate immutable
# snapshot.  Only the source-to-first-stage arc is cut; the second stage and
# snapshot remain ordinarily timed in the AXI domain.
set telemetry_payload_source [tracker_cells $tracker_glob \
  "telemetry_sample_payload_reg*"]
set telemetry_payload_sync_1 [tracker_cells $tracker_glob \
  "telemetry_payload_sync_1_reg*"]
set telemetry_payload_sync_2 [tracker_cells $tracker_glob \
  "telemetry_payload_sync_2_reg*"]
set telemetry_snapshot [tracker_cells $tracker_glob "telemetry_snapshot_reg*"]
set telemetry_sync_1_d [get_pins -quiet -of_objects $telemetry_payload_sync_1 \
  -filter {REF_PIN_NAME == D}]
set telemetry_sync_2_d [get_pins -quiet -of_objects $telemetry_payload_sync_2 \
  -filter {REF_PIN_NAME == D}]
set telemetry_snapshot_d [get_pins -quiet -of_objects $telemetry_snapshot \
  -filter {REF_PIN_NAME == D}]
if {[llength $telemetry_sync_1_d] != 448 ||
    [llength $telemetry_sync_2_d] != 448 ||
    [llength $telemetry_snapshot_d] != 448} {
  error "telemetry payload timing objects are incomplete"
}
set telemetry_first_path [get_timing_paths -quiet -delay_type max \
  -max_paths 1 -from $telemetry_payload_source -to $telemetry_sync_1_d]
set telemetry_second_path [get_timing_paths -quiet -delay_type max \
  -max_paths 1 -from $telemetry_payload_sync_1 -to $telemetry_sync_2_d]
set telemetry_snapshot_path [get_timing_paths -quiet -delay_type max \
  -max_paths 1 -from $telemetry_payload_sync_2 -to $telemetry_snapshot_d]
if {[llength $telemetry_first_path] != 1 ||
    [get_property EXCEPTION $telemetry_first_path] ne "False Path"} {
  error "telemetry source-to-first-stage arc is not false-pathed"
}
if {[llength $telemetry_second_path] != 1 ||
    [get_property EXCEPTION $telemetry_second_path] eq "False Path" ||
    [get_property SLACK $telemetry_second_path] < 0.0} {
  error "telemetry first-to-second-stage arc is not safely timed"
}
if {[llength $telemetry_snapshot_path] != 1 ||
    [get_property EXCEPTION $telemetry_snapshot_path] eq "False Path" ||
    [get_property SLACK $telemetry_snapshot_path] < 0.0} {
  error "telemetry second-stage-to-snapshot arc is not safely timed"
}

# The distributed descriptor RAM is bundled data.  Its RAM-write-clock data
# path must be false-pathed after ownership crosses, while the same-clock read
# address path to the very same D pins must remain ordinarily timed.
set descriptor_registers [tracker_cells $tracker_glob \
  "i_core/i_raw_tracking_core/i_capture_bridge/i_descriptor_fifo/read_data_reg*"]
set descriptor_d_pins [get_pins -quiet -of_objects $descriptor_registers \
  -filter {REF_PIN_NAME == D}]
set descriptor_payload_memory [tracker_cells $tracker_glob \
  "i_core/i_raw_tracking_core/i_capture_bridge/i_descriptor_fifo/payload_memory_reg*"]
set descriptor_read_address [tracker_cells $tracker_glob \
  "i_core/i_raw_tracking_core/i_capture_bridge/i_descriptor_fifo/read_binary_reg*"]
if {[llength $descriptor_d_pins] != 161 ||
    [llength $descriptor_payload_memory] == 0 ||
    [llength $descriptor_read_address] == 0} {
  error "capture descriptor timing objects are incomplete"
}
set descriptor_payload_path [get_timing_paths -quiet -delay_type max \
  -max_paths 1 -from $descriptor_payload_memory -to $descriptor_d_pins]
if {[llength $descriptor_payload_path] != 1 ||
    [get_property EXCEPTION $descriptor_payload_path] ne "False Path"} {
  error "capture descriptor bundled-data RAM arc is not false-pathed"
}
set descriptor_address_path [get_timing_paths -quiet -delay_type max \
  -max_paths 1 -from $descriptor_read_address -to $descriptor_d_pins]
if {[llength $descriptor_address_path] != 1 ||
    [get_property EXCEPTION $descriptor_address_path] eq "False Path" ||
    [get_property SLACK $descriptor_address_path] < 0.0} {
  error "capture descriptor same-clock read-address arc is not safely timed"
}

set tracker_dsps [get_cells -quiet -hier -filter \
  "NAME =~ ${tracker_glob}/* && REF_NAME == DSP48E1"]
set tracker_ramb18 [get_cells -quiet -hier -filter \
  "NAME =~ ${tracker_glob}/* && REF_NAME == RAMB18E1"]
set tracker_ramb36 [get_cells -quiet -hier -filter \
  "NAME =~ ${tracker_glob}/* && REF_NAME == RAMB36E1"]
if {[llength $tracker_dsps] != 3} {
  error "expected exactly three tracker DSP48E1 cells, got [llength $tracker_dsps]"
}
if {[llength $tracker_ramb18] != 3 || [llength $tracker_ramb36] != 4} {
  error "expected tracker RAMB18/RAMB36 counts 3/4, got [llength $tracker_ramb18]/[llength $tracker_ramb36]"
}

set tx_dma_cells [get_cells -quiet -hier -filter \
  {NAME =~ *axi_ad9361_dac_dma*}]
if {[llength $tx_dma_cells] != 0} {
  error "RX-only shell unexpectedly contains a TX DMA hierarchy"
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
  error "routed setup or hold path is missing"
}
set setup_wns [get_property SLACK $setup_path]
set hold_whs [get_property SLACK $hold_path]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
  error "routed timing failed: setup WNS $setup_wns ns, hold WHS $hold_whs ns"
}

report_timing_summary -delay_type min_max -max_paths 30 \
  -file [file join $report_dir starlink_pss_tracker_timing.rpt]
set tracker_bus_skew [report_bus_skew -warn_on_violation \
  -cells $tracker_cell -return_string]
set bus_skew_file [open \
  [file join $report_dir starlink_pss_tracker_bus_skew.rpt] w]
puts -nonewline $bus_skew_file $tracker_bus_skew
close $bus_skew_file
set bus_skew_violated [regexp -all {Slack \(VIOLATED\)} $tracker_bus_skew]
set bus_skew_met [regexp -all {Slack \(MET\)} $tracker_bus_skew]
if {$bus_skew_violated != 0 || $bus_skew_met != 2} {
  error "expected two met tracker bus-skew constraints, got met=$bus_skew_met violated=$bus_skew_violated"
}

set cdc_path [file join $report_dir starlink_pss_tracker_cdc.rpt]
report_cdc -details -file $cdc_path
set cdc_file [open $cdc_path r]
set cdc_report [read $cdc_file]
close $cdc_file
set tracker_critical_cdc [regexp -all -line \
  {CDC-[0-9]+[ \t]+Critical.*starlink_pss_tracker} $cdc_report]
if {$tracker_critical_cdc != 0} {
  error "tracker introduced $tracker_critical_cdc Critical CDC rows"
}

set route_report [report_route_status -return_string]
set route_file [open \
  [file join $report_dir starlink_pss_tracker_route_status.rpt] w]
puts -nonewline $route_file $route_report
close $route_file
if {![regexp {# of nets with routing errors\.*[ \t]*:[ \t]*0[ \t]*:} \
    $route_report]} {
  error "routed design contains routing errors"
}

set utilization [report_utilization -return_string]
set utilization_file [open \
  [file join $report_dir starlink_pss_tracker_utilization.rpt] w]
puts -nonewline $utilization_file $utilization
close $utilization_file

set summary [open \
  [file join $report_dir starlink_pss_tracker_routed_summary.txt] w]
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "hold_whs_ns=$hold_whs"
puts $summary "tracker_dsp48e1=[llength $tracker_dsps]"
puts $summary "tracker_ramb18e1=[llength $tracker_ramb18]"
puts $summary "tracker_ramb36e1=[llength $tracker_ramb36]"
puts $summary "tracker_bus_skew_met=$bus_skew_met"
puts $summary "tracker_bus_skew_violated=$bus_skew_violated"
puts $summary "tracker_critical_cdc_rows=$tracker_critical_cdc"
puts $summary "tx_dma_hierarchies=[llength $tx_dma_cells]"
puts $summary "telemetry_payload_bits=[llength $telemetry_payload_source]"
puts $summary "telemetry_payload_synchronizer_bits=[expr {[llength $telemetry_payload_sync_1] + [llength $telemetry_payload_sync_2]}]"
puts $summary "telemetry_snapshot_bits=[llength $telemetry_snapshot]"
close $summary

puts "STARLINK_PSS_TRACKER_ROUTED_PASS setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs dsp48e1=[llength $tracker_dsps] ramb18e1=[llength $tracker_ramb18] ramb36e1=[llength $tracker_ramb36]"
close_design
