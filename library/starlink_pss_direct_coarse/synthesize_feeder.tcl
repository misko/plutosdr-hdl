# Bounded feeder+MAC cost measurement. All negative evidence is retained.
if {$argc != 1} {error "usage: synthesize_feeder.tcl OUTPUT"}
if {[version -short] ne "2022.2"} {error "requires Vivado 2022.2"}
set_param general.maxThreads 2
set src [file dirname [file normalize [info script]]]
set out [file normalize [lindex $argv 0]]
file mkdir $out
read_verilog [file join $src starlink_pss_direct_mac6.v]
read_verilog [file join $src starlink_pss_direct_feeder.v]
read_xdc [file join $src slice.xdc]
synth_design -mode out_of_context -top starlink_pss_direct_feeder -part xc7z010clg400-1 \
  -generic [list COEFFICIENT_FILE=[file join $src direct_groups_q15.mem]]
opt_design
report_utilization -hierarchical -file [file join $out utilization_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -file [file join $out timing_synth.rpt]
place_design
route_design
report_utilization -hierarchical -file [file join $out utilization_hierarchy.rpt]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -file [file join $out timing.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_control_sets -verbose -file [file join $out control_sets.rpt]
write_checkpoint -force [file join $out feeder_routed.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set dsp [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram18 [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set bram36 [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
set fp [open [file join $out summary.txt] w]
puts $fp "scope=isolated_history_feeder_plus_mac_post_route"
puts $fp "clock_mhz=200"
puts $fp "setup_wns_ns=$setup"
puts $fp "hold_whs_ns=$hold"
puts $fp "dsp48e1=$dsp"
puts $fp "ramb18=$bram18"
puts $fp "ramb36=$bram36"
close $fp
if {$dsp != 18 || $bram18 + 2*$bram36 != 8} {error "unexpected DSP/history RAM inference"}
if {$setup < 0 || $hold < 0} {error "isolated timing failed: setup=$setup hold=$hold"}
