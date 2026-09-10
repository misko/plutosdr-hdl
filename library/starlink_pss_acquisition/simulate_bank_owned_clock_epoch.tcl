# Isolated actual generated MMCM + actual idle FFT bank reset-lifecycle study.
if {$argc != 1} { error "expected NEW_OUTPUT" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file dirname [file normalize [info script]]]
set out [file normalize [lindex $argv 0]]
if {[file exists $out]} { error "refusing to overwrite clock epoch evidence" }
set rtl_names {starlink_pss_fft_bank_owned_slice starlink_pss_realtime_input_guard
  starlink_pss_realtime_result_guard starlink_pss_block_mailbox
  starlink_pss_forward_kernel_join starlink_pss_kernel_rom starlink_pss_spectrum_product}
set paths [list [info script]]
foreach name $rtl_names { lappend paths [file join $script_dir ${name}.v] }
foreach name {create_shared_realtime_xfft_ip.tcl create_bank_owned_clock_ip.tcl verify_realtime_probe_result.tcl} {
  lappend paths [file join $script_dir $name]
}
foreach name {tb_starlink_pss_bank_clock_epoch.sv upper_edge_pss_kernel_q17.mem} {
  lappend paths [file join $script_dir tb $name]
}
foreach path $paths { if {![file isfile $path]} { error "missing clock epoch source $path" } }
set frozen [file join $out frozen_sources]
file mkdir $frozen
foreach path $paths { file copy $path $frozen }
foreach helper {create_shared_realtime_xfft_ip create_bank_owned_clock_ip verify_realtime_probe_result} {
  source [file join $frozen ${helper}.tcl]
}
set project_name bank_clock_epoch
set project_dir [file join $out project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set gen [file join $project_dir ${project_name}.gen sources_1 ip]
set clock_files [pss_create_bank_owned_clock_ip [file join $gen starlink_bank_clock175_candidate]]
set fft_wrapper [file join $gen starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $fft_wrapper
foreach name $rtl_names { add_files -norecurse [file join $frozen ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $frozen tb_starlink_pss_bank_clock_epoch.sv]
add_files -fileset sim_1 -norecurse [file join $frozen upper_edge_pss_kernel_q17.mem]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_bank_clock_epoch [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set receipt [open [file join $out scope.txt] w]
puts $receipt "scope=actual_generated_MMCM_and_idle_bank_reset_only"
puts $receipt "input_clock_MHz=100 nominal_output_MHz=175 average_period_tolerance_ns=0.005 measured_edges_per_epoch=1024"
puts $receipt "epochs=3 lock_drop_stimulus=MMCM_reset not_input_clock_loss_detection=true"
puts $receipt "no_payload_no_receiver_no_place_no_route_no_radio_no_board_reference_change=true"
puts $receipt "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $receipt "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $frozen *]]] {*}$clock_files $fft_wrapper]"
close $receipt
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $log r]; set transcript [read $channel]; close $channel
if {[regexp -line {^BANK_CLOCK_EPOCH_FAIL } $transcript]} { error "clock epoch assertion failed" }
set markers [list {BANK_CLOCK_EPOCH_PASS epochs=3 measured_edges=3072 mmcm_reset_lock_drop=1 manual_epoch_reset=1 actual_idle_bank=1 NO_PAYLOAD_PHYSICAL_OR_RADIO_CLAIM}]
require_realtime_probe_pass $log $markers BANK_CLOCK_PERIOD_PASS 3
require_realtime_probe_pass $log $markers BANK_CLOCK_EPOCH_READY 3
close_project
puts "BANK_CLOCK_EPOCH_ACTUAL_IP_VERIFIED_NO_PHYSICAL_CLAIM"
