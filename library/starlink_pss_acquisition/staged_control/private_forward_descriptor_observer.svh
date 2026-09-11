  wire descriptor_old_reserve_ready,descriptor_old_capture_ready,descriptor_old_output_valid;
  wire descriptor_old_output_last,descriptor_old_done,descriptor_old_busy,descriptor_old_fault,descriptor_old_private_fault;
  wire [35:0] descriptor_old_data;
  wire [8:0] descriptor_old_position;
  wire [4:0] descriptor_old_exponent;
  wire [69:0] descriptor_old_metadata;
  starlink_pss_forward_return_private_status descriptor_reference (
    .clk(fft_clk),.resetn(dut.fast_running),.abort_epoch(dut.forward_buffer.abort_epoch),
    .reserve_valid(dut.forward_buffer.reserve_valid),
    .reserve_descriptor(dut.forward_buffer.reserve_descriptor),
    .capture_valid(dut.forward_buffer.capture_valid),
    .capture_data(dut.forward_buffer.capture_data),
    .capture_position(dut.forward_buffer.capture_position),
    .capture_last(dut.forward_buffer.capture_last),
    .capture_exponent(dut.forward_buffer.capture_exponent),
    .capture_descriptor(dut.forward_buffer.capture_descriptor),
    .seal_valid(dut.forward_buffer.seal_valid),
    .output_ready(dut.forward_buffer.output_ready),
    .reserve_ready(descriptor_old_reserve_ready),.capture_ready(descriptor_old_capture_ready),
    .output_valid(descriptor_old_output_valid),.output_data(descriptor_old_data),
    .output_position(descriptor_old_position),.output_last(descriptor_old_output_last),
    .output_exponent(descriptor_old_exponent),.output_descriptor(descriptor_old_metadata),
    .done_pulse(descriptor_old_done),.busy(descriptor_old_busy),.fault(descriptor_old_fault),
    .private_fault(descriptor_old_private_fault)
  );
  integer private_descriptor_checks=0,private_descriptor_loads=0,private_descriptor_fault_loads=0,private_descriptor_differences=0;
  task automatic compare_private_descriptor;
    begin
      if({dut.forward_buffer.reserve_ready,dut.forward_buffer.capture_ready,dut.forward_buffer.output_valid,
          dut.forward_buffer.done_pulse,dut.forward_buffer.busy,dut.forward_buffer.fault,dut.forward_buffer.private_fault} !==
         {descriptor_old_reserve_ready,descriptor_old_capture_ready,descriptor_old_output_valid,
          descriptor_old_done,descriptor_old_busy,descriptor_old_fault,descriptor_old_private_fault})
        $fatal(1,"private descriptor changed current controls");
      if(dut.forward_buffer.output_valid &&
         {dut.forward_buffer.output_data,dut.forward_buffer.output_position,dut.forward_buffer.output_last,
          dut.forward_buffer.output_exponent,dut.forward_buffer.output_descriptor} !==
         {descriptor_old_data,descriptor_old_position,descriptor_old_output_last,descriptor_old_exponent,descriptor_old_metadata})
        $fatal(1,"private descriptor changed valid replay");
      if({dut.forward_buffer.state,dut.forward_buffer.fault_q,dut.forward_buffer.replay_valid,dut.forward_buffer.write_count,
          dut.forward_buffer.read_count,dut.forward_buffer.exponent,dut.forward_buffer.output_position} !==
         {descriptor_reference.state,descriptor_reference.fault_q,descriptor_reference.replay_valid,descriptor_reference.write_count,
          descriptor_reference.read_count,descriptor_reference.exponent,descriptor_reference.output_position})
        $fatal(1,"private descriptor changed other bank state");
      if(dut.forward_buffer.descriptor !== descriptor_reference.descriptor)begin
        if(dut.forward_buffer.fault!==1 || descriptor_old_fault!==1 || dut.forward_buffer.output_valid!==0 ||
           dut.forward_buffer.reserve_ready!==0 || dut.forward_buffer.capture_ready!==0)
          $fatal(1,"private descriptor difference escaped quarantine");
        private_descriptor_differences=private_descriptor_differences+1;
      end
      private_descriptor_checks=private_descriptor_checks+1;
    end
  endtask
  always @(posedge fft_clk)begin
    if(dut.fast_running)begin
      compare_private_descriptor;
      if(dut.forward_buffer.reserve_valid && dut.forward_buffer.reserve_ready)begin
        private_descriptor_loads=private_descriptor_loads+1;
        if(dut.forward_buffer.fault_now===1)private_descriptor_fault_loads=private_descriptor_fault_loads+1;
      end
    end
    #0.001;
    if(dut.fast_running)compare_private_descriptor;
  end
  task automatic report_private_forward_descriptor;
    begin
      if(private_descriptor_checks<10000 || private_descriptor_loads<18)$fatal(1,"vacuous descriptor comparison");
      $display("PRIVATE_FORWARD_DESCRIPTOR_PASS checks=%0d loads=%0d fault_loads=%0d private_differences=%0d controls_exact=1 valid_payload_exact=1 quarantined_difference=1",
        private_descriptor_checks,private_descriptor_loads,private_descriptor_fault_loads,private_descriptor_differences);
    end
  endtask
