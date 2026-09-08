# Measure the EXISTING radix-4 burst arithmetic at 100/200 MHz before choosing
# a time-shared forward/inverse service. This does not qualify its future CDC,
# job scheduler, I/O placement, or full receiver. No detector profile changes.
# Usage: vivado -mode batch -source measure_shared_xfft_clock.tcl -tclargs OUTPUT ?MHZ?
if {$argc < 1 || $argc > 2} { error "expected output directory and optional MHz" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set output_dir [file normalize [lindex $argv 0]]
set clock_mhz [expr {$argc == 2 ? [lindex $argv 1] : 200}]
if {$clock_mhz ni {100 200}} { error "clock probe is restricted to 100/200 MHz" }
file mkdir $output_dir
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
# XFFT 9.1 emits a fixed 10 ns OOC XDC even when target_clock_frequency is
# 200. That CONFIG selects arithmetic; it does NOT constrain implementation.
# Explicitly replace this standalone clock with the actual probe period. Keep
# the original synthesis period in the evidence; no receiver constraint changes.
create_clock -name [get_property NAME $core_clock] \
  -period [expr {1000.0 / $clock_mhz}] $clock_port
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
