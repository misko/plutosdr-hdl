# Runs after INIT_DESIGN, before placement, ONLY for the opt-in paired build.
# This is a structural/constraint gate, NOT a placement/route/timing pass.
source [file join [file dirname [info script]] starlink_pss_build_options.tcl]
set pss_gate_options [pss_resolve_build_options [array get ::env]]
if {![info exists ::env(STARLINK_PSS_SHARED_XFFT)] ||
    $::env(STARLINK_PSS_SHARED_XFFT) ne "1"} {
  error "shared-XFFT implementation gate requires explicit opt-in"
}
set realtime_xfft [dict get $pss_gate_options realtime_xfft]
set boundary_stop [dict get $pss_gate_options boundary_stop]
proc pss_shared_one {pattern} {
  set cells [get_cells -quiet -hier -regexp $pattern]
  if {[llength $cells] != 1} { error "shared-XFFT expected one endpoint: $pattern got [llength $cells]" }
  return $cells
}
proc pss_shared_period {cells expected} {
  set clocks [get_clocks -quiet -of_objects \
    [get_pins -of_objects $cells -filter {REF_PIN_NAME == C}]]
  if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - $expected) > 0.001} {
    error "shared-XFFT wrong actual register clock: $cells expected $expected ns clocks=$clocks"
  }
}
set gate_report [open shared_xfft_init_gate.txt w]
puts $gate_report "scope=complete_receiver_structure_and_constraints_ONLY_not_fit_or_timing"
pss_shared_one {.*transform_service/shared_xfft$}
pss_shared_one {.*starlink_pss_tracker/inst$}
pss_shared_one {.*starlink_pilot_capture/inst$}
pss_shared_one {.*starlink_pilot_dma/inst$}
set cores [get_cells -quiet -hier -filter \
  {REF_NAME =~ *starlink_pss_fft512_bfp18* || ORIG_REF_NAME =~ *starlink_pss_fft512_bfp18*}]
if {[llength $cores] != 1} { error "shared-XFFT expected exactly one generated transform core" }
set is_realtime_core [string match *starlink_pss_fft512_bfp18_rt_candidate* \
  "[get_property REF_NAME $cores] [get_property ORIG_REF_NAME $cores]"]
if {$is_realtime_core != $realtime_xfft} {
  error "shared-XFFT generated core does not match explicit realtime selector"
}
puts $gate_report "realtime_xfft=$realtime_xfft generated_core=[get_property REF_NAME $cores]"
puts $gate_report "generated_cores=1 coarse_and_fine_and_pilot_dma_present=1"
# Look for surviving state from BOTH halves of the stop protocol, not an
# invented fixed flop count or merely the environment/BD parameter. These
# ordinary 100 MHz registers remain timed; this adds no exception or waiver.
foreach {role pattern} {
  stop_controller {.*starlink_pss_acquisition/inst/phase_map_control/stop_(staged|active|accepted_ticket|terminal_valid|terminal_generation)_reg(\[[0-9]+\])?$}
  stop_map_fence {.*starlink_pss_acquisition/inst/acquisition/phase_map/stop_(pending|done|complete|failed)_reg$}
} {
  set state [get_cells -quiet -hier -regexp $pattern]
  if {$boundary_stop} {
    if {![llength $state]} { error "boundary-stop missing synthesized $role state" }
    pss_shared_period $state 10.0
  } elseif {[llength $state]} {
    error "boundary-stop disabled but synthesized $role state is present"
  }
  puts $gate_report "$role boundary_stop=$boundary_stop surviving_registers=[llength $state]"
}
set mailbox_reset_chains [get_cells -quiet -hier -regexp \
  {.*transform_service/(input_mailbox|output_mailbox)/.*reset.*sync_reg\[[01]\]$}]
if {[llength $mailbox_reset_chains]} {
  error "shared-XFFT mailboxes must consume the common reset-release pair"
}
set common_reset_chains [get_cells -quiet -hier -regexp \
  {.*transform_service/(slow_reset_fast_sync|fast_reset_fast_sync|slow_reset_slow_sync|fast_reset_slow_sync)_reg\[[01]\]$}]
