create_clock -name map_clk -period 10.000 [get_ports map_clk]
create_clock -name axi_clk -period 10.000 [get_ports s_axi_aclk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports map_clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y1 [get_ports s_axi_aclk]
set_clock_groups -asynchronous \
  -group [get_clocks map_clk] \
  -group [get_clocks axi_clk]

set map_inputs [get_ports [list \
  map_reset map_ready_mask* map_generation_0* map_generation_1* \
  map_start_index_0* map_start_index_1* map_read_valid map_read_data* \
  map_read_error accepted_score_count* discarded_score_count* \
  discontinuity_abort_count* map_publish_count* map_overrun_count* \
  score_protocol_error_count* map_arithmetic_overflow_count* \
  map_read_error_count* map_release_error_count* detector_health_flags* \
  ingress_overflow_sticky ingress_dropped_sample_count* \
  ingress_fifo_level* ingress_maximum_fifo_level* scheduler_gap_count* \
  scheduler_index_error_count* scheduler_overflow_count* \
  detector_fault_count* score_phase_index_discontinuity_count* \
  score_denominator_zero_count* candidate_fifo_stored_count* \
  candidate_fifo_maximum_stored_count*]]
set map_outputs [get_ports [list \
  map_read_request map_read_bank map_read_index* map_release \
  map_release_bank acquisition_enable acquisition_flush]]
set axi_inputs [get_ports [list \
  s_axi_awvalid s_axi_awaddr* s_axi_wvalid s_axi_wdata* s_axi_wstrb* \
  s_axi_bready s_axi_arvalid s_axi_araddr* s_axi_rready \
  s_axi_awprot* s_axi_arprot*]]
set axi_outputs [get_ports [list \
  irq s_axi_awready s_axi_wready s_axi_bvalid s_axi_bresp* \
  s_axi_arready s_axi_rvalid s_axi_rresp* s_axi_rdata*]]

# Model registered logic immediately outside the OOC boundary.  The 2--3 ns
# window includes source clock-to-Q and interconnect while leaving at least
# 7 ns of setup budget at 100 MHz.  Full-system implementation replaces this
# synthetic boundary contract with the actual neighboring registers.
set_input_delay -clock map_clk -max 3.000 $map_inputs
set_input_delay -clock map_clk -min 2.000 $map_inputs
set_output_delay -clock map_clk -max 0.500 $map_outputs
set_output_delay -clock map_clk -min 0.000 $map_outputs
set_input_delay -clock axi_clk -max 3.000 $axi_inputs
set_input_delay -clock axi_clk -min 2.000 $axi_inputs
set_output_delay -clock axi_clk -max 0.500 $axi_outputs
set_output_delay -clock axi_clk -min 0.000 $axi_outputs

set_false_path -from [get_ports s_axi_aresetn]
set_false_path \
  -from [get_ports map_reset] \
  -to [get_pins {map_reset_control_sync_reg[0]/D}]
set_false_path \
  -from [get_ports {map_ready_mask[*]}] \
  -to [get_pins {ready_mask_sync_1_reg[*]/D}]
