# Isolated synthesis of the actual PSMA controller with/without the producer
# summary selection. Synthetic 0 ns I/O delays serve ONLY this structural probe;
# this does not edit, route, qualify or promote a receiver checkpoint.
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
puts $report "scope=actual_controller_isolated_synthesis_structure_not_receiver_physical_qualification"
puts $report "source_hashes=$source_hashes"
puts $report "synthetic_IO_delays_ns=0 clock_period_ns=10 full_receiver_constraints_untouched=1"
puts $report "mode1_premise=real_same_clock_same_reset_acquisition_health_producer"
puts $report "mode\tLUT_primitives\tFF_primitives\tcounter_to_stop_paths\tflag_to_stop_paths"
set_param general.maxThreads 2
foreach mode {0 1} {
  create_project -in_memory stop_health_$mode -part xc7z010clg400-1
  read_verilog [file join $frozen starlink_pss_axi_lite.v]
  read_verilog [file join $frozen axi_starlink_pss_phase_map_sync.v]
  synth_design -mode out_of_context -top axi_starlink_pss_phase_map_sync \
    -part xc7z010clg400-1 -flatten_hierarchy rebuilt \
    -generic [list ENABLE_BOUNDARY_STOP=1 USE_SHARED_XFFT=1 INPUT_RATE_MSPS=15 \
      HEALTH_COUNTERS_FROM_FLAGS=$mode]
  create_clock -period 10.0 -name control_clk [get_ports s_axi_aclk]
  set inputs [get_ports -filter {DIRECTION == IN && NAME != s_axi_aclk && NAME != map_clk}]
  set_input_delay -clock control_clk 0 $inputs
  set_output_delay -clock control_clk 0 [all_outputs]
  set counters [get_ports -quiet -filter {
    NAME =~ scheduler_gap_count* || NAME =~ scheduler_index_error_count* ||
    NAME =~ scheduler_overflow_count* || NAME =~ detector_fault_count* ||
    NAME =~ score_phase_index_discontinuity_count*}]
  if {[llength $counters] != 160} { error "expected all five full-width counter ports" }
  set flags [get_ports -quiet -filter {NAME =~ detector_health_flags*}]
  if {[llength $flags] != 32} { error "expected the unchanged health flag port" }
  set stop [get_ports -quiet stop_request]
  if {[llength $stop] != 1} { error "missing public stop output" }
  set counter_paths [get_timing_paths -quiet -from $counters -to $stop -max_paths 1]
  set flag_paths [get_timing_paths -quiet -from $flags -to $stop -max_paths 1]
  if {[llength $counter_paths] != (1 - $mode) || [llength $flag_paths] != 1} {
    error "unexpected synthesized counter/flag stop dependency"
  }
  set luts [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ LUT*}]
  set flops [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ FD*}]
  puts $report "$mode\t[llength $luts]\t[llength $flops]\t[llength $counter_paths]\t[llength $flag_paths]"
  flush $report
  report_utilization -file [file join $output mode${mode}_utilization.rpt]
  report_timing -from $flags -to $stop -max_paths 1 -file [file join $output mode${mode}_flag_path.rpt]
  if {!$mode} {
    report_timing -from $counters -to $stop -max_paths 1 -file [file join $output mode${mode}_counter_path.rpt]
  }
  write_checkpoint [file join $output mode${mode}_synth.dcp]
  close_project
}
if {[exec sha256sum {*}[lsort [glob [file join $frozen *]]]] ne $source_hashes} {
  error "frozen sources changed during measurement"
}
puts $report "STOP_HEALTH_SYNTHESIS_COMPARED full_receiver_timing_and_hardware_qualified=false"
close $report
puts "STOP_HEALTH_SYNTHESIS_COMPARED full_receiver_timing_and_hardware_qualified=false"
