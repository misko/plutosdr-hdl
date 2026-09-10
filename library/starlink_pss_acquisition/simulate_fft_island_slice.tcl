# Isolated actual-core simulation. Never reuse or overwrite evidence.
if {$argc != 2} { error "expected NEW_OUTPUT FROZEN_VECTOR_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite island evidence" }
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
set rtl_names {starlink_pss_fft_island_slice starlink_pss_shared_realtime_xfft_service
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_block_mailbox starlink_pss_forward_kernel_join
  starlink_pss_kernel_rom starlink_pss_spectrum_product}
foreach name $rtl_names { file copy [file join $script_dir ${name}.v] $source_dir }
file copy [info script] $source_dir
file copy [file join $script_dir create_shared_realtime_xfft_ip.tcl] $source_dir
file copy [file join $script_dir tb tb_starlink_pss_fft_island_slice.sv] $source_dir
set vector_names {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents
  inverse_exponents upper_edge_pss_kernel_q17}
foreach name $vector_names { file copy [file join $vector_dir ${name}.mem] $source_dir }
set project_name fft_island_slice
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
foreach name $rtl_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $source_dir tb_starlink_pss_fft_island_slice.sv]
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem] }
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=isolated_actual_core_fft_product_ifft_same_clock_slice"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "clock_period_ns=5; no_synthesis_no_receiver_no_RF=true"
puts $channel "outer_CDC_not_instantiated; local_mailbox_copies_ACKs_retained=true"
puts $channel "source_hashes=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper]"
close $channel
set_property top tb_starlink_pss_fft_island_slice [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set logfile [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
set channel [open $logfile r]
set log [read $channel]
close $channel
if {[string first "FFT_ISLAND_SLICE_PASS" $log] < 0 || [regexp -nocase {fatal:|error:} $log]} {
  error "island simulation failed; inspect $logfile"
}
close_project
puts "FFT_ISLAND_ACTUAL_CORE_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM"
