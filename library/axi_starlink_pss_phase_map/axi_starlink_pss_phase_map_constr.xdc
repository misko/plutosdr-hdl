# CDC constraints for the experimental Starlink PSS phase-map AXI bridge.

set pss_map_sync_first [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg\[0\]|map_reset_sync_reg\[0\]|map_reset_control_sync_reg\[0\]|control_enable_map_sync_reg\[0\]|flush_request_sync_reg\[0\]|read_request_sync_reg\[0\]|read_request_bank_sync_1_reg|read_request_index_sync_1_reg\[[0-9]+\]|release_request_sync_reg\[0\]|release_request_bank_sync_1_reg|snapshot_request_sync_reg\[0\]|read_response_sync_reg\[0\]|read_response_payload_sync_1_reg\[[0-9]+\]|release_response_sync_reg\[0\]|release_error_sync_reg\[0\]|snapshot_response_sync_reg\[0\]|snapshot_payload_sync_1_reg\[[0-9]+\]|ready_mask_sync_1_reg\[[0-9]+\]).*}]

set_property ASYNC_REG TRUE $pss_map_sync_first
set_property SHREG_EXTRACT NO $pss_map_sync_first
set_false_path -quiet -to $pss_map_sync_first

set pss_map_reset_sync_all [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg|map_reset_sync_reg|map_reset_control_sync_reg)\[[01]\].*}]
set pss_map_reset_async_pins [get_pins -quiet \
  -of_objects $pss_map_reset_sync_all \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -quiet -to $pss_map_reset_async_pins

# Every bundled payload is immutable from request/response toggle issue until
# the opposite domain acknowledges it.  Bound first-stage skew in addition to
# cutting setup/hold at the metastability-catching register.
set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -regexp \
    {.*(read_request_bank_reg|read_request_index_reg\[[0-9]+\]).*}] \
  -to [get_cells -quiet -hier -regexp \
    {.*(read_request_bank_sync_1_reg|read_request_index_sync_1_reg\[[0-9]+\]).*}]

set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -regexp \
    {.*read_response_payload_reg\[[0-9]+\].*}] \
  -to [get_cells -quiet -hier -regexp \
    {.*read_response_payload_sync_1_reg\[[0-9]+\].*}]

set_bus_skew 10.000 \
  -from [get_cells -quiet -hier -regexp \
    {.*snapshot_source_payload_reg\[[0-9]+\].*}] \
  -to [get_cells -quiet -hier -regexp \
    {.*snapshot_payload_sync_1_reg\[[0-9]+\].*}]
