  // Original mailbox sees the full echoed bank fault, exactly as the parent.
  starlink_pss_completion_mailbox_stage #(.PRIVATE_FINAL_CAPTURE(1)) abort_echo_reference (
    .clk(fft_clk),
    .resetn(dut.fast_running),
    .abort_epoch(dut.fast_fault),
    .allocate_valid(dut.output_allocate_valid),
    .allocate_descriptor(dut.engine_metadata),
    .allocated_ready(1'b1),
    .complete_valid(dut.output_complete_valid),
    .complete_tag(dut.inverse_tag),
    .complete_final_data(dut.guard_return_data[1]),
    .replay_ready(dut.output_replay_private_ready),
    .bank_request(dut.output_request),
    .bank_ack_sync(dut.output_ack_sync),
    .bank_fault(dut.output_bank_fault),
    .lookup_valid(dut.inverse_descriptor_live),
    .lookup_tag(dut.inverse_tag),
    .allocate_ready(),
    .allocated_valid(),
    .allocated_tag(),
    .complete_ready(),
    .replay_valid(),
    .replay_tag(),
    .replay_data(),
    .publication_busy(),
    .published_valid(),
    .released_valid(),
    .released_tag(),
    .lookup_found(),
    .lookup_committed(),
    .lookup_descriptor(),
    .occupied(),
    .committed(),
    .tags_exhausted(),
    .fault()
  );
  integer echo_checks=0,echo_removed=0,echo_fault_edges=0,echo_completions=0;
  task automatic check_abort_echo;
    begin
      if(dut.fast_running===1)begin
        echo_checks=echo_checks+1;
        if(dut.output_control.allocate_ready!==abort_echo_reference.allocate_ready)
          $fatal(1,"abort echo changed original mailbox allocate_ready");
        if(dut.output_control.allocated_valid!==abort_echo_reference.allocated_valid)
          $fatal(1,"abort echo changed original mailbox allocated_valid");
        if(dut.output_control.allocated_tag!==abort_echo_reference.allocated_tag)
          $fatal(1,"abort echo changed original mailbox allocated_tag");
        if(dut.output_control.complete_ready!==abort_echo_reference.complete_ready)
          $fatal(1,"abort echo changed original mailbox complete_ready");
        if(dut.output_control.replay_valid!==abort_echo_reference.replay_valid)
          $fatal(1,"abort echo changed original mailbox replay_valid");
        if(dut.output_control.replay_tag!==abort_echo_reference.replay_tag)
          $fatal(1,"abort echo changed original mailbox replay_tag");
        if(dut.output_control.replay_data!==abort_echo_reference.replay_data)
          $fatal(1,"abort echo changed original mailbox replay_data");
        if(dut.output_control.publication_busy!==abort_echo_reference.publication_busy)
          $fatal(1,"abort echo changed original mailbox publication_busy");
        if(dut.output_control.published_valid!==abort_echo_reference.published_valid)
          $fatal(1,"abort echo changed original mailbox published_valid");
        if(dut.output_control.released_valid!==abort_echo_reference.released_valid)
          $fatal(1,"abort echo changed original mailbox released_valid");
        if(dut.output_control.released_tag!==abort_echo_reference.released_tag)
          $fatal(1,"abort echo changed original mailbox released_tag");
        if(dut.output_control.lookup_found!==abort_echo_reference.lookup_found)
          $fatal(1,"abort echo changed original mailbox lookup_found");
        if(dut.output_control.lookup_committed!==abort_echo_reference.lookup_committed)
          $fatal(1,"abort echo changed original mailbox lookup_committed");
        if(dut.output_control.lookup_descriptor!==abort_echo_reference.lookup_descriptor)
          $fatal(1,"abort echo changed original mailbox lookup_descriptor");
        if(dut.output_control.occupied!==abort_echo_reference.occupied)
          $fatal(1,"abort echo changed original mailbox occupied");
        if(dut.output_control.committed!==abort_echo_reference.committed)
          $fatal(1,"abort echo changed original mailbox committed");
        if(dut.output_control.tags_exhausted!==abort_echo_reference.tags_exhausted)
          $fatal(1,"abort echo changed original mailbox tags_exhausted");
        if(dut.output_control.fault!==abort_echo_reference.fault)
          $fatal(1,"abort echo changed original mailbox fault");
        if(dut.output_control.command_state!==abort_echo_reference.command_state)
          $fatal(1,"abort echo changed original mailbox command_state");
        if(dut.output_control.phase!==abort_echo_reference.phase)
          $fatal(1,"abort echo changed original mailbox phase");
        if(dut.output_control.command_opcode!==abort_echo_reference.command_opcode)
          $fatal(1,"abort echo changed original mailbox command_opcode");
        if(dut.output_control.command_tag!==abort_echo_reference.command_tag)
          $fatal(1,"abort echo changed original mailbox command_tag");
        if(dut.output_control.active_tag!==abort_echo_reference.active_tag)
          $fatal(1,"abort echo changed original mailbox active_tag");
        if(dut.output_control.command_descriptor!==abort_echo_reference.command_descriptor)
          $fatal(1,"abort echo changed original mailbox command_descriptor");
        if(dut.output_control.final_data!==abort_echo_reference.final_data)
          $fatal(1,"abort echo changed original mailbox final_data");
        if(dut.output_control.initial_request!==abort_echo_reference.initial_request)
          $fatal(1,"abort echo changed original mailbox initial_request");
        if(dut.output_control.fault_q!==abort_echo_reference.fault_q)
          $fatal(1,"abort echo changed original mailbox fault_q");
        if(dut.output_control.allocated_pending!==abort_echo_reference.allocated_pending)
          $fatal(1,"abort echo changed original mailbox allocated_pending");
        if(dut.output_control.released_pending!==abort_echo_reference.released_pending)
          $fatal(1,"abort echo changed original mailbox released_pending");
        if(dut.output_control.publication_seen!==abort_echo_reference.publication_seen)
          $fatal(1,"abort echo changed original mailbox publication_seen");
        if(dut.output_control.published_pending!==abort_echo_reference.published_pending)
          $fatal(1,"abort echo changed original mailbox published_pending");
        if(dut.output_control.complete_pending!==abort_echo_reference.complete_pending)
          $fatal(1,"abort echo changed original mailbox complete_pending");
        if(dut.output_control.scalar_fault!==abort_echo_reference.scalar_fault)
          $fatal(1,"abort echo changed original mailbox scalar_fault");
        if(dut.output_control.ledger.state0!==abort_echo_reference.ledger.state0)
          $fatal(1,"abort echo changed original mailbox ledger.state0");
        if(dut.output_control.ledger.state1!==abort_echo_reference.ledger.state1)
          $fatal(1,"abort echo changed original mailbox ledger.state1");
        if(dut.output_control.ledger.tag0!==abort_echo_reference.ledger.tag0)
          $fatal(1,"abort echo changed original mailbox ledger.tag0");
        if(dut.output_control.ledger.tag1!==abort_echo_reference.ledger.tag1)
          $fatal(1,"abort echo changed original mailbox ledger.tag1");
        if(dut.output_control.ledger.next_tag!==abort_echo_reference.ledger.next_tag)
          $fatal(1,"abort echo changed original mailbox ledger.next_tag");
        if(dut.output_control.ledger.descriptor0!==abort_echo_reference.ledger.descriptor0)
          $fatal(1,"abort echo changed original mailbox ledger.descriptor0");
        if(dut.output_control.ledger.descriptor1!==abort_echo_reference.ledger.descriptor1)
          $fatal(1,"abort echo changed original mailbox ledger.descriptor1");
        if(dut.output_control.ledger.exhausted!==abort_echo_reference.ledger.exhausted)
          $fatal(1,"abort echo changed original mailbox ledger.exhausted");
        if(dut.output_control.ledger.fault_q!==abort_echo_reference.ledger.fault_q)
          $fatal(1,"abort echo changed original mailbox ledger.fault_q");
        if(dut.output_control.ledger.response_pending!==abort_echo_reference.ledger.response_pending)
          $fatal(1,"abort echo changed original mailbox ledger.response_pending");
        if(dut.output_control.ledger.pending!==abort_echo_reference.ledger.pending)
          $fatal(1,"abort echo changed original mailbox ledger.pending");
        if(dut.output_control.ledger.pending_good!==abort_echo_reference.ledger.pending_good)
          $fatal(1,"abort echo changed original mailbox ledger.pending_good");
        if(dut.output_control.ledger.pending_slot!==abort_echo_reference.ledger.pending_slot)
          $fatal(1,"abort echo changed original mailbox ledger.pending_slot");
        if(dut.output_control.ledger.pending_opcode!==abort_echo_reference.ledger.pending_opcode)
          $fatal(1,"abort echo changed original mailbox ledger.pending_opcode");
        if(dut.output_control.ledger.pending_tag!==abort_echo_reference.ledger.pending_tag)
          $fatal(1,"abort echo changed original mailbox ledger.pending_tag");
        if(dut.output_control.ledger.pending_descriptor!==abort_echo_reference.ledger.pending_descriptor)
          $fatal(1,"abort echo changed original mailbox ledger.pending_descriptor");
        if(dut.output_bank_local_fault!==dut.output_bank_fault)begin
          if(dut.fast_fault===0)$fatal(1,"intrinsic bank fault omitted");
          echo_removed=echo_removed+1;
        end
        if(dut.fast_fault)echo_fault_edges=echo_fault_edges+1;
      end
    end
  endtask
  always @(posedge fft_clk)begin
    check_abort_echo;
    if(dut.fast_running && dut.output_complete_accept)echo_completions=echo_completions+1;
    #0.001;check_abort_echo;
  end
  task automatic report_abort_echo;
    begin
      if(echo_checks<10000 || echo_completions<18)$fatal(1,"vacuous abort echo proof");
      $display("ABORT_ECHO_PASS checks=%0d completions=%0d removed_echoes=%0d quarantine_checks=%0d original_mailbox_exact=1",echo_checks,echo_completions,echo_removed,echo_fault_edges);
    end
  endtask
