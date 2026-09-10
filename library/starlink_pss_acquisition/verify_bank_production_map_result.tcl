# Strict terminal inventory, including late errors after a displayed PASS.
# The bench enforces numeric equality; this rejects missing/duplicate/malformed
# evidence and cannot independently infer RF truth or redo the simulation.
proc pss_map_fields {line prefix keys} {
  set fields [dict create]
  if {[lindex $line 0] ne $prefix} { error "wrong map evidence prefix" }
  foreach token [lrange [split $line " "] 1 end] {
    if {![regexp {^([a-z_]+)=([0-9]+(?:\.[0-9]+)?)$} $token ignored key value] ||
        [dict exists $fields $key]} { error "malformed/duplicate map evidence field" }
    dict set fields $key $value
  }
  if {[lsort [dict keys $fields]] ne [lsort $keys]} { error "map evidence field inventory mismatch" }
  return $fields
}
proc require_bank_production_map_pass {log_path production} {
  if {$production ni {0 1}} { error "invalid production verification mode" }
  set count [expr {$production ? 1 : 2}]
  set bins [expr {$production ? 20000 : 343}]
  set frames [expr {$production ? 64 : 2}]
  set selected [expr {$bins*$frames}]
  set blocks [expr {($selected+446)/447}]
  set support [expr {($blocks-1)*447+512}]
  set pass "BANK_PRODUCTION_MAP_PASS production=$production complete_maps=$count fresh_partial=447 actual_core=1 slow_mhz=100 fft_mhz=175 PERIODIC_GEOMETRY_ARITHMETIC_NOT_RF_OR_PHYSICAL_TIMING"
  set partial "BANK_PRODUCTION_MAP_PARTIAL fresh_scores=447 accepted=447 aborts=1 failed=1 historical_generation=$count reason=10 full_production_map_recovery=0"
  require_realtime_probe_pass $log_path [list $pass $partial] BANK_PRODUCTION_MAP_COMPLETE $count
  set channel [open $log_path r]; set transcript [read $channel]; close $channel
  if {[regexp -nocase -line {^[ \t]*BANK_PRODUCTION_MAP_(FAIL|FAULT) } $transcript]} {
    error "production-map failed assertion, including late failure"
  }
  set epoch 0; set totals 0; set partials 0; set progress 0; set visible_sum 0
  set keys {epoch bins frames selected residue fft_support source_at_stop potential_tail visible_scores visible_tail
    forward_input inverse_input forward product inverse energies ratios retained_source map_words elapsed_ns}
  set total_keys {exact_scores admitted_scores visible_tail_scores exact_source exact_forward_input exact_inverse_input exact_forward
    exact_product exact_inverse exact_energies exact_ratios exact_map_words terminals}
  foreach line [split $transcript "\n"] {
    if {[string first "BANK_PRODUCTION_MAP_COMPLETE " $line]==0} {
      incr epoch
      set f [pss_map_fields $line BANK_PRODUCTION_MAP_COMPLETE $keys]
      foreach {key expected} [list epoch $epoch bins $bins frames $frames selected $selected \
          residue 239 fft_support $support potential_tail 208 map_words $bins] {
        if {[dict get $f $key] != $expected} { error "wrong complete-map $key" }
      }
      if {[dict get $f visible_scores]<$selected || [dict get $f visible_scores]>$blocks*447 ||
          [dict get $f visible_tail]!=[dict get $f visible_scores]-$selected} {
        error "invalid visible versus admitted tail accounting"
      }
      incr visible_sum [dict get $f visible_scores]
      if {[dict get $f source_at_stop]<$support || [dict get $f retained_source]<=100 ||
          [dict get $f elapsed_ns]<=0} { error "missing real source/time support" }
      foreach key {forward_input inverse_input forward product inverse} {
        if {[dict get $f $key]<$blocks*512 || [dict get $f $key]>($blocks+1)*512} {
          error "incomplete/unbounded actual transform inventory: $key"
        }
      }
      foreach key {energies ratios} {
        if {[dict get $f $key]<$selected || [dict get $f $key]>($blocks+1)*447} {
          error "incomplete/unbounded exact energy/ratio prefix"
        }
      }
    } elseif {[string first "BANK_PRODUCTION_MAP_TOTAL " $line]==0} {
      incr totals
      set f [pss_map_fields $line BANK_PRODUCTION_MAP_TOTAL $total_keys]
      foreach {key expected} [list exact_scores [expr {$visible_sum+447}] \
          admitted_scores [expr {$count*$selected+447}] \
          visible_tail_scores [expr {$visible_sum-$count*$selected}] \
          exact_map_words [expr {$count*$bins}] terminals [expr {$count+1}]] {
        if {[dict get $f $key]!=$expected} { error "wrong aggregate map inventory: $key" }
      }
      foreach key {exact_forward_input exact_inverse_input exact_forward exact_product exact_inverse} {
        if {[dict get $f $key]<($count*$blocks+1)*512} { error "missing aggregate transform prefix" }
      }
      if {[dict get $f exact_source]<$count*$support+512 ||
          [dict get $f exact_energies]<$count*$selected+447 ||
          [dict get $f exact_ratios]<$count*$selected+447} { error "missing aggregate source/ratio prefix" }
    } elseif {[string first "BANK_PRODUCTION_MAP_PARTIAL " $line]==0} {
      incr partials
    } elseif {[string first "BANK_PRODUCTION_MAP_PROGRESS " $line]==0} {
      incr progress
      set f [pss_map_fields $line BANK_PRODUCTION_MAP_PROGRESS {selected_prefix time_ns}]
      if {[dict get $f selected_prefix]!=$progress*200000 || [dict get $f time_ns]<=0} {
        error "wrong production progress prefix"
      }
    }
  }
  if {$totals!=1 || $partials!=1 || $progress!=($production ? 6 : 0)} {
    error "production-map terminal/progress inventory mismatch"
  }
}
