# Vivado 2022.2 OOC gate for the composed Stage-15 tracking slice.
# Usage: vivado -mode batch -source synthesize_tracking_ooc.tcl -tclargs OUTPUT

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [file join $script_dir .. common ad_mem.v]
read_verilog [file join $script_dir starlink_pss_async_fifo.v]
read_verilog [file join $script_dir starlink_sat_add48.v]
read_verilog [file join $script_dir starlink_pss_candidate_scheduler.v]
read_verilog [file join $script_dir starlink_pss_capture_bridge.v]
read_verilog [file join $script_dir starlink_pss_sliding_correlator.v]
read_verilog [file join $script_dir starlink_pss_tracking_core.v]
read_xdc [file join $script_dir starlink_pss_tracking_core_ooc.xdc]

synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high \
  -top starlink_pss_tracking_core \
  -part xc7z010clg400-1
opt_design -directive ExploreArea

write_checkpoint -force \
  [file join $output_dir starlink_pss_tracking_core_synth.dcp]
set utilization_report [report_utilization -return_string]
set timing_report [report_timing_summary -delay_type max -max_paths 30 -return_string]
set utilization_file [open \
  [file join $output_dir starlink_pss_tracking_core_utilization_synth.rpt] w]
puts -nonewline $utilization_file $utilization_report
close $utilization_file
set timing_file [open \
  [file join $output_dir starlink_pss_tracking_core_timing_synth.rpt] w]
puts -nonewline $timing_file $timing_report
close $timing_file

set hierarchical_utilization_report [report_utilization \
  -hierarchical -hierarchical_depth 4 -return_string]
set hierarchical_utilization_file [open \
  [file join $output_dir starlink_pss_tracking_core_utilization_hierarchical_synth.rpt] w]
puts -nonewline $hierarchical_utilization_file $hierarchical_utilization_report
close $hierarchical_utilization_file

set cdc_report [report_cdc -details -return_string]
set cdc_file [open \
  [file join $output_dir starlink_pss_tracking_core_cdc_synth.rpt] w]
puts -nonewline $cdc_file $cdc_report
close $cdc_file

set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir starlink_pss_tracking_core_methodology_synth.rpt] w]
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
  [file join $output_dir starlink_pss_tracking_core_check_timing.rpt] w]
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
  if {$category eq "no_input_delay" && $category_count == 3 &&
      [regexp {There are 3 input ports with no input delay but user has a false path constraint} \
        $check_timing_report]} {
    continue
  }
  if {$category_count != 0} {
    error "check_timing category $category is not clean: $category_count"
  }
}
set check_timing_unexpected $check_timing_report
regsub -all {checking no_input_delay \(3\)} $check_timing_unexpected \
  {checking no_input_delay (0)} check_timing_unexpected
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $check_timing_unexpected unused unexpected_nonzero_count]} {
  error "an unexpected check_timing category is nonzero: $unexpected_nonzero_count"
}

set dsp_cells [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
if {[llength $dsp_cells] != 3} {
  error "expected exactly three DSP48E1 cells, got [llength $dsp_cells]"
}
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] != 1} {
  error "no constrained maximum-delay path exists"
}
set setup_wns [get_property SLACK $setup_path]

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

set budget_pass [expr {
  $setup_wns >= 0.0 &&
  $slice_luts <= 2500 &&
  $slice_registers <= 2000 &&
  $block_ram_tiles <= 5.0 &&
  $utilization_dsps == 3
}]

set summary_path [file join $output_dir starlink_pss_tracking_core_ooc_summary.txt]
set summary [open $summary_path w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "control_clock_period_ns=10.000"
puts $summary "sample_clock_period_ns=16.667"
puts $summary "engine_clock_period_ns=10.000"
puts $summary "timing_scope=post_opt_unplaced_max_delay_only"
puts $summary "hold_analysis=not_available_post_opt_unplaced"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_expected_false_pathed_reset_no_input_delay=3"
puts $summary "check_timing_unexpected_nonzero_categories=0"
puts $summary "slice_luts=$slice_luts"
puts $summary "slice_registers=$slice_registers"
puts $summary "block_ram_tiles=$block_ram_tiles"
puts $summary "dsp48e1=[llength $dsp_cells]"
puts $summary "milestone_budget_pass=$budget_pass"
close $summary

puts "STARLINK_TRACKING_OOC_MEASURED setup_wns_ns=$setup_wns slice_luts=$slice_luts slice_registers=$slice_registers block_ram_tiles=$block_ram_tiles dsp48e1=[llength $dsp_cells] budget_pass=$budget_pass"
if {!$budget_pass} {
  error "tracking milestone gate failed: WNS=$setup_wns LUT=$slice_luts FF=$slice_registers BRAM=$block_ram_tiles DSP=$utilization_dsps"
}
puts "STARLINK_TRACKING_OOC_PASS"
close_design
