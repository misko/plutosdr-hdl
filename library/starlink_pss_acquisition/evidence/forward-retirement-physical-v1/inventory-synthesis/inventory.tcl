# Read-only checkpoint inspection, separate from all physical scripts/options.
# Never optimize, place, route, change constraints/properties, or write a DCP.
if {$argc != 3 || [version -short] ne "2022.2"} {
  error "expected Vivado2022.2 SOURCE_DCP EXPECTED_SHA256 NEW_OUTPUT"
}
set source_dcp [file normalize [lindex $argv 0]]
set expected [lindex $argv 1]
set output_dir [file normalize [lindex $argv 2]]
if {[file exists $output_dir]} { error "refusing to overwrite inventory" }
if {![regexp {^[0-9a-f]{64}$} $expected] ||
    [lindex [exec sha256sum $source_dcp] 0] ne $expected} {
  error "unexpected checkpoint input"
}
file mkdir $output_dir
file copy [info script] [file join $output_dir inventory.tcl]
set_param general.maxThreads 2
open_checkpoint $source_dcp
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {
  error "black box in supposedly complete slice"
}
report_clocks -file [file join $output_dir clocks.rpt]
set inventory [open [file join $output_dir dsp_inventory.txt] w]
puts $inventory "source_dcp=$source_dcp"
puts $inventory "source_dcp_sha256=$expected"
puts $inventory "inspection_only=true; no_design_or_constraint_mutation=true"
set dsps [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]
puts $inventory "dsp_count=[llength $dsps]"
if {[llength $dsps] != 21} { error "unexpected complete-slice DSP count" }
set product_count 0
foreach cell [lsort $dsps] {
  set name [get_property NAME $cell]
  puts $inventory "\nCELL=$name"
  # Preserve all actual primitive properties, not preliminary inference text.
  # Vivado exposes primitive generics under CONFIG.* in some netlist views.
  foreach property [lsort [list_property $cell]] {
    puts $inventory "property.$property=[get_property $property $cell]"
  }
  if {![string match "product/*" $name]} { continue }
  incr product_count
  regsub -all {[^A-Za-z0-9_]} $name _ stem
  foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME =~ CE*}]] {
    set pin_name [get_property REF_PIN_NAME $pin]
    set nets [get_nets -quiet -segments -of_objects $pin]
    set drivers [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION == OUT}]
    puts $inventory "enable.$pin_name.nets=[lsort $nets]"
    puts $inventory "enable.$pin_name.drivers=[lsort $drivers]"
    foreach driver $drivers {
      foreach driver_cell [get_cells -quiet -of_objects $driver] {
        set ref [get_property REF_NAME $driver_cell]
        puts $inventory "enable.$pin_name.driver_cell=$driver_cell ref=$ref"
        if {[lsearch -exact [list_property $driver_cell] INIT] >= 0} {
          puts $inventory "enable.$pin_name.driver_INIT=[get_property INIT $driver_cell]"
        }
      }
    }
    set starts [all_fanin -flat -startpoints_only -to $pin]
    set cone [all_fanin -flat -only_cells -to $pin]
    puts $inventory "enable.$pin_name.startpoints=[lsort $starts]"
    puts $inventory "enable.$pin_name.cone_cells=[lsort $cone]"
    set counts [dict create]
    foreach cone_cell $cone {
      dict incr counts [get_property REF_NAME $cone_cell]
    }
    puts $inventory "enable.$pin_name.cone_ref_counts=$counts"
    set paths [get_timing_paths -quiet -to $pin -delay_type max -max_paths 1]
    if {[llength $paths]} {
      set path [lindex $paths 0]
      puts $inventory "enable.$pin_name.worst_start=[get_property STARTPOINT_PIN $path]"
      puts $inventory "enable.$pin_name.worst_end=[get_property ENDPOINT_PIN $path]"
      puts $inventory "enable.$pin_name.slack=[get_property SLACK $path]"
      report_timing -to $pin -delay_type max -max_paths 1 \
        -file [file join $output_dir ${stem}_${pin_name}.rpt]
    } else {
      puts $inventory "enable.$pin_name.timing_path=none"
    }
  }
}
puts $inventory "product_dsp_count=$product_count"
close $inventory
if {$product_count != 4} { error "unexpected product DSP hierarchy" }
close_design
if {[lindex [exec sha256sum $source_dcp] 0] ne $expected} {
  error "checkpoint changed during read-only observation"
}
puts "PAYLOAD_DSP_CHECKPOINT_INVENTORY_RECORDED_NO_PHYSICAL_MUTATION"
