# Complete coarse composition SYNTHESIS only, from actually passing frozen RTL.
# No receiver build, placement/route, clock waiver or numerical modification.
if {$argc != 2} { error "expected NEW_OUTPUT PASSED_NUMERIC_SIMULATION_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set evidence_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite coarse synthesis evidence" }
set prior_sources [file join $evidence_dir frozen_sources]
set simlog [file join $evidence_dir project iq_to_score_bank_owned.sim sim_1 behav xsim simulate.log]
set toplog [file join $evidence_dir [file tail $evidence_dir].log]
source [file join $prior_sources verify_realtime_probe_result.tcl]
set markers [list {BANK_IQ_FAULT_RESET_GAP_PASS qualifier_mutations=5 descriptor=1 core_fault=1 fft_reset=1 slow_reset=1 source_gap=1 source_index=1 exact_epochs=4 exact_scores=5364 autonomous_gap_index_recovery=1}]
require_realtime_probe_pass $simlog $markers IQ_TO_SCORE_XFFT_PASS 1
require_realtime_probe_pass $simlog $markers BANK_IQ_EXACT_REPLAY_PASS 3
set channel [open $simlog r]; set simulation [read $channel]; close $channel
if {[regexp -line {^IQ_TO_SCORE_XFFT(_LONGRUN)?_(FAIL|FAULT) } $simulation]} {
  error "failed numerical simulation cannot admit synthesis"
}
set channel [open $toplog r]; set top_transcript [read $channel]; close $channel
if {![regexp -line {^BANK_IQ_TO_SCORE_ACTUAL_CORE_VERIFIED mode=numeric fast_mhz=(175|200) NO_PHYSICAL_OR_RF_CLAIM$} $top_transcript]} {
  error "missing positive numeric runner terminal"
}
set channel [open [file join $evidence_dir scope.txt] r]; set prior_scope [read $channel]; close $channel
set rtl_names {starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_block_mailbox starlink_pss_forward_kernel_join starlink_pss_kernel_rom
  starlink_pss_spectrum_product starlink_pss_overlap_scheduler starlink_pss_energy_cache
  starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo starlink_pss_energy_join
  starlink_pss_score_prepare starlink_pss_score_divider starlink_pss_score_divider_radix4
  starlink_pss_score_lanes starlink_pss_candidate_score_path}
set copy_paths {}
foreach name $rtl_names { lappend copy_paths [file join $prior_sources ${name}.v] }
foreach name {create_shared_realtime_xfft_ip.tcl upper_edge_pss_kernel_q17.mem} {
  lappend copy_paths [file join $prior_sources $name]
}
foreach path $copy_paths {
  if {![file isfile $path] || [string first [exec sha256sum $path] $prior_scope] < 0} {
    error "required source missing or changed since passing simulation: $path"
  }
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $copy_paths { file copy $path $source_dir }
foreach name {fft_bank_owned_synth_threads.tcl fft_bank_owned_resource_probe.xdc} {
  file copy [file join $script_dir $name] $source_dir
}
file copy [info script] $source_dir
set project_name iq_bank_owned_synthesis
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
foreach name $rtl_names { add_files -norecurse [file join $source_dir ${name}.v] }
add_files -fileset constrs_1 -norecurse [file join $source_dir fft_bank_owned_resource_probe.xdc]
set_property top starlink_pss_iq_to_score_bank_owned [get_filesets sources_1]
set_property generic KERNEL_ROM_FILE=[file join $source_dir upper_edge_pss_kernel_q17.mem] [get_filesets sources_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
set_property -dict [list {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context}] [get_runs synth_1]
create_ip_run [get_ips starlink_pss_fft512_bfp18_rt_candidate]
set ip_run [get_runs starlink_pss_fft512_bfp18_rt_candidate_synth_1]
set_property strategy Flow_AreaOptimized_high $ip_run
foreach run [list $ip_run [get_runs synth_1]] {
  set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 $run
  set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $source_dir fft_bank_owned_synth_threads.tcl] $run
}
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=complete_canonical_coarse_iq_to_score_actual_core_OOC_synthesis"
puts $channel "source_simulation=$evidence_dir"
puts $channel "source_simulation_hashes=[exec sha256sum $simlog $toplog [file join $evidence_dir scope.txt]]"
puts $channel "source_hashes_before_synthesis=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper]"
puts $channel "top_resource_probe_clocks_MHz=100,175; generated_IP_OOC_clock_unchanged=true"
puts $channel "no_place_no_route_no_receiver_no_RF_no_timing_pass_claim=true"
puts $channel "maxThreads_each_synthesis_process=2"
close $channel
launch_runs $ip_run -jobs 2
wait_on_run $ip_run
if {[get_property STATUS $ip_run] ne "synth_design Complete!"} { error "actual FFT synthesis failed" }
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "coarse composition synthesis failed" }
open_run synth_1
set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $blackboxes]} { error "coarse resource inventory contains black boxes: $blackboxes" }
report_utilization -file [file join $output_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $output_dir hierarchy.rpt]
report_clocks -file [file join $output_dir synthesis_clocks.rpt]
check_timing -verbose -file [file join $output_dir check_timing_unqualified.rpt]
report_cdc -details -file [file join $output_dir cdc_unqualified.rpt]
write_checkpoint [file join $output_dir iq_bank_owned_synth.dcp]
set channel [open [file join $output_dir resource_receipt.txt] w]
puts $channel "scope=whole_coarse_scheduler_three_banks_fft_product_energy_qualifier_fifo_normalization_scoring"
puts $channel "black_boxes=0"
foreach {label pattern} {dsp48e1 DSP48E1 ramb18e1 RAMB18E1 ramb36e1 RAMB36E1} {
  puts $channel "$label=[llength [get_cells -quiet -hier -filter REF_NAME==$pattern]]"
}
puts $channel "synthesis_only=true; no_achieved_clock_or_receiver_area_saving_claim=true"
close $channel
close_project
puts "BANK_IQ_TO_SCORE_COMPLETE_COARSE_SYNTHESIS_RESOURCES_RECORDED"
