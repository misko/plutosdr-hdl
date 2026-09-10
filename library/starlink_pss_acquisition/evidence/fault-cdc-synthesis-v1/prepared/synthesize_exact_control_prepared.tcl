# Full three-bank slice SYNTHESIS resource inventory, not receiver or timing.
# Sources are copied from an actually passing simulation, then hashed BEFORE
# synthesis. The original generated IP configuration and OOC clock are retained.
if {$argc != 3} { error "expected NEW_OUTPUT PREPARED EXPECTED_PREPARED_SHA256" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file join [file dirname [file normalize [info script]]] frozen_sources]
set output_dir [file normalize [lindex $argv 0]]
set evidence_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite synthesis evidence" }
# Prepared-inventory identity is supplied separately by the reviewed caller.
set expected_prepared [lindex $argv 2]
set prepared_inventory [file join $evidence_dir SHA256SUMS]
if {![regexp {^[0-9a-f]{64}$} $expected_prepared] ||
    [lindex [exec sha256sum $prepared_inventory] 0] ne $expected_prepared} {
  error "unexpected exact-control physical preparation"
}
set audit_helper [file join $evidence_dir prepare_exact_control_physical.py]
set old_directory [pwd]; cd $evidence_dir
exec sha256sum -c SHA256SUMS --quiet
cd $old_directory
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B $audit_helper --verify $evidence_dir --expected $expected_prepared]
source [file join $evidence_dir exact_physical_settings.tcl]
if {$registered != 1 || $distributed != 1 || $scratch != 1 || $per_cause != 1} { error "wrong combined physical options" }
set prior_sources [file join $evidence_dir frozen_sources]
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
set rtl_names {starlink_pss_fft_bank_owned_slice starlink_pss_realtime_input_guard
  starlink_pss_realtime_result_guard starlink_pss_block_mailbox
  starlink_pss_forward_kernel_join starlink_pss_kernel_rom starlink_pss_spectrum_product}
foreach name $rtl_names { file copy [file join $prior_sources ${name}.v] $source_dir }
foreach name {create_shared_realtime_xfft_ip.tcl upper_edge_pss_kernel_q17.mem} {
  file copy [file join $prior_sources $name] $source_dir
}
foreach name {fft_bank_owned_synth_threads.tcl fft_bank_owned_resource_probe.xdc} {
  file copy [file join $script_dir $name] $source_dir
}
file copy [info script] $source_dir
set project_name fft_bank_owned_synthesis
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
foreach name $rtl_names { add_files -norecurse [file join $source_dir ${name}.v] }
add_files -fileset constrs_1 -norecurse [file join $source_dir fft_bank_owned_resource_probe.xdc]
set_property top starlink_pss_fft_bank_owned_slice [get_filesets sources_1]
set_property generic [list KERNEL_ROM_FILE=[file join $source_dir upper_edge_pss_kernel_q17.mem] \
  REGISTERED_SCHEDULING=$registered DISTRIBUTED_FAST_FAULT=$distributed \
  PRIVATE_NEXT_START_SCRATCH=$scratch PER_CAUSE_FAULT_CDC=$per_cause] [get_filesets sources_1]
set physical_generics [get_property GENERIC [get_filesets sources_1]]
foreach {name value} [list REGISTERED_SCHEDULING $registered DISTRIBUTED_FAST_FAULT $distributed PRIVATE_NEXT_START_SCRATCH $scratch PER_CAUSE_FAULT_CDC $per_cause] {
  if {[lsearch -exact $physical_generics ${name}=$value] < 0} { error "missing physical parameter $name" }
}
if {[lsearch -all -inline -glob $physical_generics PER_CAUSE_FAULT_CDC=*] ne [list PER_CAUSE_FAULT_CDC=1]} {
  error "requires exactly one explicit C1 physical parameter"
}
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
puts $channel "scope=actual_generated_fft_plus_three_bank_island_synthesis_resources"
puts $channel "source_preparation=$evidence_dir"
puts $channel "expected_preparation_sha256=$expected_prepared"
puts $channel "source_simulation_log=$simlog"
puts $channel "registered_scheduling=$registered"
puts $channel "distributed_fast_fault=$distributed; private_next_start_scratch=$scratch; per_cause_fault_cdc=$per_cause"
puts $channel "effective_top_generics=$physical_generics"
puts $channel "source_simulation_hash=[exec sha256sum $simlog]"
puts $channel "source_hashes_before_synthesis=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper]"
puts $channel "top_resource_probe_clocks_MHz=100,175; generated_IP_OOC_clock_unchanged=true"
puts $channel "no_place_no_route_no_receiver_no_RF_no_timing_pass_claim=true"
puts $channel "maxThreads_each_synthesis_process=2"
close $channel
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B $audit_helper --verify $evidence_dir --expected $expected_prepared --copied $source_dir]
launch_runs $ip_run -jobs 2
wait_on_run $ip_run
if {[get_property STATUS $ip_run] ne "synth_design Complete!"} { error "actual FFT synthesis failed" }
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "slice synthesis failed" }
open_run synth_1
set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $blackboxes]} { error "resource inventory contains black boxes: $blackboxes" }
report_utilization -file [file join $output_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $output_dir hierarchy.rpt]
report_clocks -file [file join $output_dir synthesis_clocks.rpt]
check_timing -verbose -file [file join $output_dir check_timing_unqualified.rpt]
report_cdc -details -file [file join $output_dir cdc_unqualified.rpt]
write_checkpoint [file join $output_dir fft_bank_owned_synth.dcp]
set channel [open [file join $output_dir resource_receipt.txt] w]
puts $channel "black_boxes=0"
foreach {label pattern} {dsp48e1 DSP48E1 ramb18e1 RAMB18E1 ramb36e1 RAMB36E1} {
  puts $channel "$label=[llength [get_cells -quiet -hier -filter REF_NAME==$pattern]]"
}
puts $channel "synthesis_only=true; no_achieved_clock_or_receiver_area_saving_claim=true"
close $channel
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B $audit_helper --verify $evidence_dir --expected $expected_prepared --copied $source_dir]
close_project
puts "FFT_BANK_OWNED_THREE_BANK_SYNTHESIS_RESOURCES_RECORDED"
