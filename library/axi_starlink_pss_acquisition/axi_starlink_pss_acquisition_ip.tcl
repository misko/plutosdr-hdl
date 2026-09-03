# Complete experimental 15/30/60 MS/s acquisition IP for the one-RX Pluto shell.

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create axi_starlink_pss_acquisition

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

set acq_dir "$ad_hdl_dir/library/starlink_pss_acquisition"
set map_dir "$ad_hdl_dir/library/axi_starlink_pss_phase_map"
adi_ip_files axi_starlink_pss_acquisition [list \
  "$acq_dir/starlink_pss_sample_cdc.v" \
  "$acq_dir/starlink_pss_x2_ddc.v" \
  "$acq_dir/starlink_pss_overlap_scheduler.v" \
  "$acq_dir/starlink_pss_energy_cache.v" \
  "$acq_dir/starlink_pss_xfft_block_adapter.v" \
  "$acq_dir/starlink_pss_xfft_intermediate_buffer.v" \
  "$acq_dir/starlink_pss_kernel_rom.v" \
  "$acq_dir/starlink_pss_forward_kernel_join.v" \
  "$acq_dir/starlink_pss_spectrum_product.v" \
  "$acq_dir/starlink_pss_ifft_qualifier.v" \
  "$acq_dir/starlink_pss_raw_result_fifo.v" \
  "$acq_dir/starlink_pss_energy_join.v" \
  "$acq_dir/starlink_pss_score_prepare.v" \
  "$acq_dir/starlink_pss_score_divider.v" \
  "$acq_dir/starlink_pss_score_divider_radix4.v" \
  "$acq_dir/starlink_pss_score_lanes.v" \
  "$acq_dir/starlink_pss_candidate_score_path.v" \
  "$acq_dir/starlink_pss_iq_to_score.v" \
  "$acq_dir/starlink_pss_score_phase_tagger.v" \
  "$acq_dir/starlink_pss_phase_map_bank.v" \
  "$acq_dir/starlink_pss_phase_map.v" \
  "$acq_dir/starlink_pss_acquisition_health.v" \
  "$acq_dir/starlink_pss_iq_to_phase_map.v" \
  "$acq_dir/tb/upper_edge_pss_kernel_q17.mem" \
  "$acq_dir/tb/upper_edge_pss30_x2_ddc_kernel_q17.mem" \
  "$acq_dir/tb/upper_edge_pss60_x4_ddc_kernel_q17.mem" \
  "$map_dir/starlink_pss_axi_lite.v" \
  "axi_starlink_pss_phase_map_sync.v" \
  "axi_starlink_pss_acquisition.v" \
  "axi_starlink_pss_acquisition_constr.xdc" \
  "$acq_dir/starlink_pss_sample_cdc_constr.xdc" ]

adi_ip_properties axi_starlink_pss_acquisition
set_property display_name "Experimental 15/30/60 MS/s Continuous PSS Acquisition" \
  [ipx::current_core]
set_property description \
  "Loss-aware RX CDC, optional x2/x4 acquisition DDC, continuous shared-XFFT phase maps, and atomic PSMA control" \
  [ipx::current_core]

set sample_clock_intf [ipx::infer_bus_interface sample_clk \
  xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]]
set sample_reset_intf [ipx::infer_bus_interface sample_reset \
  xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
set sample_reset_polarity [ipx::add_bus_parameter POLARITY $sample_reset_intf]
set_property value ACTIVE_HIGH $sample_reset_polarity
set sample_associated_reset [ipx::add_bus_parameter ASSOCIATED_RESET \
  $sample_clock_intf]
set_property value sample_reset $sample_associated_reset

set axi_clock_intf [ipx::infer_bus_interface s_axi_aclk \
  xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]]
set axi_reset_intf [ipx::infer_bus_interface s_axi_aresetn \
  xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
set axi_reset_polarity [ipx::add_bus_parameter POLARITY $axi_reset_intf]
set_property value ACTIVE_LOW $axi_reset_polarity
set axi_associated_busif [ipx::add_bus_parameter ASSOCIATED_BUSIF \
  $axi_clock_intf]
set_property value s_axi $axi_associated_busif
set axi_associated_reset [ipx::add_bus_parameter ASSOCIATED_RESET \
  $axi_clock_intf]
set_property value s_axi_aresetn $axi_associated_reset

ipx::infer_bus_interface irq xilinx.com:signal:interrupt_rtl:1.0 \
  [ipx::current_core]

set_property -dict [list \
  value_validation_type list \
  value_validation_list "7" \
] [ipx::get_user_parameters SAMPLE_FIFO_ADDRESS_WIDTH \
  -of_objects [ipx::current_core]]

set_property -dict [list \
  value_validation_type list \
  value_validation_list "15 30 60" \
] [ipx::get_user_parameters INPUT_RATE_MSPS \
  -of_objects [ipx::current_core]]

ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
