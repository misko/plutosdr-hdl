create_clock -name acquisition_clk -period 10.000 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

set fifo_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set fifo_outputs [get_ports -filter {DIRECTION == OUT}]
set_input_delay -clock acquisition_clk -max 1.000 $fifo_inputs
set_input_delay -clock acquisition_clk -min 0.500 $fifo_inputs
set_output_delay -clock acquisition_clk -max 0.500 $fifo_outputs
set_output_delay -clock acquisition_clk -min 0.000 $fifo_outputs
