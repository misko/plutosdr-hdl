# CDC constraints for the experimental Stage-15 exact tracker.
#
# AXI-reset assertion is asynchronous and release is synchronized separately
# in the AXI/engine and sample domains.  Sample reset crosses to AXI through a
# two-stage level synchronizer and holds the local sample side synchronously.
# Candidate descriptors, capture-bank descriptors, and bank-return tokens use
# Gray pointers or toggles with two destination-domain synchronizer stages. The
# current sample index is Gray encoded before crossing to AXI so software can
# schedule against a coherent near-current value.

set pss_tracker_sync_first [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg\[0\]|sample_reset_sync_reg\[0\]|sample_reset_control_sync_reg\[0\]|sample_index_gray_sync_1_reg\[[0-9]+\]|candidate_pending_sync_reg\[0\]|capture_active_sync_reg\[0\]|telemetry_request_sync_reg\[0\]|telemetry_ack_sync_reg\[0\]|telemetry_payload_sync_1_reg\[[0-9]+\]|i_candidate_scheduler/i_command_fifo/.*_sync_1_reg\[[0-9]+\]|i_capture_bridge/i_descriptor_fifo/.*_sync_1_reg\[[0-9]+\]|i_capture_bridge/sample_release_toggle_sync_1_reg\[[0-9]+\]).*}]

set_property ASYNC_REG TRUE $pss_tracker_sync_first
set_property SHREG_EXTRACT NO $pss_tracker_sync_first
set_false_path -quiet -to $pss_tracker_sync_first

# The distributed capture-descriptor RAM is intentionally sampled only after
# its Gray write pointer has crossed two engine clocks.  Cut only the RAM-write
# clock -> read-data D bundled-data arc.  The engine-clock read address and CE
# paths into the same destination registers remain normally timed.
set pss_tracker_descriptor_payload_memory [get_cells -quiet -hier -regexp \
  {.*i_capture_bridge/i_descriptor_fifo/payload_memory_reg.*}]
set pss_tracker_descriptor_read_data [get_cells -quiet -hier -regexp \
  {.*i_capture_bridge/i_descriptor_fifo/read_data_reg\[[0-9]+\].*}]
set pss_tracker_descriptor_read_data_d [get_pins -quiet \
  -of_objects $pss_tracker_descriptor_read_data \
  -filter {REF_PIN_NAME == D}]
set_false_path -quiet \
  -from $pss_tracker_descriptor_payload_memory \
  -to $pss_tracker_descriptor_read_data_d

# AXI-reset assertion into the reset synchronizers is asynchronous by
# construction; only their D-stage deassertion path is timed. Downstream state
# uses the synchronized reset outputs synchronously. The sample-reset level
# synchronizer is included because its first stage is separately false-pathed
# above as a conventional asynchronous data crossing.
set pss_tracker_reset_sync_all [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg|sample_reset_sync_reg|sample_reset_control_sync_reg)\[[01]\].*}]
set pss_tracker_reset_async_pins [get_pins -quiet \
  -of_objects $pss_tracker_reset_sync_all \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -quiet -to $pss_tracker_reset_async_pins

# Constrain skew even though setup/hold is intentionally cut at the first
# synchronizer stage.  One 100 MHz AXI period is tighter than one accepted
# 15 MS/s sample interval and preserves the one-bit-at-a-time Gray contract.
set pss_tracker_index_gray_source [get_cells -quiet -hier -regexp \
  {.*sample_index_gray_reg\[[0-9]+\].*}]
set_bus_skew 10.000 \
  -from $pss_tracker_index_gray_source \
  -to [get_cells -quiet -hier -regexp \
    {.*sample_index_gray_sync_1_reg\[[0-9]+\].*}]

# The telemetry payload is immutable from the sample-domain capture edge until
# acknowledgement and two additional AXI settling cycles.  Bound first-stage
# bus skew to one AXI period in addition to the ordinary synchronizer cut.
set pss_tracker_telemetry_source [get_cells -quiet -hier -regexp \
  {.*telemetry_sample_payload_reg\[[0-9]+\].*}]
set_bus_skew 10.000 \
  -from $pss_tracker_telemetry_source \
  -to [get_cells -quiet -hier -regexp \
    {.*telemetry_payload_sync_1_reg\[[0-9]+\].*}]
