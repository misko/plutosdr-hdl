# Actual globally optimized tracker subtree, through public AXI and RX ports.
# A functional test only: no ADC/IIO/RF, routed timing, or CDC clearance claim.
if {$argc != 2} { error "expected CONTEXT_DIRECTORY NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set context [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
if {[file exists $output]} { error "output must be new" }
set netlist [file join $context tracker_bd_netlist.v]
set receipt_path [file join $context context.txt]
if {![file isfile $netlist] || ![file isfile $receipt_path]} { error "missing frozen netlist context" }
set netlist_hash [lindex [exec sha256sum $netlist] 0]
set channel [open $receipt_path r]
set receipt_text [read $channel]
close $channel
if {[string first "$netlist_hash  $netlist" $receipt_text] < 0 ||
    [llength [lsearch -all -exact [split $receipt_text "\n"] \
      {DESCRIPTOR_CONTEXT_INSPECTED functional_and_physical_qualified=false}]] != 1} {
  error "incomplete or mismatched netlist export receipt"
}
set expected_origin {tracker_bd lopt_startpoints=i_system_wrapper/system_i/axi_ad9361/inst/i_rx/i_up_adc_common/i_xfer_cntrl/d_data_cntrl_int_reg[0]/C}
if {[llength [lsearch -all -exact [split $receipt_text "\n"] $expected_origin]] != 1} {
  error "unqualified global lopt source"
}
set frozen [file join $output frozen_sources]
file mkdir $frozen
foreach path [list [info script] $netlist $receipt_path \
    [file join $source_dir tb tb_axi_starlink_pss_tracker.sv] \
    [file join $source_dir ../common/up_adc_common.v] \
    [file join $source_dir ../../projects/pluto/system_bd.tcl] \
    [file join $source_dir ../starlink_pss_acquisition/verify_realtime_probe_result.tcl]] {
  file copy $path $frozen
}
set report [open [file join $output scope.txt] w]
puts $report "scope=globally_optimized_tracker_subtree_public_AXI_RX_functional_test"
puts $report "board_contract=15MS_shared_paired_injection_disabled_timestamp_equals_index_lopt_equals_not_sample_reset"
puts $report "netlist_sha256=$netlist_hash"
puts $report "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]]]"
puts $report "ADC_DMA_IIO_RF_physical_CDC_timing_qualified=false"
close $report
source [file join $frozen verify_realtime_probe_result.tcl]
set project_dir [file join $output project]
create_project global_tracker $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [file join $frozen tracker_bd_netlist.v]
add_files -fileset sim_1 -norecurse [file join $frozen tb_axi_starlink_pss_tracker.sv]
set_property verilog_define STARLINK_TRACKER_GLOBAL_NETLIST [get_filesets sim_1]
set_property top tb_axi_starlink_pss_tracker [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
file mkdir [file join $project_dir global_tracker.sim sim_1 behav xsim build]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log_path [file join $project_dir global_tracker.sim sim_1 behav xsim simulate.log]
require_realtime_probe_pass $log_path [list \
  {AXI_TRACKER_PASS rate=15 taps=66 lags=61 winner_lag=30 packet_words=26 telemetry=serial_bram concurrent_snapshot=1 deferred_candidate=1 irq=level reset_epoch=coordinated}] \
  AXI_TRACKER_PASS 1
require_realtime_probe_pass $log_path [list \
  {AXI_TRACKER_METADATA_PASS checked_packets=3 retained_for_epoch_reset=1}] \
  AXI_TRACKER_METADATA_PASS 1
close_project
set report [open [file join $output scope.txt] a]
puts $report "result_log_sha256=[lindex [exec sha256sum $log_path] 0]"
puts $report "GLOBAL_DESCRIPTOR_TRACKER_FUNCTIONAL_VERIFIED hardware_and_timing_qualified=false"
close $report
puts "GLOBAL_DESCRIPTOR_TRACKER_FUNCTIONAL_VERIFIED hardware_and_timing_qualified=false"
