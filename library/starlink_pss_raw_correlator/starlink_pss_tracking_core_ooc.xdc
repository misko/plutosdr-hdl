# OOC contract for the composed queued-candidate tracking slice.  The sample
# clock is constrained at the eventual exact-60 ceiling even though Stage 15
# runs it at 15 MHz; control and engine clocks are 100 MHz.
create_clock -name tracking_control_clock -period 10.000 [get_ports i_control_clk]
create_clock -name tracking_sample_clock -period 16.667 [get_ports i_sample_clk]
create_clock -name tracking_engine_clock -period 10.000 [get_ports i_engine_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports i_control_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports i_sample_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y2 [get_ports i_engine_clk]

set_clock_groups -asynchronous \
  -group [get_clocks tracking_control_clock] \
  -group [get_clocks tracking_sample_clock] \
  -group [get_clocks tracking_engine_clock]

# The shared reset is asserted for one coordinated epoch and is synchronized
# by the future AXI integration shell before release.  It is not a timed data
# input to any one of the three domains at this isolated boundary.
set_false_path -from [get_ports {
  i_control_resetn
  i_sample_resetn
  i_engine_resetn
}]

set_input_delay -clock tracking_control_clock -max 2.000 [get_ports {
  i_candidate_submit
  i_candidate_request_id[*]
  i_candidate_center_index[*]
  i_candidate_center_timestamp[*]
}]
set_input_delay -clock tracking_control_clock -min 0.000 [get_ports {
  i_candidate_submit
  i_candidate_request_id[*]
  i_candidate_center_index[*]
  i_candidate_center_timestamp[*]
}]

set_input_delay -clock tracking_sample_clock -max 2.000 [get_ports {
  i_sample_enable
  i_sample_valid
  i_sample_index[*]
  i_sample_timestamp[*]
  i_sample_i[*]
  i_sample_q[*]
}]
set_input_delay -clock tracking_sample_clock -min 0.000 [get_ports {
  i_sample_enable
  i_sample_valid
  i_sample_index[*]
  i_sample_timestamp[*]
  i_sample_i[*]
  i_sample_q[*]
}]

set_input_delay -clock tracking_engine_clock -max 2.000 [get_ports {
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_coefficient_commit
  i_coefficient_generation[*]
  i_result_ready
}]
set_input_delay -clock tracking_engine_clock -min 0.000 [get_ports {
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_coefficient_commit
  i_coefficient_generation[*]
  i_result_ready
}]

set_output_delay -clock tracking_control_clock -max 2.000 [get_ports {
  o_candidate_submit_ready
  o_candidate_submit_accepted
  o_candidate_queue_room[*]
  o_queue_overrun_count[*]
}]
set_output_delay -clock tracking_control_clock -min 0.000 [get_ports {
  o_candidate_submit_ready
  o_candidate_submit_accepted
  o_candidate_queue_room[*]
  o_queue_overrun_count[*]
}]

set_output_delay -clock tracking_sample_clock -max 2.000 [get_ports {
  o_candidate_pending
  o_capture_active
  o_admitted_count[*]
  o_completed_capture_count[*]
  o_rejected_count[*]
  o_late_count[*]
  o_duplicate_count[*]
  o_overlap_count[*]
  o_aborted_count[*]
  o_valid_gap_abort_count[*]
  o_index_jump_abort_count[*]
  o_timestamp_abort_count[*]
  o_capture_bank_free[*]
  o_capture_published_count[*]
  o_capture_abort_discard_count[*]
  o_capture_buffer_overrun_count[*]
  o_capture_protocol_error_count[*]
}]
set_output_delay -clock tracking_sample_clock -min 0.000 [get_ports {
  o_candidate_pending
  o_capture_active
  o_admitted_count[*]
  o_completed_capture_count[*]
  o_rejected_count[*]
  o_late_count[*]
  o_duplicate_count[*]
  o_overlap_count[*]
  o_aborted_count[*]
  o_valid_gap_abort_count[*]
  o_index_jump_abort_count[*]
  o_timestamp_abort_count[*]
  o_capture_bank_free[*]
  o_capture_published_count[*]
  o_capture_abort_discard_count[*]
  o_capture_buffer_overrun_count[*]
  o_capture_protocol_error_count[*]
}]

set_output_delay -clock tracking_engine_clock -max 2.000 [get_ports {
  o_coefficient_ready
  o_coefficient_commit_ready
  o_coefficient_commit_accepted
  o_coefficient_commit_rejected
  o_active_coefficient_valid
  o_active_coefficient_generation[*]
  o_active_coefficient_energy[*]
  o_shadow_coefficient_count[*]
  o_configuration_idle
  o_result_valid
  o_result_request_id[*]
  o_result_center_index[*]
  o_result_center_timestamp[*]
  o_result_lag[*]
  o_result_timestamp[*]
  o_result_coefficient_generation[*]
  o_result_c_re[*]
  o_result_c_im[*]
  o_result_ex[*]
  o_result_eh[*]
  o_result_saturation_events[*]
  o_engine_consumed_count[*]
  o_bound_error_count[*]
}]
set_output_delay -clock tracking_engine_clock -min 0.000 [get_ports {
  o_coefficient_ready
  o_coefficient_commit_ready
  o_coefficient_commit_accepted
  o_coefficient_commit_rejected
  o_active_coefficient_valid
  o_active_coefficient_generation[*]
  o_active_coefficient_energy[*]
  o_shadow_coefficient_count[*]
  o_configuration_idle
  o_result_valid
  o_result_request_id[*]
  o_result_center_index[*]
  o_result_center_timestamp[*]
  o_result_lag[*]
  o_result_timestamp[*]
  o_result_coefficient_generation[*]
  o_result_c_re[*]
  o_result_c_im[*]
  o_result_ex[*]
  o_result_eh[*]
  o_result_saturation_events[*]
  o_engine_consumed_count[*]
  o_bound_error_count[*]
}]
