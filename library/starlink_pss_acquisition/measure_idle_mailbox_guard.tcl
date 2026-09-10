# Actual guard synthesis, not routing/timing or proof of the caller premise.
# Only idle admission should lose the full current mailbox fault dependency;
# active retirement, final publication and sticky reasons must retain it.
if {$argc != 1} { error "expected NEW_OUTPUT_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set source_dir [file dirname [file normalize [info script]]]
set output [file normalize [lindex $argv 0]]
if {[file exists $output]} { error "output directory must be new" }
file mkdir $output
file copy [info script] [file join $output measurement_source.tcl]
set source [file join $output guard.v]
file copy [file join $source_dir starlink_pss_realtime_result_guard.v] $source
set source_hash [lindex [exec sha256sum $source] 0]
set report [open [file join $output scope.txt] w]
puts $report "scope=actual_result_guard_idle_mailbox_mode_structural_synthesis_only"
puts $report "source_sha256=$source_hash"
puts $report "source_identity=hash_not_clean_commit_claim caller_contract_and_full_receiver_qualified=false"
puts $report "USE_PHASE_INPUT_FAULT=1 both_modes=true"
puts $report "mode\tendpoint\tfull_mailbox_fault_ports\tidle_mailbox_fault_ports"
set_param general.maxThreads 2
foreach mode {0 1} {
  create_project -in_memory -part xc7z010clg400-1
  read_verilog $source
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -control_set_opt_threshold 4 \
    -top starlink_pss_realtime_result_guard -part xc7z010clg400-1 \
    -generic [list USE_PHASE_INPUT_FAULT=1 USE_IDLE_MAILBOX_FAULT=$mode]
  create_clock -name fast -period 5.0 [get_ports clk]
  opt_design -directive ExploreArea
  foreach endpoint {job_ready mailbox_input_valid mailbox_commit_valid {fault_reasons_reg[0]}} {
    if {$endpoint eq {fault_reasons_reg[0]}} {
      set cell [get_cells -quiet $endpoint]
      if {[llength $cell] != 1} { error "missing exact fault register" }
      set pin [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == D}]
    } else {
      set pin [get_ports -quiet $endpoint]
    }
    if {[llength $pin] != 1} { error "missing exact endpoint $endpoint" }
    set starts [all_fanin -flat -startpoints_only -to $pin]
    set full [filter $starts {CLASS == port && NAME == mailbox_input_fault}]
    set idle [filter $starts {CLASS == port && NAME == idle_mailbox_fault_now}]
    puts $report "$mode\t$endpoint\t[llength $full]\t[llength $idle]"
    puts $report "  startpoints=[lsort $starts]"
    if {$endpoint eq "job_ready" && $mode == 1} {
      if {[llength $full] || [llength $idle] != 1} {
        error "idle admission dependency cut missing"
      }
    } elseif {[llength $full] != 1 || [llength $idle]} {
      error "full current mailbox validation changed at $endpoint mode=$mode"
    }
  }
  foreach {name pattern} {LUT LUT* FF FD* DSP DSP48E1 RAM18 RAMB18E1 RAM36 RAMB36E1} {
    set cells [get_cells -quiet -hier -filter [format {IS_PRIMITIVE && REF_NAME =~ %s} $pattern]]
    puts $report "mode${mode}_${name}=[llength $cells]"
  }
  report_utilization -file [file join $output mode${mode}_utilization.rpt]
  write_verilog -mode funcsim [file join $output mode${mode}_netlist.v]
  write_checkpoint [file join $output mode${mode}_synth.dcp]
  puts $report "mode${mode}_netlist_sha256=[lindex [exec sha256sum [file join $output mode${mode}_netlist.v]] 0]"
  flush $report
  close_project
}
if {[lindex [exec sha256sum $source] 0] ne $source_hash} { error "frozen source changed" }
puts $report "IDLE_MAILBOX_DEPENDENCY_MEASURED active_final_faults_retained=1 whole_receiver_and_timing_unqualified=1"
close $report
puts "IDLE_MAILBOX_DEPENDENCY_MEASURED active_final_faults_retained=1 whole_receiver_and_timing_unqualified=1"
