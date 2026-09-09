# Simulation return alone is not success: xsim can stop on $fatal while Vivado
# continues its Tcl script. Require terminal bench evidence after close_sim.
proc require_realtime_probe_pass {log_path required_markers row_prefix expected_rows} {
  if {![file isfile $log_path]} { error "missing realtime simulation log" }
  if {![regexp {^[A-Z_]+$} $row_prefix] ||
      ![string is integer -strict $expected_rows] || $expected_rows < 1 ||
      $expected_rows > 4096 || [llength $required_markers] < 1 ||
      [llength $required_markers] > 4} { error "invalid realtime bench verification contract" }
  set channel [open $log_path r]
  # Vivado 2022.2 does not provide Tcl's newer try/finally command. Still
  # attempt close on read failure and retain the first failed operation.
  set read_failed [catch {read $channel} contents]
  set close_failed [catch {close $channel} close_error]
  if {$read_failed} { error "cannot read realtime simulation log: $contents" }
  if {$close_failed} { error "cannot close realtime simulation log: $close_error" }
  set contents [string map [list "\r" ""] $contents]
  if {[regexp -nocase -line {^[ \t]*(fatal|error)(:|[ \t])} $contents]} {
    error "realtime simulation log contains a fatal/error diagnostic"
  }
  set lines [split $contents "\n"]
  foreach marker $required_markers {
    if {$marker eq "" || [llength [lsearch -all -exact $lines $marker]] != 1} {
      error "realtime simulation lacks exactly one required terminal bench pass"
    }
  }
  set rows 0
  foreach line $lines {
    if {[string first "${row_prefix} " $line] == 0} { incr rows }
  }
  if {$rows != $expected_rows} { error "realtime simulation job inventory is incomplete" }
}
