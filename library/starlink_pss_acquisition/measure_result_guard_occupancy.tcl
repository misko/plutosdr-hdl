# Compare synthesized private occupancy dependencies against a frozen baseline.
# No full receiver, CDC, routed timing or functional-equivalence claim.
if {$argc != 2} { error "expected NEW_OUTPUT BASELINE_FULL_COMMIT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $script_dir ../..]]
set output [file normalize [lindex $argv 0]]
set baseline [lindex $argv 1]
if {![regexp {^[0-9a-f]{40}$} $baseline] ||
    [exec git -C $repo rev-parse "${baseline}^{commit}"] ne $baseline} {
  error "immutable baseline commit required"
}
if {[file exists $output]} { error "refusing to overwrite measurement evidence" }
set relative library/starlink_pss_acquisition/starlink_pss_realtime_result_guard.v
set baseline_source [exec git -C $repo show "${baseline}:$relative"]
file mkdir $output
file copy [info script] [file join $output measurement_source.tcl]
set baseline_path [file join $output baseline_guard.v]
set channel [open $baseline_path w]
puts $channel $baseline_source
close $channel
set candidate_path [file join $output candidate_guard.v]
file copy [file join $repo $relative] $candidate_path
set report [open [file join $output scope.txt] w]
puts $report "scope=isolated_guard_synthesis_dependency_and_resource_comparison"
puts $report "baseline_revision=$baseline candidate_source_identity=sha256_not_clean_commit_claim"
puts $report "baseline_sha256=[lindex [exec sha256sum $baseline_path] 0]"
puts $report "candidate_sha256=[lindex [exec sha256sum $candidate_path] 0]"
puts $report "functional_equivalence_routed_timing_CDC_receiver_qualified=false"
foreach variant {baseline candidate} source [list $baseline_path $candidate_path] \
    occupancy_name {return_valid_reg return_occupied_reg} {
  create_project -in_memory -part xc7z010clg400-1
  read_verilog $source
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -top starlink_pss_realtime_result_guard -part xc7z010clg400-1
  create_clock -name fast -period 5.0 [get_ports clk]
  set_clock_uncertainty 0.15 [get_clocks fast]
  opt_design -directive ExploreArea
  set occupancy [get_cells -quiet $occupancy_name]
  if {[llength $occupancy] != 1} { error "missing exact $variant occupancy register" }
  set data_pin [get_pins -quiet -of_objects $occupancy -filter {REF_PIN_NAME == D}]
  if {[llength $data_pin] != 1} { error "missing occupancy D pin" }
  set starts [all_fanin -flat -startpoints_only -to $data_pin]
  set raw_validation_ports {}
  foreach start $starts {
    if {[get_property CLASS $start] eq "port" &&
        [regexp {^(external_fault_now|mailbox_input_fault|input_bank_reserved|output_bank_reserved|certified_input_beat|certified_input_complete|core_event_frame_started|core_output_tuser\[|core_output_tlast|core_status_tdata\[|core_status_tvalid)} $start]} {
      lappend raw_validation_ports $start
    }
  }
  puts $report "${variant}_occupancy_D_startpoints=[lsort $starts]"
  puts $report "${variant}_raw_validation_ports=[lsort $raw_validation_ports]"
  puts $report "${variant}_raw_validation_port_count=[llength $raw_validation_ports]"
  if {$variant eq "baseline" && ![llength $raw_validation_ports]} {
    error "baseline does not demonstrate the intended current-fault dependency"
  }
  if {$variant eq "candidate" && [llength $raw_validation_ports]} {
    error "candidate still routes current raw validation through occupancy D"
  }
  foreach {label filter} {
    lut {IS_PRIMITIVE && REF_NAME =~ LUT*}
    ff {IS_PRIMITIVE && REF_NAME =~ FD*}
    dsp {IS_PRIMITIVE && REF_NAME == DSP48E1}
    ram18 {IS_PRIMITIVE && REF_NAME == RAMB18E1}
    ram36 {IS_PRIMITIVE && REF_NAME == RAMB36E1}
  } {
    puts $report "${variant}_${label}=[llength [get_cells -quiet -hier -filter $filter]]"
  }
  report_utilization -file [file join $output ${variant}_utilization.rpt]
  report_control_sets -verbose -file [file join $output ${variant}_control_sets.rpt]
  report_timing -to $data_pin -delay_type max -max_paths 10 \
    -file [file join $output ${variant}_occupancy_timing.rpt]
  write_verilog -mode funcsim [file join $output ${variant}_netlist.v]
  write_checkpoint [file join $output ${variant}_synth.dcp]
  puts $report "${variant}_netlist_sha256=[lindex [exec sha256sum [file join $output ${variant}_netlist.v]] 0]"
  close_project
}
puts $report "GUARD_OCCUPANCY_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
close $report
puts "GUARD_OCCUPANCY_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
