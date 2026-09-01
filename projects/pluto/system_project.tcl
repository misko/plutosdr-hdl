source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create pluto 0 {} "xc7z010clg400-1"

# The metadata-capable RX DMAC uses a 26-bit length counter so the largest
# supported frame remains one transfer. Keep its existing local area strategy;
# the RX-only experiment changes no DMA semantics.
set rx_dma_synth_run [get_runs system_axi_ad9361_adc_dma_0_synth_1]
set_property strategy Flow_AreaOptimized_high $rx_dma_synth_run
# The area strategies default this threshold to one, creating enough small
# control sets to defeat slice packing.  Four is Vivado's normal synthesis
# threshold and keeps the optimization local without changing the logic.
set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 4 \
  $rx_dma_synth_run

adi_project_files pluto [list \
  "system_top.v" \
  "system_constr.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

set_property is_enabled false [get_files  *system_sys_ps7_0.xdc]

# Retain the known default implementation flow. The RX-only shell and detector
# must earn fresh placed/routed timing evidence rather than inheriting the old
# full-design placement experiments.
adi_project_run pluto
source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl
