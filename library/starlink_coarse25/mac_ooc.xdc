create_clock -name calc_clk -period 10.000 [get_ports clk]
set_input_delay -clock calc_clk 1.000 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock calc_clk 1.000 [all_outputs]
