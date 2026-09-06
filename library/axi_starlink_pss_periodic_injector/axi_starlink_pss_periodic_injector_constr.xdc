# CDC constraints for the 15 MS/s periodic PSS qualification source.

set pssi_sync_first [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg\[0\]|sample_reset_sync_reg\[0\]|sample_reset_control_sync_reg\[0\]|sample_index_gray_sync_1_reg\[[0-9]+\]|i_periodic_injection_mux/arm_ack_sync_reg\[0\]|i_periodic_injection_mux/completion_sync_reg\[0\]|i_periodic_injection_mux/mismatch_sync_reg\[0\]|i_periodic_injection_mux/sample_active_sync_reg\[0\]|i_periodic_injection_mux/arm_request_sync_reg\[0\]|i_periodic_injection_mux/arm_start_sync_1_reg\[[0-9]+\]).*}]

set_property ASYNC_REG TRUE $pssi_sync_first
set_property SHREG_EXTRACT NO $pssi_sync_first
set_false_path -quiet -to $pssi_sync_first

set pssi_reset_sync_all [get_cells -quiet -hier -regexp \
  {.*(control_reset_sync_reg|sample_reset_sync_reg|sample_reset_control_sync_reg)\[[01]\].*}]
set pssi_reset_async_pins [get_pins -quiet \
  -of_objects $pssi_reset_sync_all \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
set_false_path -quiet -to $pssi_reset_async_pins

# One AXI period bounds both coherent multi-bit crossings. The Gray source is
# sampled continuously; the arm payload remains immutable until acknowledged.
set pssi_index_gray_source [get_cells -quiet -hier -regexp \
  {.*sample_index_gray_reg\[[0-9]+\].*}]
set_bus_skew 10.000 \
  -from $pssi_index_gray_source \
  -to [get_cells -quiet -hier -regexp \
    {.*sample_index_gray_sync_1_reg\[[0-9]+\].*}]

set pssi_arm_payload_source [get_cells -quiet -hier -regexp \
  {.*i_periodic_injection_mux/arm_start_mailbox_reg\[[0-9]+\].*}]
set pssi_arm_payload_sync_1 [get_cells -quiet -hier -regexp \
  {.*i_periodic_injection_mux/arm_start_sync_1_reg\[[0-9]+\].*}]
set_bus_skew 10.000 \
  -from $pssi_arm_payload_source \
  -to $pssi_arm_payload_sync_1
