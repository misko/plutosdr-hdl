// Test orchestration only: seven fixed contexts, one DUT and one FFT instance.
integer context_id=-1, context_done=0, words_log=0;
integer total_source=0,total_forward=0,total_product=0,total_inverse=0,total_read=0;
integer total_F=0,total_I=0;
task automatic prepare_context(input integer id,input integer stall,input integer side);
  begin
    @(negedge fft_clk); resetn=0;fft_resetn=0;input_valid=0;run_slow=1;
    repeat(8)@(negedge fft_clk);
    context_id=id;STALL=stall;RESET_SIDE=side;new_epoch=0;
    forward_jobs=0;inverse_jobs=0;read_count=0;source_count=0;
    forward_words=0;product_words=0;inverse_words=0;status_count=0;
    output_fixture_base=0;last_forward_admit=-1;max_forward_interval=0;
    max_retained_wait=0;max_inverse_publication_interval=0;
    ack_f_input=0;ack_f_output=0;ack_f_handoff=0;held_final_prefetch=0;parked_full_source=0;
    ack_zero_controls=0;overlap_inputs=0;overlap_reads=0;retained_finals=0;parked_wait_i=0;
    last_inverse_publish=-1;last_real_release=-1;first_dispatch=-1;
    selected_fixture=0;raw_words=0;raw_phase=0;inverse_publications=0;
    stalled=0;held_output=0;
    $display("RACT_BEGIN context=%0d stall=%0d reset=%0d cycle=%0d",id,stall,side,fast_cycles);
  end
endtask
task automatic finish_context;
  begin
    if(context_id!=context_done)$fatal(1,"actual context identity/order");
    if(actual_active||actual_inputs!=512||actual_raw!=512||actual_status!=1)
      $fatal(1,"actual current core not complete at context end");
    if(`D.retained_reusable!==1||`D.retained_published!==0||`D.state!==`D.WAIT_BANK||
       `D.next_inverse!==0||`D.any_fast_fault!==0||output_valid!==0)
      $fatal(1,"actual context terminal ownership");
    if(local_guard_observer.current_faults!=0||local_guard_observer.sticky_faults!=0||
       local_guard_observer.duplicate_checks!=0)$fatal(1,"unexpected healthy input observer fault");
    total_source=total_source+source_count;total_forward=total_forward+forward_words;
    total_product=total_product+product_words;total_inverse=total_inverse+inverse_words;
    total_read=total_read+read_count;total_F=total_F+forward_jobs;total_I=total_I+inverse_jobs;
    $display("RACT_CONTEXT context=%0d source=%0d F=%0d I=%0d forward=%0d product=%0d inverse=%0d read=%0d status=%0d dispatch=%0d service=%0d publication_interval=%0d retained_wait=%0d cycle=%0d",
      context_id,source_count,forward_jobs,inverse_jobs,forward_words,product_words,inverse_words,
      read_count,status_count,first_dispatch,max_forward_interval,max_inverse_publication_interval,max_retained_wait,fast_cycles);
    context_done=context_done+1;
  end
endtask
initial begin
  if(FAULT_KIND!==0||FAULT_OFFSET!==0||FAULT_BOUNDARY!==0||BLOCKS!==3)
    $fatal(1,"only seven fixed actual contexts admitted");
  words_log=$fopen("actual_words.csv","w");if(!words_log)$fatal(1,"actual numerical log open");
  $fdisplay(words_log,"context,stream,job,position,data,start,exponent,fast,slow,time_fs");
  prepare_context(0,0,0);run_context();finish_context();
  prepare_context(1,1,0);run_context();finish_context();
  prepare_context(2,2,0);run_context();finish_context();
  prepare_context(3,4,0);run_context();finish_context();
  prepare_context(4,5,0);run_context();finish_context();
  prepare_context(5,0,1);run_context();finish_context();
  prepare_context(6,0,2);run_context();finish_context();
  if(context_done!=7||total_source!=10752||total_F!=21||total_I!=19||
     total_forward!=9728||total_product!=9728||total_inverse!=9728||total_read!=8704||
     actual_jobs!=40||actual_commits!=38||actual_aborts!=2||actual_raw_total!=19456||
     actual_status_total!=38||local_guard_observer.forward_starts!=21||
     local_guard_observer.inverse_starts!=19||local_guard_observer.pre_checks<1024||
     local_guard_observer.post_checks!=local_guard_observer.pre_checks||
     local_guard_observer.reset_checks<7||local_guard_observer.closed_prefetch==0||
     payload_checks<1024||payload_join_occupied==0||payload_product_occupied==0||
     forward_checks<1024||forward_cycles==0)$fatal(1,"actual seven-context total/shadow inventory");
  $fclose(words_log);
  $display("RACT_SHADOW input_pre=%0d input_post=%0d input_resets=%0d Fstarts=%0d Istarts=%0d arithmetic=%0d retirement=%0d",
    local_guard_observer.pre_checks,local_guard_observer.post_checks,local_guard_observer.reset_checks,
    local_guard_observer.forward_starts,local_guard_observer.inverse_starts,payload_checks,forward_checks);
  $display("RACT_PASS contexts=7 source=10752 F=21 I=19 pairs=19 aborted_F=2 forward=9728 product=9728 inverse=9728 read=8704 raw=19456 status=38 physical_inputs=%0d discarded_old_unread=1024",actual_input_total);
  $finish;
end
