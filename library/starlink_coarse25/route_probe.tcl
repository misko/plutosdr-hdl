# Registered-boundary feasibility; never a full-board deployment gate.
set origin [file dirname [file normalize [info script]]]
if {$argc != 1} { error "usage: route_probe.tcl ABSOLUTE_ARTIFACT_DIRECTORY" }
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "refusing to overwrite route evidence" }
file mkdir $output
cd $origin
set_param general.maxThreads 2
read_verilog [file join $origin starlink_coarse25_mac.v]
read_verilog [file join $origin starlink_coarse25_mac_probe.v]
synth_design -top starlink_coarse25_mac_probe -part xc7z010clg400-1 -mode out_of_context
create_clock -name calc_clk -period 10.000 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
set_output_delay -clock calc_clk 1.000 [all_outputs]
write_checkpoint [file join $output synthesized.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint [file join $output routed.dcp]
report_utilization -hierarchical -file [file join $output utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output timing.rpt]
check_timing -verbose -file [file join $output check_timing.rpt]
report_timing -max_paths 10 -file [file join $output worst_paths.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing timing paths" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
puts "COARSE25_REGISTERED_PROBE_ONLY setup_slack=$wns hold_slack=$whs full_board_qualified=0"
if {$wns < 0 || $whs < 0} { error "registered-boundary MAC timing failed" }
