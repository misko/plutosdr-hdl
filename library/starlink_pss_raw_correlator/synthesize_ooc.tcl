# Vivado 2022.2 out-of-context synthesis gate for the first exact-PSS engine.
# Usage:
#   vivado -mode batch -source synthesize_ooc.tcl -tclargs /absolute/output/dir

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [file join $script_dir starlink_sat_add48.v]
read_verilog [file join $script_dir starlink_pss_raw_correlator.v]
read_xdc [file join $script_dir starlink_pss_raw_correlator_ooc.xdc]

synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -top starlink_pss_raw_correlator \
  -part xc7z010clg400-1

write_checkpoint -force [file join $output_dir starlink_pss_raw_correlator_synth.dcp]
report_utilization \
  -file [file join $output_dir starlink_pss_raw_correlator_utilization_synth.rpt]
set utilization_report [report_utilization -return_string]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $output_dir starlink_pss_raw_correlator_timing_synth.rpt]

# Report generation alone is not an evidence gate.  Parse returned report text,
# retain that exact parsed text for review, fail if its schema changes, and require all
# methodology and default timing-coverage categories to remain exactly clean.
set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir starlink_pss_raw_correlator_methodology_synth.rpt] w]
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
  [file join $output_dir starlink_pss_raw_correlator_check_timing.rpt] w]
puts -nonewline $check_timing_file $check_timing_report
close $check_timing_file
set expected_check_timing_categories [list \
  no_clock \
  constant_clock \
  pulse_width_clock \
  unconstrained_internal_endpoints \
  no_input_delay \
  no_output_delay \
  multiple_clock \
  generated_clocks \
  loops \
  partial_input_delay \
  partial_output_delay \
  latch_loops]
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
if {[llength $dsp_cells] != 3} {
  error "expected exactly three DSP48E1 cells, got [llength $dsp_cells]"
}
foreach dsp $dsp_cells {
  if {[get_property REF_NAME $dsp] ne "DSP48E1"} {
    error "unexpected DSP primitive [get_property REF_NAME $dsp] at $dsp"
  }
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] != 1} {
  error "no constrained maximum-delay path exists at 100 MHz"
}
set setup_wns [get_property SLACK $setup_path]
if {$setup_wns < 0.0} {
  error "100 MHz post-synthesis setup timing failed with WNS $setup_wns ns"
}

set lut_cells [get_cells -quiet -hier -filter {
  REF_NAME == LUT1 || REF_NAME == LUT2 || REF_NAME == LUT3 ||
  REF_NAME == LUT4 || REF_NAME == LUT5 || REF_NAME == LUT6 ||
  REF_NAME == LUT6_2
}]
set ff_cells [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]
set ramb36_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]
set ramb18_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]

if {![regexp {\| Slice LUTs\* +\| +([0-9]+) +\|} \
      $utilization_report unused slice_luts]} {
  error "could not parse Slice LUTs from report_utilization"
}
if {![regexp {\| Slice Registers +\| +([0-9]+) +\|} \
      $utilization_report unused slice_registers]} {
  error "could not parse Slice Registers from report_utilization"
}
if {![regexp {\| Block RAM Tile +\| +([0-9]+) +\|} \
      $utilization_report unused block_ram_tiles]} {
  error "could not parse Block RAM Tile from report_utilization"
}
if {![regexp {\| DSPs +\| +([0-9]+) +\|} \
      $utilization_report unused utilization_dsps]} {
  error "could not parse DSPs from report_utilization"
}
if {$utilization_dsps != 3} {
  error "report_utilization expected three DSPs, got $utilization_dsps"
}

set summary_path [file join $output_dir starlink_pss_raw_correlator_ooc_summary.txt]
set summary [open $summary_path w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "clock_period_ns=10.000"
puts $summary "timing_scope=post_synthesis_max_delay_only"
puts $summary "hold_analysis=not_available_post_synthesis"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_nonzero_categories=0"
puts $summary "slice_luts=$slice_luts"
puts $summary "slice_registers=$slice_registers"
puts $summary "block_ram_tiles=$block_ram_tiles"
puts $summary "lut_primitives=[llength $lut_cells]"
puts $summary "ff_primitives=[llength $ff_cells]"
puts $summary "ramb36e1=[llength $ramb36_cells]"
puts $summary "ramb18e1=[llength $ramb18_cells]"
puts $summary "dsp48e1=[llength $dsp_cells]"
close $summary

puts "STARLINK_RAW_OOC_PASS timing_scope=post_synthesis_max_delay_only hold_analysis=not_available_post_synthesis setup_wns_ns=$setup_wns methodology_violations=$methodology_violation_count check_timing_nonzero_categories=0 slice_luts=$slice_luts slice_registers=$slice_registers block_ram_tiles=$block_ram_tiles dsp48e1=[llength $dsp_cells]"
close_design
