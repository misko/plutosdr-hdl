# Vivado 2022.2 OOC gate for the Starlink PSS phase-map AXI/CDC bridge.
# Usage: vivado -mode batch -source synthesize_ooc.tcl -tclargs OUTPUT

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

read_verilog [list \
  [file join $script_dir starlink_pss_axi_lite.v] \
  [file join $script_dir axi_starlink_pss_phase_map.v]]
read_xdc [file join $script_dir axi_starlink_pss_phase_map_ooc.xdc]
read_xdc [file join $script_dir axi_starlink_pss_phase_map_constr.xdc]

synth_design \
  -mode out_of_context \
  -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high \
  -top axi_starlink_pss_phase_map \
  -part xc7z010clg400-1
opt_design -directive ExploreArea
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

set utilization_report [report_utilization -hierarchical -return_string]
set timing_report [report_timing_summary \
  -delay_type min_max -max_paths 30 -return_string]
set cdc_report [report_cdc -details -return_string]
set bus_skew_report [report_bus_skew -warn_on_violation -return_string]
foreach {name contents} [list \
    axi_starlink_pss_phase_map_utilization_routed.rpt $utilization_report \
    axi_starlink_pss_phase_map_timing_routed.rpt $timing_report \
    axi_starlink_pss_phase_map_cdc_routed.rpt $cdc_report \
    axi_starlink_pss_phase_map_bus_skew_routed.rpt $bus_skew_report] {
  set report_file [open [file join $output_dir $name] w]
  puts -nonewline $report_file $contents
  close $report_file
}

set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir axi_starlink_pss_phase_map_methodology_routed.rpt] w]
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
  [file join $output_dir axi_starlink_pss_phase_map_check_timing_routed.rpt] w]
puts -nonewline $check_timing_file $check_timing_report
close $check_timing_file
if {![string match {*checking no_input_delay (1)*} $check_timing_report] ||
    ![string match {*There are 0 input ports with no input delay specified.*} \
      $check_timing_report] ||
    ![string match {*There is 1 input port with no input delay but user has a false path constraint.*} \
      $check_timing_report] ||
    ![regexp {\n\n+s_axi_aresetn\n} $check_timing_report]} {
  error "expected only the explicitly false-pathed asynchronous AXI reset to lack an input delay"
}
set normalized_check_timing [string map \
  {{checking no_input_delay (1)} {checking no_input_delay (0)}} \
  $check_timing_report]
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $normalized_check_timing unused unexpected_nonzero_count]} {
  error "a check_timing category is nonzero: $unexpected_nonzero_count"
}

set critical_cdc_count [regexp -all -line {CDC-[0-9]+[ \t]+Critical} \
  $cdc_report]
if {$critical_cdc_count != 0} {
  error "phase-map bridge introduced $critical_cdc_count Critical CDC rows"
}
set cdc_summary_count [regexp -all -line {^CDC-[0-9]+[ \t]+} $cdc_report]
foreach expected_cdc_summary {
  {^CDC-3[ \t]+Info[ \t]+11[ \t]+1-bit synchronized with ASYNC_REG property$}
  {^CDC-6[ \t]+Warning[ \t]+3[ \t]+Multi-bit synchronized with ASYNC_REG property$}
  {^CDC-9[ \t]+Info[ \t]+2[ \t]+Asynchronous reset synchronized with ASYNC_REG property$}
  {^CDC-26[ \t]+Warning[ \t]+3[ \t]+LUTRAM read/write potential collision$}
} {
  if {![regexp -line $expected_cdc_summary $cdc_report]} {
    error "unexpected CDC summary; expected pattern $expected_cdc_summary"
  }
}
if {$cdc_summary_count != 4} {
  error "unexpected CDC class count: $cdc_summary_count"
}
set bus_skew_violated [regexp -all {Slack \(VIOLATED\)} $bus_skew_report]
set bus_skew_met [regexp -all {Slack \(MET\)} $bus_skew_report]
if {$bus_skew_violated != 0 || $bus_skew_met != 3} {
  error "expected three met bundled-data bus-skew constraints, got met=$bus_skew_met violated=$bus_skew_violated"
}

set ramb36_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]
set ramb18_cells [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]
set dsp_cells [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
if {[llength $ramb36_cells] != 0 || [llength $ramb18_cells] != 0 ||
    [llength $dsp_cells] != 0} {
  error "AXI bridge must use no BRAM/DSP resources"
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
  error "constrained setup and hold paths are required"
}
set setup_wns [get_property SLACK $setup_path]
set hold_whs [get_property SLACK $hold_path]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
  error "100 MHz post-route timing failed: setup=$setup_wns hold=$hold_whs"
}

foreach {label pattern} {
  total_luts {\| axi_starlink_pss_phase_map +\| +\(top\) +\| +([0-9]+) +\|}
  total_ffs {\| axi_starlink_pss_phase_map +\| +\(top\) +\| +[0-9]+ +\| +[0-9]+ +\| +[0-9]+ +\| +[0-9]+ +\| +([0-9]+) +\|}
} {
  if {![regexp $pattern $utilization_report unused value]} {
    error "could not parse $label from hierarchical utilization"
  }
  set $label $value
}
if {$total_luts > 1400 || $total_ffs > 3200} {
  error "AXI/CDC bridge logic budget exceeded: LUT=$total_luts FF=$total_ffs"
}

set snapshot_source [get_cells -quiet -hier -regexp \
  {.*snapshot_source_payload_reg\[[0-9]+\].*}]
set snapshot_sync [get_cells -quiet -hier -regexp \
  {.*snapshot_payload_sync_[12]_reg\[[0-9]+\].*}]
set snapshot_destination [get_cells -quiet -hier -regexp \
  {.*snapshot_payload_reg\[[0-9]+\].*}]
if {[llength $snapshot_source] != 482 ||
    [llength $snapshot_sync] != 964 ||
    [llength $snapshot_destination] != 482} {
  error "snapshot mailbox bits are incomplete: source=[llength $snapshot_source] sync=[llength $snapshot_sync] destination=[llength $snapshot_destination]"
}

write_checkpoint -force \
  [file join $output_dir axi_starlink_pss_phase_map_routed.dcp]
set summary [open \
  [file join $output_dir axi_starlink_pss_phase_map_ooc_summary.txt] w]
puts $summary "vivado_version=[version -short]"
puts $summary "part=xc7z010clg400-1"
puts $summary "map_clock_period_ns=10.000"
puts $summary "axi_clock_period_ns=10.000"
puts $summary "timing_scope=post_route"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "hold_whs_ns=$hold_whs"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_expected_async_reset_only=1"
puts $summary "critical_cdc_rows=$critical_cdc_count"
puts $summary "bus_skew_met=$bus_skew_met"
puts $summary "bus_skew_violated=$bus_skew_violated"
puts $summary "snapshot_source_bits=[llength $snapshot_source]"
puts $summary "snapshot_synchronizer_bits=[llength $snapshot_sync]"
puts $summary "snapshot_destination_bits=[llength $snapshot_destination]"
puts $summary "total_luts=$total_luts"
puts $summary "total_ffs=$total_ffs"
puts $summary "ramb36e1=[llength $ramb36_cells]"
puts $summary "ramb18e1=[llength $ramb18_cells]"
puts $summary "dsp48e1=[llength $dsp_cells]"
close $summary

puts "STARLINK_PSS_PHASE_MAP_AXI_OOC_PASS timing_scope=post_route setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs total_luts=$total_luts total_ffs=$total_ffs critical_cdc_rows=$critical_cdc_count bus_skew_met=$bus_skew_met"
close_design
