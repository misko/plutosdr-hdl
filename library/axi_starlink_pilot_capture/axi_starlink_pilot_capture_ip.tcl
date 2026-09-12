# Experimental opt-in post-decimation capture, not a production TAG2 device.
source ../../scripts/adi_env.tcl
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl
adi_ip_create axi_starlink_pilot_capture
set pilot_dir "$ad_hdl_dir/library/starlink_pss_acquisition"
set coarse_dir "$ad_hdl_dir/library/starlink_coarse25"
adi_ip_files axi_starlink_pilot_capture [list \
  "$coarse_dir/starlink_coarse25_mac.v" \
  "$coarse_dir/starlink_coarse25_score.v" \
  "$coarse_dir/starlink_coarse25_datapath.v" \
  "$coarse_dir/starlink_coarse25_fold.v" \
  "$coarse_dir/starlink_coarse25_detector.v" \
  "$coarse_dir/starlink_coarse25_registers.v" \
  "$coarse_dir/coarse25_q15.mem" \
  "$pilot_dir/starlink_pss_score_divider.v" \
  "$ad_hdl_dir/library/axi_starlink_pss_phase_map/starlink_pss_axi_lite.v" \
  "$pilot_dir/starlink_pilot_ddc.v" \
  "$pilot_dir/starlink_pilot_halfband2.v" \
  "$pilot_dir/starlink_pilot_fir3.v" \
  "$pilot_dir/pilot_mixer_q16.mem" \
  "$pilot_dir/pilot_halfband2_q17.mem" \
  "$pilot_dir/pilot_fir3_q17.mem" \
  "axi_starlink_pilot_capture.v"]
adi_ip_properties axi_starlink_pilot_capture
# The tap uses explicit scalar/index pins, not ADI's inferred read-FIFO ABI.
ipx::remove_bus_interface canonical [ipx::current_core]
set_property display_name "Experimental paired 2.5 MS/s pilot capture" [ipx::current_core]
adi_add_bus "m_axis" "master" \
  "xilinx.com:interface:axis_rtl:1.0" "xilinx.com:interface:axis:1.0" \
  [list {"m_axis_tvalid" "TVALID"} {"m_axis_tready" "TREADY"} {"m_axis_tdata" "TDATA"}]
set axi_clock [ipx::get_bus_interfaces s_axi_aclk -of_objects [ipx::current_core]]
set_property value "s_axi:m_axis" \
  [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $axi_clock]
ipx::infer_bus_interface irq xilinx.com:signal:interrupt_rtl:1.0 [ipx::current_core]
set_property -dict [list value_validation_type list value_validation_list "15 30 60"] \
  [ipx::get_user_parameters INPUT_RATE_MSPS -of_objects [ipx::current_core]]
set_property -dict [list value_validation_type list value_validation_list "0 1"] \
  [ipx::get_user_parameters COARSE25_BYPASS -of_objects [ipx::current_core]]
set_property -dict [list value_validation_type list value_validation_list "5"] \
  [ipx::get_user_parameters OUTPUT_FIFO_BITS -of_objects [ipx::current_core]]
ipx::create_xgui_files [ipx::current_core]
ipx::save_core [ipx::current_core]
