# Read-only structural comparison of the PIL1 quiescent CLEAR reset cut.
# A disconnected combinational cone is not timing closure or RF qualification.
if {$argc != 5} {
  error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY HDL_COMMIT CHECKPOINT_SHA256 old|registered"
}
if {[version -short] ne "2022.2"} { error "pilot CLEAR audit requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set source_revision [lindex $argv 2]
set expected_checkpoint_sha256 [lindex $argv 3]
set expected_mode [lindex $argv 4]
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {$expected_mode ni {old registered}} { error "CLEAR mode must be old or registered" }
if {![regexp {^[0-9a-f]{40}$} $source_revision]} { error "HDL source must be a full immutable commit" }
if {![regexp {^[0-9a-f]{64}$} $expected_checkpoint_sha256]} { error "expected checkpoint SHA256 required" }
if {![file isfile $checkpoint]} { error "missing input checkpoint" }
if {[file exists $output_dir]} { error "refusing to overwrite pilot CLEAR evidence" }
set checkpoint_sha256 [lindex [exec sha256sum $checkpoint] 0]
if {$checkpoint_sha256 ne $expected_checkpoint_sha256} { error "checkpoint SHA256 mismatch" }
if {[exec git -C $repo rev-parse "${source_revision}^{commit}"] ne $source_revision} {
  error "source commit did not resolve exactly"
}
set pilot_source [exec git -C $repo show "${source_revision}:library/axi_starlink_pilot_capture/axi_starlink_pilot_capture.v"]
if {$expected_mode eq "registered"} {
  if {![regexp {reg clear_ok;} $pilot_source] || ![regexp {clear_ok <= clear_admit;} $pilot_source]} {
    error "source commit does not contain the registered CLEAR cut"
  }
} elseif {![regexp {wire clear_ok = clear_request && !active && empty;} $pilot_source]} {
  error "source commit does not contain the original combinational CLEAR"
}
file mkdir $output_dir
file copy [file normalize [info script]] [file join $output_dir audit_source.tcl]
set source_file [open [file join $output_dir pilot_source.v] w]
puts $source_file $pilot_source
close $source_file
cd $output_dir
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} {
  error "pilot CLEAR audit requires the complete xc7z010 receiver"
}
set fifo_sources [get_cells -quiet -hier -regexp \
  {.*starlink_pilot_capture/inst/fifo_count_reg\[[0-9]+\]$}]
set clear_sources [get_cells -quiet -hier -regexp \
  {.*starlink_pilot_capture/inst/.*clear_ok_reg(_replica[^/]*)?$}]
set endpoints [get_pins -quiet -hier -regexp \
  {.*starlink_pilot_capture/inst/ddc/fir3/job_index_reg\[[0-9]+\]/(CE|D)$}]
if {[llength $fifo_sources] != 6 || [llength $endpoints] != 128} {
  error "missing expected six FIFO count registers or 128 FIR job-index CE/D pins; do not infer isolation"
}
if {($expected_mode eq "old" && [llength $clear_sources] != 0) ||
    ($expected_mode eq "registered" && [llength $clear_sources] != 1)} {
  error "registered CLEAR source inventory does not match the pinned source mode"
}
foreach source [concat $fifo_sources $clear_sources] {
  if {![get_property IS_SEQUENTIAL $source]} { error "expected sequential source $source" }
}
set fifo_names [get_property NAME $fifo_sources]
set clear_names {}
if {[llength $clear_sources]} { set clear_names [get_property NAME $clear_sources] }
set report [open fanin.txt w]
puts $report "checkpoint=$checkpoint"
puts $report "checkpoint_sha256=$checkpoint_sha256"
puts $report "hdl_source_revision=$source_revision"
puts $report "pilot_source_sha256=[lindex [exec sha256sum pilot_source.v] 0]"
puts $report "source_association=caller_attested_build_provenance_not_derived_from_checkpoint"
puts $report "scope=structural_combinational_fanin_not_path_sensitization_or_timing_closure"
puts $report "hardware_qualified=false"
puts $report "expected_mode=$expected_mode"
puts $report "fifo_count_registers=[llength $fifo_sources]"
puts $report "registered_clear_sources=[llength $clear_sources]"
puts $report "job_index_control_pins=[llength $endpoints]"
set fifo_dependent 0
set clear_dependent 0
foreach endpoint [lsort $endpoints] {
  set starts [all_fanin -flat -startpoints_only -only_cells -to $endpoint]
  set names [lsort -unique [get_property NAME $starts]]
  set fifo_hits {}
  set clear_hits {}
  foreach name $fifo_names { if {[lsearch -exact $names $name] >= 0} { lappend fifo_hits $name } }
  foreach name $clear_names { if {[lsearch -exact $names $name] >= 0} { lappend clear_hits $name } }
  if {[llength $fifo_hits]} { incr fifo_dependent }
  if {[llength $clear_hits]} { incr clear_dependent }
  puts $report "endpoint=$endpoint fifo_count_sources=[llength $fifo_hits] registered_clear_sources=[llength $clear_hits]"
  foreach name $names { puts $report "  startpoint=$name" }
}
puts $report "fifo_count_dependent_endpoints=$fifo_dependent"
puts $report "registered_clear_dependent_endpoints=$clear_dependent"
close $report
# Do not invent clocks when inspecting a synthesis checkpoint. Its structural
# inventory is useful even when board clocks are absent from this checkpoint.
report_timing -from [concat $fifo_sources $clear_sources] -to $endpoints \
  -max_paths 25 -nworst 1 -file source_paths.rpt
if {$expected_mode eq "old" && $fifo_dependent == 0} { error "original dependency was not reproduced" }
if {$expected_mode eq "registered" && ($fifo_dependent != 0 || $clear_dependent == 0)} {
  error "registered CLEAR cut was not established"
}
puts "PILOT_CLEAR_FANIN_AUDIT_FINISHED mode=$expected_mode fifo_dependent=$fifo_dependent clear_dependent=$clear_dependent hardware_qualified=false"
close_design
