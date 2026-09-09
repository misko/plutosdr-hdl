# Read-only check of the *actual receiver* descriptor storage/clock structure.
# Unplaced timing-path existence is not physical timing or CDC qualification.
if {$argc != 4} { error "expected CHECKPOINT NEW_OUTPUT HDL_COMMIT CHECKPOINT_SHA256" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set revision [lindex $argv 2]
set expected_hash [lindex $argv 3]
if {![regexp {^[0-9a-f]{40}$} $revision] || ![regexp {^[0-9a-f]{64}$} $expected_hash]} {
  error "full source revision and checkpoint SHA256 required"
}
if {![file isfile $checkpoint] || [file exists $output]} { error "checkpoint must exist and output must be new" }
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint SHA256 mismatch" }
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {[exec git -C $repo rev-parse "${revision}^{commit}"] ne $revision} { error "revision did not resolve" }
file mkdir $output
file copy [file normalize [info script]] [file join $output audit_source.tcl]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z010clg400-1"} { error "wrong receiver part" }
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_receiver_descriptor_BRAM_clock_structure_and_path_existence_only"
puts $report "physical_timing_CDC_RF_hardware_qualified=false"
puts $report "caller_attested_source_revision=$revision source_association_not_derived_from_checkpoint=1"
puts $report "checkpoint_sha256=$expected_hash"
set brams [get_cells -quiet -hier -filter {
  NAME =~ */i_capture_bridge/i_descriptor_fifo/* &&
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1)}]
if {![llength $brams]} { error "receiver descriptor FIFO is not block RAM" }
if {[llength $brams] != 3} { error "unexpected descriptor BRAM bank count" }
set lutram [get_cells -quiet -hier -filter {
  NAME =~ */i_capture_bridge/i_descriptor_fifo/* && IS_PRIMITIVE &&
  REF_NAME =~ RAM* && REF_NAME !~ RAMB*}]
if {[llength $lutram]} { error "descriptor FIFO retains distributed payload memory" }
proc one_clock {pins} {
  set clocks [get_clocks -quiet -of_objects $pins]
  if {[llength $clocks] != 1} { error "expected one actual clock for $pins" }
  return $clocks
}
foreach {domain prefix} {write read_gray_write read write_gray_read} {
  foreach stage {1 2} {
    set cells [get_cells -quiet -hier -regexp \
      [format {.*i_capture_bridge/i_descriptor_fifo/%s_sync_%d_reg\[[0-9]+\]$} $prefix $stage]]
    if {[llength $cells] != 3} { error "descriptor pointer synchronizer must retain three bits per stage" }
    foreach cell $cells {
      if {![get_property ASYNC_REG $cell]} { error "unmarked descriptor synchronizer" }
    }
    set stage_clock [one_clock [get_pins -of_objects $cells -filter {REF_PIN_NAME == C}]]
    if {$stage == 1} { set clocks($domain) $stage_clock } elseif {$stage_clock ne $clocks($domain)} {
      error "descriptor synchronizer stages use different destination clocks"
    }
    puts $report "$domain stage=$stage bits=3 clock=$clocks($domain) period_ns=[get_property PERIOD $clocks($domain)]"
    if {$stage == 1} { set first $cells } else {
      set paths [get_timing_paths -quiet -from $first -to $cells -max_paths 3 -nworst 1]
      if {[llength $paths] != 3} { error "descriptor second synchronization stage is not fully timed" }
      foreach path $paths {
        if {abs([get_property REQUIREMENT $path] - [get_property PERIOD $clocks($domain)]) > 0.001} {
          error "unexpected second-stage pointer timing requirement"
        }
      }
    }
  }
}
if {$clocks(read) eq $clocks(write) || abs([get_property PERIOD $clocks(read)] - 10.0) > 0.001} {
  error "unexpected receiver descriptor read/write clock domains"
}
# Global synthesis absorbs the reducer's 144-bit winner metadata into the two
# RAMB36 output registers. This is NOT the standalone FIFO's DOA_REG=0 shape.
# The actual optimized tracker subtree is tested separately through public AXI
# and RX ports by simulate_global_descriptor_tracker.tcl. This audit only checks
# the observed structural profile and normally timed controls, not equivalence.
set registered_banks 0
set unregistered_banks 0
foreach ram $brams {
  report_property -all $ram -file [file join $output [file tail $ram].rpt]
  set primitive [get_property REF_NAME $ram]
  if {$primitive eq "RAMB36E1"} {
    set expected_width 72
    set expected_register 1
    incr registered_banks
  } elseif {$primitive eq "RAMB18E1"} {
    set expected_width 36
    set expected_register 0
    incr unregistered_banks
  } else { error "unexpected descriptor BRAM primitive" }
  if {[get_property READ_WIDTH_A $ram] != $expected_width ||
      [get_property WRITE_WIDTH_B $ram] != $expected_width ||
      [get_property READ_WIDTH_B $ram] != 0 || [get_property WRITE_WIDTH_A $ram] != 0 ||
      [get_property DOA_REG $ram] != $expected_register ||
      [get_property DOB_REG $ram] != $expected_register} {
    error "descriptor BRAM has unexpected port/latency structure: $ram READ_WIDTH_A=[get_property READ_WIDTH_A $ram] READ_WIDTH_B=[get_property READ_WIDTH_B $ram] WRITE_WIDTH_A=[get_property WRITE_WIDTH_A $ram] WRITE_WIDTH_B=[get_property WRITE_WIDTH_B $ram] DOA_REG=[get_property DOA_REG $ram] DOB_REG=[get_property DOB_REG $ram]"
  }
  foreach {pin domain} {CLKARDCLK read CLKBWRCLK write} {
    set actual [one_clock [get_pins -of_objects $ram -filter "REF_PIN_NAME == $pin"]]
    if {$actual ne $clocks($domain)} { error "descriptor BRAM port clock does not match pointer ownership domain" }
  }
  set address_enable [get_pins -of_objects $ram -filter \
    {REF_PIN_NAME =~ ADDRARDADDR* || REF_PIN_NAME == ENARDEN}]
  set paths [get_timing_paths -quiet -to $address_enable -max_paths 1]
  if {[llength $paths] != 1 || abs([get_property REQUIREMENT $paths] - 10.0) > 0.001} {
    error "descriptor BRAM read control lacks its normal timed path"
  }
  puts $report "bram=$ram primitive=$primitive read_width=$expected_width output_registered=$expected_register read_control_requirement_ns=[get_property REQUIREMENT $paths]"
  if {$expected_register} {
    set register_enable [get_pins -of_objects $ram -filter {REF_PIN_NAME == REGCEAREGCE}]
    set paths [get_timing_paths -quiet -to $register_enable -max_paths 1]
    if {[llength $register_enable] != 1 || [llength $paths] != 1 ||
        abs([get_property REQUIREMENT $paths] - 10.0) > 0.001} {
      error "descriptor fused register enable lacks its normal timed path"
    }
    set sources [all_fanin -quiet -flat -startpoints_only -to $register_enable]
    if {![llength [lsearch -all -glob $sources */g_slice_exact_reducer.i_exact_reducer/*]]} {
      error "descriptor fused register enable has no exact-reducer source"
    }
    puts $report "fused_register_enable_requirement_ns=[get_property REQUIREMENT $paths] sources=$sources"
  }
}
if {$registered_banks != 2 || $unregistered_banks != 1} {
  error "unexpected descriptor BRAM global register-fusion profile"
}
puts $report "global_register_fusion_profile=two_registered_72_bit_banks_one_unregistered_36_bit_bank functional_equivalence_separate=1"
report_cdc -details -file [file join $output cdc.rpt]
report_exceptions -file [file join $output exceptions.rpt]
report_exceptions -ignored -file [file join $output ignored_exceptions.rpt]
if {[lindex [exec sha256sum $checkpoint] 0] ne $expected_hash} { error "checkpoint changed during audit" }
puts $report "DESCRIPTOR_BRAM_STRUCTURE_VERIFIED physical_CDC_timing_unqualified=1"
close $report
close_design
puts "DESCRIPTOR_BRAM_STRUCTURE_VERIFIED physical_CDC_timing_unqualified=1"
