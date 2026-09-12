  integer capacity_checks=0,capacity_inputs=0,capacity_outputs=0,capacity_cancelled=0;
  integer capacity_count=0,capacity_full_cycles=0,capacity_refills=0;
  reg [120:0] capacity_head,capacity_tail,capacity_input_word;
  reg capacity_push,capacity_pop,capacity_abort,capacity_run;
  reg capacity_product_before,capacity_output_before;
  task automatic compare_replay_capacity;
    begin
      if(dut.replay_occupancy!==2'(capacity_count))$fatal(1,"replay capacity occupancy mismatch");
      if(dut.replay_valid && (capacity_count==0 || dut.replay_payload!==capacity_head))
        $fatal(1,"replay capacity changed accepted word/descriptor");
      if(dut.forward_buffer_read_ready!==(!dut.replay_fifo.fault_q && capacity_count<2))
        $fatal(1,"replay source capacity is not local");
      if(dut.forward_buffer_reserve && !dut.replay_fifo_empty)
        $fatal(1,"new forward reservation before buffered words retired");
      capacity_checks=capacity_checks+1;
    end
  endtask
  always @(posedge fft_clk)begin
    capacity_run=dut.fast_running;
    capacity_abort=dut.replay_fifo_fault===1 || dut.fast_fault===1;
    capacity_push=dut.forward_buffer_valid===1 && dut.forward_buffer_read_ready===1;
    capacity_pop=dut.joiner.input_valid===1 && dut.kernel_ready===1;
    capacity_input_word={dut.forward_buffer_descriptor,dut.forward_buffer_exponent,dut.forward_buffer_last,dut.forward_buffer_position,dut.forward_buffer_data};
    capacity_product_before=dut.product_owner_request;capacity_output_before=dut.output_request;
    if(!capacity_run)capacity_count=0;
    else begin
      compare_replay_capacity;
      if(dut.replay_occupancy==2)capacity_full_cycles=capacity_full_cycles+1;
      if(capacity_abort)begin
        if(dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
          $fatal(1,"buffer cancellation lacks current publication veto");
        capacity_cancelled=capacity_cancelled+capacity_count+(capacity_push?1:0);
        capacity_count=0;
      end else begin
        if(capacity_pop)begin
          if(capacity_count==0 || dut.replay_payload!==capacity_head)$fatal(1,"kernel consumed unstored word");
          capacity_head=capacity_tail;capacity_count=capacity_count-1;
          capacity_outputs=capacity_outputs+1;
        end
        if(capacity_push)begin
          if(capacity_count==0)capacity_head=capacity_input_word;
          else if(capacity_count==1)capacity_tail=capacity_input_word;
          else $fatal(1,"replay accepted without reserved storage");
          capacity_count=capacity_count+1;capacity_inputs=capacity_inputs+1;
        end
        if(capacity_push && capacity_pop)capacity_refills=capacity_refills+1;
      end
    end
    #0.001;
    if(capacity_run && dut.fast_running)begin
      compare_replay_capacity;
      if(capacity_abort && (dut.product_owner_request!==capacity_product_before || dut.output_request!==capacity_output_before ||
          dut.replay_private_valid!==0 || !dut.replay_fifo_empty))
        $fatal(1,"buffer cancellation retained words or published ownership");
    end
  end
  task automatic report_replay_capacity;
    begin
      if(capacity_checks<10000 || capacity_outputs<9216 || capacity_refills<9000)
        $fatal(1,"vacuous replay capacity comparison");
      $display("REPLAY_CAPACITY_PASS checks=%0d inputs=%0d outputs=%0d cancelled=%0d full_cycles=%0d refills=%0d word_exact=1 current_veto=1",
        capacity_checks,capacity_inputs,capacity_outputs,capacity_cancelled,capacity_full_cycles,capacity_refills);
    end
  endtask
