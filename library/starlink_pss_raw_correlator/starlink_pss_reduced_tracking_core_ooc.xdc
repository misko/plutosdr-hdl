# OOC contract for the complete Stage-15 TRACK_ONE composition.  The sample
# domain is constrained at the future exact-60 ceiling; control and engine run
# at 100 MHz.
create_clock -name reduced_control_clock -period 10.000 [get_ports i_control_clk]
create_clock -name reduced_sample_clock -period 16.667 [get_ports i_sample_clk]
create_clock -name reduced_engine_clock -period 10.000 [get_ports i_engine_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports i_control_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports i_sample_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y2 [get_ports i_engine_clk]

set_clock_groups -asynchronous \
  -group [get_clocks reduced_control_clock] \
  -group [get_clocks reduced_sample_clock] \
  -group [get_clocks reduced_engine_clock]

set_false_path -from [get_ports {
  i_control_resetn
  i_sample_resetn
  i_engine_resetn
}]

set_input_delay -clock reduced_control_clock -max 2.000 [get_ports {
  i_candidate_submit
  i_candidate_request_id[*]
  i_candidate_center_index[*]
  i_candidate_center_timestamp[*]
  i_result_word_index[*]
  i_result_word_read
  i_result_release
}]
set_input_delay -clock reduced_control_clock -min 0.000 [get_ports {
  i_candidate_submit
  i_candidate_request_id[*]
  i_candidate_center_index[*]
  i_candidate_center_timestamp[*]
  i_result_word_index[*]
  i_result_word_read
  i_result_release
}]

set_input_delay -clock reduced_sample_clock -max 2.000 [get_ports {
  i_sample_enable
  i_sample_valid
  i_sample_index[*]
  i_sample_timestamp[*]
  i_sample_i[*]
  i_sample_q[*]
}]
set_input_delay -clock reduced_sample_clock -min 0.000 [get_ports {
  i_sample_enable
  i_sample_valid
  i_sample_index[*]
  i_sample_timestamp[*]
  i_sample_i[*]
  i_sample_q[*]
}]

set_input_delay -clock reduced_engine_clock -max 2.000 [get_ports {
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_coefficient_commit
  i_coefficient_generation[*]
}]
set_input_delay -clock reduced_engine_clock -min 0.000 [get_ports {
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_coefficient_commit
  i_coefficient_generation[*]
}]

set_output_delay -clock reduced_control_clock -max 2.000 [get_ports {
  o_candidate_submit_ready
  o_candidate_submit_accepted
  o_candidate_queue_room[*]
  o_queue_overrun_count[*]
  o_result_available
  o_result_bank
  o_result_word_valid
  o_result_word_data[*]
  o_result_consumed_count[*]
}]
set_output_delay -clock reduced_control_clock -min 0.000 [get_ports {
  o_candidate_submit_ready
  o_candidate_submit_accepted
  o_candidate_queue_room[*]
  o_queue_overrun_count[*]
  o_result_available
  o_result_bank
  o_result_word_valid
  o_result_word_data[*]
  o_result_consumed_count[*]
}]

set_output_delay -clock reduced_sample_clock -max 2.000 [get_ports {
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
set_output_delay -clock reduced_sample_clock -min 0.000 [get_ports {
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

set_output_delay -clock reduced_engine_clock -max 2.000 [get_ports {
  o_coefficient_ready
  o_coefficient_commit_ready
  o_coefficient_commit_accepted
  o_coefficient_commit_rejected
  o_active_coefficient_valid
  o_active_coefficient_generation[*]
  o_active_coefficient_energy[*]
  o_shadow_coefficient_count[*]
  o_engine_consumed_count[*]
  o_correlator_bound_error_count[*]
  o_reducer_processed_job_count[*]
  o_reducer_emitted_result_count[*]
  o_reducer_invalid_tuple_count[*]
  o_reducer_bound_error_count[*]
  o_reducer_protocol_error_count[*]
  o_result_bank_free[*]
  o_result_published_count[*]
  o_result_overrun_count[*]
}]
set_output_delay -clock reduced_engine_clock -min 0.000 [get_ports {
  o_coefficient_ready
  o_coefficient_commit_ready
  o_coefficient_commit_accepted
  o_coefficient_commit_rejected
  o_active_coefficient_valid
  o_active_coefficient_generation[*]
  o_active_coefficient_energy[*]
  o_shadow_coefficient_count[*]
  o_engine_consumed_count[*]
  o_correlator_bound_error_count[*]
  o_reducer_processed_job_count[*]
  o_reducer_emitted_result_count[*]
  o_reducer_invalid_tuple_count[*]
  o_reducer_bound_error_count[*]
  o_reducer_protocol_error_count[*]
  o_result_bank_free[*]
  o_result_published_count[*]
  o_result_overrun_count[*]
}]
