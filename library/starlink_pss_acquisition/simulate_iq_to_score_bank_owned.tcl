# Isolated actual-core numerical and continuous canonical15 capacity study.
# OUTPUT numeric VECTOR_DIR FAST_MHZ or OUTPUT capacity PROFILE FAST_MHZ ?64|4096?
if {$argc ni {4 5}} { error "expected NEW_OUTPUT numeric VECTORS FAST_MHZ or NEW_OUTPUT capacity nominal|bursty-stalled FAST_MHZ ?64|4096?" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set mode [lindex $argv 1]
set profile [lindex $argv 2]
set fast_mhz [lindex $argv 3]
set capacity_blocks 64
if {$argc == 5} {
  if {$mode ne "capacity"} { error "numeric mode has no capacity block override" }
  set capacity_blocks [lindex $argv 4]
}
if {$capacity_blocks ni {64 4096}} { error "capacity supports only 64 or 4096 blocks" }
if {$mode ni {numeric capacity} || $fast_mhz ni {175 200}} { error "unsupported bank composition probe" }
if {$mode eq "capacity" && $profile ni {nominal bursty-stalled}} { error "unsupported capacity profile" }
if {[file exists $output_dir]} { error "refusing to overwrite bank composition evidence" }
set rtl_names {starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_block_mailbox starlink_pss_forward_kernel_join starlink_pss_kernel_rom
  starlink_pss_spectrum_product starlink_pss_overlap_scheduler starlink_pss_energy_cache
  starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo starlink_pss_energy_join
  starlink_pss_score_prepare starlink_pss_score_divider starlink_pss_score_divider_radix4
  starlink_pss_score_lanes starlink_pss_candidate_score_path}
set source_dir [file join $output_dir frozen_sources]
set input_paths [list [info script]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach name {create_shared_realtime_xfft_ip prepare_iq_to_score_bank_owned verify_realtime_probe_result} {
  lappend input_paths [file join $script_dir ${name}.tcl]
}
set bench_name tb_starlink_pss_iq_to_score_xfft
if {$mode eq "capacity"} { append bench_name _longrun }
lappend input_paths [file join $script_dir tb ${bench_name}.sv]
lappend input_paths [file join $script_dir tb bank_owned_iq_fault_scenarios.svh]
lappend input_paths [file join $script_dir tb bank_owned_iq_capacity_checks.svh]
set vector_names {upper_edge_pss_kernel_q17}
set vector_dir [file join $script_dir tb]
if {$mode eq "numeric"} {
  set vector_dir [file normalize $profile]
  lappend vector_names samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents scores_u8
}
foreach name $vector_names { lappend input_paths [file join $vector_dir ${name}.mem] }
foreach path $input_paths { if {![file isfile $path]} { error "missing source $path" } }
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir prepare_iq_to_score_bank_owned.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $source_dir ${bench_name}.sv] r]
set bench [read $channel]; close $channel
set bench [prepare_bank_owned_bench $bench $mode]
set bench_path [file join $output_dir ${bench_name}.sv]
set channel [open $bench_path w]; puts -nonewline $channel $bench; close $channel
set project_name iq_to_score_bank_owned
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
foreach name $rtl_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse $bench_path
set_property include_dirs [list $source_dir] [get_filesets sim_1]
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem] }
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_core_bank_owned_complete_coarse_pipeline mode=$mode profile=$profile fast_mhz=$fast_mhz slow_mhz=100 source_msps=15"
puts $channel "capacity_blocks=$capacity_blocks numerical_fixture_blocks=3 source15_30_60_adapters_not_included=true no_receiver_no_physical_no_RF=true"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "source_hashes=[exec sha256sum {*}[glob [file join $source_dir *]] $bench_path $wrapper]"
close $channel
set generics [list FAST_MHZ=$fast_mhz]
if {$mode eq "capacity"} { lappend generics CAPACITY_BLOCKS=$capacity_blocks }
if {$mode eq "capacity" && $profile eq "bursty-stalled"} {
  lappend generics SOURCE_BURST_MODE=1 SCORE_STALL_MODE=1
}
set_property top $bench_name [get_filesets sim_1]
set_property generic $generics [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set logfile [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $logfile r]; set transcript [read $channel]; close $channel
if {[regexp -line {^IQ_TO_SCORE_XFFT(_LONGRUN)?_(FAIL|FAULT) } $transcript]} {
  error "bank-owned bench reported a failed assertion; inspect $logfile"
}
if {$mode eq "numeric"} {
  set terminal_markers [list \
    {BANK_IQ_FAULT_RESET_GAP_PASS qualifier_mutations=5 descriptor=1 core_fault=1 fft_reset=1 slow_reset=1 source_gap=1 source_index=1 exact_epochs=4 exact_scores=5364 autonomous_gap_index_recovery=1}]
  require_realtime_probe_pass $logfile $terminal_markers IQ_TO_SCORE_XFFT_PASS 1
  require_realtime_probe_pass $logfile $terminal_markers BANK_IQ_EXACT_REPLAY_PASS 3
} else {
  set capacity_scores [expr {$capacity_blocks * 447}]
  set capacity_samples [expr {$capacity_scores + 65}]
  set terminal_markers [list "BANK_IQ_CAPACITY_COMPLETE blocks=$capacity_blocks samples=$capacity_samples scores=$capacity_scores"]
  require_realtime_probe_pass $logfile $terminal_markers IQ_TO_SCORE_XFFT_LONGRUN_PROGRESS $capacity_blocks
  require_realtime_probe_pass $logfile $terminal_markers IQ_TO_SCORE_XFFT_LONGRUN_PASS 1
  require_realtime_probe_pass $logfile $terminal_markers IQ_TO_SCORE_XFFT_BACKLOG_PASS 1
  require_realtime_probe_pass $logfile $terminal_markers BANK_IQ_CAPACITY_METADATA_PASS 1
}
close_project
puts "BANK_IQ_TO_SCORE_ACTUAL_CORE_VERIFIED mode=$mode fast_mhz=$fast_mhz NO_PHYSICAL_OR_RF_CLAIM"
