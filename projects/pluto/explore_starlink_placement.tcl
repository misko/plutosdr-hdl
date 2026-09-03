# Explore placement packing for the experimental RX-only PSS build.
#
# This deliberately starts every attempt from the same global-synthesis
# checkpoint.  It never changes project sources or promotes an implementation
# artifact.  A successful attempt is still subject to route, timing, CDC, and
# functional evidence gates before it can become a Stage-15 candidate.
#
# Usage (all attempts):
#   vivado -mode batch -source explore_starlink_placement.tcl -tclargs \
#     /absolute/path/system_top.dcp /absolute/path/output-directory
# Usage (one named attempt):
#   vivado -mode batch -source explore_starlink_placement.tcl -tclargs \
#     /absolute/path/system_top.dcp /absolute/path/output-directory \
#     default_explore

if {$argc != 2 && $argc != 3} {
  error "expected a synthesis checkpoint, output directory, and optional attempt label"
}
if {[version -short] ne "2022.2"} {
  error "placement comparison requires Vivado 2022.2, got [version -short]"
}

set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set requested_label [expr {$argc == 3 ? [lindex $argv 2] : ""}]
file mkdir $output_dir

# The first item is a stable label, followed by opt_design and place_design
# directives.  "Default" means omit the directive exactly as the standard ADI
# implementation run does.
set attempts [list \
  [list default_explore Default Explore] \
  [list area_explore ExploreArea Explore] \
  [list area_spread_high ExploreArea AltSpreadLogic_high] \
  [list area_post_place ExploreArea ExtraPostPlacementOpt] \
  [list area_wirelength ExploreArea WLDrivenBlockPlacement] \
  [list remap_spread_high ExploreWithRemap AltSpreadLogic_high]]

set successful_attempts 0
foreach attempt $attempts {
  lassign $attempt label opt_directive place_directive
  if {$requested_label ne "" && $requested_label ne $label} {
    continue
  }
  puts "STARLINK_PLACE_ATTEMPT_BEGIN label=$label opt=$opt_directive place=$place_directive"
  open_checkpoint $checkpoint

  if {$opt_directive eq "Default"} {
    set opt_failed [catch {opt_design} opt_message]
  } else {
    set opt_failed [catch {
      opt_design -directive $opt_directive
    } opt_message]
  }

  set attempt_dir [file join $output_dir $label]
  file mkdir $attempt_dir
  if {$opt_failed} {
    set summary [open [file join $attempt_dir summary.txt] w]
    puts $summary "status=opt_failed"
    puts $summary "opt_directive=$opt_directive"
    puts $summary "place_directive=$place_directive"
    puts $summary "message=$opt_message"
    close $summary
    puts "STARLINK_PLACE_ATTEMPT_FAIL label=$label stage=opt"
    close_design
    continue
  }

  set place_failed [catch {
    place_design -directive $place_directive
  } place_message]
  report_utilization -file [file join $attempt_dir utilization.rpt]
  report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $attempt_dir timing.rpt]

  set summary [open [file join $attempt_dir summary.txt] w]
  puts $summary "opt_directive=$opt_directive"
  puts $summary "place_directive=$place_directive"
  if {$place_failed} {
    puts $summary "status=place_failed"
    puts $summary "message=$place_message"
    puts "STARLINK_PLACE_ATTEMPT_FAIL label=$label stage=place"
  } else {
    incr successful_attempts
    puts $summary "status=placed"
    set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
    set setup_wns [expr {[llength $setup_path] == 1 ?
        [get_property SLACK $setup_path] : "missing"}]
    puts $summary "setup_wns_ns=$setup_wns"
    write_checkpoint -force [file join $attempt_dir system_top_placed.dcp]
    puts "STARLINK_PLACE_ATTEMPT_PASS label=$label setup_wns_ns=$setup_wns"
  }
  close $summary
  close_design
}

if {$requested_label ne "" && ![file exists [file join $output_dir $requested_label summary.txt]]} {
  error "unknown placement attempt label: $requested_label"
}

puts "STARLINK_PLACE_EXPLORATION_DONE successful_attempts=$successful_attempts"
if {$successful_attempts == 0} {
  exit 1
}
