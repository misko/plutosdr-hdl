# Read-only resource inventory of a caller-attested saved receiver checkpoint.
# Never synthesizes/optimizes/places/routes or changes a constraint/checkpoint.
if {$argc != 4} { error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY HDL_COMMIT CHECKPOINT_SHA256" }
if {[version -short] ne "2022.2"} { error "resource audit requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set revision [lindex $argv 2]
set expected_hash [lindex $argv 3]
if {![regexp {^[0-9a-f]{40}$} $revision] || ![regexp {^[0-9a-f]{64}$} $expected_hash]} {
  error "full source revision and checkpoint SHA256 required"
}
if {![file isfile $checkpoint] || [file exists $output]} {
  error "checkpoint must exist and audit output must be new"
}
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint SHA256 mismatch" }
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {[exec git -C $repo rev-parse "${revision}^{commit}"] ne $revision} {
  error "source revision did not resolve exactly"
}
file mkdir $output
file copy [file normalize [info script]] [file join $output audit_source.tcl]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} { error "wrong receiver part" }
set receipt [open [file join $output scope.txt] w]
puts $receipt "scope=read_only_checkpoint_resource_inventory_not_fit_timing_or_hardware_qualification"
puts $receipt "checkpoint=$checkpoint"
puts $receipt "checkpoint_sha256=$expected_hash"
puts $receipt "caller_attested_source_revision=$revision"
puts $receipt "source_association_not_derived_from_checkpoint=1"
report_utilization -file [file join $output utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 12 -file [file join $output hierarchy.rpt]
report_control_sets -verbose -file [file join $output control_sets.rpt]
set storage [open [file join $output storage.tsv] w]
puts $storage "primitive\tinstance"
foreach cell [lsort [get_cells -quiet -hier -filter \
    {IS_PRIMITIVE && (REF_NAME =~ RAM* || REF_NAME =~ SRL*)}]] {
  puts $storage "[get_property REF_NAME $cell]\t$cell"
}
close $storage
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint changed during audit" }
puts $receipt "RESOURCE_INVENTORY_FINISHED hardware_qualified=false"
close $receipt
close_design
puts "RESOURCE_INVENTORY_FINISHED hardware_qualified=false"
