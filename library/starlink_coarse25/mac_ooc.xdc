create_clock -name calc_clk -period 10.000 [get_ports clk]
set_input_delay -clock calc_clk 1.000 [get_ports {reset sample_valid sample_i[*] sample_q[*] sample_index[*]}]
set_output_delay -clock calc_clk 1.000 [all_outputs]
