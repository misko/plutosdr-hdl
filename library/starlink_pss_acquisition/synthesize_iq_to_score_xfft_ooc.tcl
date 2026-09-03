# Vivado 2022.2 OOC gate for the complete 15 MS/s CI16-to-score path.
# Usage: vivado -mode batch -source synthesize_iq_to_score_xfft_ooc.tcl \
#        -tclargs OUTPUT

if {$argc != 1} {
  error "expected one absolute output directory"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set project_dir [file join $output_dir project]
set project_name starlink_pss_iq_to_score_xfft_ooc
set memory_file [file join $script_dir tb upper_edge_pss_kernel_q23.mem]
file mkdir $output_dir
if {![file isfile $memory_file]} {
  error "kernel memory artifact is missing: $memory_file"
}

create_project -force $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name starlink_pss_fft512_bfp24
set_property -dict [list \
  CONFIG.channels {1} \
  CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {100} \
  CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {20} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {24} \
  CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} \
  CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} \
  CONFIG.xk_index {true} \
  CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} \
  CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_luts} \
] [get_ips starlink_pss_fft512_bfp24]
generate_target all [get_ips starlink_pss_fft512_bfp24]

set wrappers [glob -nocomplain \
  [file join $project_dir ${project_name}.gen sources_1 ip \
    starlink_pss_fft512_bfp24 synth starlink_pss_fft512_bfp24.vhd]]
if {[llength $wrappers] != 1} {
  error "could not locate generated XFFT synthesis wrapper"
}
set wrapper_file [open [lindex $wrappers 0] r]
set wrapper_text [read $wrapper_file]
close $wrapper_file
if {![regexp {C_ARCH => 1,} $wrapper_text]} {
  error "20 MS/s automatic selection did not choose radix-4 burst C_ARCH=1"
}

foreach source_name {
  starlink_pss_overlap_scheduler.v
  starlink_pss_energy_cache.v
  starlink_pss_xfft_block_adapter.v
  starlink_pss_kernel_rom.v
  starlink_pss_forward_kernel_join.v
  starlink_pss_spectrum_product.v
  starlink_pss_ifft_qualifier.v
  starlink_pss_raw_result_fifo.v
  starlink_pss_energy_join.v
  starlink_pss_score_prepare.v
  starlink_pss_score_divider.v
  starlink_pss_score_lanes.v
  starlink_pss_candidate_score_path.v
  starlink_pss_iq_to_score.v
} {
  add_files -norecurse [file join $script_dir $source_name]
}
add_files -fileset constrs_1 -norecurse \
  [file join $script_dir starlink_pss_iq_to_score_xfft_ooc.xdc]
set_property top starlink_pss_iq_to_score [get_filesets sources_1]
set_property generic "KERNEL_ROM_FILE=$memory_file" [get_filesets sources_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property -dict [list \
  {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} \
] [get_runs synth_1]

create_ip_run [get_ips starlink_pss_fft512_bfp24]
launch_runs starlink_pss_fft512_bfp24_synth_1 -jobs 4
wait_on_run starlink_pss_fft512_bfp24_synth_1
if {[get_property STATUS [get_runs starlink_pss_fft512_bfp24_synth_1]] \
    ne "synth_design Complete!"} {
  error "XFFT synthesis did not complete"
}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
  error "composition synthesis did not complete"
}
open_run synth_1
opt_design -directive ExploreArea

set utilization_report [report_utilization -hierarchical -return_string]
set timing_report [report_timing_summary \
  -delay_type min_max -max_paths 20 -return_string]
foreach {name contents} [list \
    starlink_pss_iq_to_score_xfft_utilization_opt.rpt $utilization_report \
    starlink_pss_iq_to_score_xfft_timing_opt.rpt $timing_report] {
  set report_file [open [file join $output_dir $name] w]
  puts -nonewline $report_file $contents
  close $report_file
}

set methodology_report [report_methodology -return_string]
set methodology_file [open \
  [file join $output_dir starlink_pss_iq_to_score_xfft_methodology_opt.rpt] w]
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
  [file join $output_dir starlink_pss_iq_to_score_xfft_check_timing.rpt] w]
puts -nonewline $check_timing_file $check_timing_report
close $check_timing_file
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} \
    $check_timing_report unused unexpected_nonzero_count]} {
  error "a check_timing category is nonzero: $unexpected_nonzero_count"
}

if {![regexp {\| starlink_pss_iq_to_score +\| +\(top\) +\| +([0-9]+) +\| +[0-9]+ +\| +[0-9]+ +\| +[0-9]+ +\| +([0-9]+) +\|} \
      $utilization_report unused lut_count register_count]} {
  error "could not parse top LUT/register counts from hierarchical utilization"
}
set ramb36_count [llength \
  [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
set ramb18_count [llength \
  [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
set dsp_count [llength \
  [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
set bram_tiles [expr {$ramb36_count + 0.5 * $ramb18_count}]
if {$lut_count > 17600 || $register_count > 35200 ||
    $bram_tiles > 60.0 || $dsp_count > 80} {
  error "composition exceeds xc7z010 resources: LUT=$lut_count FF=$register_count BRAM=$bram_tiles DSP=$dsp_count"
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

write_checkpoint -force \
  [file join $output_dir starlink_pss_iq_to_score_xfft_opt.dcp]
set summary [open \
  [file join $output_dir starlink_pss_iq_to_score_xfft_ooc_summary.txt] w]
puts $summary "vivado_version=[version -short]"
puts $summary "xfft_version=9.1"
puts $summary "part=xc7z010clg400-1"
puts $summary "xfft_instances=2"
puts $summary "xfft_architecture=radix_4_burst"
puts $summary "sample_rate_msps=15"
puts $summary "acquisition_clock_mhz=100"
puts $summary "clock_period_ns=10.000"
puts $summary "timing_scope=post_opt_unplaced"
puts $summary "setup_wns_ns=$setup_wns"
puts $summary "hold_whs_ns=$hold_whs"
puts $summary "methodology_violations=$methodology_violation_count"
puts $summary "check_timing_nonzero_categories=0"
puts $summary "total_luts=$lut_count"
puts $summary "total_ffs=$register_count"
puts $summary "ramb36e1=$ramb36_count"
puts $summary "ramb18e1=$ramb18_count"
puts $summary "bram_tiles=$bram_tiles"
puts $summary "dsp48e1=$dsp_count"
close $summary

puts "STARLINK_IQ_TO_SCORE_XFFT_OOC_PASS setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs total_luts=$lut_count total_ffs=$register_count ramb36e1=$ramb36_count ramb18e1=$ramb18_count dsp48e1=$dsp_count"
close_design
close_project
