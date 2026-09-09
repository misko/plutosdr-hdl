# Storage-only experiment for the existing 161-bit, three-usable-entry capture
# descriptor FIFO. Does NOT change capture_bridge's selected implementation.
# Not a CDC, functional-equivalence, timing, or complete-receiver fit gate.
if {$argc != 1} { error "expected NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output must be new" }
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach path [list [info script] [file join $source_dir starlink_pss_async_fifo.v] \
    [file join $source_dir starlink_pss_capture_bridge.v]] {
  file copy $path $frozen
}
set receipt [open [file join $output scope.txt] w]
puts $receipt "scope=isolated_descriptor_fifo_storage_selection_experiment_no_runtime_change"
puts $receipt "DATA_WIDTH=161 ADDRESS_WIDTH=2 usable_entries=3"
puts $receipt "source_revision=[exec git -C $source_dir rev-parse HEAD]"
puts $receipt "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]]]"
foreach storage {distributed block} {
  create_project -in_memory -part xc7z010clg400-1
  read_verilog [file join $frozen starlink_pss_async_fifo.v]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -generic DATA_WIDTH=161 -generic ADDRESS_WIDTH=2 -generic RAM_STYLE=$storage \
    -top starlink_pss_async_fifo -part xc7z010clg400-1
  opt_design -directive ExploreArea
  report_utilization -file [file join $output ${storage}_utilization.rpt]
  report_control_sets -verbose -file [file join $output ${storage}_control_sets.rpt]
  write_verilog -mode funcsim [file join $output ${storage}_netlist.v]
  puts $receipt "${storage}_netlist_sha256=[lindex [exec sha256sum [file join $output ${storage}_netlist.v]] 0]"
  foreach {label filter} {
    ff {IS_PRIMITIVE && REF_NAME =~ FD*}
    ram18 {IS_PRIMITIVE && REF_NAME == RAMB18E1}
    ram36 {IS_PRIMITIVE && REF_NAME == RAMB36E1}
  } {
    puts $receipt "${storage}_${label}=[llength [get_cells -quiet -hier -filter $filter]]"
  }
  close_project
}
puts $receipt "DESCRIPTOR_STORAGE_MEASURED equivalence_CDC_timing_receiver_fit_qualified=false"
close $receipt
puts "DESCRIPTOR_STORAGE_MEASURED equivalence_CDC_timing_receiver_fit_qualified=false"
