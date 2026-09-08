# Read-only netlist diagnostics; does not modify/reuse the implementation run.
# Usage: vivado ... -tclargs CHECKPOINT NEW_OUTPUT_DIRECTORY
if {$argc != 2} { error "expected checkpoint and new output directory" }
set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite netlist evidence" }
file mkdir $output_dir
cd $output_dir
open_checkpoint $checkpoint
# A standalone synthesis DCP does not carry the project's implementation-only
# board clocks/pin constraints. Read their actual source, not surrogate clocks.
read_xdc [file join $script_dir system_constr.xdc]
read_xdc [file join $script_dir ../../library/starlink_pss_acquisition/starlink_pss_shared_xfft_constr.xdc]
source [file join $script_dir shared_xfft_impl_gate.tcl]
report_utilization -hierarchical -hierarchical_depth 12 -file utilization_hierarchical.rpt
report_control_sets -verbose -file control_sets.rpt
report_timing_summary -delay_type min_max -max_paths 20 -file timing.rpt
puts "SHARED_RECEIVER_NETLIST_INSPECTED_NOT_A_NEW_IMPLEMENTATION"
close_design
