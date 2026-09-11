# Standalone registered-boundary viability experiment. Not full RX/board timing.
if {$argc != 1 || [version -short] ne "2022.2"} { error "expected Vivado2022.2 NEW_OUTPUT" }
set source_dir [file dirname [info script]]
set output [lindex $argv 0]
if {[file pathtype $output] ne "absolute" || [file exists $output]} { error "new absolute output required" }
file mkdir $output
set_param general.maxThreads 2
foreach name {starlink_pss_descriptor_commands.v descriptor_commands_timing_probe.v route_descriptor_commands.tcl} {
  file copy [file join $source_dir $name] [file join $output $name]
}
read_verilog -sv [file join $output starlink_pss_descriptor_commands.v]
read_verilog -sv [file join $output descriptor_commands_timing_probe.v]
synth_design -top descriptor_commands_timing_probe -part xc7z010clg400-1 -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 5.714 -name island_175 [get_ports clk]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint [file join $output descriptor_commands_routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $output timing.rpt]
report_timing -from [all_registers] -to [all_registers] -delay_type max -max_paths 20 -file [file join $output internal_setup.rpt]
report_timing -from [all_registers] -to [all_registers] -delay_type min -max_paths 20 -file [file join $output internal_hold.rpt]
report_route_status -file [file join $output route_status.rpt]
report_utilization -hierarchical -file [file join $output hierarchy.rpt]
check_timing -verbose -file [file join $output check_timing.rpt]
report_exceptions -file [file join $output exceptions.rpt]
write_xdc [file join $output constraints.xdc]
foreach name {starlink_pss_descriptor_commands.v descriptor_commands_timing_probe.v route_descriptor_commands.tcl} {
  if {[lindex [exec sha256sum [file join $source_dir $name]] 0] ne [lindex [exec sha256sum [file join $output $name]] 0]} { error "source changed during physical test" }
}
puts DESCRIPTOR_COMMANDS_ROUTE_RECORDED_NOT_RECEIVER_OR_BOARD_SIGNOFF
