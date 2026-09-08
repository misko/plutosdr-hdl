# Physical implementation probe of a single 512x36 transform block mailbox.
# Internal paths only; OOC I/O placement and integrated CDC are NOT qualified.
# The metadata bus uses the complete-block ownership protocol, not independent
# synchronizers for each bit. Retain report_cdc for explicit integration review.
if {$argc != 2} { error "expected OUTPUT INPUT_MHZ (100 or 200)" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set output_dir [file normalize [lindex $argv 0]]
set input_mhz [lindex $argv 1]
if {$input_mhz ni {100 200}} { error "requires 100->200 or 200->100 MHz" }
set output_mhz [expr {300 - $input_mhz}]
if {[file exists $output_dir]} { error "refusing to overwrite probe evidence" }
file mkdir $output_dir
set script_dir [file dirname [file normalize [info script]]]
read_verilog [file join $script_dir starlink_pss_block_mailbox.v]
synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high -top starlink_pss_block_mailbox -part xc7z010clg400-1
create_clock -name mailbox_in -period [expr {1000.0 / $input_mhz}] [get_ports input_clk]
create_clock -name mailbox_out -period [expr {1000.0 / $output_mhz}] [get_ports output_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports input_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports output_clk]
set_input_delay -clock mailbox_in -max 1.0 [get_ports {input_valid input_data* input_position* input_last input_metadata*}]
set_input_delay -clock mailbox_in -min 0.0 [get_ports {input_valid input_data* input_position* input_last input_metadata*}]
set_output_delay -clock mailbox_in -max 1.0 [get_ports {input_ready input_fault}]
set_output_delay -clock mailbox_in -min 0.0 [get_ports {input_ready input_fault}]
set_input_delay -clock mailbox_out -max 1.0 [get_ports output_ready]
set_input_delay -clock mailbox_out -min 0.0 [get_ports output_ready]
set_output_delay -clock mailbox_out -max 1.0 [get_ports {output_valid output_data* output_position* output_last output_metadata*}]
set_output_delay -clock mailbox_out -min 0.0 [get_ports {output_valid output_data* output_position* output_last output_metadata*}]
set_false_path -from [get_ports {input_resetn output_resetn}]
# Bound only the asynchronous launch -> first synchronizer stage, leaving the
# second stage conventionally timed. There are no blanket clock-group waivers.
foreach {launch first_stage destination_mhz} [list \
    request_toggle_reg {request_sync_reg[0]} $output_mhz \
    acknowledge_toggle_reg {acknowledge_sync_reg[0]} $input_mhz] {
  set start [get_cells -quiet $launch]
  set stop [get_cells -quiet $first_stage]
  if {[llength $start] != 1 || [llength $stop] != 1} { error "missing ownership synchronizer" }
  set_max_delay -datapath_only [expr {1000.0 / $destination_mhz}] -from $start -to $stop
}
# Metadata is captured before the final input beat commits the block, remains
# unchanged until ACK returns, and is latched only after synchronized request.
# Bound the bundled bus to two destination cycles, much shorter than that hold.
set metadata_source [get_cells -quiet -regexp {metadata_in_hold_reg\[[0-9]+\]}]
set metadata_destination [get_cells -quiet -regexp {metadata_out_hold_reg\[[0-9]+\]}]
if {[llength $metadata_source] != 70 || [llength $metadata_destination] != 70} {
  error "missing exact 70-bit held metadata bus"
}
set_max_delay -datapath_only [expr {2000.0 / $output_mhz}] \
  -from $metadata_source -to $metadata_destination
opt_design -directive ExploreArea
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
write_checkpoint [file join $output_dir mailbox_routed.dcp]
report_utilization -file [file join $output_dir utilization.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $output_dir timing.rpt]
report_cdc -details -file [file join $output_dir cdc.rpt]
report_exceptions -file [file join $output_dir exceptions.rpt]
report_methodology -file [file join $output_dir methodology.rpt]
report_route_status -file [file join $output_dir route_status.rpt]
check_timing -verbose -file [file join $output_dir check_timing.rpt]
set registers [all_registers]
set setup [get_timing_paths -quiet -from $registers -to $registers -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -from $registers -to $registers -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing internal timing paths" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set channel [open [file join $output_dir summary.txt] w]
puts $channel "scope=standalone_mailbox_storage_and_internal_timing_NOT_integrated_CDC_IO_receiver"
puts $channel "input_mhz=$input_mhz"
puts $channel "output_mhz=$output_mhz"
puts $channel "setup_wns_ns=$wns"
puts $channel "hold_whs_ns=$whs"
puts $channel "bram18=[llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]"
puts $channel "bram36=[llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]"
puts $channel "input_metadata_bits=[llength $metadata_source]"
puts $channel "integrated_cdc_qualified=false"
puts $channel "whole_receiver_qualified=false"
puts $channel "source_sha256=[exec sha256sum [file join $script_dir starlink_pss_block_mailbox.v]]"
close $channel
if {$wns < 0 || $whs < 0} { error "mailbox internal timing failed WNS=$wns WHS=$whs" }
puts "BLOCK_MAILBOX_INTERNAL_TIMING_PASS INPUT_MHZ=$input_mhz OUTPUT_MHZ=$output_mhz WNS=$wns WHS=$whs CDC_IO_RECEIVER_UNQUALIFIED"
close_design
