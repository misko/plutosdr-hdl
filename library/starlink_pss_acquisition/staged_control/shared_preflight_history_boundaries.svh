  reg [69:0] shared_injected_metadata;
  reg shared_injected_lease;
  integer shared_boundary_index;
  task automatic shared_preflight_boundary(input integer which);
    integer kind,n;
    reg [5:0] expected_history;
    reg product_before,output_before;
    begin
      aux_reset;aux_ready=0;
      kind=which<6?which:3;
      fork
        aux_send;
        begin
          while(!(dut.fast_running && dut.state==dut.VERIFY_LEASE &&
                  dut.preparation_valid===1 && dut.shared_preflight_history===0))@(negedge fft_clk);
          product_before=dut.product_owner_request;output_before=dut.output_request;
          shared_injected_metadata=dut.engine_metadata ^ 70'h1000;
          if(which==6)shared_injected_metadata[12]=1'bx;
          if(which==7)shared_injected_metadata[12]=1'bz;
          shared_injected_lease=!dut.held_lease;
          aux_fault_expected=1;
          case(kind)
            0:force dut.preflight_valid=1'b0;
            1:force dut.preflight_position=9'd1;
            2:force dut.preflight_lease=shared_injected_lease;
            3:force dut.engine_metadata=shared_injected_metadata;
            4:force dut.product_bank_ready=1'b0;
            5:force dut.preparation_age=6'd63;
          endcase
          #0.001;
          expected_history=dut.preflight_events_now;
          if(which==6 || which==7)begin
            if(expected_history[3]!==1'bx)$fatal(1,"unknown raw descriptor did not reach preflight comparison");
          end else if(expected_history[kind]!==1)$fatal(1,"raw preflight cause not exercised");
          if(dut.shared_preflight_history!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
            $fatal(1,"preflight history changed before edge or publication escaped");
          @(posedge fft_clk);#0.001;
          if(dut.shared_preflight_history!==expected_history ||
             dut.owners[0].result_guard.fault_reasons[0] !== (|expected_history) ||
             dut.owners[1].result_guard.fault_reasons[0] !== (|expected_history) ||
             dut.product_owner_request!==product_before || dut.output_request!==output_before ||
             dut.job_accept!==0 || dut.completion_accept!==0)
            $fatal(1,"shared preflight cause latency or same-edge quarantine mismatch");
          if(which>=8)begin
            if(which==8)resetn=0;else fft_resetn=0;
            #0.001;
            if(dut.fast_running!==0 || dut.shared_preflight_history!==0 ||
               dut.owners[0].result_guard.fault_reasons!==0 || dut.owners[1].result_guard.fault_reasons!==0)
              $fatal(1,"one-sided raw reset retained shared history");
          end
          @(negedge fft_clk);
          release dut.preflight_valid;release dut.preflight_position;release dut.preflight_lease;
          release dut.engine_metadata;release dut.product_bank_ready;release dut.preparation_age;
        end
      join
      if(which>=8)begin
        repeat(12)@(negedge fft_clk);resetn=1;fft_resetn=1;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept ||
           dut.product_owner_request!==product_before || dut.output_request!==output_before)
          $fatal(1,"preflight rejection/reset leaked work");
      end
      if(which<8 && fault!==1)$fatal(1,"preflight failure not reported within bounded interval");
      if(which>=8 && (fault!==0 || dut.shared_preflight_history!==0))$fatal(1,"reset resurrected shared history");
      aux_recover;
      $display("SHARED_PREFLIGHT_BOUNDARY_PASS case=%0d cause=%0d raw_reset=%0d fresh_reads=512 fresh_releases=1",which,kind,which>=8);
    end
  endtask
  task automatic run_shared_preflight_boundaries;
    begin
      for(shared_boundary_index=0;shared_boundary_index<10;shared_boundary_index=shared_boundary_index+1)
        shared_preflight_boundary(shared_boundary_index);
      $display("SHARED_PREFLIGHT_BOUNDARIES_PASS cases=10 causes=6 metadata_unknown=2 raw_resets=2 original_guards_exact=1");
    end
  endtask
