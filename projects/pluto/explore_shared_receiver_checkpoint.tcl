# Bounded physical implementation experiment on a saved, source-pinned design.
# Own constraints are retained; no clocks, timing exceptions, or RTL are changed.
# No bitstream is produced. Even positive slack is not deployment qualification.
if {$argc != 3} { error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY spread-high|spread-medium|place-explore|area-explore|post-route" }
set script_dir [file dirname [file normalize [info script]]]
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set mode [lindex $argv 2]
if {$mode ni {spread-high spread-medium place-explore area-explore post-route}} { error "unsupported implementation experiment" }
if {![file isfile $checkpoint]} { error "missing input checkpoint" }
if {[file exists $output_dir]} { error "refusing to overwrite experiment evidence" }
file mkdir $output_dir
if {$mode in {place-explore area-explore}} {
  file copy [file normalize [info script]] [file join $output_dir trial_source.tcl.txt]
}
cd $output_dir
open_checkpoint $checkpoint
source [file join $script_dir shared_xfft_impl_gate.tcl]
set provenance [open input.txt w]
puts $provenance "checkpoint=$checkpoint"
puts $provenance "checkpoint_sha256=[exec sha256sum $checkpoint]"
puts $provenance "mode=$mode"
puts $provenance "timing_constraints_changed=false"
puts $provenance "hardware_qualified=false"
puts $provenance "additional_area_optimization=[expr {$mode eq {area-explore}}]"
close $provenance
if {$mode ne "post-route"} {
  # Bounded UG904 spread-placement variants, followed by one post-route Explore
  # pass. Input must be the full receiver's pre-placement opt DCP.
  # Explicit bounded alternatives after both spreading modes fail packing.
  # UG835 v2022.2 documents Explore's extra placement effort and ExploreArea's
  # LUT-area re-synthesis. Neither changes RTL, clocks, or timing exceptions.
  # https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/opt_design
  # https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/place_design
  if {$mode eq "area-explore"} {
    opt_design -directive ExploreArea
    write_checkpoint area_optimized.dcp
    # Recheck the complete receiver/CDC contract after netlist optimization.
    source [file join $script_dir shared_xfft_impl_gate.tcl]
  }
  if {$mode eq "place-explore"} {
    place_design -directive Explore
  } elseif {$mode in {spread-high area-explore}} {
    place_design -directive AltSpreadLogic_high
  } else {
    place_design -directive AltSpreadLogic_medium
  }
  write_checkpoint spread_placed.dcp
  phys_opt_design -directive AggressiveExplore
  route_design -directive AlternateCLBRouting
  write_checkpoint spread_routed.dcp
}
phys_opt_design -directive Explore
write_checkpoint result_routed.dcp
report_utilization -hierarchical -hierarchical_depth 12 -file utilization.rpt
report_timing_summary -report_unconstrained -delay_type min_max -max_paths 25 -file timing.rpt
report_bus_skew -file bus_skew.rpt
report_route_status -file route_status.rpt
report_methodology -file methodology.rpt
check_timing -verbose -file check_timing.rpt
set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup] != 1 || [llength $hold] != 1} { error "missing timing evidence" }
set summary [open summary.txt w]
puts $summary "mode=$mode"
puts $summary "setup_wns_ns=[get_property SLACK $setup]"
puts $summary "hold_whs_ns=[get_property SLACK $hold]"
puts $summary "hardware_qualified=false"
puts $summary "scope=physical_experiment_only_not_deployment"
close $summary
puts "SHARED_RECEIVER_PHYSICAL_EXPERIMENT_FINISHED_NOT_DEPLOYMENT_QUALIFICATION"
close_design
