# Identical logical budgets to the reviewed175MHz rounding study, not board IO.
create_clock -name product_clk -period 5.714 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
set product_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set product_outputs [get_ports -filter {DIRECTION == OUT}]
set_input_delay -clock product_clk -max 1.000 $product_inputs
set_input_delay -clock product_clk -min 0.500 $product_inputs
set_output_delay -clock product_clk -max 0.500 $product_outputs
set_output_delay -clock product_clk -min 0.000 $product_outputs
