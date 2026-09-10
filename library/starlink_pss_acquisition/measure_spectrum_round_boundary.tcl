# Isolated A/B physical measurement, NOT bank or receiver qualification.
# Both choices use identical 18-bit pipeline, clock, IO assumptions and flow.
if {$argc != 2 || [lindex $argv 1] ni {0 1}} {
  error "expected NEW_OUTPUT and literal BOUNDARY_ROUND_SAT 0|1"
}
if {[version -short] ne "2022.2"} { error "Vivado2022.2 required" }
set output_dir [file normalize [lindex $argv 0]]
set option_value [lindex $argv 1]
if {[file exists $output_dir]} { error "refusing to overwrite evidence" }
set source_dir [file dirname [file normalize [info script]]]
set source_files [list starlink_pss_spectrum_product.v measure_spectrum_round_boundary.tcl]
file mkdir $output_dir
set hashes [open [file join $output_dir input_sources.sha256] w]
foreach name $source_files {
  file copy [file join $source_dir $name] [file join $output_dir $name]
  puts $hashes [exec sha256sum [file join $output_dir $name]]
}
close $hashes
cd $output_dir
set_param general.maxThreads 2
read_verilog starlink_pss_spectrum_product.v
synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -directive AreaOptimized_high -top starlink_pss_spectrum_product \
  -part xc7z010clg400-1 -generic [list DATA_WIDTH=18 BOUNDARY_ROUND_SAT=$option_value]
if {[llength [get_ports {input_i[*]}]] != 18} { error "wrong synthesized component width" }
# Logical OOC port budgets, identical to the old product study except for the
# explicitly tested175MHz clock. These are NOT measured ADC/board IO delays.
create_clock -name product_clk -period 5.714 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
set product_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set product_outputs [get_ports -filter {DIRECTION == OUT}]
set_input_delay -clock product_clk -max 1.000 $product_inputs
set_input_delay -clock product_clk -min 0.500 $product_inputs
set_output_delay -clock product_clk -max 0.500 $product_outputs
set_output_delay -clock product_clk -min 0.000 $product_outputs
opt_design -directive ExploreArea
write_checkpoint product_opt.dcp
report_utilization -hierarchical -file utilization_opt.rpt
place_design
phys_opt_design
route_design
write_checkpoint product_route.dcp
report_utilization -hierarchical -file utilization_route.rpt
report_timing_summary -delay_type min_max -max_paths 30 -file timing_route.rpt
report_timing -delay_type max -max_paths 30 -path_type full_clock_expanded -file setup_paths.rpt
report_methodology -file methodology.rpt
report_route_status -file route_status.rpt
check_timing -verbose -file check_timing.rpt
set overflow_pins [get_pins -quiet -of_objects \
  [get_cells -quiet -hier -filter {NAME =~ *output_overflow_reg*}] \
  -filter {REF_PIN_NAME == D}]
if {[llength $overflow_pins] > 0} {
  report_timing -delay_type max -to $overflow_pins -max_paths 20 \
    -path_type full_clock_expanded -file overflow_paths.rpt
}
set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing constrained paths" }
set result [open measurement.txt w]
puts $result "scope=isolated18bit_product_not_bank_or_receiver"
puts $result "boundary_round_sat=$option_value"
puts $result "clock_period_ns=5.714"
puts $result "setup_slack_ns=[get_property SLACK $setup]"
puts $result "hold_slack_ns=[get_property SLACK $hold]"
puts $result "overflow_D_pins=[llength $overflow_pins]"
puts $result "dsp48_count=[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]"
close $result
exec sha256sum -c input_sources.sha256
puts "ROUND_BOUNDARY_PHYSICAL_MEASURED option=$option_value setup=[get_property SLACK $setup] hold=[get_property SLACK $hold]"
close_design
