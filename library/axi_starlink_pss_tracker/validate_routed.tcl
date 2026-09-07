# Validate the experimental Stage-15 tracker in a routed Pluto checkpoint.
# Usage:
#   vivado -mode batch -source validate_routed.tcl \
#     -tclargs /path/system_top_routed.dcp /path/report-directory \
#              ?rate_msps injection_enabled?

if {$argc != 2 && $argc != 4} {
  error "expected checkpoint, report directory, and optional rate/injection mode"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set rate_msps 15
set injection_enabled 1
if {$argc == 4} {
  set rate_msps [lindex $argv 2]
  set injection_enabled [lindex $argv 3]
}
if {$rate_msps ni {15 30 60}} {
  error "rate_msps must be 15, 30, or 60"
}
if {$injection_enabled ni {0 1}} {
  error "injection_enabled must be 0 or 1"
}
if {$rate_msps != 15 && $injection_enabled} {
  error "injection is qualified only for the 15 MS/s tracker"
}
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
  telemetry_capture_active "telemetry_capture_active_reg*" 1
  telemetry_write_index "telemetry_write_index_reg*" 4
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

foreach {label suffix expected} {
  injection_arm_ack_synchronizers "i_injection_mux/arm_ack_sync_reg*" 2
  injection_completion_synchronizers "i_injection_mux/completion_sync_reg*" 2
  injection_mismatch_synchronizers "i_injection_mux/mismatch_sync_reg*" 2
  injection_active_synchronizers "i_injection_mux/sample_active_sync_reg*" 2
  injection_arm_request_synchronizers "i_injection_mux/arm_request_sync_reg*" 2
  injection_start_synchronizers "i_injection_mux/arm_start_sync_*_reg*" 128
} {
  set cells [tracker_cells $tracker_glob $suffix]
  set mode_expected [expr {$injection_enabled ? $expected : 0}]
  if {[llength $cells] != $mode_expected} {
    error "expected $mode_expected $label, got [llength $cells]"
  }
  foreach cell $cells {
    if {![get_property ASYNC_REG $cell]} {
      error "missing ASYNC_REG on $cell"
    }
  }
}

# Telemetry crosses only request/acknowledge toggles.  Fourteen counters are
# written sequentially into one true dual-clock RAM after the scheduler is
# idle, and the AXI side cannot read it until acknowledgement.  Prove the
# intended RAM implementation and reject any accidental resurrection of the
# former 1,344-register bundled-data mailbox.
set telemetry_memory [tracker_cells $tracker_glob \
  "i_telemetry_memory/*"]
set telemetry_ramb18 [get_cells -quiet -hier -filter \
  "NAME =~ ${tracker_glob}/i_telemetry_memory/* && REF_NAME == RAMB18E1"]
set stale_telemetry_payload [tracker_cells $tracker_glob \
  "telemetry_sample_payload_reg*"]
set stale_telemetry_payload_sync [tracker_cells $tracker_glob \
  "telemetry_payload_sync_*_reg*"]
set stale_telemetry_snapshot [tracker_cells $tracker_glob \
  "telemetry_snapshot_reg*"]
if {[llength $telemetry_memory] == 0 || [llength $telemetry_ramb18] != 1} {
  error "expected one true dual-clock telemetry RAMB18E1"
}
if {[llength $stale_telemetry_payload] != 0 ||
    [llength $stale_telemetry_payload_sync] != 0 ||
    [llength $stale_telemetry_snapshot] != 0} {
  error "obsolete wide telemetry mailbox remains in the routed tracker"
}

# The injection arm mailbox follows the same stable bundled-data rule. The
# 64-bit start payload is captured only after the request toggle and
# two additional sample-domain settling clocks.
set injection_payload_source [tracker_cells $tracker_glob \
  "i_injection_mux/arm_start_mailbox_reg*"]
set injection_payload_sync_1 [tracker_cells $tracker_glob \
  "i_injection_mux/arm_start_sync_1_reg*"]
set injection_payload_sync_2 [tracker_cells $tracker_glob \
  "i_injection_mux/arm_start_sync_2_reg*"]
if {$injection_enabled} {
  set injection_sync_1_d [get_pins -quiet -of_objects $injection_payload_sync_1 \
    -filter {REF_PIN_NAME == D}]
  set injection_sync_2_d [get_pins -quiet -of_objects $injection_payload_sync_2 \
    -filter {REF_PIN_NAME == D}]
  if {[llength $injection_payload_source] < 64 ||
      [llength $injection_sync_1_d] != 64 ||
      [llength $injection_sync_2_d] != 64} {
    error "injection arm payload timing objects are incomplete: source=[llength $injection_payload_source] sync1=[llength $injection_sync_1_d] sync2=[llength $injection_sync_2_d]"
  }
  set injection_first_path [get_timing_paths -quiet -delay_type max \
    -max_paths 1 -from $injection_payload_source -to $injection_sync_1_d]
  set injection_second_path [get_timing_paths -quiet -delay_type max \
    -max_paths 1 -from $injection_payload_sync_1 -to $injection_sync_2_d]
  if {[llength $injection_first_path] != 1 ||
      [get_property EXCEPTION $injection_first_path] ne "False Path"} {
    error "injection payload source-to-first-stage arc is not false-pathed"
  }
  if {[llength $injection_second_path] != 1 ||
      [get_property EXCEPTION $injection_second_path] eq "False Path" ||
      [get_property SLACK $injection_second_path] < 0.0} {
    error "injection payload first-to-second-stage arc is not safely timed"
  }
} elseif {[llength $injection_payload_source] != 0 ||
          [llength $injection_payload_sync_1] != 0 ||
          [llength $injection_payload_sync_2] != 0} {
  error "disabled injection fixture was not removed"
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
set expected_tracker_dsps [expr {$rate_msps == 60 ? 13 : 3}]
array set expected_tracker_ramb18 {15,0 3 15,1 4 30,0 8 60,0 6}
array set expected_tracker_ramb36 {15,0 4 15,1 4 30,0 6 60,0 12}
set mode_key "$rate_msps,$injection_enabled"
if {[llength $tracker_dsps] != $expected_tracker_dsps} {
  error "expected $expected_tracker_dsps tracker DSP48E1 cells, got [llength $tracker_dsps]"
}
if {[llength $tracker_ramb18] != $expected_tracker_ramb18($mode_key) ||
    [llength $tracker_ramb36] != $expected_tracker_ramb36($mode_key)} {
  error "expected tracker RAMB18/RAMB36 counts $expected_tracker_ramb18($mode_key)/$expected_tracker_ramb36($mode_key), got [llength $tracker_ramb18]/[llength $tracker_ramb36]"
}
set injection_fixture_ramb18 [get_cells -quiet -hier -filter \
  "NAME =~ ${tracker_glob}/i_injection_mux/fixture_memory_reg* && REF_NAME == RAMB18E1"]
if {[llength $injection_fixture_ramb18] != $injection_enabled} {
  error "expected $injection_enabled dual-clock injection fixture RAMB18E1 cells, got [llength $injection_fixture_ramb18]"
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
set expected_bus_skew_met [expr {$injection_enabled ? 2 : 1}]
if {$bus_skew_violated != 0 || $bus_skew_met != $expected_bus_skew_met} {
  error "expected $expected_bus_skew_met met tracker bus-skew constraints, got met=$bus_skew_met violated=$bus_skew_violated"
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
puts $summary "rate_msps=$rate_msps"
puts $summary "injection_enabled=$injection_enabled"
puts $summary "tracker_dsp48e1=[llength $tracker_dsps]"
puts $summary "tracker_ramb18e1=[llength $tracker_ramb18]"
puts $summary "tracker_ramb36e1=[llength $tracker_ramb36]"
puts $summary "tracker_bus_skew_met=$bus_skew_met"
puts $summary "tracker_bus_skew_violated=$bus_skew_violated"
puts $summary "tracker_critical_cdc_rows=$tracker_critical_cdc"
puts $summary "tx_dma_hierarchies=[llength $tx_dma_cells]"
puts $summary "telemetry_ramb18e1=[llength $telemetry_ramb18]"
puts $summary "stale_telemetry_payload_cells=[llength $stale_telemetry_payload]"
puts $summary "stale_telemetry_payload_synchronizer_cells=[llength $stale_telemetry_payload_sync]"
puts $summary "stale_telemetry_snapshot_cells=[llength $stale_telemetry_snapshot]"
puts $summary "injection_payload_logical_bits=[expr {$injection_enabled ? 64 : 0}]"
puts $summary "injection_payload_source_cells=[llength $injection_payload_source]"
puts $summary "injection_payload_synchronizer_bits=[expr {[llength $injection_payload_sync_1] + [llength $injection_payload_sync_2]}]"
close $summary

puts "STARLINK_PSS_TRACKER_ROUTED_PASS rate_msps=$rate_msps injection_enabled=$injection_enabled setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs dsp48e1=[llength $tracker_dsps] ramb18e1=[llength $tracker_ramb18] ramb36e1=[llength $tracker_ramb36] injection_payload_logical_bits=[expr {$injection_enabled ? 64 : 0}] injection_payload_source_cells=[llength $injection_payload_source]"
close_design
