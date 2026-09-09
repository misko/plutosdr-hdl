# Isolated, explicitly authorized physical experiment; never a production hook.
# No clock/constraint/RTL/IP edits, retiming, broad directives, or hardware.
if {$argc != 6} {
  error "expected CHECKPOINT NEW_OUTPUT_DIRECTORY HDL_COMMIT SHA256 MODE TRIAL_ID"
}
if {[version -short] ne "2022.2"} {error "direction trial requires Vivado 2022.2"}
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
set source_revision [lindex $argv 2]
set expected_sha256 [lindex $argv 3]
set trial_mode [lindex $argv 4]
set trial_id [lindex $argv 5]
set authorized_revision 0463f887d592452c940d3c70589becc330d70a0c
# Independently sealed final0463 artifact; no mutable path is trusted.
set authorized_sha256 bc9060040b8577c780b4df1b8ecf482986a744563c510e1bd13150c1b01e7e3a
set authorized_trial_id shared-realtime-0463-direction-replication-v1
set repo [file normalize [file join [file dirname [info script]] ../..]]
if {$trial_mode ni {inspect replicate}} {error "mode must be inspect or replicate"}
if {![regexp {^[0-9a-f]{40}$} $source_revision]} {error "full immutable HDL commit required"}
if {![regexp {^[0-9a-f]{64}$} $expected_sha256]} {error "checkpoint SHA256 required"}
if {$trial_mode eq "inspect" && $trial_id ne "read-only-inspection"} {
  error "inspect requires read-only-inspection identity"
}
if {$trial_mode eq "replicate" && ($authorized_sha256 eq {} ||
    $source_revision ne $authorized_revision || $expected_sha256 ne $authorized_sha256 ||
    $trial_id ne $authorized_trial_id)} {
  error "replication artifact/source/trial identity is not authorized"
}
if {![file isfile $checkpoint]} {error "missing checkpoint"}
if {[file exists $output_dir]} {error "refusing to overwrite direction trial evidence"}
if {[lindex [exec sha256sum -- $checkpoint] 0] ne $expected_sha256} {
  error "checkpoint SHA256 mismatch"
}
if {[exec git -C $repo rev-parse "${source_revision}^{commit}"] ne $source_revision} {
  error "source commit did not resolve exactly"
}
set source_files {
  library/starlink_pss_acquisition/starlink_pss_shared_realtime_xfft_service.v
  library/starlink_pss_acquisition/starlink_pss_realtime_input_guard.v
  library/starlink_pss_acquisition/starlink_pss_realtime_result_guard.v
  library/starlink_pss_acquisition/starlink_pss_block_mailbox.v
}
set frozen_sources {}
foreach path $source_files {lappend frozen_sources [exec git -C $repo show "${source_revision}:$path"]}
file mkdir $output_dir
file copy [file normalize [info script]] [file join $output_dir trial_source.tcl]
foreach path $source_files content $frozen_sources {
  set channel [open [file join $output_dir [file tail $path]] w]
  puts $channel $content
  close $channel
}
cd $output_dir
set summary [open summary.txt w]
puts $summary "scope=isolated_physical_trial_not_deployment"
puts $summary "checkpoint=$checkpoint\ncheckpoint_sha256=$expected_sha256"
puts $summary "hdl_commit=$source_revision\nmode=$trial_mode\ntrial_id=$trial_id"
puts $summary "source_association=caller_attested_build_provenance_not_derived_from_checkpoint"
puts $summary "hardware_qualified=false"
flush $summary
set operation_started 0