if {[llength $common_reset_chains] != 8} {
  error "shared-XFFT requires exactly four two-flop common reset-release chains"
}
puts $gate_report "mailbox_local_reset_flops=0 common_service_reset_flops=8"
set pilot_pacer [get_cells -quiet -hier -filter \
  {NAME =~ */starlink_pilot_capture/inst/ddc/pacer_memory/* && \
   (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1)}]
if {[llength $pilot_pacer] != 1 || [get_property REF_NAME $pilot_pacer] ne "RAMB18E1"} {
  error "shared receiver pilot pacer must use exactly one RAMB18, not LUTRAM"
}
puts $gate_report "pilot_pacer_ramb18=1"
foreach {box launch capture source_period destination_period requirement} {
  input_mailbox request_toggle_reg request_sync_reg 10.0 5.0 5.0
  input_mailbox acknowledge_toggle_reg acknowledge_sync_reg 5.0 10.0 10.0
  output_mailbox request_toggle_reg request_sync_reg 5.0 10.0 10.0
  output_mailbox acknowledge_toggle_reg acknowledge_sync_reg 10.0 5.0 5.0
  {} fast_fault_reg fast_fault_sync_reg 5.0 10.0 10.0
} {
  set prefix {.*transform_service/}
  if {$box ne ""} { append prefix "$box/" }
  set start [pss_shared_one "${prefix}${launch}\$"]
  set stop [pss_shared_one [format {%s%s\[0\]$} $prefix $capture]]
  pss_shared_period $start $source_period
  pss_shared_period $stop $destination_period
  set path [get_timing_paths -quiet -from $start -to $stop -max_paths 1]
  if {[llength $path] != 1 || abs([get_property REQUIREMENT $path] - $requirement) > 0.001} {
    error "shared-XFFT missing required ownership/fault timing path: $box/$capture"
  }
  puts $gate_report "$box/$capture source_ns=$source_period destination_ns=$destination_period requirement_ns=[get_property REQUIREMENT $path]"
}
foreach {box source_period destination_period requirement nominal_width} {
  input_mailbox 10.0 5.0 10.0 70
  output_mailbox 5.0 10.0 20.0 75
} {
  set source [get_cells -quiet -hier -regexp \
    [format {.*transform_service/%s/metadata_in_hold_reg\[[0-9]+\]$} $box]]
  set destination [get_cells -quiet -hier -regexp \
    [format {.*transform_service/%s/metadata_out_hold_reg\[[0-9]+\]$} $box]]
  if {![llength $source] || ![llength $destination]} { error "shared-XFFT missing metadata bus" }
  pss_shared_period $source $source_period
  pss_shared_period $destination $destination_period
  set paths [get_timing_paths -quiet -from $source -to $destination -max_paths $nominal_width -nworst 1]
  if {[llength $paths] != [llength $destination]} {
    error "shared-XFFT metadata endpoint not timed: $box paths=[llength $paths] endpoints=[llength $destination]"
  }
  foreach path $paths {
    if {abs([get_property REQUIREMENT $path] - $requirement) > 0.001} {
      error "shared-XFFT wrong held-metadata timing requirement: $box"
    }
  }
  puts $gate_report "$box nominal_metadata_bits=$nominal_width surviving_source_bits=[llength $source] surviving_destination_bits=[llength $destination] requirement_ns=$requirement"
}
if {$realtime_xfft} {
  set source [pss_shared_one {.*transform_service/input_mailbox/input_fault_reg$}]
  set first [pss_shared_one {.*transform_service/input_fault_fast_sync_reg\[0\]$}]
  set second [pss_shared_one {.*transform_service/input_fault_fast_sync_reg\[1\]$}]
  pss_shared_period $source 10.0
  pss_shared_period $first 5.0
  pss_shared_period $second 5.0
  foreach flop [concat $first $second] {
    if {![get_property ASYNC_REG $flop]} {
      error "realtime-XFFT sticky source fault requires marked two-flop synchronization"
    }
  }
  foreach {launch capture scope} [list $source $first crossing $first $second second_stage] {
    set path [get_timing_paths -quiet -from $launch -to $capture -max_paths 1]
    if {[llength $path] != 1 || abs([get_property REQUIREMENT $path] - 5.0) > 0.001} {
      error "realtime-XFFT missing or waived source fault $scope timing path"
    }
    puts $gate_report "input_fault_fast_sync/$scope requirement_ns=[get_property REQUIREMENT $path]"
  }
} elseif {[llength [get_cells -quiet -hier -regexp \
    {.*transform_service/input_fault_fast_sync_reg\[[01]\]$}]]} {
  error "nonrealtime receiver unexpectedly contains realtime source-fault synchronization"
}
puts $gate_report "SHARED_XFFT_INIT_GATE_PASS receiver_fit_and_timing_unqualified=1"
close $gate_report
report_clocks -file shared_xfft_init_clocks.rpt
report_cdc -details -file shared_xfft_init_cdc.rpt
report_exceptions -file shared_xfft_init_exceptions.rpt
report_exceptions -ignored -file shared_xfft_init_ignored_exceptions.rpt
puts "SHARED_XFFT_INIT_GATE_PASS receiver_fit_and_timing_unqualified=1"
