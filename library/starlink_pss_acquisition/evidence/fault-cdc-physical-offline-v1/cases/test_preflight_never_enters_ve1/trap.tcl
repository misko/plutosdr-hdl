proc version {args} {return "2022.2"}
proc set_param {args} {}
proc create_project {args} {puts "OFFLINE_CREATE_PROJECT_TRAP"; exit 0}
set script [lindex $argv 0]
set argv [lrange $argv 1 end]; set argc [llength $argv]
source $script
error "unexpected fallthrough"
