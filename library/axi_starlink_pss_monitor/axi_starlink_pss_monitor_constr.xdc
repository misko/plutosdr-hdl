# CDC constraints for the Starlink candidate event mailbox.
#
# The request and acknowledgement toggles use conventional two-flop
# synchronizers.  The wide payload is a bundled-data path: its source registers
# are held unchanged until an acknowledgement has completed the round trip.
# A 10 ns datapath bound ensures every payload bit settles within one 100 MHz
# Pluto sys_cpu_clk period, still leaving an additional synchronizer cycle
# before the destination snapshot is captured.

set starlink_pss_sync_cells [get_cells -quiet -hier -filter {
  NAME =~ *i_event_cdc/request_sync_1_reg ||
  NAME =~ *i_event_cdc/request_sync_2_reg ||
  NAME =~ *i_event_cdc/acknowledge_sync_1_reg ||
  NAME =~ *i_event_cdc/acknowledge_sync_2_reg
}]
set_property ASYNC_REG TRUE $starlink_pss_sync_cells
set_property SHREG_EXTRACT NO $starlink_pss_sync_cells

set_false_path -quiet -to [get_cells -quiet -hier -filter {
  NAME =~ *i_event_cdc/request_sync_1_reg ||
  NAME =~ *i_event_cdc/acknowledge_sync_1_reg
}]

set starlink_pss_mailbox_cells [get_cells -quiet -hier -filter {
  IS_SEQUENTIAL && (
    NAME =~ *i_event_cdc/mailbox_event_count_reg* ||
    NAME =~ *i_event_cdc/mailbox_sample_index_reg* ||
    NAME =~ *i_event_cdc/mailbox_metric_num_reg* ||
    NAME =~ *i_event_cdc/mailbox_metric_den_reg*
  )
}]
set starlink_pss_snapshot_cells [get_cells -quiet -hier -filter {
  IS_SEQUENTIAL && (
    NAME =~ *i_event_cdc/snapshot_event_count_reg* ||
    NAME =~ *i_event_cdc/snapshot_sample_index_reg* ||
    NAME =~ *i_event_cdc/snapshot_metric_num_reg* ||
    NAME =~ *i_event_cdc/snapshot_metric_den_reg*
  )
}]

set_max_delay -datapath_only 10.000 \
  -from $starlink_pss_mailbox_cells \
  -to $starlink_pss_snapshot_cells
set_bus_skew 10.000 \
  -from $starlink_pss_mailbox_cells \
  -to $starlink_pss_snapshot_cells
