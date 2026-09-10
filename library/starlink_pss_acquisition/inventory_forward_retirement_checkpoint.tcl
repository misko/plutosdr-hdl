# Additive read-only observation; the original DSP helper and every physical
# script stay byte-identical. The first inspection closes its design, then
# this second read observes the same immutable DCP's kernel-control cone.
set forward_inspection_script [file normalize [info script]]
source [file join [file dirname $forward_inspection_script] inventory_payload_dsp_checkpoint.tcl]
file copy $forward_inspection_script [file join $output_dir forward_inventory.tcl]
set_param general.maxThreads 2
open_checkpoint $source_dcp
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {
  error "black box in kernel enable inspection"
}
set kernel_registers [get_cells -quiet -hier -filter {
  NAME =~ joiner/kernel_rom/expected_next_block_start_reg* && REF_NAME =~ FD*
}]
set kernel_enables [get_pins -quiet -of_objects $kernel_registers -filter {REF_PIN_NAME == CE}]
if {![llength $kernel_enables]} { error "no actual expected-next kernel register enables" }
set kernel_inventory [open [file join $output_dir kernel_enable_inventory.txt] w]
puts $kernel_inventory "source_dcp=$source_dcp"
puts $kernel_inventory "source_dcp_sha256=$expected"
puts $kernel_inventory "inspection_only=true; no_design_or_constraint_mutation=true"
puts $kernel_inventory "kernel_register_count=[llength $kernel_registers]"
puts $kernel_inventory "kernel_ce_count=[llength $kernel_enables]"
# Keep the mapping of every actual CE, but inspect common driver cones once.
set kernel_groups [dict create]
foreach kernel_pin [lsort $kernel_enables] {
  set kernel_nets [get_nets -quiet -segments -of_objects $kernel_pin]
  set kernel_drivers [lsort [get_pins -quiet -leaf -of_objects $kernel_nets -filter {DIRECTION == OUT}]]
  puts $kernel_inventory "pin=$kernel_pin nets=[lsort $kernel_nets] drivers=$kernel_drivers"
  dict lappend kernel_groups $kernel_drivers $kernel_pin
}
puts $kernel_inventory "distinct_ce_driver_groups=[dict size $kernel_groups]"
set kernel_group_index 0
dict for {kernel_drivers kernel_pins} $kernel_groups {
  set kernel_pin [lindex $kernel_pins 0]
  set kernel_starts [lsort [all_fanin -flat -startpoints_only -to $kernel_pin]]
  set kernel_cone [lsort [all_fanin -flat -only_cells -to $kernel_pin]]
  puts $kernel_inventory "\nGROUP=$kernel_group_index"
  puts $kernel_inventory "drivers=$kernel_drivers"
  puts $kernel_inventory "destination_pins=$kernel_pins"
  puts $kernel_inventory "startpoints=$kernel_starts"
  puts $kernel_inventory "cone_cells=$kernel_cone"
  set kernel_counts [dict create]
  foreach kernel_cell $kernel_cone {
    dict incr kernel_counts [get_property REF_NAME $kernel_cell]
  }
  puts $kernel_inventory "cone_ref_counts=$kernel_counts"
  foreach {kernel_label kernel_pattern kernel_objects} [list \
    output_bank_held_metadata_starts {output_bank/metadata_in_hold_reg*} $kernel_starts \
    result_descriptor_starts {result_guard/descriptor_reg*} $kernel_starts \
    output_bank_metadata_cells {output_bank/balanced_metadata*} $kernel_cone \
    output_bank_all_cells {output_bank/*} $kernel_cone \
    kernel_identity_cells {joiner/kernel_rom/balanced_block_identity*} $kernel_cone \
    product_bank_metadata_cells {product_bank/balanced_metadata*} $kernel_cone] {
    set kernel_matches [lsearch -all -inline -glob $kernel_objects $kernel_pattern]
    puts $kernel_inventory "$kernel_label.count=[llength $kernel_matches]"
    puts $kernel_inventory "$kernel_label.objects=$kernel_matches"
  }
  foreach kernel_driver $kernel_drivers {
    foreach kernel_cell [get_cells -quiet -of_objects $kernel_driver] {
      puts $kernel_inventory "driver_cell=$kernel_cell ref=[get_property REF_NAME $kernel_cell]"
      if {[lsearch -exact [list_property $kernel_cell] INIT] >= 0} {
        puts $kernel_inventory "driver_INIT=[get_property INIT $kernel_cell]"
      }
    }
  }
  set kernel_paths [get_timing_paths -quiet -to $kernel_pins -delay_type max -max_paths 1]
  if {[llength $kernel_paths]} {
    set kernel_path [lindex $kernel_paths 0]
    puts $kernel_inventory "worst_start=[get_property STARTPOINT_PIN $kernel_path]"
    puts $kernel_inventory "worst_end=[get_property ENDPOINT_PIN $kernel_path]"
    puts $kernel_inventory "worst_slack=[get_property SLACK $kernel_path]"
    report_timing -to $kernel_pins -delay_type max -max_paths 20 \
      -file [file join $output_dir kernel_ce_group_${kernel_group_index}_max.rpt]
  } else {
    puts $kernel_inventory "worst_path=none"
  }
  incr kernel_group_index
}
close $kernel_inventory
close_design
if {[lindex [exec sha256sum $source_dcp] 0] ne $expected} {
  error "checkpoint changed during kernel-control observation"
}
puts "FORWARD_RETIREMENT_KERNEL_CE_INVENTORY_RECORDED_NO_PHYSICAL_MUTATION"
