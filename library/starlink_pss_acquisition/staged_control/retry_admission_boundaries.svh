  integer retry_boundary_index;
  reg [69:0] retry_bad_descriptor;
  task automatic retry_admission_boundary(input integer which);
    integer wanted_inverse,n;
    begin
      wanted_inverse=which<4 ? which/2 : (which<8 ? which%2 : 0);
      aux_reset;aux_ready=1;
      fork
        aux_send;
        begin
          while(!(dut.fast_running && dut.next_inverse==wanted_inverse &&
                  dut.state==dut.VERIFY_LEASE && dut.preparation_valid===1))
            @(negedge fft_clk);
          if(which==1 || which==3)force dut.cutover_admission_capacity=1'b0;
          else force dut.guard_capacity=2'b00;
          repeat(10)begin
            @(negedge fft_clk);
            if(dut.job_accept!==0 || dut.config_valid!==0 || dut.engine_input_enable!==0)
              $fatal(1,"unready held request started a core job");
          end
          if(dut.state!==dut.ARM_JOB || dut.admission_request!==1 ||
             dut.admission_gate.snapshot_valid!==1 || dut.admission_gate.sampled_good!==0)
            $fatal(1,"retrying rejected snapshot was not exercised");
          if(which<4)begin
            release dut.guard_capacity;release dut.cutover_admission_capacity;
            n=0;
            while(dut.job_accept!==1 && n<6)begin @(negedge fft_clk);n=n+1;end
            if(dut.job_accept!==1 || fault!==0)$fatal(1,"capacity recovery did not grant bounded admission");
          end else if(which<8)begin
            if(which<6)resetn=0;else fft_resetn=0;
            #0.001;
            if(dut.admission_permit!==0 || dut.job_accept!==0 || output_valid!==0)
              $fatal(1,"one-sided reset did not cancel pending grant");
            repeat(12)@(negedge fft_clk);
            release dut.guard_capacity;release dut.cutover_admission_capacity;
            resetn=1;fft_resetn=1;
          end else begin
            aux_fault_expected=1;
            if(which==9)begin
              retry_bad_descriptor=dut.engine_metadata ^ 70'h1000;
              force dut.engine_metadata=retry_bad_descriptor;
            end
            n=0;
            while(fault!==1 && n<100)begin
              @(negedge fft_clk);n=n+1;
              if(dut.job_accept!==0 || dut.config_valid!==0 || dut.engine_input_enable!==0 || output_valid)
                $fatal(1,"expired or substituted pending job escaped");
            end
            if(fault!==1)$fatal(1,"pending request not quarantined within timeout bound");
            release dut.engine_metadata;release dut.guard_capacity;release dut.cutover_admission_capacity;
          end
        end
      join
      if(which<4)aux_finish;
      else begin
        repeat(50)begin
          @(negedge fft_clk);
          if(output_valid || aux_reads || aux_releases || dut.job_accept || dut.config_valid || dut.engine_input_enable)
            $fatal(1,"cancelled admission produced stale work");
        end
        aux_recover;
      end
      $display("RETRY_ADMISSION_BOUNDARY_PASS case=%0d inverse=%0d fresh_reads=512 fresh_releases=1",which,wanted_inverse);
    end
  endtask
  task automatic run_retry_admission_boundaries;
    begin
      for(retry_boundary_index=0;retry_boundary_index<10;retry_boundary_index=retry_boundary_index+1)
        retry_admission_boundary(retry_boundary_index);
      $display("RETRY_ADMISSION_BOUNDARIES_PASS cases=10 capacity_stalls=4 one_sided_resets=4 timeout=1 descriptor_fault=1");
    end
  endtask
