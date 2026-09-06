# Bounded deterministic Stage-15 PSS qualification source. DO NOT MERGE.

source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

adi_ip_create axi_starlink_pss_periodic_injector
adi_ip_files axi_starlink_pss_periodic_injector [list \
  "$ad_hdl_dir/library/common/up_axi.v" \
  "starlink_pss_periodic_injection_mux.v" \
  "axi_starlink_pss_periodic_injector.v" \
  "axi_starlink_pss_periodic_injector_constr.xdc" ]

adi_ip_properties axi_starlink_pss_periodic_injector
set_property display_name \
  "Experimental 15 MS/s Periodic PSS Qualification Source" [ipx::current_core]
set_property description \
  "Future-indexed 130-by-130 periodic CI16 fixture with deterministic nonzero fill" \
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

ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