proc one {objects description} {
  if {[llength $objects] != 1} {error "expected exactly one $description; got [llength $objects]"}
  return [lindex $objects 0]
}
proc save_text {path content} {
  set channel [open $path w]
  puts $channel $content
  close $channel
}
proc pin {cell ref} {
  return [one [get_pins -of_objects $cell -filter "REF_PIN_NAME == $ref"] "$cell/$ref"]
}
proc net_of {pin_object} {
  return [one [get_nets -segments -top_net_of_hierarchical_group -of_objects $pin_object] "canonical net of $pin_object"]
}
proc drivers_of {pin_object} {
  return [get_pins -leaf -of_objects [get_nets -segments -of_objects $pin_object] -filter {DIRECTION == OUT}]
}
proc driver_token {pin_object equivalent_qs} {
  set driver [one [drivers_of $pin_object] "driver of $pin_object"]
  if {[lsearch -exact $equivalent_qs $driver] >= 0} {return DIRECTION_Q}
  set driver_cell [one [get_cells -of_objects $driver] "driver cell"]
  switch -- [get_property REF_NAME $driver_cell] {
    VCC {return CONST1}
    GND {return CONST0}
    default {return $driver}
  }
}
proc physical_signature {cell} {
  set bel [one [get_bels -of_objects $cell] "mapped BEL for $cell"]
  set configs {}
  foreach property [lsort [list_property $bel]] {
    if {[string match CONFIG.* $property] && ![string match *.VALUES $property] &&
        ![string match *.DEFAULT $property]} {
      set value [get_property $property $bel]
      if {$value ne {}} {dict set configs $property $value}
    }
  }
  if {![dict size $configs]} {error "effective physical configuration unavailable for $cell"}
  set mapping {}
  foreach logical [get_pins -of_objects $cell] {
    set physical [one [get_bel_pins -of_objects $logical] "BEL pin for $logical"]
    set inverse [get_property IS_INVERTED $logical]
    if {$inverse ni {0 1}} {error "unresolved effective pin polarity for $logical"}
    dict set mapping [get_property REF_PIN_NAME $logical] [list [file tail $physical] $inverse]
  }
  return [list [get_property REF_NAME $cell] $configs $mapping]
}
proc ff_signature {cell equivalent_qs} {
  if {[get_property REF_NAME $cell] ne "FDRE"} {error "direction source/replica is not FDRE"}
  set physical [physical_signature $cell]
  set configs [lindex $physical 1]
  foreach {key expected} {CONFIG.FFINIT INIT1 CONFIG.FFSR SRLOW CONFIG.LATCH_OR_FF FF CONFIG.SYNC_ATTR SYNC} {
    if {![dict exists $configs $key] || [dict get $configs $key] ne $expected} {
      error "direction effective initialization/register semantics changed: $cell $key"
    }
  }
  set inputs {}
  foreach ref {C CE D R} {dict set inputs $ref [driver_token [pin $cell $ref] $equivalent_qs]}
  if {[dict get $inputs CE] ne "CONST1" || [dict get $inputs R] ne "CONST0"} {
    error "direction CE/R premises changed"
  }
  set clock [one [get_clocks -of_objects [pin $cell C]] "direction clock"]
  if {[get_property NAME $clock] ne "clk_fpga_1" || [get_property PERIOD $clock] != 5.0} {
    error "direction clock is not the unchanged 5 ns clock"
  }
  return [list $physical $inputs]
}
proc lut_signature {cell equivalent_qs} {
  if {[get_property REF_NAME $cell] ne "LUT3"} {error "direction feedback LUT3 changed"}
  set inputs {}
  foreach ref {I0 I1 I2} {dict set inputs $ref [driver_token [pin $cell $ref] $equivalent_qs]}
  if {[dict get $inputs I2] ne "DIRECTION_Q"} {error "direction feedback identity lost"}
  return [list [physical_signature $cell] $inputs]
}
proc same_dict {left right} {
  if {[lsort [dict keys $left]] ne [lsort [dict keys $right]]} {return 0}
  dict for {key value} $left {if {$value ne [dict get $right $key]} {return 0}}
  return 1
}
proc same_signature {left right} {
  set lp [lindex $left 0]; set rp [lindex $right 0]
  return [expr {[lindex $lp 0] eq [lindex $rp 0] &&
    [same_dict [lindex $lp 1] [lindex $rp 1]] &&
    [same_dict [lindex $lp 2] [lindex $rp 2]] &&
    [same_dict [lindex $left 1] [lindex $right 1]]}]
}
proc primitive_inventory {} {
  set result {}
  foreach cell [get_cells -hier -filter {IS_PRIMITIVE}] {dict set result $cell [get_property REF_NAME $cell]}
  return $result
}
proc clock_inventory {} {
  set result {}
  foreach clock [get_clocks] {
    dict set result $clock [list [get_property PERIOD $clock] [get_property WAVEFORM $clock] [get_property SOURCE_PINS $clock]]
  }
  return $result
}
proc evidence {label family} {
  report_route_status -file "${label}_route.rpt"
  report_utilization -file "${label}_utilization.rpt"
  report_control_sets -file "${label}_control_sets.rpt"
  report_clocks -file "${label}_clocks.rpt"
  report_exceptions -file "${label}_exceptions.rpt"
  report_exceptions -ignored -file "${label}_ignored_exceptions.rpt"
  report_timing_summary -delay_type min_max -report_unconstrained -file "${label}_timing.rpt"
  check_timing -verbose -file "${label}_check_timing.rpt"
  foreach {direction args} [list inputs [list -to $family] outputs [list -from $family]] {
    foreach type {max min} {
      set paths [get_timing_paths -delay_type $type {*}$args -max_paths 10 -nworst 1]
      if {![llength $paths]} {error "unmeasured $direction $type timing"}
      if {$type eq "max"} {
        foreach path $paths {
          if {abs([get_property REQUIREMENT $path] - 5.0) > 0.001} {error "direction setup path lost its 5 ns requirement"}
        }
      }
      report_timing -delay_type $type {*}$args -max_paths 10 -nworst 1 -file "${label}_${direction}_${type}.rpt"
    }
  }
}
proc validate_replicas {before source source_sig lut lut_sig original_loads} {
  set after [primitive_inventory]
  set added {}
  dict for {name ref} $before {
    if {![dict exists $after $name] || [dict get $after $name] ne $ref} {
      error "existing primitive removed/type changed: $name"
    }
  }
  dict for {name ref} $after {
    if {![dict exists $before $name]} {
      if {![string match "${source}_replica*" $name] || $ref ne "FDRE"} {
        error "unreviewed new primitive outside direction FF replication: $name"
      }
      lappend added $name
    }
  }
  if {![llength $added]} {error "targeted replication was a no-op"}
  set family [get_cells [concat [list $source] $added]]
  set qs [get_pins -of_objects $family -filter {REF_PIN_NAME == Q}]
  if {[llength $qs] != [llength $family]} {error "replica Q count mismatch"}
  foreach cell $family {
    set current [ff_signature $cell $qs]
    if {![same_signature $source_sig $current]} {error "source/replica transition/pin/INIT mismatch: $cell"}
  }
  if {![same_signature $lut_sig [lut_signature $lut $qs]]} {error "feedback LUT function/pin mapping changed"}
  set all_loads {}
  foreach q $qs {
    set net [net_of $q]
    if {[one [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}] "replica driver"] ne $q} {
      error "replica net driver ownership mismatch"
    }
    foreach load [get_pins -leaf -of_objects $net -filter {DIRECTION == IN}] {lappend all_loads $load}
  }
  if {[llength $all_loads] != [llength [lsort -unique $all_loads]] ||
      [lsort $all_loads] ne [lsort $original_loads]} {error "original direction consumer set changed or duplicated"}
  foreach load $original_loads {
    if {[driver_token [get_pins $load] $qs] ne "DIRECTION_Q"} {error "lost direction consumer: $load"}
  }
  save_text "[expr {$::routing_performed ? {postroute} : {postreplication}}]_semantics.txt" \
    [list family $family source_signature $source_sig feedback_signature $lut_sig consumer_count [llength $all_loads]]
  return $family
}

