# Bounded storage-only comparison of the unchanged 160-bit, seven-usable-entry
# asynchronous command FIFO. Not a CDC, I/O timing, or complete receiver gate.
# Usage: vivado -mode batch -source measure_command_fifo_storage.tcl -tclargs OUTPUT
if {$argc != 1} { error "expected output directory" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir
foreach storage {block distributed} {
  read_verilog [file join $script_dir starlink_pss_async_fifo.v]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -generic DATA_WIDTH=160 -generic ADDRESS_WIDTH=3 -generic RAM_STYLE=$storage \
    -top starlink_pss_async_fifo -part xc7z010clg400-1
  opt_design -directive ExploreArea
  report_utilization -file [file join $output_dir ${storage}_utilization.rpt]
  report_control_sets -verbose -file [file join $output_dir ${storage}_control_sets.rpt]
  write_checkpoint -force [file join $output_dir ${storage}_opt.dcp]
  puts "COMMAND_FIFO_STORAGE_MEASURED style=$storage timing_and_cdc_qualified=false"
  close_design
}
