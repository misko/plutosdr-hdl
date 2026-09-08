# Runs after INIT_DESIGN, before placement, ONLY for the opt-in paired build.
# This is a structural/constraint gate, NOT a placement/route/timing pass.
if {![info exists ::env(STARLINK_PSS_SHARED_XFFT)] ||
    $::env(STARLINK_PSS_SHARED_XFFT) ne "1"} {
  error "shared-XFFT implementation gate requires explicit opt-in"
}
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
puts $gate_report "generated_cores=1 coarse_and_fine_and_pilot_dma_present=1"
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
puts $gate_report "SHARED_XFFT_INIT_GATE_PASS receiver_fit_and_timing_unqualified=1"
close $gate_report
report_clocks -file shared_xfft_init_clocks.rpt
report_cdc -details -file shared_xfft_init_cdc.rpt
report_exceptions -file shared_xfft_init_exceptions.rpt
report_exceptions -ignored -file shared_xfft_init_ignored_exceptions.rpt
puts "SHARED_XFFT_INIT_GATE_PASS receiver_fit_and_timing_unqualified=1"
