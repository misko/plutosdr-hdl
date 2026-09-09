# Actual guard/output-mailbox composition, two authorization wirings. Measure
# structural fan-in without interpreting standalone constraints as timing proof.
if {$argc != 1} { error "expected NEW_OUTPUT_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output directory must be new" }
file mkdir $output
file copy [info script] [file join $output measurement_source.tcl]
set paths [list [file join $source_dir starlink_pss_realtime_result_guard.v] \
  [file join $source_dir starlink_pss_block_mailbox.v] \
  [file join $source_dir tb starlink_pss_final_auth_probe.sv]]
set frozen {}
foreach path $paths {
  set target [file join $output [file tail $path]]
  file copy $path $target
  lappend frozen $target
}
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_guard_and_output_mailbox_structural_synthesis_ONLY"
puts $report "source_identity=frozen_hashes_not_clean_commit_claim"
puts $report "source_sha256=[exec sha256sum {*}$frozen]"
set_param general.maxThreads 2
set failed 0
foreach mode {0 1} {
  create_project -in_memory -part xc7z010clg400-1
  read_verilog [lrange $frozen 0 1]
  read_verilog -sv [lindex $frozen 2]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -top starlink_pss_final_auth_probe -part xc7z010clg400-1 \
    -generic USE_FINAL_AUTH=$mode
  create_clock -name fast -period 5.0 [get_ports clk]
  create_clock -name slow -period 10.0 [get_ports slow_clk]
  opt_design -directive ExploreArea
  set cell [get_cells -quiet output_mailbox/request_toggle_reg]
  if {[llength $cell] != 1} { error "missing exact publication register" }
  set pin [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == D}]
  set starts [all_fanin -flat -startpoints_only -to $pin]
  set raw [filter $starts {CLASS == port &&
    (NAME == external_fault_now || NAME == certified_input_beat || NAME == certified_input_complete)}]
  set phase [filter $starts {CLASS == port && NAME == phase_input_fault_now}]
  puts $report "mode=$mode endpoint=$pin raw_input_ports=[llength $raw] phase_ports=[llength $phase]"
  puts $report "startpoints=[lsort $starts]"
  if {($mode == 0 && ![llength $raw]) || ($mode == 1 &&
      ([llength $raw] || [llength $phase] != 1))} { set failed 1 }
  foreach {name pattern} {LUT LUT* FF FD* DSP DSP48E1 RAM18 RAMB18E1 RAM36 RAMB36E1} {
    set cells [get_cells -quiet -hier -filter [format {IS_PRIMITIVE && REF_NAME =~ %s} $pattern]]
    puts $report "mode${mode}_${name}=[llength $cells]"
  }
  # Retain both failed and successful diagnostic netlists before the final gate.
  report_utilization -file [file join $output mode${mode}_utilization.rpt]
  write_verilog -mode funcsim [file join $output mode${mode}_netlist.v]
  write_checkpoint [file join $output mode${mode}_synth.dcp]
  puts $report "mode${mode}_netlist_sha256=[lindex [exec sha256sum [file join $output mode${mode}_netlist.v]] 0]"
  flush $report
  close_project
}
if {$failed} {
  puts $report "FINAL_AUTH_DEPENDENCY_FAILED"
  close $report
  error "final-only authorization did not remove raw-input publication fan-in"
}
puts $report "FINAL_AUTH_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
close $report
puts "FINAL_AUTH_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
