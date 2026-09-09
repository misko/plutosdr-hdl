# Actual old/new output-mailbox synthesis. Synthetic I/O constraints below
# serve this structural experiment only; no receiver timing waiver or route.
if {$argc != 2} { error "expected NEW_OUTPUT_DIRECTORY BASELINE_FULL_COMMIT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $source_dir ../..]]
set output [file normalize [lindex $argv 0]]
set revision [lindex $argv 1]
if {![regexp {^[0-9a-f]{40}$} $revision] ||
    [exec git -C $repo rev-parse "${revision}^{commit}"] ne $revision} {
  error "exact baseline commit required"
}
if {[file exists $output]} { error "output directory must be new" }
set relative library/starlink_pss_acquisition/starlink_pss_block_mailbox.v
set baseline [exec git -C $repo show "${revision}:$relative"]
file mkdir $output
file copy [info script] [file join $output measurement_source.tcl]
set channel [open [file join $output baseline.v] w]
puts $channel $baseline
close $channel
file copy [file join $repo $relative] [file join $output candidate.v]
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_output_mailbox_isolated_synthesis_not_receiver_timing_or_CDC_qualification"
puts $report "baseline_commit=$revision"
puts $report "source_sha256=[exec sha256sum [file join $output baseline.v] [file join $output candidate.v]]"
puts $report "synthetic_input_output_delay_ns=0 fast_clock_ns=5 slow_clock_ns=10"
set_param general.maxThreads 2
foreach variant {baseline candidate} {
  create_project -in_memory -part xc7z010clg400-1
  read_verilog [file join $output ${variant}.v]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -top starlink_pss_block_mailbox -part xc7z010clg400-1 \
    -generic [list ADDRESS_WIDTH=9 DATA_WIDTH=36 METADATA_WIDTH=75 \
      RESET_RELEASE_EXTERNAL=1 EXPLICIT_COMMIT=1]
  create_clock -name fast -period 5.0 [get_ports input_clk]
  create_clock -name slow -period 10.0 [get_ports output_clk]
  set_input_delay -clock fast 0 [get_ports -filter {DIRECTION == IN && NAME != input_clk && NAME != output_clk}]
  set_output_delay -clock fast 0 [get_ports input_framing_fault_now]
  opt_design -directive ExploreArea
  set held [get_cells -quiet -regexp {metadata_in_hold_reg\[[0-9]+\]}]
  set incoming [get_ports -quiet -filter {NAME =~ input_metadata*}]
  if {[llength $held] != 75 || [llength $incoming] != 75} {
    error "expected all75 retained and input metadata bits"
  }
  set destination [get_ports input_framing_fault_now]
  set fanin [all_fanin -flat -only_cells -to $destination]
  set carries [filter $fanin {IS_PRIMITIVE && REF_NAME == CARRY4}]
  set leaf_nets [get_nets -quiet -regexp {balanced_metadata.leaf_equal\[[0-9]+\]}]
  set group_nets [get_nets -quiet -regexp {balanced_metadata.group_equal\[[0-9]+\]}]
  puts $report "variant=$variant framing_fanin_carry4=[llength $carries] leaf_nets=[llength $leaf_nets] group_nets=[llength $group_nets]"
  foreach {name pattern} {LUT LUT* FF FD* DSP DSP48E1 RAM18 RAMB18E1 RAM36 RAMB36E1} {
    set resources [get_cells -quiet -hier -filter [format {IS_PRIMITIVE && REF_NAME =~ %s} $pattern]]
    puts $report "${variant}_${name}=[llength $resources]"
  }
  report_timing -from $held -to $destination -max_paths 10 \
    -file [file join $output ${variant}_held_metadata.rpt]
  report_timing -from $incoming -to $destination -max_paths 10 \
    -file [file join $output ${variant}_incoming_metadata.rpt]
  report_utilization -file [file join $output ${variant}_utilization.rpt]
  write_verilog -mode funcsim [file join $output ${variant}_netlist.v]
  write_checkpoint [file join $output ${variant}_synth.dcp]
  puts $report "${variant}_netlist_sha256=[lindex [exec sha256sum [file join $output ${variant}_netlist.v]] 0]"
  flush $report
  close_project
}
puts $report "MAILBOX_METADATA_TREE_MEASURED receiver_timing_and_hardware_unqualified=1"
close $report
puts "MAILBOX_METADATA_TREE_MEASURED receiver_timing_and_hardware_unqualified=1"
