# CDC constraints for the loss-detecting Starlink PSS sample ingress.

set pss_sample_cdc_sync_first [get_cells -quiet -hier -regexp \
  {.*(source_reset_source_sync_reg\[0\]|acquisition_reset_source_sync_reg\[0\]|source_reset_acquisition_sync_reg\[0\]|acquisition_reset_acquisition_sync_reg\[0\]|read_pointer_gray_sync_1_reg\[[0-9]+\]|write_pointer_gray_sync_1_reg\[[0-9]+\]|dropped_count_gray_sync_1_reg\[[0-9]+\]).*}]

set_property ASYNC_REG TRUE $pss_sample_cdc_sync_first
set_property SHREG_EXTRACT NO $pss_sample_cdc_sync_first
set_false_path -quiet -to $pss_sample_cdc_sync_first

set pss_sample_cdc_reset_sync_all [get_cells -quiet -hier -regexp \
  {.*(source_reset_source_sync_reg|acquisition_reset_source_sync_reg|source_reset_acquisition_sync_reg|acquisition_reset_acquisition_sync_reg)\[[01]\].*}]
set pss_sample_cdc_reset_async_pins [get_pins -quiet \
  -of_objects $pss_sample_cdc_reset_sync_all \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -quiet -to $pss_sample_cdc_reset_async_pins

# Constrain each Gray-coded bus to settle within one 100 MHz acquisition
# period even though setup/hold is cut at its metastability-catching stage.
# This preserves the one-transition-in-flight property in both directions.
set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -filter {IS_SEQUENTIAL && \
    (NAME =~ *source_pointer_gray_reg* || \
     NAME =~ *source_pointer_binary_reg*)}] \
  -to [get_cells -quiet -hier -regexp \
    {.*write_pointer_gray_sync_1_reg\[[0-9]+\].*}]

set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -filter {IS_SEQUENTIAL && \
    (NAME =~ *acquisition_pointer_gray_reg* || \
     NAME =~ *acquisition_pointer_binary_reg*)}] \
  -to [get_cells -quiet -hier -regexp \
    {.*read_pointer_gray_sync_1_reg\[[0-9]+\].*}]

set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -filter {IS_SEQUENTIAL && \
    NAME =~ *source_dropped_count_gray_reg*}] \
  -to [get_cells -quiet -hier -regexp \
    {.*dropped_count_gray_sync_1_reg\[[0-9]+\].*}]
