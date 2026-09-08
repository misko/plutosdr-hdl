# Fixed 100/200 MHz complete-block mailbox timing contract.
# XDC's synthesis parser accepts declarative constraints, not Tcl control flow.
# The paired-only build policy and post-synthesis audit verify actual endpoint
# clocks. Default profiles have no matching endpoints (quiet no-op).
# Do NOT use asynchronous clock groups or waive metadata/data paths.

set_max_delay -quiet -datapath_only 5.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/request_toggle_reg$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/request_sync_reg\[0\]$}]
set_max_delay -quiet -datapath_only 10.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/acknowledge_toggle_reg$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/acknowledge_sync_reg\[0\]$}]
set_max_delay -quiet -datapath_only 10.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/request_toggle_reg$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/request_sync_reg\[0\]$}]
set_max_delay -quiet -datapath_only 5.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/acknowledge_toggle_reg$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/acknowledge_sync_reg\[0\]$}]

# Producer holds metadata from first beat until ACK. Consumer captures only
# after the final beat's synchronized commit. Two destination cycles bound
# the bundled bus, while all second synchronizer stages remain normally timed.
set_max_delay -quiet -datapath_only 10.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/metadata_in_hold_reg\[[0-9]+\]$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/input_mailbox/metadata_out_hold_reg\[[0-9]+\]$}]
set_max_delay -quiet -datapath_only 20.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/metadata_in_hold_reg\[[0-9]+\]$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/output_mailbox/metadata_out_hold_reg\[[0-9]+\]$}]
set_max_delay -quiet -datapath_only 10.000 \
  -from [get_cells -quiet -hier -regexp {.*transform_service/fast_fault_reg$}] \
  -to [get_cells -quiet -hier -regexp {.*transform_service/fast_fault_sync_reg\[0\]$}]

# Only asynchronous assertion pins of named reset-release synchronizers.
set pss_shared_reset_cells [get_cells -quiet -hier -regexp \
  {.*(fft_reset_release_sync|slow_reset_fast_sync|fast_reset_fast_sync|slow_reset_slow_sync|fast_reset_slow_sync|in_reset_in_sync|out_reset_in_sync|in_reset_out_sync|out_reset_out_sync)_reg\[[01]\]$}]
set_false_path -quiet -to [get_pins -quiet -of_objects $pss_shared_reset_cells \
  -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
