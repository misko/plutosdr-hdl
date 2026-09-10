# Actual-core three-bank island; never overwrites prior evidence.
if {$argc ni {3 4}} { error "expected NEW_OUTPUT FROZEN_VECTORS FAST_MHZ ?join-gate-removed|registered-scheduling?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set fast_mhz [lindex $argv 2]
set mode [expr {$argc == 4 ? [lindex $argv 3] : "normal"}]
if {$mode ni {normal join-gate-removed registered-scheduling}} { error "unsupported mode" }
set mutation [expr {$mode eq "join-gate-removed"}]
set registered [expr {$mode eq "registered-scheduling"}]
if {$fast_mhz ni {150 175 200}} { error "unsupported probe frequency" }
if {[file exists $output_dir]} { error "refusing to overwrite bank-owned evidence" }
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
set rtl_names {starlink_pss_fft_bank_owned_slice starlink_pss_realtime_input_guard
  starlink_pss_realtime_result_guard starlink_pss_block_mailbox
  starlink_pss_forward_kernel_join starlink_pss_kernel_rom starlink_pss_spectrum_product}
foreach name $rtl_names { file copy [file join $script_dir ${name}.v] $source_dir }
if {$mutation} {
  set mutation_path [file join $source_dir starlink_pss_fft_bank_owned_slice.v]
  set channel [open $mutation_path r]; set candidate [read $channel]; close $channel
  set old {.input_valid(return_valid && !next_inverse && !fast_fault && product_bank_ready)}
  set new {.input_valid(return_valid && !next_inverse && !fast_fault)}
  if {[string first $old $candidate] < 0} { error "mutation target missing" }
  if {[string first $old $candidate] != [string last $old $candidate]} { error "mutation target not unique" }
  set candidate [string map [list $old $new] $candidate]
  set channel [open $mutation_path w]; puts -nonewline $channel $candidate; close $channel
}
file copy [info script] $source_dir
file copy [file join $script_dir create_shared_realtime_xfft_ip.tcl] $source_dir
file copy [file join $script_dir tb tb_starlink_pss_fft_bank_owned_slice.sv] $source_dir
set vector_names {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents
  inverse_exponents upper_edge_pss_kernel_q17}
foreach name $vector_names { file copy [file join $vector_dir ${name}.mem] $source_dir }
set project_name fft_bank_owned_slice
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
foreach name $rtl_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $source_dir tb_starlink_pss_fft_bank_owned_slice.sv]
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem] }
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_core_three_bank_capture_product_inverse_island"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "fast_clock_mhz=$fast_mhz slow_clock_mhz=100 no_physical_no_receiver_no_RF=true"
puts $channel "join_gate_removed_mutation=$mutation"
puts $channel "registered_scheduling=$registered"
puts $channel "source_CDC_product_local_output_CDC_banks_instantiated=true"
puts $channel "forward_ACK=actual_validated_product_bank_ownership; inverse_ACK=actual_slow_last_read"
puts $channel "source_hashes=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper]"
close $channel
set_property top tb_starlink_pss_fft_bank_owned_slice [get_filesets sim_1]
set_property generic [list FAST_MHZ=$fast_mhz QUICK_MUTATION=$mutation REGISTERED_SCHEDULING=$registered] [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set logfile [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $logfile r]
set log [read $channel]
close $channel
if {$mutation} {
  if {[string first "Fatal: join acceptance differs from guard retirement" $log] < 0 ||
      [string first "FFT_BANK_OWNED_SLICE_PASS" $log] >= 0} {
    error "mutation did not fail its specific held-final witness; inspect $logfile"
  }
  close_project
  puts "FFT_BANK_OWNED_JOIN_GATE_MUTATION_REJECTED_BY_ACTUAL_CORE_WITNESS"
  exit
}
if {[string first "FFT_BANK_OWNED_SLICE_PASS" $log] < 0 || [regexp -nocase {fatal:|error:} $log]} {
  error "bank-owned simulation failed; inspect $logfile"
}
if {$registered && [string first "REGISTERED_SCHEDULING_PASS" $log] < 0} {
  error "registered scheduling boundary tests did not complete"
}
if {$registered && [string first "PREFLIGHT_REASON_SPLIT_PASS" $log] < 0} {
  error "preflight reason/admission split matrix did not complete"
}
if {[string first "HELD_PHASE_INPUT_PASS" $log] < 0} {
  error "held-phase input tuple/active fault matrix did not complete"
}
if {[string first "BALANCED_IDENTITY_ACTUAL_PASS enabled=$registered " $log] < 0} {
  error "balanced/default identity actual-core comparison did not complete"
}
if {[string first "HELD_PREFLIGHT_ACTUAL_PASS registered=$registered " $log] < 0} {
  error "held-preflight full current-cause/phase qualification comparison did not complete"
}
close_project
puts "FFT_BANK_OWNED_ACTUAL_CORE_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM"
