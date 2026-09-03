# Vivado 2022.2 mixed-language behavioral gate for the real XFFT pair.
# Usage: vivado -mode batch -source simulate_iq_to_score_xfft.tcl \
#        -tclargs OUTPUT VECTOR_DIRECTORY

if {$argc != 2} {
  error "expected absolute output and vector directories"
}
if {[version -short] ne "2022.2"} {
  error "this evidence gate requires Vivado 2022.2, got [version -short]"
}

set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
set project_dir [file join $output_dir project]
set project_name starlink_pss_iq_to_score_xfft_sim
file mkdir $output_dir

foreach required_file {
  samples_ci16.mem
  forward_q23.mem
  product_q23.mem
  inverse_q23.mem
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
  -module_name starlink_pss_fft512_bfp24
set_property -dict [list \
  CONFIG.channels {1} \
  CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {100} \
  CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {20} \
  CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} \
  CONFIG.input_width {24} \
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
  CONFIG.butterfly_type {use_luts} \
] [get_ips starlink_pss_fft512_bfp24]
generate_target all [get_ips starlink_pss_fft512_bfp24]

set wrappers [glob -nocomplain \
  [file join $project_dir ${project_name}.gen sources_1 ip \
    starlink_pss_fft512_bfp24 synth starlink_pss_fft512_bfp24.vhd]]
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
  starlink_pss_overlap_scheduler.v \
  starlink_pss_energy_cache.v \
  starlink_pss_xfft_block_adapter.v \
  starlink_pss_kernel_rom.v \
  starlink_pss_forward_kernel_join.v \
  starlink_pss_spectrum_product.v \
  starlink_pss_ifft_qualifier.v \
  starlink_pss_raw_result_fifo.v \
  starlink_pss_energy_join.v \
  starlink_pss_score_prepare.v \
  starlink_pss_score_divider.v \
  starlink_pss_score_lanes.v \
  starlink_pss_candidate_score_path.v \
  starlink_pss_iq_to_score.v \
]
foreach source_name $rtl_sources {
  add_files -norecurse [file join $script_dir $source_name]
}

add_files -fileset sim_1 -norecurse \
  [file join $script_dir tb tb_starlink_pss_iq_to_score_xfft.sv]
add_files -fileset sim_1 -norecurse \
  [file join $script_dir tb upper_edge_pss_kernel_q23.mem]
foreach vector_file [glob [file join $vector_dir *.mem]] {
  add_files -fileset sim_1 -norecurse $vector_file
}
set_property file_type {Memory Initialization Files} \
  [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_iq_to_score_xfft [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project

puts "STARLINK_IQ_TO_SCORE_XFFT_SIMULATION_COMPLETE"
