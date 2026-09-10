proc version {args} {return "2022.2"}
proc set_param {name value} {
  if {$name ne "general.maxThreads" || $value != 2} {error "changed threads"}
}
proc create_project {args} {puts "OFFLINE_CREATE_PROJECT_TRAP"; exit 0}
set prepared [lindex $argv 0]
set argv [list $prepared]; set argc 1
source [file join $prepared frozen_sources simulate_exact_control_prepared.tcl]
error "unexpected fallthrough"
