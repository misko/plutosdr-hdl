# Read-only inventory of a complete-coarse OOC checkpoint with its OWN clocks.
# No applied constraints, implementation, timing pass or receiver qualification.
if {$argc != 3} { error "expected CHECKPOINT EXPECTED_SHA256 NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set expected_hash [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {![regexp {^[0-9a-f]{64}$} $expected_hash]} { error "invalid expected checkpoint hash" }
if {![file isfile $checkpoint]} { error "missing checkpoint" }
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint hash mismatch" }
if {[file exists $output_dir]} { error "refusing to overwrite bank CDC evidence" }
file mkdir $output_dir
file copy [info script] [file join $output_dir audit_source.tcl]
open_checkpoint $checkpoint
proc bank_one {pattern} {
  set cells [get_cells -quiet -hier -regexp $pattern]
  if {[llength $cells] != 1} { error "bank audit expected one endpoint: $pattern got [llength $cells]" }
  return $cells
}
proc bank_clock {cell expected} {
  set clock [get_clocks -quiet -of_objects [get_pins -of_objects $cell -filter {REF_PIN_NAME == C}]]
  if {[llength $clock] != 1 || abs([get_property PERIOD $clock] - $expected) > 0.001} {
    error "bank audit unexpected actual register clock: $cell expected $expected got $clock"
  }
  return $clock
}
proc bank_path {channel label source destination source_period destination_period} {
  set source_clock [bank_clock $source $source_period]
  set destination_clock [bank_clock $destination $destination_period]
  set path [get_timing_paths -quiet -from $source -to $destination -max_paths 1]
  if {[llength $path] != 1} { error "bank audit missing timed path: $label $source -> $destination" }
  puts $channel "$label source=$source destination=$destination launch_clock=$source_clock capture_clock=$destination_clock requirement_ns=[get_property REQUIREMENT $path] slack_ns=[get_property SLACK $path]"
}
bank_one {^island/source_bank$}
bank_one {^island/product_bank$}
bank_one {^island/output_bank$}
set channel [open [file join $output_dir endpoints.txt] w]
puts $channel "scope=read_only_complete_coarse_OOC_bank_CDC_inventory_saved_constraints_only"
puts $channel "checkpoint=$checkpoint sha256=$expected_hash"
puts $channel "physical_receiver_CDC_timing_qualified=false no_constraints_applied=true"
set chains 0
foreach {box source_period destination_period nominal_bits} {
  source_bank 10.0 5.714 70
  product_bank 5.714 5.714 70
  output_bank 5.714 10.0 75
} {
  foreach {launch capture launch_period capture_period} [list \
    request_toggle_reg request_sync_reg $source_period $destination_period \
    acknowledge_toggle_reg acknowledge_sync_reg $destination_period $source_period] {
    set prefix "island/$box/"
    set source [bank_one "^${prefix}${launch}\$"]
    set first [bank_one [format {^%s%s\[0\]$} $prefix $capture]]
    set second [bank_one [format {^%s%s\[1\]$} $prefix $capture]]
    foreach flop [list $first $second] {
      if {![get_property ASYNC_REG $flop]} { error "unmarked bank ownership synchronizer: $flop" }
    }
    bank_path $channel "$box/$capture/first" $source $first $launch_period $capture_period
    bank_path $channel "$box/$capture/second" $first $second $capture_period $capture_period
    incr chains
  }
  set source [get_cells -quiet -hier -regexp [format {^island/%s/metadata_in_hold_reg\[[0-9]+\]$} $box]]
  set destination [get_cells -quiet -hier -regexp [format {^island/%s/metadata_out_hold_reg\[[0-9]+\]$} $box]]
  if {![llength $source] || ![llength $destination] || [llength $source] > $nominal_bits ||
      [llength $destination] > $nominal_bits} { error "missing/oversized bank held metadata: $box" }
  bank_clock $source $source_period
  bank_clock $destination $destination_period
  # Check each surviving destination, not a single aggregate path which can
  # hide a waived bit. Constant optimized fields are reported, not invented FFs.
  foreach capture $destination {
    bank_path $channel "$box/metadata" $source $capture $source_period $destination_period
  }
  puts $channel "$box nominal_metadata_bits=$nominal_bits surviving_source_bits=[llength $source] surviving_destination_bits=[llength $destination]"
  set memories [get_cells -quiet -hier -filter \
    "NAME =~ island/$box/payload_memory* && (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1)"]
  if {![llength $memories]} { error "missing bank payload BRAM: $box" }
  foreach memory $memories {
    puts $channel "$box payload_bram=$memory primitive=[get_property REF_NAME $memory]"
    foreach pin_name {CLKARDCLK CLKBWRCLK} {
      set pin [get_pins -quiet $memory/$pin_name]
      puts $channel "$box payload_clock_pin=$pin clocks=[get_clocks -quiet -of_objects $pin]"
    }
    foreach property {READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B WRITE_MODE_A WRITE_MODE_B DOA_REG DOB_REG} {
      puts $channel "$box payload_property=$property value=[get_property $property $memory]"
    }
  }
}
foreach {source_pattern first_pattern second_pattern source_period destination_period} {
  {^island/source_bank/input_fault_reg$} {^island/source_fault_fast_reg\[0\]$} {^island/source_fault_fast_reg\[1\]$} 10.0 5.714
  {^island/fast_fault_reg$} {^island/fast_fault_slow_reg\[0\]$} {^island/fast_fault_slow_reg\[1\]$} 5.714 10.0
} {
  set source [bank_one $source_pattern]
  set first [bank_one $first_pattern]
  set second [bank_one $second_pattern]
  foreach flop [list $first $second] {
    if {![get_property ASYNC_REG $flop]} { error "unmarked bank fault synchronizer: $flop" }
  }
  bank_path $channel fault/first $source $first $source_period $destination_period
  bank_path $channel fault/second $first $second $destination_period $destination_period
  incr chains
}
foreach {name period} {slow_reset_fast 5.714 fast_reset_fast 5.714 slow_reset_slow 10.0 fast_reset_slow 10.0} {
  set first [bank_one [format {^island/%s_reg\[0\]$} $name]]
  set second [bank_one [format {^island/%s_reg\[1\]$} $name]]
  foreach flop [list $first $second] {
    if {![get_property ASYNC_REG $flop]} { error "unmarked common reset synchronizer: $flop" }
  }
  bank_path $channel "$name/second" $first $second $period $period
}
if {$chains != 8} { error "bank ownership/fault chain inventory incomplete" }
close $channel
report_clocks -file [file join $output_dir clocks.rpt]
report_cdc -details -file [file join $output_dir cdc.rpt]
report_exceptions -file [file join $output_dir exceptions.rpt]
report_exceptions -ignored -file [file join $output_dir ignored_exceptions.rpt]
report_timing_summary -report_unconstrained -delay_type min_max -max_paths 10 -file [file join $output_dir timing.rpt]
check_timing -verbose -file [file join $output_dir check_timing.rpt]
close_design
puts "BANK_CDC_INVENTORY_WRITTEN chains=8 no_constraint_changes=1 NO_PHYSICAL_OR_RECEIVER_QUALIFICATION"
