source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl
adi_ip_create starlink_coarse25_ingress
adi_ip_files starlink_coarse25_ingress [list \
  "starlink_coarse25_ingress.v" \
  "$ad_hdl_dir/library/starlink_pss_acquisition/starlink_pss_sample_cdc.v" \
  "$ad_hdl_dir/library/starlink_pss_acquisition/starlink_pss_sample_cdc_constr.xdc" \
  "$ad_hdl_dir/library/axi_starlink_pss_acquisition/axi_starlink_pss_acquisition_constr.xdc"]
adi_ip_properties_lite starlink_coarse25_ingress
foreach intf {canonical sample} {
  set inferred [ipx::get_bus_interfaces -quiet $intf -of_objects [ipx::current_core]]
  if {[llength $inferred]} { ipx::remove_bus_interface $intf [ipx::current_core] }
}
foreach {clock reset polarity} {sample_clk sample_reset ACTIVE_HIGH calc_clk calc_resetn ACTIVE_LOW} {
  set clock_intf [ipx::infer_bus_interface $clock xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]]
  set reset_intf [ipx::infer_bus_interface $reset xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]]
  set_property value $polarity [ipx::add_bus_parameter POLARITY $reset_intf]
  set_property value $reset [ipx::add_bus_parameter ASSOCIATED_RESET $clock_intf]
}
ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
