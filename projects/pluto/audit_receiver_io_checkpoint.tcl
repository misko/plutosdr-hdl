# Read-only receiver board-I/O and AD9361 reference-clock inventory.
# Reports saved constraints; never supplies missing external timing assumptions.
if {$argc != 3} { error "expected CHECKPOINT EXPECTED_SHA256 NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set expected_hash [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {![regexp {^[0-9a-f]{64}$} $expected_hash]} { error "invalid expected checkpoint hash" }
if {![file isfile $checkpoint]} { error "missing checkpoint" }
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint hash mismatch" }
if {[file exists $output_dir]} { error "refusing to overwrite receiver IO evidence" }
file mkdir $output_dir
file copy [info script] [file join $output_dir audit_source.tcl]
open_checkpoint $checkpoint
# A checkpoint's in-memory design name is not its HDL top-module identity.
# Require the actual receiver hierarchy and processing-system primitive instead.
if {[llength [get_cells -quiet i_system_wrapper/system_i/axi_ad9361/inst]] != 1 ||
    [llength [get_cells -quiet -hier -filter {REF_NAME == PS7}]] != 1} {
  error "expected full receiver AD9361 and PS7 hierarchy"
}
set rx_ports [get_ports -quiet -regexp {^rx_(data_in\[[0-9]+\]|frame_in)$}]
if {[llength $rx_ports] != 13} { error "expected twelve RX data ports and one frame port" }
set rx_clock [get_clocks -quiet -of_objects [get_ports rx_clk_in]]
if {[llength $rx_clock] != 1} { error "expected one actual RX input clock" }
set controllers [get_cells -quiet -hier -filter {REF_NAME == IDELAYCTRL}]
if {![llength $controllers]} { error "missing AD9361 delay reference controller" }
set channel [open [file join $output_dir endpoints.txt] w]
puts $channel "scope=read_only_full_receiver_saved_board_IO_and_delay_reference"
puts $channel "checkpoint=$checkpoint sha256=$expected_hash"
puts $channel "saved_design_name=[get_property NAME [current_design]]"
puts $channel "physical_qualified=false missing_delays_not_waived=true"
puts $channel "rx_clock=$rx_clock period_ns=[get_property PERIOD $rx_clock]"
foreach controller $controllers {
  set reference [get_pins -quiet $controller/REFCLK]
  set clocks [get_clocks -quiet -of_objects $reference]
  if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - 5.0) > 0.001} {
    error "AD9361 delay reference must retain its actual 200 MHz clock: $controller $clocks"
  }
  puts $channel "delay_controller=$controller reference_pin=$reference clock=$clocks period_ns=[get_property PERIOD $clocks]"
}
foreach port [lsort [get_ports]] {
  puts $channel "port=$port direction=[get_property DIRECTION $port] package_pin=[get_property PACKAGE_PIN $port] iostandard=[get_property IOSTANDARD $port]"
}
foreach port [lsort $rx_ports] {
  set endpoints [all_fanout -flat -endpoints_only -from $port]
  puts $channel "rx_port=$port endpoints=$endpoints"
}
close $channel
report_clocks -file [file join $output_dir clocks.rpt]
report_io -file [file join $output_dir io.rpt]
check_timing -verbose -file [file join $output_dir check_timing.rpt]
report_exceptions -file [file join $output_dir exceptions.rpt]
report_exceptions -ignored -file [file join $output_dir ignored_exceptions.rpt]
foreach delay_type {max min} {
  report_timing -from $rx_ports -delay_type $delay_type -max_paths 26 -nworst 2 \
    -path_type full_clock_expanded -file [file join $output_dir rx_${delay_type}.rpt]
}
report_timing_summary -report_unconstrained -delay_type min_max -max_paths 10 \
  -file [file join $output_dir timing.rpt]
close_design
puts "RECEIVER_IO_INVENTORY_WRITTEN rx_ports=13 reference_MHz=200 NO_CONSTRAINT_CHANGES_OR_QUALIFICATION"
