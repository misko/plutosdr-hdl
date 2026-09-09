# Measure the EXISTING radix-4 burst arithmetic at 100/200 MHz before choosing
# a time-shared forward/inverse service. This does not qualify its future CDC,
# job scheduler, I/O placement, or full receiver. No detector profile changes.
# Usage: vivado -mode batch -source measure_shared_xfft_clock.tcl -tclargs OUTPUT ?MHZ? ?actual-synth?
# The additive actual-synth probe changes ONLY its fresh generated OOC clock,
# before synthesis. The default retains the historical generated-clock probe.
if {$argc < 1 || $argc > 3} { error "expected output directory, optional MHz and actual-synth" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set output_dir [file normalize [lindex $argv 0]]
set clock_mhz [expr {$argc >= 2 ? [lindex $argv 1] : 200}]
if {$clock_mhz ni {100 200}} { error "clock probe is restricted to 100/200 MHz" }
set actual_synthesis_clock [expr {$argc == 3}]
if {$actual_synthesis_clock && [lindex $argv 2] ne "actual-synth"} {
  error "the only optional synthesis-clock probe is actual-synth"
}
if {$actual_synthesis_clock && [file exists $output_dir]} {
  error "actual-synth requires a fresh output directory; no previous evidence may be overwritten"
}
file mkdir $output_dir
if {$actual_synthesis_clock} {
  file copy [file normalize [info script]] [file join $output_dir probe_source.tcl]
}
create_project shared_xfft_clock [file join $output_dir project] -part xc7z010clg400-1
set_property target_language Verilog [current_project]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name starlink_pss_fft512_bfp18
set_property -dict [list \
  CONFIG.channels {1} CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency $clock_mhz \
  CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput [expr {$clock_mhz / 5}] \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} CONFIG.input_width {18} \
  CONFIG.phase_factor_width {16} CONFIG.scaling_options {block_floating_point} \
  CONFIG.rounding_modes {convergent_rounding} CONFIG.aresetn {true} \
  CONFIG.xk_index {true} CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips starlink_pss_fft512_bfp18]
generate_target all [get_ips starlink_pss_fft512_bfp18]
set wrapper [glob [file join $output_dir project shared_xfft_clock.gen sources_1 ip \
  starlink_pss_fft512_bfp18 synth starlink_pss_fft512_bfp18.vhd]]
set channel [open $wrapper r]
set wrapper_text [read $channel]
close $channel
if {![regexp {C_ARCH => ([0-9]+),} $wrapper_text unused architecture] || $architecture != 1} {
  error "probe must retain the frozen radix-4 burst architecture C_ARCH=1"
}
if {$actual_synthesis_clock} {
  # Changing the generated standalone _ooc.xdc target is deliberately local to
  # this diagnostic project, not an edit of production IP or receiver clocks.
  # Keep the original file and refuse an unexpected generator format.
  set generated_ooc [file join $output_dir project shared_xfft_clock.gen sources_1 ip \
    starlink_pss_fft512_bfp18 starlink_pss_fft512_bfp18_ooc.xdc]
  set channel [open $generated_ooc r]
  set generated_ooc_text [read $channel]
  close $channel
  if {[regexp -all {create_clock -period 10 -name aclk \[get_ports aclk\]} $generated_ooc_text] != 1} {
    error "expected exactly one generated 10 ns OOC clock before synthesis"
  }
  file copy $generated_ooc [file join $output_dir generated_ooc_original.xdc]
  regsub {create_clock -period 10 -name aclk \[get_ports aclk\]} $generated_ooc_text \
    "create_clock -period [expr {1000.0 / $clock_mhz}] -name aclk \[get_ports aclk\]" actual_ooc_text
  set channel [open $generated_ooc w]
  puts -nonewline $channel $actual_ooc_text
  close $channel
  file copy $generated_ooc [file join $output_dir actual_synthesis_ooc.xdc]
}
create_ip_run [get_ips starlink_pss_fft512_bfp18]
set synthesis_run [get_runs starlink_pss_fft512_bfp18_synth_1]
set_property strategy Flow_AreaOptimized_high $synthesis_run
set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 $synthesis_run
launch_runs $synthesis_run -jobs 4
wait_on_run $synthesis_run
open_run $synthesis_run
set clock_port [get_ports aclk]
set core_clock [get_clocks -of_objects $clock_port]
if {[llength $clock_port] != 1 || [llength $core_clock] != 1} {
  error "expected exactly one generated OOC clock on aclk"
}
set synthesis_clock_period_ns [get_property PERIOD $core_clock]
if {$actual_synthesis_clock} {
  if {abs($synthesis_clock_period_ns - 1000.0 / $clock_mhz) > 0.001} {
    error "actual-synth did not synthesize with the requested clock period"
  }
  # Save these BEFORE any implementation-clock command. They record the clock
  # actually retained by the synthesis checkpoint, not a post-hoc override.
  report_clocks -file [file join $output_dir synthesis_clocks.rpt]
  report_utilization -file [file join $output_dir synthesis_utilization.rpt]
  write_checkpoint [file join $output_dir fft_synth.dcp]
  write_verilog -mode funcsim [file join $output_dir fft_synth_netlist.v]
  set synth_ce_registers [get_cells -hier -filter {NAME =~ *gen_ce_non_real_time.ce_predicted_reg* && REF_NAME == FDRE}]
  if {[llength $synth_ce_registers] == 0} { error "missing synthesized CE prediction registers" }
  report_timing -from [all_registers] \
    -to [get_pins -of_objects $synth_ce_registers -filter {REF_PIN_NAME == D}] \
    -max_paths 20 -file [file join $output_dir synthesis_ce_prediction_fanin.rpt]
  report_timing -from $synth_ce_registers -to [all_registers] -max_paths 20 \
    -file [file join $output_dir synthesis_ce_distribution_fanout.rpt]
}
# XFFT 9.1 emits a fixed 10 ns OOC XDC even when target_clock_frequency is
# 200. That CONFIG selects arithmetic; it does NOT constrain implementation.
# Explicitly replace this standalone clock with the actual probe period. Keep
# the original synthesis period in the evidence; no receiver constraint changes.
if {!$actual_synthesis_clock} {
  create_clock -name [get_property NAME $core_clock] \
    -period [expr {1000.0 / $clock_mhz}] $clock_port
}
set core_clock [get_clocks -of_objects $clock_port]
if {[llength $core_clock] != 1 ||
    abs([get_property PERIOD $core_clock] - 1000.0 / $clock_mhz) > 0.001} {
  error "explicit probe clock is missing or has the wrong period"
}
set_property HD.CLK_SRC BUFGCTRL_X0Y0 $clock_port
set_input_delay -clock $core_clock -max 1.000 \
  [get_ports -filter {DIRECTION == IN && NAME != aclk}]
