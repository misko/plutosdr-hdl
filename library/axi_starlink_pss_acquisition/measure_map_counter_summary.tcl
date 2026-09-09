# Isolated structural measurement of the real PSMA controller. The temporary
# zero I/O delays below are probe constraints, never receiver timing waivers.
if {$argc != 1} { error "expected NEW_OUTPUT_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output must be new" }
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach source [list [info script] \
    [file join $source_dir axi_starlink_pss_phase_map_sync.v] \
    [file join $source_dir ../axi_starlink_pss_phase_map/starlink_pss_axi_lite.v]] {
  file copy $source $frozen
}
set source_hashes [exec sha256sum {*}[lsort [glob [file join $frozen *]]]]
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_controller_isolated_synthesis_not_receiver_physical_qualification"
puts $report "source_hashes=$source_hashes"
puts $report "synthetic_IO_delays_ns=0 clock_period_ns=10 receiver_constraints_untouched=1"
puts $report "mode1_premise=real_same_clock_same_reset_map_producer_atomic_sticky_summary"
puts $report "mode\tLUT_primitives\tFF_primitives\tcounter_stop_paths\tflag_stop_paths\tcounter_stop_fanin_ports\tflag_stop_fanin_ports"
set_param general.maxThreads 2
foreach mode {0 1} {
  create_project -in_memory map_summary_$mode -part xc7z010clg400-1
  read_verilog [file join $frozen starlink_pss_axi_lite.v]
  read_verilog [file join $frozen axi_starlink_pss_phase_map_sync.v]
  synth_design -mode out_of_context -top axi_starlink_pss_phase_map_sync \
    -part xc7z010clg400-1 -flatten_hierarchy rebuilt \
    -generic [list ENABLE_BOUNDARY_STOP=1 USE_SHARED_XFFT=1 INPUT_RATE_MSPS=15 \
      HEALTH_COUNTERS_FROM_FLAGS=1 MAP_COUNTERS_FROM_FLAG=$mode]
  create_clock -period 10.0 -name control_clk [get_ports s_axi_aclk]
  set inputs [get_ports -filter {DIRECTION == IN && NAME != s_axi_aclk && NAME != map_clk}]
  set_input_delay -clock control_clk 0 $inputs
  set_output_delay -clock control_clk 0 [all_outputs]
  set counters [get_ports -quiet -filter {
    NAME =~ discarded_score_count* || NAME =~ discontinuity_abort_count* ||
    NAME =~ map_overrun_count* || NAME =~ score_protocol_error_count* ||
    NAME =~ map_arithmetic_overflow_count* || NAME =~ map_read_error_count* ||
    NAME =~ map_release_error_count*}]
  if {[llength $counters] != 224} { error "expected seven full-width counter inputs" }
  set flag [get_ports -quiet map_counter_fault]
  set stop [get_ports -quiet stop_request]
  if {[llength $flag] != 1 || [llength $stop] != 1} { error "missing flag/stop ports" }
  set counter_paths [get_timing_paths -quiet -from $counters -to $stop -max_paths 1]
  set flag_paths [get_timing_paths -quiet -from $flag -to $stop -max_paths 1]
  set fanin [all_fanin -flat -startpoints_only -to $stop]
  set counter_fanin [filter $fanin {
    CLASS == port && (NAME =~ discarded_score_count* || NAME =~ discontinuity_abort_count* ||
    NAME =~ map_overrun_count* || NAME =~ score_protocol_error_count* ||
    NAME =~ map_arithmetic_overflow_count* || NAME =~ map_read_error_count* ||
    NAME =~ map_release_error_count*)}]
  set flag_fanin [filter $fanin {CLASS == port && NAME == map_counter_fault}]
  if {[llength $counter_paths] != (1 - $mode) || [llength $flag_paths] != $mode ||
      [llength $counter_fanin] != 224 * (1 - $mode) || [llength $flag_fanin] != $mode} {
    error "unexpected synthesized map counter/flag stop dependency"
  }
  set luts [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ LUT*}]
  set flops [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ FD*}]
  puts $report "$mode\t[llength $luts]\t[llength $flops]\t[llength $counter_paths]\t[llength $flag_paths]\t[llength $counter_fanin]\t[llength $flag_fanin]"
  flush $report
  report_utilization -file [file join $output mode${mode}_utilization.rpt]
  if {$mode} {
    report_timing -from $flag -to $stop -max_paths 1 -file [file join $output mode${mode}_flag_path.rpt]
  } else {
    report_timing -from $counters -to $stop -max_paths 1 -file [file join $output mode${mode}_counter_path.rpt]
  }
  write_verilog -mode funcsim [file join $output mode${mode}_controller_funcsim.v]
  write_checkpoint [file join $output mode${mode}_synth.dcp]
  close_project
}
if {[exec sha256sum {*}[lsort [glob [file join $frozen *]]]] ne $source_hashes} {
  error "frozen sources changed during measurement"
}
puts $report "MAP_COUNTER_SUMMARY_SYNTHESIS_COMPARED full_receiver_timing_and_hardware_qualified=false"
close $report
puts "MAP_COUNTER_SUMMARY_SYNTHESIS_COMPARED full_receiver_timing_and_hardware_qualified=false"
