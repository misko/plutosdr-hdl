# Measure the EXISTING serial/DSP reducer alternatives inside the full 15 MS/s
# TRACK_ONE core. Only a frozen copy's generate choice changes. Runtime sources,
# receiver constraints and the normal rate-dependent selection remain untouched.
# This is resource evidence, not functional equivalence or receiver qualification.
if {$argc != 2} { error "expected NEW_OUTPUT_DIRECTORY PINNED_HDL_COMMIT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $script_dir ../..]]
set output [file normalize [lindex $argv 0]]
set revision [lindex $argv 1]
if {![regexp {^[0-9a-f]{40}$} $revision] ||
    [exec git -C $repo rev-parse ${revision}^{commit}] ne $revision} {
  error "requires a full existing source commit"
}
if {[file exists $output]} { error "output must be new" }
set frozen [file join $output frozen_sources]
file mkdir $frozen
file copy [info script] $frozen
set rtl_files {
  starlink_pss_async_fifo.v starlink_sat_add48.v
  starlink_pss_candidate_scheduler.v starlink_pss_capture_bridge.v
  starlink_pss_sliding_correlator.v starlink_pss_tracking_core.v
  starlink_pss_exact_reducer.v starlink_pss_exact_track_reducer.v
  starlink_pss_result_store.v
}
set source_paths [list library/common/ad_mem.v]
foreach name [concat $rtl_files {
  starlink_pss_reduced_tracking_core.v
  starlink_pss_reduced_tracking_core_ooc.xdc
}] { lappend source_paths library/starlink_pss_raw_correlator/$name }
foreach path $source_paths {
  set contents [exec git -C $repo show ${revision}:$path]
  set handle [open [file join $frozen [file tail $path]] w]
  puts $handle $contents
  close $handle
}
set handle [open [file join $frozen starlink_pss_reduced_tracking_core.v] r]
set original [read $handle]
close $handle
set before {if (RATE_MULTIPLIER == 4) begin : g_dsp_exact_reducer}
set after {if (1) begin : g_dsp_exact_reducer}
set position [string first $before $original]
if {$position < 0 || $position != [string last $before $original]} {
  error "expected unique original rate-dependent reducer choice"
}
if {[regexp -all {\.i_include_eh[ \t]+\(1'b0\)} $original] != 2} {
  error "both original TRACK_ONE paths must cancel constant Eh"
}
set selected [string map [list $before $after] $original]
if {[string map [list $after $before] $selected] ne $original} {
  error "frozen derivative changed more than the generate choice"
}
set handle [open [file join $frozen dsp_selected_core.v] w]
puts -nonewline $handle $selected
close $handle
set hashes [exec sha256sum {*}[lsort [glob [file join $frozen *]]]]
set report [open [file join $output scope.txt] w]
puts $report "scope=isolated_full_TRACK_ONE_resource_choice_not_receiver_or_functional_qualification"
puts $report "source_commit=$revision rate_multiplier=1"
puts $report "variant=frozen_generate_choice_only original_runtime_sources_untouched=1"
puts $report "source_hashes=$hashes"
puts $report "constraints=unchanged_existing_OOC_contract control_engine_ns=10 sample_ns=16.667"
set_param general.maxThreads 2
foreach mode {serial dsp} core {starlink_pss_reduced_tracking_core.v dsp_selected_core.v} {
  create_project -in_memory track_choice_$mode -part xc7z010clg400-1
  foreach name [concat {ad_mem.v} $rtl_files [list $core]] {
    read_verilog [file join $frozen $name]
  }
  read_xdc [file join $frozen starlink_pss_reduced_tracking_core_ooc.xdc]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -generic RATE_MULTIPLIER=1 -top starlink_pss_reduced_tracking_core \
    -part xc7z010clg400-1
  opt_design -directive ExploreArea
  set luts [llength [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ LUT*}]]
  set flops [llength [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ FD*}]]
  set dsps [llength [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
  set ram36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
  set ram18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
  set expected_dsps [expr {$mode eq "serial" ? 3 : 13}]
  if {$dsps != $expected_dsps} { error "unexpected $mode DSP inventory: $dsps" }
  set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
  if {[llength $setup] != 1} { error "missing constrained maximum-delay path" }
  puts $report "$mode LUT_primitives=$luts FF_primitives=$flops DSP48E1=$dsps RAMB36=$ram36 RAMB18=$ram18 unplaced_setup_ns=[get_property SLACK $setup]"
  flush $report
  report_utilization -hierarchical -hierarchical_depth 5 -file [file join $output ${mode}_hierarchy.rpt]
  report_utilization -file [file join $output ${mode}_utilization.rpt]
  report_control_sets -verbose -file [file join $output ${mode}_control_sets.rpt]
  report_timing_summary -delay_type max -max_paths 20 -file [file join $output ${mode}_timing.rpt]
  report_cdc -details -file [file join $output ${mode}_cdc.rpt]
  report_methodology -file [file join $output ${mode}_methodology.rpt]
  check_timing -verbose -file [file join $output ${mode}_check_timing.rpt]
  write_verilog -mode funcsim -rename_top track_choice_$mode [file join $output ${mode}_netlist.v]
  write_checkpoint [file join $output ${mode}_opt.dcp]
  close_project
}
if {[exec sha256sum {*}[lsort [glob [file join $frozen *]]]] ne $hashes} {
  error "frozen inputs changed"
}
puts $report "TRACK_REDUCER_CHOICE_MEASURED receiver_timing_and_functional_qualification=false"
close $report
puts "TRACK_REDUCER_CHOICE_MEASURED receiver_timing_and_functional_qualification=false"