set_input_delay -clock $core_clock -min 0.000 \
  [get_ports -filter {DIRECTION == IN && NAME != aclk}]
set_output_delay -clock $core_clock -max 1.000 [all_outputs]
set_output_delay -clock $core_clock -min 0.000 [all_outputs]
opt_design -directive ExploreArea
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
write_checkpoint -force [file join $output_dir fft_routed.dcp]
report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $output_dir timing.rpt]
set methodology [report_methodology -return_string]
set routing [report_route_status -return_string]
set clocks [check_timing -verbose -return_string]
foreach {name contents} [list methodology $methodology route_status $routing check_timing $clocks] {
  set channel [open [file join $output_dir "$name.rpt"] w]
  puts -nonewline $channel $contents
  close $channel
}
report_clocks -file [file join $output_dir clocks.rpt]
if {$actual_synthesis_clock} {
  # Both sides matter: replication can improve the wide CE distribution while
  # making its shared prediction cone slower. Never report only the D endpoint.
  set ce_registers [get_cells -hier -filter {NAME =~ *gen_ce_non_real_time.ce_predicted_reg* && REF_NAME == FDRE}]
  if {[llength $ce_registers] == 0} { error "missing expected nonrealtime CE prediction registers" }
  set ce_data_pins [get_pins -of_objects $ce_registers -filter {REF_PIN_NAME == D}]
  report_timing -from [all_registers] -to $ce_data_pins -max_paths 20 \
    -path_type full_clock_expanded -file [file join $output_dir ce_prediction_fanin.rpt]
  report_timing -from $ce_registers -to [all_registers] -max_paths 20 \
    -path_type full_clock_expanded -file [file join $output_dir ce_distribution_fanout.rpt]
  report_high_fanout_nets -timing -max_nets 20 -file [file join $output_dir high_fanout.rpt]
  write_verilog -mode funcsim [file join $output_dir fft_routed_netlist.v]
}
set registers [all_registers]
set setup [get_timing_paths -quiet -from $registers -to $registers -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -from $registers -to $registers -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing internal timed paths" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set channel [open [file join $output_dir summary.txt] w]
puts $channel "scope=single_XFFT_internal_register_to_register_NOT_IO_CDC_scheduler_or_receiver"
puts $channel "vivado_version=[version -short]"
puts $channel "clock_mhz=$clock_mhz"
if {$actual_synthesis_clock} {
  puts $channel "synthesis_clock_mode=actual-synth"
  puts $channel "original_generated_ooc_clock_period_ns=10.000"
  puts $channel "ce_prediction_register_count=[llength $ce_registers]"
}
puts $channel "synthesis_ooc_clock_period_ns=$synthesis_clock_period_ns"
puts $channel "implementation_clock_period_ns=[get_property PERIOD $core_clock]"
puts $channel "architecture=$architecture"
puts $channel "setup_wns_ns=$wns"
puts $channel "hold_whs_ns=$whs"
puts $channel "dsp48e1=[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]"
puts $channel "bram18=[llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]"
puts $channel "bram36=[llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]"
puts $channel "internal_timing_passed=[expr {$wns >= 0 && $whs >= 0}]"
puts $channel "whole_receiver_qualified=false"
close $channel
if {$wns < 0 || $whs < 0} { error "internal FFT timing failed: WNS=$wns WHS=$whs" }
# Unplaced boundary hold paths remain unqualified. Vivado also reports XDCC-1
# and XDCC-7 for the explicit 10 ns -> 5 ns standalone clock replacement above.
# Accept only those exact single-clock override diagnostics, retaining them in
# methodology.rpt; this does not waive receiver clock constraints or CDC checks.
foreach violation [get_methodology_violations -quiet] {
  if {$clock_mhz == 200 && $synthesis_clock_period_ns == 10.000 &&
      $violation in {XDCC-1#1 XDCC-7#1}} { continue }
  if {![regexp {^TIMING-15#[0-9]+$} $violation]} {
    error "unexpected methodology violation: $violation"
  }
}
if {[regexp {checking [a-z_]+ \(([1-9][0-9]*)\)} $clocks]} {
  error "check_timing gate failed; inspect check_timing.rpt"
}
if {![regexp {# of nets with routing errors[. ]+: +0} $routing]} {
  error "routing gate failed; inspect route_status.rpt"
}
set channel [open [file join $output_dir summary.txt] a]
puts $channel "internal_ooc_gate=pass"
close $channel
puts "SHARED_XFFT_CLOCK_INTERNAL_PASS MHZ=$clock_mhz WNS=$wns WHS=$whs FULL_RECEIVER_UNQUALIFIED"
close_design
close_project
