# Compare actual full pilot-capture synthesis with/without local replication.
# This isolated experiment does not qualify receiver placement, timing or IIO.
if {$argc < 1 || $argc > 2} { error "expected NEW_OUTPUT_DIRECTORY and optional data-enable" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $source_dir ../..]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output must be new" }
set baseline 84a1a3589a08f5af72323755d38b9d7ef9153846
set variant fanout
if {$argc == 2} {
  if {[lindex $argv 1] ne "data-enable"} { error "unknown snapshot measurement variant" }
  set variant data-enable
  set baseline 24bac44461c78868689ddb6b35e2f4edfd6d5d5d
}
set control_path library/axi_starlink_pilot_capture/axi_starlink_pilot_capture.v
set old_source [exec git -C $repo show ${baseline}:$control_path]
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach source [list [info script] [file join $repo $control_path] \
    [file join $repo library/axi_starlink_pss_phase_map/starlink_pss_axi_lite.v] \
    [file join $repo library/starlink_pss_acquisition/starlink_pilot_ddc.v] \
    [file join $repo library/starlink_pss_acquisition/starlink_pilot_halfband2.v] \
    [file join $repo library/starlink_pss_acquisition/starlink_pilot_fir3.v] \
    [file join $repo library/starlink_pss_acquisition/pilot_mixer_q16.mem] \
    [file join $repo library/starlink_pss_acquisition/pilot_halfband2_q17.mem] \
    [file join $repo library/starlink_pss_acquisition/pilot_fir3_q17.mem]] {
  file copy $source $frozen
}
set handle [open [file join $frozen baseline.v] w]
puts $handle $old_source
close $handle
set hashes [exec sha256sum {*}[lsort [glob [file join $frozen *]]]]
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_pilot_capture_isolated_synthesis_not_receiver_timing_or_hardware"
puts $report "baseline_commit=$baseline"
puts $report "variant=$variant"
puts $report "source_hashes=$hashes"
puts $report "clock_period_ns=10 synthetic_IO_delays_ns=0 receiver_constraints_untouched=1"
set_param general.maxThreads 2
cd $frozen
foreach mode {baseline replicated} source {baseline.v axi_starlink_pilot_capture.v} {
  create_project -in_memory snapshot_$mode -part xc7z010clg400-1
  foreach file {starlink_pss_axi_lite.v starlink_pilot_ddc.v starlink_pilot_halfband2.v starlink_pilot_fir3.v} {
    read_verilog [file join $frozen $file]
  }
  read_verilog [file join $frozen $source]
  synth_design -mode out_of_context -top axi_starlink_pilot_capture \
    -part xc7z010clg400-1 -flatten_hierarchy full -directive AreaOptimized_high \
    -control_set_opt_threshold 4 -generic {INPUT_RATE_MSPS=15 OUTPUT_FIFO_BITS=5}
  create_clock -period 10.0 -name control_clk [get_ports s_axi_aclk]
  set_input_delay -clock control_clk 0 [get_ports -filter {DIRECTION == IN && NAME != s_axi_aclk}]
  set_output_delay -clock control_clk 0 [all_outputs]
  set drivers [get_cells -quiet -hier -filter {IS_SEQUENTIAL && NAME =~ snapshot_request_reg*}]
  if {![llength $drivers]} { error "snapshot request driver inventory is empty" }
  set maximum 0
  set total 0
  foreach driver $drivers {
    set pin [get_pins -of_objects $driver -filter {REF_PIN_NAME == Q}]
    set nets [get_nets -of_objects $pin]
    set loads [get_pins -leaf -of_objects $nets -filter {DIRECTION == IN}]
    set count [llength $loads]
    set maximum [expr {max($maximum, $count)}]
    incr total $count
    puts $report "$mode driver=$driver loads=$count"
  }
  set luts [llength [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ LUT*}]]
  set flops [llength [get_cells -quiet -hier -filter {IS_PRIMITIVE && REF_NAME =~ FD*}]]
  set snapshot_regs [get_cells -quiet -hier -filter {IS_SEQUENTIAL && NAME =~ snapshot_reg*}]
  if {[llength $snapshot_regs] < 500} { error "snapshot payload inventory is incomplete" }
  set variable_ce 0
  foreach register $snapshot_regs {
    set ce [get_pins -of_objects $register -filter {REF_PIN_NAME == CE}]
    if {[llength $ce] != 1} { error "snapshot payload register has no unique CE" }
    set ce_net [get_nets -of_objects $ce]
    set ce_driver [get_cells -of_objects [get_pins -leaf -of_objects $ce_net -filter {DIRECTION == OUT}]]
    if {[llength $ce_driver] != 1} { error "snapshot CE lacks unique driver" }
    if {[get_property REF_NAME $ce_driver] ne "VCC"} { incr variable_ce }
  }
  puts $report "$mode drivers=[llength $drivers] max_loads=$maximum total_loads=$total LUT_primitives=$luts FF_primitives=$flops"
  puts $report "$mode snapshot_payload_FFs=[llength $snapshot_regs] variable_CE_pins=$variable_ce"
  flush $report
  if {$mode eq "baseline"} {
    if {$variant eq "fanout" && ([llength $drivers] != 1 || $maximum < 500)} {
      error "baseline high-fanout premise not reproduced"
    }
    if {$variant eq "data-enable" && ([llength $drivers] < 2 || $maximum > 32 || $variable_ce < 500)} {
      error "baseline replicated-enable premise not reproduced"
    }
    set old_loads $total
    set old_payload [llength $snapshot_regs]
  } else {
    if {[llength $drivers] < 2 || $maximum > 32 ||
        ($variant eq "fanout" && $total != $old_loads)} {
      error "replication did not preserve and bound the actual snapshot loads"
    }
    if {$variant eq "data-enable" && ($variable_ce != 0 || [llength $snapshot_regs] != $old_payload)} {
      error "snapshot data-enable remap did not preserve payload registers with constant CE"
    }
  }
  report_utilization -file [file join $output ${mode}_utilization.rpt]
  report_control_sets -verbose -file [file join $output ${mode}_control_sets.rpt]
  report_timing -from $drivers -max_paths 10 -file [file join $output ${mode}_snapshot_paths.rpt]
  write_verilog -mode funcsim -rename_top pilot_snapshot_$mode [file join $output ${mode}_netlist.v]
  write_checkpoint [file join $output ${mode}_synth.dcp]
  close_project
}
if {[exec sha256sum {*}[lsort [glob [file join $frozen *]]]] ne $hashes} { error "frozen sources changed" }
puts $report "PILOT_SNAPSHOT_FANOUT_MEASURED receiver_timing_and_hardware_qualified=false"
close $report
puts "PILOT_SNAPSHOT_FANOUT_MEASURED receiver_timing_and_hardware_qualified=false"