set routing_performed 0
set opened 0
set run_code [catch {
  open_checkpoint $checkpoint
  set opened 1
  if {[get_property PART [current_design]] ne "xc7z010clg400-1"} {error "expected complete xc7z010 receiver"}
  if {![report_route_status -boolean_check ROUTED_FULLY] || [report_route_status -boolean_check ERRORS_IN_ROUTES]} {
    error "source checkpoint is not fully routed without routing errors"
  }
  set source_name {i_system_wrapper/system_i/starlink_pss_acquisition/inst/acquisition/shared_transform.iq_to_score/realtime_transform.transform_service/shared_xfft/U0/i_synth/xfft_inst/non_floating_point.arch_b.xfft_inst/single_channel.datapath/i_fwd_inv_reg}
  set source [one [get_cells $source_name] "exact direction source"]
  one [get_cells -hier -filter {NAME =~ *i_fwd_inv_reg*}] "unreplicated direction name family"
  set q [pin $source Q]
  set net [net_of $q]
  set original_loads [get_pins -leaf -of_objects $net -filter {DIRECTION == IN}]
  if {[llength $original_loads] != 56 || [one [drivers_of $q] driver] ne $q} {
    error "expected exactly 56 original direction consumers and one Q driver"
  }
  set core [one [get_cells -hier -filter {NAME =~ *transform_service/shared_xfft}] "realtime core"]
  if {![string match *starlink_pss_fft512_bfp18_rt_candidate* "[get_property REF_NAME $core] [get_property ORIG_REF_NAME $core]"]} {
    error "expected explicitly selected realtime FFT"
  }
  set source_sig [ff_signature $source [list $q]]
  set lut [one [get_cells -of_objects [drivers_of [pin $source D]]] "feedback LUT"]
  set lut_sig [lut_signature $lut [list $q]]
  set before [primitive_inventory]
  set clocks_before [clock_inventory]
  save_text baseline_semantics.txt [list source $source net $net consumers $original_loads \
    source_signature $source_sig feedback_signature $lut_sig primitive_inventory $before clocks $clocks_before]
  evidence baseline $source
  if {$trial_mode eq "replicate"} {
    puts $summary "operation=one_force_replication_on_exact_net\ntarget=$net"
    flush $summary
    set operation_started 1
    phys_opt_design -force_replication_on_nets $net -verbose
    write_checkpoint postreplication_candidate.dcp
    set family [validate_replicas $before $source $source_sig $lut $lut_sig $original_loads]
    if {![report_route_status -boolean_check ROUTED_FULLY] || [report_route_status -boolean_check ERRORS_IN_ROUTES]} {
      puts $summary "routing=required_normal_route_design_once"
      flush $summary
      set routing_performed 1
      route_design
      set family [validate_replicas $before $source $source_sig $lut $lut_sig $original_loads]
    } else {puts $summary "routing=not_required"}
    if {![report_route_status -boolean_check PLACED_FULLY] ||
        ![report_route_status -boolean_check ROUTED_FULLY] ||
        [report_route_status -boolean_check ERRORS_IN_ROUTES]} {error "trial remains incompletely placed/routed"}
    if {![same_dict $clocks_before [clock_inventory]]} {error "clock definitions changed"}
    evidence final $family
    write_checkpoint final_trial.dcp
    puts $summary "direction_replica_semantic_audit=pass\nreplicas=[expr {[llength $family] - 1}]"
    puts $summary "timing_qualification=independent_full_receiver_audit_required"
  }
  if {[lindex [exec sha256sum -- $checkpoint] 0] ne $expected_sha256} {error "original checkpoint changed"}
  close_design
  set opened 0
} message options]
if {$run_code} {
  puts $summary "DIRECTION_TRIAL_REJECTED operation_started=$operation_started routing_performed=$routing_performed reason=$message"
  puts $summary "errorinfo=[dict get $options -errorinfo]"
  if {$operation_started && $opened} {
    puts $summary "negative_checkpoint_capture=[catch {write_checkpoint rejected_trial.dcp} capture_message] $capture_message"
    puts $summary "negative_route_report=[catch {report_route_status -file rejected_route.rpt} route_message] $route_message"
  }
  puts $summary "original_sha256_after=[lindex [exec sha256sum -- $checkpoint] 0]"
  close $summary
  if {$opened} {catch {close_design}}
  return -options $options $message
}
puts $summary "DIRECTION_TRIAL_FINISHED mode=$trial_mode hardware_qualified=false"
close $summary
puts "DIRECTION_TRIAL_FINISHED mode=$trial_mode hardware_qualified=false"
