# Reset constraint owned by the integrated acquisition wrapper. Component CDC
# constraints are packaged from their independently qualified source files.

set pss_acquisition_sample_reset_sync [get_cells -quiet -hier -regexp \
  {.*sample_reset_release_reg\[[01]\].*}]
set_property ASYNC_REG TRUE $pss_acquisition_sample_reset_sync
set_property SHREG_EXTRACT NO $pss_acquisition_sample_reset_sync
set pss_acquisition_sample_reset_async_pins [get_pins -quiet \
  -of_objects $pss_acquisition_sample_reset_sync \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -quiet -to $pss_acquisition_sample_reset_async_pins
