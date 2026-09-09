# Compare actual old/new input-checker cursor fan-in for both identity modes.
# No routing, timing waiver, or full-receiver qualification is performed.
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
set relative library/starlink_pss_acquisition/starlink_pss_realtime_input_guard.v
set baseline [exec git -C $repo show "${revision}:$relative"]
file mkdir $output
file copy [info script] [file join $output measurement_source.tcl]
set channel [open [file join $output baseline.v] w]
puts $channel $baseline
close $channel
file copy [file join $repo $relative] [file join $output candidate.v]
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_input_checker_cursor_structural_synthesis_ONLY"
puts $report "baseline_commit=$revision"
puts $report "source_sha256=[exec sha256sum [file join $output baseline.v] [file join $output candidate.v]]"
set_param general.maxThreads 2
set failed 0
foreach identity {0 1} {
  foreach variant {baseline candidate} {
    create_project -in_memory -part xc7z010clg400-1
    read_verilog [file join $output ${variant}.v]
    synth_design -mode out_of_context -flatten_hierarchy rebuilt \
      -directive AreaOptimized_high -control_set_opt_threshold 4 \
      -top starlink_pss_realtime_input_guard -part xc7z010clg400-1 \
      -generic CHECK_INPUT_BLOCK_IDENTITY=$identity
    create_clock -name fast -period 5.0 [get_ports clk]
    opt_design -directive ExploreArea
    set cells [get_cells -quiet -regexp {expected_position_reg\[[0-9]+\]}]
    if {[llength $cells] != 9} { error "expected exactly nine cursor registers" }
    set pins [get_pins -quiet -of_objects $cells -filter {REF_PIN_NAME == D || REF_PIN_NAME == CE}]
    set starts [all_fanin -flat -startpoints_only -to $pins]
    set metadata [filter $starts {CLASS == port &&
      (NAME =~ input_position* || NAME =~ input_metadata* || NAME == input_last)}]
    puts $report "identity=$identity variant=$variant metadata_ports=[llength $metadata] startpoints=[lsort $starts]"
    if {($variant eq "baseline" && ![llength $metadata]) ||
        ($variant eq "candidate" && [llength $metadata])} { set failed 1 }
    foreach {name pattern} {LUT LUT* FF FD* DSP DSP48E1 RAM18 RAMB18E1 RAM36 RAMB36E1} {
      set resources [get_cells -quiet -hier -filter [format {IS_PRIMITIVE && REF_NAME =~ %s} $pattern]]
      puts $report "${variant}_${identity}_${name}=[llength $resources]"
    }
    write_verilog -mode funcsim [file join $output ${variant}_${identity}_netlist.v]
    write_checkpoint [file join $output ${variant}_${identity}_synth.dcp]
    puts $report "${variant}_${identity}_netlist_sha256=[lindex [exec sha256sum [file join $output ${variant}_${identity}_netlist.v]] 0]"
    flush $report
    close_project
  }
}
if {$failed} {
  puts $report "INPUT_CURSOR_DEPENDENCY_FAILED"
  close $report
  error "input cursor still depends on presented metadata"
}
puts $report "INPUT_CURSOR_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
close $report
puts "INPUT_CURSOR_DEPENDENCY_MEASURED whole_receiver_and_timing_unqualified=1"
