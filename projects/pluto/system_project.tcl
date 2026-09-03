source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create pluto 0 {} "xc7z010clg400-1"

# The complete detector is intentionally area-first.  This also lets the same
# source file exercise ADI's global-synthesis path, where Vivado can optimize
# across the tracker/acquisition IP boundaries instead of treating their OOC
# checkpoints as fixed islands.
set top_synth_run [get_runs synth_1]
set_property strategy Flow_AreaOptimized_high $top_synth_run
set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 \
  $top_synth_run

# The metadata-capable RX DMAC uses a 26-bit length counter so the largest
# supported frame remains one transfer. Keep its existing local area strategy;
# the RX-only experiment changes no DMA semantics.
if {$ADI_USE_OOC_SYNTHESIS == 1} {
  set rx_dma_synth_run [get_runs system_axi_ad9361_adc_dma_0_synth_1]
  set_property strategy Flow_AreaOptimized_high $rx_dma_synth_run
  # The area strategies default this threshold to one, creating enough small
  # control sets to defeat slice packing.  Four is Vivado's normal synthesis
  # threshold and keeps the optimization local without changing the logic.
  set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 \
    $rx_dma_synth_run

  # Keep both experimental PSS blocks independently synthesized with the same
  # area-first policy used by their OOC gates. The complete route remains the
  # authority on whether the combined tracker/acquisition shell fits.
  foreach pss_synth_run [list \
      [get_runs system_starlink_pss_tracker_0_synth_1] \
      [get_runs system_starlink_pss_acquisition_0_synth_1]] {
    set_property strategy Flow_AreaOptimized_high $pss_synth_run
    set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 \
      $pss_synth_run
  }
}

adi_project_files pluto [list \
  "system_top.v" \
  "system_constr.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

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
