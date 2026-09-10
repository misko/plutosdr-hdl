# Additive negative adaptation. Healthy runner/helper/bench remain unchanged.
source [file join [file dirname [file normalize [info script]]] prepare_bank_native_paired.tcl]

proc prepare_expired_paired_bench {bench checks} {
  set bench [prepare_native_paired_bench $bench $checks]
  return [native_replace_once $bench {module tb_starlink_bank_native_paired #(} {module tb_starlink_bank_native_expired #(}]
}

proc prepare_expired_native_runner {value} {
  foreach {old replacement} {
    {lappend native_python_relatives tests/starlink_oracle/bank_native_true_pss.py tests/starlink_oracle/pilot_ddc.py}
    {lappend native_python_relatives tests/starlink_oracle/bank_native_true_pss.py tests/starlink_oracle/pilot_ddc.py tests/starlink_oracle/bank_native_expired.py}
    {-m tests.starlink_oracle.bank_native_true_pss verify [lindex $argv 1] [lindex $argv 2] $native_dir}
    {-m tests.starlink_oracle.bank_native_expired verify [lindex $argv 1] [lindex $argv 2] $native_dir $expired_dir}
    {BANK_NATIVE_TRUE_PSS_ORACLE_VERIFIED source=4096 blocks=3 scores=1341 map_words=447 pilot_bytes=2048 packet_words=26 profile=520-pss winner_lag=0}
    {BANK_NATIVE_EXPIRED_ORACLE_VERIFIED profile=520-pss-expired request=15005202 rejected=1 late=1 admitted=0 packets=0 public_registers=31}
    {[file join $script_dir tb bank_native_paired_checks.svh]}
    {[file join $script_dir tb bank_native_expired_checks.svh]}
    {[file join $source_dir bank_native_paired_checks.svh]}
    {[file join $source_dir bank_native_expired_checks.svh]}
    {set bench_name tb_starlink_bank_native_paired}
    {set bench_name tb_starlink_bank_native_expired}
    {[prepare_native_paired_bench $native_bench $native_checks]}
    {[prepare_expired_paired_bench $native_bench $native_checks]}
    {set project_name bank_native_paired}
    {set project_name bank_native_expired}
    {native_verify_outputs $simulation_dir $source_dir $fast_mhz $native_profile}
    {expired_verify_outputs $simulation_dir $source_dir $fast_mhz $native_profile}
    {scope=actual_original15_source_public_native_AXI_bank_PSMA_PIL1_static_anchor}
    {scope=actual_original15_expired_native_public_command_coarse_pilot_independent}
    {fixture=bank-native-original-overlay-520-pss-v1 native_anchor=$native_profile}
    {fixture=bank-native-original-overlay-520-pss-v1 native_event_profile=520-pss-expired native_packets_expected=0 native_anchor=$native_profile}
  } {
    set value [native_replace_once $value $old $replacement]
  }
  set value [native_replace_once $value {  [file join $script_dir simulate_paired_realtime_psma_stop.tcl]} {  [file join $script_dir simulate_bank_native_paired.tcl] \
  [file join $script_dir prepare_bank_native_expired.tcl] \
  [file join $native_fw tests test_starlink_bank_native_expired.py] \
  [file join $native_fw tests starlink_oracle bank_native_expired.py] \
  [file join $expired_dir native_expired_contract.json] \
  [file join $expired_dir native_expired_registers.mem] \
  [file join $script_dir simulate_paired_realtime_psma_stop.tcl]}]
  set value [native_replace_once $value {lappend vector_names native_coefficients_q15.mem native_expected_packet.mem} {lappend vector_names native_coefficients_q15.mem native_expected_packet.mem native_expired_registers.mem}]
  # Drop only the old healthy-only postprocessor. The independent negative
  # verifier below is used instead, while the full legacy coarse/pilot verifier
  # still runs and remains required. Reject ambiguous structural anchors.
  set start {proc native_verify_outputs }
  set finish "\neval \$native_runner"
  foreach anchor [list $start $finish] {
    if {[string first $anchor $value] < 0 || [string first $anchor $value] != [string last $anchor $value]} {
      error "expired verifier anchor missing or duplicated"
    }
  }
  set first [string first $start $value]
  set last [string first $finish $value]
  if {$last <= $first} { error "expired verifier anchors out of order" }
  return [string replace $value $first [expr {$last-1}] {}]
}

proc expired_verify_outputs {simulation_dir source_dir fast_mhz cohort_profile} {
  if {$fast_mhz ni {175 200} || $cohort_profile ne "520-pss"} { error "invalid expired receipt profile" }
  set path [file join $simulation_dir simulate.log]
  set channel [open $path r]; set log [read $channel]; close $channel
  foreach line [split $log "\n"] {
    if {$line eq {PAIRED_LATE_FAULT_PASS actual_invalid_release=1 failed_joint_health=1 terminal_coordinates_retained=1 pilot_bytes_preserved=1}} { continue }
    if {[regexp -nocase {(^|[ \t:])([A-Z][A-Z0-9_]*_)?(FAIL|FAULT|FATAL|ERROR)([: \t_]|$)} $line]} {
      error "expired log contains failure evidence: $line"
    }
    if {[regexp {^BANK_NATIVE_(PACKET_WORD|EXACT_PASS|TRUE_PSS_PASS|PAIRED_PASS|ADMISSION)( |$)} $line]} {
      error "healthy native packet/admission receipt cannot qualify expired request"
    }
  }
  require_realtime_probe_pass $path [list \
    {BANK_EXPIRED_EXACT_PASS public_submits=1 wrapper_handshakes=1 fifo_accepts=1 sample_handshakes=1 rejected=1 late=1 admitted=0 capture_words=0 completed=0 packets=0 irq=0 public_register_reads=62 empty_across_stop=1} \
    "BANK_NATIVE_EXPIRED_PASS source_msps=15 fast_mhz=$fast_mhz profile=520-pss-expired source_words=4096 scores=894 map_words=447 pilot_bytes=2048 NATIVE_REQUEST_REJECTED_COARSE_PILOT_HEALTHY_NOT_CAUSAL"] BANK_EXPIRED_REGISTER 62
  require_realtime_probe_pass $path [list \
    {BANK_EXPIRED_EMPTY generation=1 result_status=1a000000 available=0 irq=0 packet_data_reads=0} \
    {BANK_EXPIRED_EMPTY generation=2 result_status=1a000000 available=0 irq=0 packet_data_reads=0}] BANK_EXPIRED_EMPTY 2
  set channel [open [file join $source_dir native_expired_registers.mem] r]
  set expected [split [string trim [read $channel]] "\n"]; close $channel
  if {[llength $expected] != 62} { error "expired register oracle geometry mismatch" }
  foreach word $expected { if {![regexp {^[0-9a-f]{8}$} $word]} { error "malformed expired register oracle" } }
  set rows [regexp -all -inline -line {^BANK_EXPIRED_REGISTER generation=([12]) ordinal=([0-9]+) address=([0-9a-f]{2}) value=([0-9a-f]{8})$} $log]
  if {[llength $rows] != 62*5} { error "expired register receipt malformed" }
  for {set n 0} {$n < 62} {incr n} {
    set row [lrange $rows [expr {$n*5}] [expr {$n*5+4}]]
    set ordinal [expr {$n % 31}]
    scan [lindex $expected [expr {$ordinal*2}]] %x address
    if {[lindex $row 1] != 1+$n/31 || [lindex $row 2] != $ordinal ||
        [lindex $row 3] ne [format %02x $address] || [lindex $row 4] ne [lindex $expected [expr {$ordinal*2+1}]]} {
      error "expired exact ordered public register inventory mismatch"
    }
  }
  if {[regexp -all -line {^BANK_EXPIRED_PUBLIC_SUBMIT } $log] != 1 ||
      ![regexp -line {^BANK_EXPIRED_PUBLIC_SUBMIT index=([0-9]+) request=15005202 center=8589935096$} $log all submit] ||
      $submit < 8589934576+620 || $submit > 8589934576+624} {
    error "expired public submit bounds/identity missing"
  }
  if {[regexp -all -line {^BANK_EXPIRED_REJECT } $log] != 1 ||
      ![regexp -line {^BANK_EXPIRED_REJECT index=([0-9]+) start=8589935064 lead_hex=([0-9a-f]{16}) late=1 duplicate=0 overlap=0 request=15005202$} $log all index lead] ||
      $index < $submit || $index < 8589934576+620 || $index > 8589934576+640 ||
      $lead ne [format %016x [expr {(8589935064-($index+1)) & 0xffffffffffffffff}]]} {
    error "expired sample handshake lacks exact past-start late predicate"
  }
  if {[regexp -all -line {^BANK_EXPIRED_CONCURRENCY } $log] != 1 ||
      ![regexp -line {^BANK_EXPIRED_CONCURRENCY fft_run_fast_cycles=([0-9]+) first_fast_after_reject=1 pilot_input_accepts=([0-9]+)$} $log all fast pilot] ||
      $fast < 1 || $fast > 512 || $pilot < 1 || $pilot > 24} {
    error "expired bounded actual FFT/pilot concurrency witness missing"
  }
  puts "BANK_NATIVE_EXPIRED_SIMULATION_VERIFIED fast_mhz=$fast_mhz profile=520-pss-expired rejected=1 late=1 packets=0 exact_pilot_bytes=2048"
}
