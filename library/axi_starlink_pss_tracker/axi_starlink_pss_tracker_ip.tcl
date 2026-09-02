# Experimental, host-scheduled Stage-15 exact Starlink PSS tracking IP.

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create axi_starlink_pss_tracker
adi_ip_files axi_starlink_pss_tracker [list \
  "$ad_hdl_dir/library/common/up_axi.v" \
  "$ad_hdl_dir/library/common/ad_mem.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_async_fifo.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_sat_add48.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_candidate_scheduler.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_capture_bridge.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_sliding_correlator.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_tracking_core.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_exact_reducer.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_result_store.v" \
  "$ad_hdl_dir/library/starlink_pss_raw_correlator/starlink_pss_reduced_tracking_core.v" \
  "axi_starlink_pss_tracker.v" \
  "axi_starlink_pss_tracker_constr.xdc" ]

adi_ip_properties axi_starlink_pss_tracker
set_property display_name "Experimental Stage-15 Exact PSS Tracker" \
  [ipx::current_core]
set_property description \
  "Host-scheduled 66-tap exact TRACK_ONE pipeline with atomic result packets" \
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
  value_validation_list "15" \
] [ipx::get_user_parameters RATE_MSPS -of_objects [ipx::current_core]]

set_property -dict [list \
  value_validation_type range_long \
  value_validation_range_minimum 2 \
  value_validation_range_maximum 6 \
] [ipx::get_user_parameters COMMAND_FIFO_ADDRESS_WIDTH \
  -of_objects [ipx::current_core]]

ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
