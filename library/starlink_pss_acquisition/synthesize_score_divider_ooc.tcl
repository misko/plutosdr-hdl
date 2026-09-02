# Vivado 2022.2 OOC gate for one exact normalized-power score-divider lane.
# Usage: vivado -mode batch -source synthesize_score_divider_ooc.tcl \
#        -tclargs OUTPUT

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [file join $script_dir starlink_pss_score_divider.v]
read_xdc [file join $script_dir starlink_pss_score_divider_ooc.xdc]

synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high \
  -top starlink_pss_score_divider \
  -part xc7z010clg400-1
opt_design -directive ExploreArea

set utilization_report [report_utilization -hierarchical -return_string]
set timing_report [report_timing_summary \
  -delay_type min_max -max_paths 20 -return_string]
foreach {name contents} [list \
    starlink_pss_score_divider_utilization_opt.rpt $utilization_report \
    starlink_pss_score_divider_timing_opt.rpt $timing_report] {
  set report_file [open [file join $output_dir $name] w]
  puts -nonewline $report_file $contents
  close $report_file
}

set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir starlink_pss_score_divider_methodology_opt.rpt] w]
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
  [file join $output_dir starlink_pss_score_divider_check_timing.rpt] w]
puts -nonewline $check_timing_file $check_timing_report
close $check_timing_file
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $check_timing_report unused unexpected_nonzero_count]} {
  error "a check_timing category is nonzero: $unexpected_nonzero_count"
}

set ramb36_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]
set ramb18_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]
set dsp_cells [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
if {[llength $ramb36_cells] != 0 || [llength $ramb18_cells] != 0} {
  error "score divider must not consume BRAM"
}
if {[llength $dsp_cells] != 0} {
  error "score divider must not consume DSP48E1 cells"
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
  error "constrained setup and hold paths are required"
}
set setup_wns [get_property SLACK $setup_path]
set hold_whs [get_property SLACK $hold_path]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
  error "100 MHz post-opt timing failed: setup=$setup_wns hold=$hold_whs"
}

foreach {label pattern} {
  total_luts {\| starlink_pss_score_divider +\| +\(top\) +\| +([0-9]+) +\|}
  total_ffs {\| starlink_pss_score_divider +\| +\(top\) +\| +[0-9]+ +\| +[0-9]+ +\| +[0-9]+ +\| +[0-9]+ +\| +([0-9]+) +\|}
} {
  if {![regexp $pattern $utilization_report unused value]} {
    error "could not parse $label from hierarchical utilization"
  }
  set $label $value
}
if {$total_luts > 1500 || $total_ffs > 1000} {
  error "score-divider logic budget exceeded: LUT=$total_luts FF=$total_ffs"
}

write_checkpoint -force \
  [file join $output_dir starlink_pss_score_divider_opt.dcp]
set summary [open \
  [file join $output_dir starlink_pss_score_divider_ooc_summary.txt] w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "ratio_bits=69"
puts $summary "score_bits=8"
puts $summary "restoring_iterations=8"
puts $summary "clock_period_ns=10.000"
puts $summary "timing_scope=post_opt_unplaced"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "hold_whs_ns=$hold_whs"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_nonzero_categories=0"
puts $summary "total_luts=$total_luts"
puts $summary "total_ffs=$total_ffs"
puts $summary "ramb36e1=[llength $ramb36_cells]"
puts $summary "ramb18e1=[llength $ramb18_cells]"
puts $summary "dsp48e1=[llength $dsp_cells]"
close $summary

puts "STARLINK_SCORE_DIVIDER_OOC_PASS setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs total_luts=$total_luts total_ffs=$total_ffs"
close_design
