create_clock -name pss_sample_source_clock -period 16.270 \
  [get_ports source_clk]
create_clock -name pss_acquisition_clock -period 10.000 \
  [get_ports acquisition_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports source_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports acquisition_clk]

set_clock_groups -asynchronous \
  -group [get_clocks pss_sample_source_clock] \
  -group [get_clocks pss_acquisition_clock]

set source_inputs [get_ports [list \
  source_sample_valid source_sample_gap source_sample_i* source_sample_q* \
  source_sample_index*]]
set source_outputs [get_ports source_fifo_full]
set acquisition_outputs [get_ports [list \
  acquisition_sample_valid acquisition_sample_gap acquisition_sample_i* \
  acquisition_sample_q* acquisition_sample_index* dropped_sample_count* \
  overflow_sticky fifo_level* maximum_fifo_level*]]

set_input_delay -clock pss_sample_source_clock -max 3.000 $source_inputs
set_input_delay -clock pss_sample_source_clock -min 2.000 $source_inputs
set_output_delay -clock pss_sample_source_clock -max 1.000 $source_outputs
set_output_delay -clock pss_sample_source_clock -min 0.000 $source_outputs
set_output_delay -clock pss_acquisition_clock -max 1.000 $acquisition_outputs
set_output_delay -clock pss_acquisition_clock -min 0.000 $acquisition_outputs

set_false_path -from [get_ports {source_resetn acquisition_resetn}]
