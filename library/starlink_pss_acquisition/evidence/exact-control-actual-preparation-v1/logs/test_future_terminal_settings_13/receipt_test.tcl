proc exact_verify_receipts {log registered distributed scratch extras} {
  set lines [regexp -all -inline -line {^EXACT_CONTROL_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} { error "expected exactly one candidate terminal" }
  set pattern {^EXACT_CONTROL_ACTUAL_PASS registered=([01]) distributed=([01]) scratch=([01]) extra=([01]) checks=([0-9]+) active=([0-9]+) consumed=([0-9]+) private_differences=([0-9]+) final_fault_edges=([0-9]+) owned_stalls=([0-9]+) reset_owned_edges=([0-9]+) independent_actual_core=1$}
  if {![regexp $pattern [lindex $lines 0] unused r d s e checks active consumed differences final_faults stalls resets]} {
    error "malformed candidate settings/count receipt"
  }
  if {$r != $registered || $d != $distributed || $s != $scratch || $e != $extras} {
    error "candidate receipt does not match explicit run settings"
  }
  if {$checks <= 0 || $active <= 0 || $consumed <= 0} {
    error "candidate active/public/identity coverage missing"
  }
  set extra_lines [regexp -all -inline -line {^EXACT_CONTROL_EXTRA_EPOCHS_PASS[^\n]*$} $log]
  if {$extras} {
    # Candidate and independently driven reference each execute/assert their
    # own four extra epochs before printing this exact receipt. The candidate
    # cannot finish until reference_done; neither bench shares these counters.
    if {$final_faults < 2 || $stalls < 3 || [llength $extra_lines] != 2} {
      error "extra epoch active evidence or independent receipt missing"
    }
    foreach line $extra_lines {
      if {$line ne "EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=2 healthy_recoveries=4"} {
        error "extra epoch counts differ from frozen expectations"
      }
    }
  } elseif {[llength $extra_lines] != 0} {
    error "extra epochs ran without explicit selection"
  }
  return "EXACT_CONTROL_RECEIPTS_VERIFIED"
}

set log {EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=1 healthy_recoveries=4
EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=2 healthy_recoveries=4
EXACT_CONTROL_ACTUAL_PASS registered=1 distributed=1 scratch=1 extra=1 checks=500 active=300 consumed=2 private_differences=19 final_fault_edges=2 owned_stalls=9 reset_owned_edges=0 independent_actual_core=1
}
if {[catch {exact_verify_receipts $log 1 1 1 1} reason]} {puts $reason; exit 1}
puts $reason
