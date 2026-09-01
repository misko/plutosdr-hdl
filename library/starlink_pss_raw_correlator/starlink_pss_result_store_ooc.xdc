# OOC contract for the atomic result-publication store.  Engine and control
# clocks are unrelated 100 MHz domains in the eventual integration shell.
create_clock -name result_engine_clock -period 10.000 [get_ports i_engine_clk]
create_clock -name result_control_clock -period 10.000 [get_ports i_control_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports i_engine_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports i_control_clk]

set_clock_groups -asynchronous \
  -group [get_clocks result_engine_clock] \
  -group [get_clocks result_control_clock]

# These resets are asserted as one coordinated epoch and synchronized by the
# future shell before release; they are not timed data inputs at this boundary.
set_false_path -from [get_ports {i_engine_resetn i_control_resetn}]

set_input_delay -clock result_engine_clock -max 2.000 [get_ports i_result_*]
set_input_delay -clock result_engine_clock -min 0.000 [get_ports i_result_*]
set_output_delay -clock result_engine_clock -max 2.000 [get_ports o_result_*]
set_output_delay -clock result_engine_clock -min 0.000 [get_ports o_result_*]

set_input_delay -clock result_control_clock -max 2.000 [get_ports {
  i_control_word_index[*]
  i_control_word_read
  i_control_result_release
}]
set_input_delay -clock result_control_clock -min 0.000 [get_ports {
  i_control_word_index[*]
  i_control_word_read
  i_control_result_release
}]
set_output_delay -clock result_control_clock -max 2.000 [get_ports o_control_*]
set_output_delay -clock result_control_clock -min 0.000 [get_ports o_control_*]
