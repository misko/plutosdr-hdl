source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create pluto 0 {} "xc7z010clg400-1"

# The complete detector is intentionally area-first.  This also lets the same
# source file exercise ADI's global-synthesis path, where Vivado can optimize
# across the tracker/acquisition IP boundaries instead of treating their OOC
# checkpoints as fixed islands.
set top_synth_run [get_runs synth_1]
set control_set_threshold 4
set_property strategy Flow_AreaOptimized_high $top_synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD \
  $control_set_threshold \
  $top_synth_run

# The metadata-capable RX DMAC uses a 26-bit length counter so the largest
# supported frame remains one transfer. Keep its existing local area strategy;
# the RX-only experiment changes no DMA semantics.
if {$ADI_USE_OOC_SYNTHESIS == 1} {
  set rx_dma_synth_run [get_runs -quiet system_axi_ad9361_adc_dma_0_synth_1]
  if {[llength $rx_dma_synth_run] == 1} {
    set_property strategy Flow_AreaOptimized_high $rx_dma_synth_run
    # The area strategies default this threshold to one, creating enough small
    # control sets to defeat slice packing.  Four is Vivado's normal synthesis
    # threshold and keeps the optimization local without changing the logic.
    set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD \
      $control_set_threshold \
      $rx_dma_synth_run
  }

  # Keep every instantiated experimental PSS block independently synthesized
  # with the same area-first policy used by its OOC gate. The complete route
  # remains the authority on whether the selected profile fits.
  set pss_synth_runs [get_runs system_starlink_pss_acquisition_0_synth_1]
  set tracker_synth_run [get_runs -quiet system_starlink_pss_tracker_0_synth_1]
  if {[llength $tracker_synth_run] == 1} {
    lappend pss_synth_runs $tracker_synth_run
  }
  foreach pss_synth_run $pss_synth_runs {
    set_property strategy Flow_AreaOptimized_high $pss_synth_run
    set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD \
      $control_set_threshold \
      $pss_synth_run
  }
}

adi_project_files pluto [list \
  "system_top.v" \
  "system_constr.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

if {[info exists ::env(STARLINK_PSS_PROFILE)] &&
    $::env(STARLINK_PSS_PROFILE) eq "detector-only"} {
  # Match the detector-only block design, whose expansion AXI SPI and IIC
  # interfaces are deliberately absent.  This define changes only the shell
  # connections to those optional header pins; PS7 SPI0 still controls AD9361.
  set_property verilog_define STARLINK_PSS_DETECTOR_ONLY [current_fileset]
}

set_property is_enabled false [get_files  *system_sys_ps7_0.xdc]

# Retain the known default implementation flow at 15/30 MS/s.  The 60 MS/s
# design is placement-sensitive near 75% LUT and 87.5% BRAM utilization, so use
# one named Vivado strategy which adds Explore placement/routing and post-route
# physical optimization.  This is still a fresh full implementation; it does
# not reuse a prior checkpoint or relax any timing constraint.
if {[info exists ::env(STARLINK_PSS_RATE_MSPS)] &&
    $::env(STARLINK_PSS_RATE_MSPS) eq "60"} {
  set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
}

adi_project_run pluto
source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl
