# Read-only context inventory for global synthesis's downstream BRAM registers.
# Does not change the netlist/constraints or qualify functional/physical timing.
if {$argc != 3} { error "expected CHECKPOINT NEW_OUTPUT CHECKPOINT_SHA256" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set digest [lindex $argv 2]
if {![regexp {^[0-9a-f]{64}$} $digest] || ![file isfile $checkpoint] || [file exists $output]} {
  error "expected pinned existing checkpoint and new output"
}
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "checkpoint mismatch" }
file mkdir $output
file copy [info script] [file join $output inspection_source.tcl]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} { error "wrong receiver part" }
set report [open [file join $output context.txt] w]
puts $report "scope=global_descriptor_BRAM_context_not_functional_or_physical_qualification"
puts $report "checkpoint_sha256=$digest"
set brams [get_cells -quiet -hier -filter {
  NAME =~ */i_capture_bridge/i_descriptor_fifo/* &&
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1)}]
if {![llength $brams]} { error "no descriptor block RAM" }
foreach ram $brams {
  puts $report "RAM $ram READ_WIDTH_A=[get_property READ_WIDTH_A $ram] DOA_REG=[get_property DOA_REG $ram] DOB_REG=[get_property DOB_REG $ram]"
  foreach pin_name {CLKARDCLK CLKBWRCLK} {
    set pins [get_pins -quiet -of_objects $ram -filter "REF_PIN_NAME == $pin_name"]
    puts $report "$pin_name clocks=[get_clocks -quiet -of_objects $pins]"
  }
  report_property -all $ram -file [file join $output [file tail $ram].rpt]
  foreach pin_name {ENARDEN REGCEAREGCE RSTREGARSTREG RSTRAMARSTRAM} {
    set pins [get_pins -quiet -of_objects $ram -filter "REF_PIN_NAME == $pin_name"]
    puts $report "$pin_name nets=[get_nets -quiet -of_objects $pins]"
    foreach endpoint [all_fanin -quiet -flat -startpoints_only -to $pins] {
      puts $report "  source=$endpoint"
    }
  }
  set data_pins [get_pins -quiet -of_objects $ram -filter {DIRECTION == OUT && (REF_PIN_NAME =~ DO* || REF_PIN_NAME =~ DOP*)}]
  foreach endpoint [all_fanout -quiet -flat -endpoints_only -from $data_pins] {
    puts $report "  consumer=$endpoint"
  }
}
help write_verilog
set core [get_cells -quiet -hier -filter {NAME =~ */starlink_pss_tracker/inst/i_core}]
if {[llength $core] != 1} { error "expected one fine core" }
puts $report "fine_core=$core REF_NAME=[get_property REF_NAME $core]"
write_verilog -mode funcsim -cell $core [file join $output fine_core_netlist.v]
foreach {label pattern} {
  tracker_instance */starlink_pss_tracker/inst
  tracker_bd */starlink_pss_tracker
} {
  set cell [get_cells -quiet -hier -filter "NAME =~ $pattern"]
  if {[llength $cell] != 1} { error "expected one $label" }
  puts $report "$label=$cell REF_NAME=[get_property REF_NAME $cell]"
  set lopt [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == lopt}]
  if {[llength $lopt]} {
    set lopt_net [get_nets -quiet -of_objects $lopt]
    puts $report "$label lopt_net=$lopt_net"
    report_property -all $lopt_net -file [file join $output ${label}_lopt.rpt]
    set drivers [get_pins -quiet -of_objects $lopt_net -filter {DIRECTION == OUT}]
    puts $report "$label lopt_drivers=$drivers"
    puts $report "$label lopt_startpoints=[all_fanin -quiet -flat -startpoints_only -to $lopt]"
    set cone [all_fanin -quiet -flat -levels 1 -to $lopt]
    puts $report "$label lopt_immediate_cone=$cone"
    foreach driver_cell [get_cells -quiet -of_objects $cone -filter {IS_PRIMITIVE}] {
      report_property -all $driver_cell -file [file join $output ${label}_lopt_[file tail $driver_cell].rpt]
    }
  }
  write_verilog -mode funcsim -cell $cell [file join $output ${label}_netlist.v]
}
puts $report "exported_netlist_hashes=[exec sha256sum {*}[lsort [glob [file join $output *_netlist.v]]]]"
if {[lindex [exec sha256sum $checkpoint] 0] ne $digest} { error "checkpoint changed during inspection" }
puts $report "DESCRIPTOR_CONTEXT_INSPECTED functional_and_physical_qualified=false"
close $report
close_design
puts "DESCRIPTOR_CONTEXT_INSPECTED functional_and_physical_qualified=false"
