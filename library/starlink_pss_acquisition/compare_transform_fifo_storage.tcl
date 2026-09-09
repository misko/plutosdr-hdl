# Isolated, source-pinned synthesis comparison, NOT receiver fit or timing.
# Usage: vivado ... -source compare_transform_fifo_storage.tcl -tclargs NEW_OUTPUT
if {$argc != 1} { error "expected NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set repo [file normalize [file join $source_dir ../..]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output must be new" }
set baseline_commit ced8a17d21e5ea00a134eb075a095d5ecf435955
set relative_source library/starlink_pss_acquisition/starlink_pss_transform_fifo.v
set baseline [exec git -C $repo show "${baseline_commit}:${relative_source}"]
file mkdir $output
file copy [file normalize [info script]] [file join $output comparison_source.tcl]
set baseline_file [open [file join $output baseline.v] w]
puts $baseline_file $baseline
close $baseline_file
file copy [file join $source_dir starlink_pss_transform_fifo.v] [file join $output candidate.v]
set receipt [open [file join $output scope.txt] w]
puts $receipt "scope=isolated_synthesis_only_not_full_receiver_fit_timing_or_hardware"
puts $receipt "baseline_commit=$baseline_commit"
foreach variant {baseline candidate} {
  set path [file join $output ${variant}.v]
  puts $receipt "${variant}_source_sha256=[lindex [exec sha256sum $path] 0]"
  create_project -in_memory -part xc7z010clg400-1
  read_verilog $path
  synth_design -mode out_of_context -top starlink_pss_transform_fifo \
    -part xc7z010clg400-1 -flatten_hierarchy rebuilt
  report_utilization -file [file join $output ${variant}_utilization.rpt]
  report_control_sets -verbose -file [file join $output ${variant}_control_sets.rpt]
  write_verilog -mode funcsim [file join $output ${variant}_netlist.v]
  puts $receipt "${variant}_netlist_sha256=[lindex [exec sha256sum [file join $output ${variant}_netlist.v]] 0]"
  foreach {label filter} {
    lut {IS_PRIMITIVE && REF_NAME =~ LUT*}
    ff {IS_PRIMITIVE && REF_NAME =~ FD*}
    ram18 {IS_PRIMITIVE && REF_NAME == RAMB18E1}
    ram36 {IS_PRIMITIVE && REF_NAME == RAMB36E1}
    distributed_ram {IS_PRIMITIVE && REF_NAME =~ RAM* && REF_NAME !~ RAMB*}
  } {
    set count [llength [get_cells -quiet -hier -filter $filter]]
    set counts($variant,$label) $count
    puts $receipt "${variant}_${label}=$count"
  }
  close_project
}
if {$counts(candidate,ram18) + $counts(candidate,ram36) == 0} {
  error "candidate did not infer block RAM"
}
puts $receipt "FIFO_STORAGE_COMPARISON_FINISHED hardware_qualified=false"
close $receipt
puts "FIFO_STORAGE_COMPARISON_FINISHED hardware_qualified=false"
