  integer partition_checks=0,partition_external_only=0;
  reg partition_pending,partition_run;
  reg partition_product_before,partition_output_before;
  reg partition_expected;
  always @(posedge fft_clk)begin
    partition_run=dut.fast_running;
    partition_pending=0;
    partition_product_before=dut.product_owner_request;
    partition_output_before=dut.output_request;
    if(partition_run)begin
      partition_checks=partition_checks+1;
      partition_expected=dut.replay_fifo.fault_q || dut.replay_fifo.abort_epoch!==0 ||
        (dut.replay_fifo.cancel_now!==0 && dut.replay_fifo.cancel_now!==1) ||
        (dut.replay_fifo.input_valid!==0 && dut.replay_fifo.input_valid!==1) ||
        (dut.replay_fifo.output_ready!==0 && dut.replay_fifo.output_ready!==1) ||
        dut.replay_occupancy>2;
      if(dut.replay_fifo_local_fault!==partition_expected)
        $fatal(1,"actual ring local fault partition mismatch");
      if(dut.forward_buffer_fault===1 && dut.replay_fifo_local_fault===0)begin
        partition_external_only=partition_external_only+1;
        partition_pending=1;
        if(dut.replay_fifo_fault!==1 || dut.replay_valid!==0 ||
           dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
          $fatal(1,"partition lost original current publication veto");
      end
    end
    #0.001;
    if(partition_pending && dut.fast_running)begin
      if(dut.forward_buffer_private_fault!==1 || dut.replay_fifo_local_fault!==1 ||
         dut.replay_fifo.fault_q!==1 || dut.replay_private_valid!==0 ||
         !dut.replay_fifo_empty || dut.registered_quarantine!==1 ||
         dut.product_owner_request!==partition_product_before || dut.output_request!==partition_output_before)
        $fatal(1,"partition cancellation lost registered cause or ownership fencing");
    end
  end
  task automatic report_replay_local_fault;
    $display("REPLAY_CANCELLATION_PARTITION_PASS checks=%0d external_only=%0d current_veto=1 registered_cause=1",partition_checks,partition_external_only);
  endtask
