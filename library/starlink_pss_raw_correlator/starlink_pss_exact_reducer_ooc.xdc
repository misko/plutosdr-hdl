# 100 MHz engine-clock contract for the exact rational reducer milestone.
create_clock -name reducer_engine_clock -period 10.000 [get_ports i_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports i_clk]

set_input_delay -clock reducer_engine_clock -max 2.000 \
  [get_ports -filter {DIRECTION == IN && NAME != i_clk}]
set_input_delay -clock reducer_engine_clock -min 0.000 \
  [get_ports -filter {DIRECTION == IN && NAME != i_clk}]
set_output_delay -clock reducer_engine_clock -max 2.000 [all_outputs]
set_output_delay -clock reducer_engine_clock -min 0.000 [all_outputs]
