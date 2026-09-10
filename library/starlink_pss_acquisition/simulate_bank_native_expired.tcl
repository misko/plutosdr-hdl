# Separate opt-in negative profile. Does not edit or weaken the healthy runner.
# NEW_OUTPUT SCORE PILOT NATIVE EXPIRED_CONTRACT FAST_MHZ 520-pss-expired
if {$argc != 7} { error "expected NEW_OUTPUT SCORE PILOT NATIVE EXPIRED_CONTRACT FAST_MHZ 520-pss-expired" }
if {[lindex $argv 5] ni {175 200} || [lindex $argv 6] ne "520-pss-expired"} {
  error "expired profile requires literal175|200 and520-pss-expired"
}
for {set n 0} {$n < 5} {incr n} { lset argv $n [file normalize [lindex $argv $n]] }
set expired_dir [lindex $argv 4]
set expired_script_dir [file dirname [file normalize [info script]]]
source [file join $expired_script_dir prepare_bank_native_expired.tcl]
set channel [open [file join $expired_script_dir simulate_bank_native_paired.tcl] r]
set expired_parent [read $channel]; close $channel
set expired_parent [prepare_expired_native_runner $expired_parent]
set argv [list [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3] [lindex $argv 5] 520-pss]
set argc 6
eval $expired_parent
