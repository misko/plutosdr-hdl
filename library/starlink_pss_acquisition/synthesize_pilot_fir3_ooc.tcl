# Experimental pilot FIR/DDC standalone resource/timing investigation.
# Core register-to-register routed timing is gated. OOC ports have no placement
# contract: their reported timing is NOT qualified by this experiment.
if {$argc < 1 || $argc > 2} { error "expected output directory and optional pilot-ddc selector" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set top starlink_pilot_fir3
set source_files {starlink_pilot_fir3.v}
set identity_files {starlink_pilot_fir3.v pilot_fir3_q17.mem starlink_pss_x2_ddc_ooc.xdc}
set dsp_budget 8
set bram_budget 4
set lut_budget 1800
set register_budget 2000
if {$argc == 2} {
  if {[lindex $argv 1] ne "pilot-ddc"} { error "unknown core selector" }
  set top starlink_pilot_ddc
  lappend source_files starlink_pilot_halfband2.v starlink_pilot_ddc.v
  lappend identity_files starlink_pilot_halfband2.v starlink_pilot_ddc.v \
      pilot_halfband2_q17.mem pilot_mixer_q16.mem
  set dsp_budget 14
  set bram_budget 5
  set lut_budget 3200
  set register_budget 3200
}
file mkdir $output_dir
cd $script_dir
foreach source_file $source_files { read_verilog [file join $script_dir $source_file] }
# The input/output timing budget is identical to the existing acquisition DDC.
read_xdc [file join $script_dir starlink_pss_x2_ddc_ooc.xdc]
synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high -top $top -part xc7z010clg400-1
opt_design -directive ExploreArea
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

write_checkpoint -force [file join $output_dir "${top}_routed.dcp"]
set utilization [report_utilization -return_string]
set timing [report_timing_summary -delay_type min_max -max_paths 20 -return_string]
set methodology [report_methodology -return_string]
set clocks [check_timing -verbose -return_string]
set routing [report_route_status -return_string]
foreach {name contents} [list utilization $utilization timing $timing \
    methodology $methodology check_timing $clocks route_status $routing] {
  set channel [open [file join $output_dir "$name.rpt"] w]
  puts -nonewline $channel $contents
  close $channel
}
foreach {label pattern} {
  luts {\| Slice LUTs\*? +\| +([0-9]+) +\|}
  registers {\| Slice Registers +\| +([0-9]+) +\|}
} {
  if {![regexp $pattern $utilization unused value]} { error "cannot parse $label" }
  set $label $value
}
set dsps [llength [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
set bram18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
set bram36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set registers_for_timing [all_registers]
set setup [get_timing_paths -quiet -from $registers_for_timing \
    -to $registers_for_timing -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -from $registers_for_timing \
    -to $registers_for_timing -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing constrained path" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set channel [open [file join $output_dir summary.txt] w]
puts $channel "scope=standalone_routed_register_to_register_NOT_IO_or_full_receiver_fit"
puts $channel "top=$top"
puts $channel "vivado_version=[version -short]"
puts $channel "part=xc7z010clg400-1"
puts $channel "clock_period_ns=10.000"
puts $channel "luts=$luts"
puts $channel "registers=$registers"
puts $channel "dsp48e1=$dsps"
puts $channel "bram18=$bram18"
puts $channel "bram36=$bram36"
puts $channel "setup_wns_ns=$wns"
puts $channel "hold_whs_ns=$whs"
puts $channel "boundary_timing_qualified=false"
puts $channel "whole_design_hold_whs_ns=[get_property SLACK [get_timing_paths -quiet -delay_type min -max_paths 1]]"
foreach source_file $identity_files {
  puts $channel "source_sha256=[exec sha256sum [file join $script_dir $source_file]]"
}
close $channel
if {$dsps != $dsp_budget || $bram36 + 0.5 * $bram18 > $bram_budget ||
    $luts > $lut_budget || $registers > $register_budget} {
  error "resource budget exceeded: DSP=$dsps BRAM18=$bram18 BRAM36=$bram36 LUT=$luts FF=$registers"
}
if {$wns < 0 || $whs < 0} { error "routed timing failed: WNS=$wns WHS=$whs" }
# Reject every methodology warning other than the explicitly unqualified OOC
# boundary hold paths. TIMING-15 on any internal path still fails via WHS.
foreach violation [get_methodology_violations -quiet] {
  if {![regexp {^TIMING-15#[0-9]+$} $violation]} {
    error "unexpected methodology violation: $violation"
  }
}
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} $clocks]} {
  error "check_timing gate failed; inspect check_timing.rpt"
}
if {![regexp {# of nets with routing errors[. ]+: +0} $routing]} {
  error "routing gate failed; inspect route_status.rpt"
}
set channel [open [file join $output_dir summary.txt] a]
puts $channel "internal_ooc_gate=pass"
close $channel
puts "STARLINK_PILOT_INTERNAL_OOC_PASS TOP=$top LUT=$luts FF=$registers DSP=$dsps BRAM36=$bram36 BRAM18=$bram18 WNS=$wns WHS=$whs IO_AND_FULL_RECEIVER_UNQUALIFIED"
close_design
