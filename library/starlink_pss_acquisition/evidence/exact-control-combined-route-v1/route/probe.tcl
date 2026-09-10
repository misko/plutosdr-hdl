# One diagnostic implementation, same inherited100/175 resource constraints as
# bank-owned169f9fb. No timing exception, external-I/O qualification or release.
if {$argc != 3 || [version -short] ne "2022.2"} {
  error "expected Vivado2022.2 SOURCE_DCP EXPECTED_SHA256 NEW_OUTPUT"
}
set source_dcp [file normalize [lindex $argv 0]]
set expected [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {[file exists $output_dir]} { error "refusing to overwrite evidence" }
if {![regexp {^[0-9a-f]{64}$} $expected] ||
    [lindex [exec sha256sum $source_dcp] 0] ne $expected} {
  error "unexpected synthesized input"
}
file mkdir $output_dir
file copy [info script] [file join $output_dir probe.tcl]
set_param general.maxThreads 2
open_checkpoint $source_dcp
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {
  error "black box in supposedly complete slice"
}
foreach {name period} {source_100 10.0 island_175 5.714} {
  set clock [get_clocks -quiet $name]
  if {[llength $clock] != 1 || abs([get_property PERIOD $clock]-$period) > 0.00001} {
    error "unexpected diagnostic clock $name"
  }
}
report_clocks -file [file join $output_dir clocks_before.rpt]
write_xdc [file join $output_dir inherited_constraints.xdc]
opt_design
place_design
phys_opt_design
route_design
report_route_status -file [file join $output_dir route_status.rpt]
report_utilization -file [file join $output_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $output_dir hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 \
  -file [file join $output_dir timing_unqualified.rpt]
check_timing -verbose -file [file join $output_dir check_timing_unqualified.rpt]
report_cdc -details -file [file join $output_dir cdc_unqualified.rpt]
set receipt [open [file join $output_dir receipt.txt] w]
puts $receipt "source_dcp_sha256=$expected"
puts $receipt "scope=isolated_completed_input_bank_owned_100_175_diagnostic_not_receiver"
foreach name {source_100 island_175} {
  foreach kind {max min} {
    set paths [get_timing_paths -quiet -from [get_clocks $name] \
      -to [get_clocks $name] -delay_type $kind -max_paths 1]
    if {[llength $paths] != 1} { error "missing internal timing path $name $kind" }
    set path [lindex $paths 0]
    puts $receipt "$name.$kind.slack=[get_property SLACK $path]"
    puts $receipt "$name.$kind.start=[get_property STARTPOINT_PIN $path]"
    puts $receipt "$name.$kind.end=[get_property ENDPOINT_PIN $path]"
    report_timing -from [get_clocks $name] -to [get_clocks $name] \
      -delay_type $kind -max_paths 20 -file [file join $output_dir ${name}_${kind}.rpt]
  }
}
puts $receipt "external_IO_CDC_and_full_receiver_unqualified=true"
puts $receipt "deployment_eligible=false"
close $receipt
write_checkpoint [file join $output_dir completed_input_diagnostic_routed.dcp]
close_design
if {[lindex [exec sha256sum $source_dcp] 0] ne $expected} {
  error "source checkpoint changed during observation"
}
puts "COMPLETED_INPUT_DIAGNOSTIC_RECORDED_NOT_A_PHYSICAL_RELEASE_PASS"
