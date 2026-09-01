# Vivado 2022.2 OOC gate for the exact rational reducer milestone.
# Usage: vivado -mode batch -source synthesize_reducer_ooc.tcl -tclargs OUTPUT

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [file join $script_dir starlink_pss_exact_reducer.v]
read_xdc [file join $script_dir starlink_pss_exact_reducer_ooc.xdc]

synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high \
  -top starlink_pss_exact_reducer \
  -part xc7z010clg400-1
opt_design -directive ExploreArea

write_checkpoint -force \
  [file join $output_dir starlink_pss_exact_reducer_opt.dcp]
set utilization_report [report_utilization -return_string]
set timing_report [report_timing_summary -delay_type max -max_paths 20 -return_string]
foreach {name contents} [list \
    starlink_pss_exact_reducer_utilization_opt.rpt $utilization_report \
    starlink_pss_exact_reducer_timing_opt.rpt $timing_report] {
  set report_file [open [file join $output_dir $name] w]
  puts -nonewline $report_file $contents
  close $report_file
}

set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir starlink_pss_exact_reducer_methodology_opt.rpt] w]
puts -nonewline $methodology_file $methodology_report
close $methodology_file
if {![regexp {Violations found: +([0-9]+)} \
      $methodology_report unused methodology_violation_count]} {
  error "could not parse methodology violation count"
}
if {$methodology_violation_count != 0} {
  error "methodology violations are not allowed, got $methodology_violation_count"
}

set check_timing_report [check_timing -verbose -return_string]
set check_timing_file [open \
  [file join $output_dir starlink_pss_exact_reducer_check_timing.rpt] w]
puts -nonewline $check_timing_file $check_timing_report
close $check_timing_file
set expected_check_timing_categories [list \
  no_clock constant_clock pulse_width_clock unconstrained_internal_endpoints \
  no_input_delay no_output_delay multiple_clock generated_clocks loops \
  partial_input_delay partial_output_delay latch_loops]
foreach category $expected_check_timing_categories {
  set category_pattern [format {checking %s \(([0-9]+)\)} $category]
  if {![regexp $category_pattern $check_timing_report unused category_count]} {
    error "could not parse check_timing category $category"
  }
  if {$category_count != 0} {
    error "check_timing category $category is not clean: $category_count"
  }
}
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $check_timing_report unused unexpected_nonzero_count]} {
  error "an unexpected check_timing category is nonzero: $unexpected_nonzero_count"
}

set dsp_cells [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
if {[llength $dsp_cells] != 0} {
  error "the bit-serial reducer must infer zero DSP48E1 cells, got [llength $dsp_cells]"
}
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] != 1} {
  error "no constrained maximum-delay path exists at 100 MHz"
}
set setup_wns [get_property SLACK $setup_path]
if {$setup_wns < 0.0} {
  error "100 MHz post-opt setup timing failed with WNS $setup_wns ns"
}

foreach {label pattern} {
  slice_luts {\| Slice LUTs\* +\| +([0-9]+) +\|}
  slice_registers {\| Slice Registers +\| +([0-9]+) +\|}
  block_ram_tiles {\| Block RAM Tile +\| +([0-9.]+) +\|}
  utilization_dsps {\| DSPs +\| +([0-9]+) +\|}
} {
  if {![regexp $pattern $utilization_report unused value]} {
    error "could not parse $label from report_utilization"
  }
  set $label $value
}

if {$slice_luts > 1600} {
  error "reducer LUT budget exceeded: $slice_luts > 1600"
}
if {$slice_registers > 1700} {
  error "reducer register budget exceeded: $slice_registers > 1700"
}
if {$block_ram_tiles != 0.0} {
  error "reducer must use zero block RAM tiles, got $block_ram_tiles"
}
if {$utilization_dsps != 0} {
  error "reducer utilization reports nonzero DSPs: $utilization_dsps"
}

set summary_path [file join $output_dir starlink_pss_exact_reducer_ooc_summary.txt]
set summary [open $summary_path w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "clock_period_ns=10.000"
puts $summary "timing_scope=post_opt_unplaced_max_delay_only"
puts $summary "hold_analysis=not_available_post_opt_unplaced"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_nonzero_categories=0"
puts $summary "slice_luts=$slice_luts"
puts $summary "slice_registers=$slice_registers"
puts $summary "block_ram_tiles=$block_ram_tiles"
puts $summary "dsp48e1=[llength $dsp_cells]"
close $summary

puts "STARLINK_REDUCER_OOC_PASS setup_wns_ns=$setup_wns slice_luts=$slice_luts slice_registers=$slice_registers block_ram_tiles=$block_ram_tiles dsp48e1=[llength $dsp_cells]"
close_design
