# Real AXI capture control, CI16 FIFO, detector and coherent result snapshots.
# Still an OOC boundary, not the AD9361/PS7/DDR receiver implementation.
set origin [file dirname [file normalize [info script]]]
if {$argc != 1} { error "usage: route_capture.tcl ABSOLUTE_ARTIFACT_DIRECTORY" }
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "refusing to overwrite route evidence" }
file mkdir $output
cd $origin
set_param general.maxThreads 2
foreach source {starlink_coarse25_mac.v starlink_coarse25_score.v starlink_coarse25_datapath.v starlink_coarse25_fold.v starlink_coarse25_detector.v starlink_coarse25_registers.v starlink_coarse25_capture_probe.v} {
  read_verilog [file join $origin $source]
}
read_verilog [file join $origin .. starlink_pss_acquisition starlink_pss_score_divider.v]
read_verilog [file join $origin .. axi_starlink_pss_phase_map starlink_pss_axi_lite.v]
read_verilog [file join $origin .. axi_starlink_pilot_capture axi_starlink_pilot_capture.v]
synth_design -top starlink_coarse25_capture_probe -part xc7z010clg400-1 -mode out_of_context
create_clock -name calc_clk -period 10.000 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
set_output_delay -clock calc_clk 1.000 [all_outputs]
write_checkpoint [file join $output synthesized.dcp]
report_utilization -hierarchical -file [file join $output synthesized_utilization.rpt]
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
puts "COARSE25_CAPTURE_OOC_ONLY setup_slack=$wns hold_slack=$whs full_board_qualified=0"
if {$wns < 0 || $whs < 0} { error "AXI capture/detector timing failed" }
