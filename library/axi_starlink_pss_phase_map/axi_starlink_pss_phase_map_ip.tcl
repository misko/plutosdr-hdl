# Experimental AXI/CDC boundary for immutable Starlink PSS phase maps.

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create axi_starlink_pss_phase_map
adi_ip_files axi_starlink_pss_phase_map [list \
  "starlink_pss_axi_lite.v" \
  "axi_starlink_pss_phase_map.v" \
  "axi_starlink_pss_phase_map_constr.xdc" ]

adi_ip_properties axi_starlink_pss_phase_map
set_property display_name "Experimental Starlink PSS Phase-Map AXI Bridge" \
  [ipx::current_core]
set_property description \
  "Atomic immutable-map readout, release, telemetry, and control across independent clocks" \
  [ipx::current_core]

set map_clock_intf [ipx::infer_bus_interface map_clk \
  xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]]
set map_reset_intf [ipx::infer_bus_interface map_reset \
  xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
set map_reset_polarity [ipx::add_bus_parameter POLARITY $map_reset_intf]
set_property value ACTIVE_HIGH $map_reset_polarity
set map_associated_reset [ipx::add_bus_parameter ASSOCIATED_RESET \
  $map_clock_intf]
set_property value map_reset $map_associated_reset

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
  value_validation_type range_long \
  value_validation_range_minimum 2 \
  value_validation_range_maximum 65535 \
] [ipx::get_user_parameters PHASE_BINS -of_objects [ipx::current_core]]
set_property -dict [list \
  value_validation_type range_long \
  value_validation_range_minimum 1 \
  value_validation_range_maximum 31 \
] [ipx::get_user_parameters PHASE_INDEX_WIDTH -of_objects [ipx::current_core]]
set_property -dict [list \
  value_validation_type range_long \
  value_validation_range_minimum 2 \
  value_validation_range_maximum 255 \
] [ipx::get_user_parameters TILE_FRAMES -of_objects [ipx::current_core]]
set_property -dict [list \
  value_validation_type range_long \
  value_validation_range_minimum 1 \
  value_validation_range_maximum 32 \
] [ipx::get_user_parameters MAP_WIDTH -of_objects [ipx::current_core]]

ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
