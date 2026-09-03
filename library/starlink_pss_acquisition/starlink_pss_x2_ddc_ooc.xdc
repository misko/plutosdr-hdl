# Acquisition-clock contract.  The DDC receives FIFO-drained samples and runs
# in the existing 100 MHz acquisition/AXI domain.
create_clock -name acquisition_clock -period 10.000 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

set data_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock acquisition_clock -max 2.000 $data_inputs
set_input_delay -clock acquisition_clock -min 0.000 $data_inputs
set_output_delay -clock acquisition_clock -max 2.000 [all_outputs]
set_output_delay -clock acquisition_clock -min 0.000 [all_outputs]
