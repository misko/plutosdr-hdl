# Vivado 2022.2 OOC resource/timing gate for the 30-to-15 MS/s DDC.

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [file join $script_dir starlink_pss_x2_ddc.v]
read_xdc [file join $script_dir starlink_pss_x2_ddc_ooc.xdc]
synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high \
  -top starlink_pss_x2_ddc \
  -part xc7z010clg400-1
opt_design -directive ExploreArea

write_checkpoint -force [file join $output_dir starlink_pss_x2_ddc_opt.dcp]
set utilization_report [report_utilization -return_string]
set timing_report [report_timing_summary -delay_type max -max_paths 30 -return_string]
foreach {name contents} [list \
    starlink_pss_x2_ddc_utilization_opt.rpt $utilization_report \
    starlink_pss_x2_ddc_timing_opt.rpt $timing_report] {
  set channel [open [file join $output_dir $name] w]
  puts -nonewline $channel $contents
  close $channel
}

set methodology_report [report_methodology -return_string]
set channel [open [file join $output_dir starlink_pss_x2_ddc_methodology_opt.rpt] w]
puts -nonewline $channel $methodology_report
close $channel
if {![regexp {Violations found: +([0-9]+)} \
      $methodology_report unused methodology_violation_count]} {
  error "could not parse methodology violation count"
}
if {$methodology_violation_count != 0} {
  error "methodology violations are not allowed: $methodology_violation_count"
}

set check_timing_report [check_timing -verbose -return_string]
set channel [open [file join $output_dir starlink_pss_x2_ddc_check_timing.rpt] w]
puts -nonewline $channel $check_timing_report
close $channel
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $check_timing_report unused unexpected_count]} {
  error "a check_timing category is nonzero: $unexpected_count"
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] != 1} {
  error "no constrained maximum-delay path exists"
}
set setup_wns [get_property SLACK $setup_path]
if {$setup_wns < 0.0} {
  error "100 MHz post-opt setup timing failed with WNS $setup_wns ns"
}

set dsp_cells [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
set bram_cells [get_cells -quiet -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]
if {[llength $dsp_cells] != 8} {
  error "x2 DDC must retain exactly eight DSP48E1 cells, got [llength $dsp_cells]"
}
if {[llength $bram_cells] != 0} {
  error "x2 DDC unexpectedly uses block RAM: [llength $bram_cells]"
}

foreach {label pattern} {
  slice_luts {\| Slice LUTs\* +\| +([0-9]+) +\|}
  slice_registers {\| Slice Registers +\| +([0-9]+) +\|}
} {
  if {![regexp $pattern $utilization_report unused value]} {
    error "could not parse $label"
  }
  set $label $value
}
if {$slice_luts > 900 || $slice_registers > 1100} {
  error "x2 DDC budget exceeded: LUT=$slice_luts FF=$slice_registers"
}

set summary [open [file join $output_dir starlink_pss_x2_ddc_ooc_summary.txt] w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "clock_period_ns=10.000"
puts $summary "timing_scope=post_opt_unplaced_max_delay_only"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_nonzero_categories=0"
puts $summary "slice_luts=$slice_luts"
puts $summary "slice_registers=$slice_registers"
puts $summary "block_ram_primitives=[llength $bram_cells]"
puts $summary "dsp48e1=[llength $dsp_cells]"
close $summary

puts "STARLINK_PSS_X2_DDC_OOC_PASS setup_wns_ns=$setup_wns slice_luts=$slice_luts slice_registers=$slice_registers block_ram_primitives=[llength $bram_cells] dsp48e1=[llength $dsp_cells]"
close_design
