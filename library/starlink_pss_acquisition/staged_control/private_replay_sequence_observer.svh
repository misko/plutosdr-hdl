  // Independent original private-sequence input, fed the same public stream.
  starlink_pss_kernel_rom #(.ROM_FILE("upper_edge_pss_kernel_q17.mem"),
    .DATA_WIDTH(18),.PRIVATE_PAYLOAD_BUBBLES(1),.PRIVATE_SEQUENCE_ADVANCE(1),
    .BALANCED_BLOCK_IDENTITY_EQ(1),.PARALLEL_INPUT_CAPACITY(1)) replay_kernel_reference (
    .clk(fft_clk),.resetn(dut.fast_running),.flush(1'b0),
    .input_valid(dut.joiner.input_valid),.input_private_valid(dut.joiner.input_valid),
    .input_ready(),.input_bin_index(dut.forward_buffer_position),
    .input_block_exponent(dut.forward_buffer_exponent),.input_last(dut.forward_buffer_last),
    .input_block_start_index(dut.forward_buffer_descriptor[68:5]),
    .output_ready(dut.joiner.output_ready),.downstream_capacity(dut.forward_parallel_capacity),
    .output_valid(),.output_kernel_i(),.output_kernel_q(),.output_bin_index(),
    .output_block_exponent(),.output_last(),.output_block_start_index(),
    .accepted_pulse(),.emitted_pulse(),.input_block_complete_pulse(),
    .sequence_error_pulse(),.metadata_error_pulse(),.protocol_fault()
  );
  integer private_replay_checks=0,private_replay_takes=0,private_replay_only=0;
  integer private_replay_final_only=0,private_replay_differences=0;
  reg replay_private_take,replay_public_take,replay_request_before,replay_output_before;
  reg replay_only_this_edge,replay_was_running;
  task automatic compare_private_replay_kernel;
    begin
      if({dut.joiner.kernel_rom.input_ready,dut.joiner.kernel_rom.output_valid,
          dut.joiner.kernel_rom.accepted_pulse,dut.joiner.kernel_rom.emitted_pulse,
          dut.joiner.kernel_rom.input_block_complete_pulse,dut.joiner.kernel_rom.sequence_error_pulse,
          dut.joiner.kernel_rom.metadata_error_pulse,dut.joiner.kernel_rom.protocol_fault} !==
         {replay_kernel_reference.input_ready,replay_kernel_reference.output_valid,
          replay_kernel_reference.accepted_pulse,replay_kernel_reference.emitted_pulse,
          replay_kernel_reference.input_block_complete_pulse,replay_kernel_reference.sequence_error_pulse,
          replay_kernel_reference.metadata_error_pulse,replay_kernel_reference.protocol_fault})
        $fatal(1,"private replay changed kernel public controls");
      if(dut.joiner.kernel_rom.output_valid &&
         {dut.joiner.kernel_rom.output_kernel_word,dut.joiner.kernel_rom.output_bin_index,
          dut.joiner.kernel_rom.output_block_exponent,dut.joiner.kernel_rom.output_last,dut.joiner.kernel_rom.output_block_start_index} !==
         {replay_kernel_reference.output_kernel_word,replay_kernel_reference.output_bin_index,
          replay_kernel_reference.output_block_exponent,replay_kernel_reference.output_last,replay_kernel_reference.output_block_start_index})
        $fatal(1,"private replay changed valid kernel payload");
      if({dut.joiner.kernel_rom.expected_bin_index,dut.joiner.kernel_rom.expected_next_block_start,dut.joiner.kernel_rom.have_previous_block} !==
         {replay_kernel_reference.expected_bin_index,replay_kernel_reference.expected_next_block_start,replay_kernel_reference.have_previous_block})begin
        if(dut.forward_buffer_fault!==1 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0 ||
           dut.job_accept || dut.completion_accept)
          $fatal(1,"private replay state difference escaped quarantine");
        private_replay_differences=private_replay_differences+1;
      end
      private_replay_checks=private_replay_checks+1;
    end
  endtask
  always @(posedge fft_clk)begin
    replay_was_running=dut.fast_running;
    replay_private_take=dut.joiner.kernel_rom.private_sequence_accept===1'b1;
    replay_public_take=dut.joiner.kernel_rom.input_accept===1'b1;
    replay_only_this_edge=replay_private_take && !replay_public_take;
    replay_request_before=dut.product_bank.owner_request;
    replay_output_before=dut.output_request;
    if(replay_was_running)begin
      compare_private_replay_kernel;
      if(replay_public_take && !replay_private_take)$fatal(1,"public replay lacks private bookkeeping");
      if(replay_private_take)private_replay_takes=private_replay_takes+1;
      if(replay_only_this_edge)begin
        if(dut.forward_buffer_fault!==1 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0 ||
           dut.forward_buffer.state!==3 || dut.forward_buffer.replay_valid!==1)
          $fatal(1,"private replay offer lacks sealed ownership/current rejection");
        private_replay_only=private_replay_only+1;
        if(dut.forward_buffer_last)private_replay_final_only=private_replay_final_only+1;
      end
    end
    #0.001;
    if(replay_was_running && dut.fast_running)begin
      compare_private_replay_kernel;
      if(replay_only_this_edge &&
         (dut.forward_buffer_private_fault!==1 || dut.forward_buffer_private_replay_valid!==0 ||
          dut.product_bank.owner_request!==replay_request_before || dut.output_request!==replay_output_before ||
          dut.registered_quarantine!==1))
        $fatal(1,"private replay divergence survived edge or changed ownership");
    end
  end
  task automatic report_private_replay_sequence;
    begin
      if(private_replay_checks<10000 || private_replay_takes<9216)$fatal(1,"vacuous private replay observer");
      $display("PRIVATE_REPLAY_SEQUENCE_PASS checks=%0d takes=%0d private_only=%0d final_only=%0d quarantined_differences=%0d public_exact=1 receipt_fenced=1",
        private_replay_checks,private_replay_takes,private_replay_only,private_replay_final_only,private_replay_differences);
    end
  endtask
