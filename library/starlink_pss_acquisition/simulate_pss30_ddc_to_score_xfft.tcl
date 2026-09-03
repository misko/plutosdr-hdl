# Vivado 2022.2 bit-exact behavioral gate for the 30/60 MS/s DDC and real
# shared-XFFT acquisition pipeline.
# Usage: vivado -mode batch -source simulate_pss30_ddc_to_score_xfft.tcl \
#        -tclargs OUTPUT VECTOR_DIRECTORY ?SOURCE_RATE_MSPS?

if {$argc != 2 && $argc != 3} {
  error "expected absolute output/vector directories and optional source rate"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set source_rate_msps 30
if {$argc == 3} {
  set source_rate_msps [lindex $argv 2]
}
if {$source_rate_msps ni {30 60}} {
  error "source rate must be 30 or 60 MS/s"
}
set project_dir [file join $output_dir project]
set project_name starlink_pss${source_rate_msps}_ddc_to_score_xfft_sim
file mkdir $output_dir

foreach required_file {
  source_ci16.mem
  ddc_ci16.mem
  forward_q17.mem
  product_q17.mem
  inverse_q17.mem
  forward_exponents.mem
  inverse_exponents.mem
  scores_u8.mem
} {
  if {![file isfile [file join $vector_dir $required_file]]} {
    error "missing replay vector $required_file"
  }
}

create_project -force $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
  -module_name starlink_pss_fft512_bfp18
set_property -dict [list \
  CONFIG.channels {1} \
  CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {100} \
  CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {20} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {18} \
  CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} \
  CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} \
  CONFIG.xk_index {true} \
  CONFIG.throttle_scheme {nonrealtime} \
  CONFIG.output_ordering {natural_order} \
  CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} \
  CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} \
  CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips starlink_pss_fft512_bfp18]
generate_target all [get_ips starlink_pss_fft512_bfp18]

set wrappers [glob -nocomplain \
  [file join $project_dir ${project_name}.gen sources_1 ip \
    starlink_pss_fft512_bfp18 synth starlink_pss_fft512_bfp18.vhd]]
if {[llength $wrappers] != 1} {
  error "could not locate generated XFFT synthesis wrapper"
}
set wrapper_file [open [lindex $wrappers 0] r]
set wrapper_text [read $wrapper_file]
close $wrapper_file
if {![regexp {C_ARCH => 1,} $wrapper_text]} {
  error "20 MS/s automatic selection did not choose radix-4 burst C_ARCH=1"
}

set rtl_sources [list \
  starlink_pss_x2_ddc.v \
  starlink_pss_overlap_scheduler.v \
  starlink_pss_energy_cache.v \
  starlink_pss_xfft_block_adapter.v \
  starlink_pss_xfft_intermediate_buffer.v \
  starlink_pss_kernel_rom.v \
  starlink_pss_forward_kernel_join.v \
  starlink_pss_spectrum_product.v \
  starlink_pss_ifft_qualifier.v \
  starlink_pss_raw_result_fifo.v \
  starlink_pss_energy_join.v \
  starlink_pss_score_prepare.v \
  starlink_pss_score_divider.v \
  starlink_pss_score_divider_radix4.v \
  starlink_pss_score_lanes.v \
  starlink_pss_candidate_score_path.v \
  starlink_pss_iq_to_score.v \
]
foreach source_name $rtl_sources {
  add_files -norecurse [file join $script_dir $source_name]
}

add_files -fileset sim_1 -norecurse \
  [file join $script_dir tb tb_starlink_pss30_ddc_to_score_xfft.sv]
set kernel_name [expr {$source_rate_msps == 60 ?
  "upper_edge_pss60_x4_ddc_kernel_q17.mem" :
  "upper_edge_pss30_x2_ddc_kernel_q17.mem"}]
add_files -fileset sim_1 -norecurse \
  [file join $script_dir tb $kernel_name]
foreach vector_file [glob [file join $vector_dir *.mem]] {
  add_files -fileset sim_1 -norecurse $vector_file
}
set_property file_type {Memory Initialization Files} \
  [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss30_ddc_to_score_xfft [get_filesets sim_1]
set_property generic "SOURCE_RATE_MSPS=$source_rate_msps" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
close_sim
set simulation_log [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
if {![file isfile $simulation_log]} {
  error "simulation log was not produced"
}
set simulation_channel [open $simulation_log r]
set simulation_text [read $simulation_channel]
close $simulation_channel
if {[regexp {PSS_DDC_XFFT_FAIL} $simulation_text]} {
  error "$source_rate_msps MS/s DDC-to-XFFT testbench reported a failure"
}
set source_count [expr {$source_rate_msps == 60 ? 5666 : 2826}]
set pass_signature \
  "PSS_DDC_XFFT_PASS rate=$source_rate_msps source=$source_count ddc=1406 blocks=3 scores=1341 pss255=3"
if {[string first $pass_signature $simulation_text] < 0} {
  error "$source_rate_msps MS/s DDC-to-XFFT pass signature is missing"
}
close_project

puts "STARLINK_PSS${source_rate_msps}_DDC_TO_SCORE_XFFT_SIMULATION_COMPLETE"
