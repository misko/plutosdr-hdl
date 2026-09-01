# 100 MHz single-engine-clock contract for the isolated raw correlator.
create_clock -name raw_engine_clock -period 10.000 [get_ports i_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports i_clk]

# Reserve two nanoseconds on both sides of the future wrapper boundary.  The
# engine has no CDC in this milestone; every interface signal is synchronous to
# i_clk and a later AXI/CDC wrapper must preserve that separation.
set_input_delay -clock raw_engine_clock -max 2.000 [get_ports {
  i_reset
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_sample_clear
  i_sample_valid
  i_sample_i[*]
  i_sample_q[*]
  i_sample_timestamp[*]
  i_start
  i_result_ready
}]
set_input_delay -clock raw_engine_clock -min 0.000 [get_ports {
  i_reset
  i_coefficient_clear
  i_coefficient_valid
  i_coefficient_i[*]
  i_coefficient_q[*]
  i_sample_clear
  i_sample_valid
  i_sample_i[*]
  i_sample_q[*]
  i_sample_timestamp[*]
  i_start
  i_result_ready
}]
set_output_delay -clock raw_engine_clock -max 2.000 [all_outputs]
set_output_delay -clock raw_engine_clock -min 0.000 [all_outputs]
