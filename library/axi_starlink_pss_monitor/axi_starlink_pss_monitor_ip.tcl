# Experimental, read-only Starlink repeated-delay candidate monitor IP.

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create axi_starlink_pss_monitor
adi_ip_files axi_starlink_pss_monitor [list \
  "$ad_hdl_dir/library/common/up_axi.v" \
  "starlink_pss_delay_candidate.v" \
  "starlink_pss_event_cdc.v" \
  "axi_starlink_pss_monitor.v" \
  "axi_starlink_pss_monitor_constr.xdc" ]

adi_ip_properties axi_starlink_pss_monitor
set_property display_name "Experimental Starlink PSS Candidate Monitor" \
  [ipx::current_core]
set_property description \
  "Read-only repeated-delay diagnostic; candidate events are not exact PSS evidence" \
  [ipx::current_core]

ipx::infer_bus_interface sample_clk xilinx.com:signal:clock_rtl:1.0 \
  [ipx::current_core]
set sample_reset_intf [ipx::infer_bus_interface sample_reset \
  xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
set sample_reset_polarity [ipx::add_bus_parameter POLARITY $sample_reset_intf]
set_property value ACTIVE_HIGH $sample_reset_polarity

ipx::infer_bus_interface s_axi_aclk xilinx.com:signal:clock_rtl:1.0 \
  [ipx::current_core]
set axi_reset_intf [ipx::infer_bus_interface s_axi_aresetn \
  xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
set axi_reset_polarity [ipx::add_bus_parameter POLARITY $axi_reset_intf]
set_property value ACTIVE_LOW $axi_reset_polarity

ipx::add_bus_parameter ASSOCIATED_BUSIF \
  [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property value s_axi [ipx::get_bus_parameters ASSOCIATED_BUSIF \
  -of_objects [ipx::get_bus_interfaces s_axi_aclk \
  -of_objects [ipx::current_core]]]

set_property -dict [list \
  value_validation_type list \
  value_validation_list "15 30 60" \
] [ipx::get_user_parameters RATE_MSPS -of_objects [ipx::current_core]]

set_property -dict [list \
  value_validation_type range_long \
  value_validation_range_minimum 1 \
  value_validation_range_maximum 32768 \
] [ipx::get_user_parameters THRESHOLD_Q15 -of_objects [ipx::current_core]]

ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
