source ../../scripts/adi_env.tcl
source $ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source $ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create pluto 0 {} "xc7z010clg400-1"

adi_project_files pluto [list \
  "system_top.v" \
  "system_constr.xdc" \
  "$ad_hdl_dir/library/common/ad_iobuf.v"]

set_property is_enabled false [get_files  *system_sys_ps7_0.xdc]

# Three directive experiments all made timing worse than the default flow
# (-2.391 default, -3.649 AltSpreadLogic_medium, -3.895 phys_opt
# AggressiveExplore + route Explore + post-route). On a device this full the
# extra optimisation passes churn placement and lengthen routes. Default flow
# it is; the remedy is floorplanning, in system_constr.xdc.
adi_project_run pluto
source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl

