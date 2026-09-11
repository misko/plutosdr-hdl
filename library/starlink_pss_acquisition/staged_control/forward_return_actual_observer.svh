  // BEGIN FORWARD RETURN ACTUAL OBSERVER
  // No connection drives dut. Capture the real generated FFT's forward return,
  // seal from the original qualified guard commit, replay to a private oracle.
  wire fr_reserve = dut.owners[0].result_guard.job_valid && dut.owners[0].result_guard.job_ready;
  wire fr_capture = dut.owners[0].result_guard.core_output_tvalid;
  wire fr_seal = dut.guard_commit[0];
  wire fr_abort = dut.any_fast_fault || dut.fast_fault;
  wire fr_reserve_ready,fr_capture_ready,fr_valid,fr_last,fr_done,fr_busy,fr_fault;
  wire [35:0] fr_data;
  wire [8:0] fr_position;
  wire [4:0] fr_exponent;
  wire [69:0] fr_descriptor;
  integer fr_cycle=0,fr_written=0,fr_read=0,fr_blocks=0,fr_words=0,fr_reservations=0,fr_seals=0,fr_stalls=0;
  reg fr_qualified=0;
  reg [35:0] fr_expected[0:511];
  reg [69:0] fr_expected_descriptor;
  reg [4:0] fr_expected_exponent;
  wire fr_ready = (fr_cycle%7)>1;
  starlink_pss_forward_return_bank forward_return_observer (
    .clk(fft_clk),.resetn(dut.fast_running),.abort_epoch(fr_abort),
    .reserve_valid(fr_reserve),.reserve_ready(fr_reserve_ready),
    .reserve_descriptor(dut.owners[0].result_guard.job_descriptor),
    .capture_valid(fr_capture),.capture_ready(fr_capture_ready),
    .capture_data({dut.core_output_data[41:24],dut.core_output_data[17:0]}),
    .capture_position(dut.core_output_user[8:0]),.capture_last(dut.core_output_last),
    .capture_exponent(dut.core_output_user[20:16]),
    .capture_descriptor(dut.owners[0].result_guard.descriptor),.seal_valid(fr_seal),
    .output_valid(fr_valid),.output_ready(fr_ready),.output_data(fr_data),
    .output_position(fr_position),.output_last(fr_last),.output_exponent(fr_exponent),
    .output_descriptor(fr_descriptor),.done_pulse(fr_done),.busy(fr_busy),.fault(fr_fault)
  );
  // Change the private sink's READY only on the opposite clock edge.
  always @(negedge fft_clk)fr_cycle=fr_cycle+1;
  always @(posedge fft_clk)begin
    if(!dut.fast_running)begin fr_written=0;fr_read=0;fr_qualified=0;end
    else if(!fr_abort)begin
      if(fr_fault)$fatal(1,"forward bank observer fault without reference quarantine");
      if(fr_reserve)begin
        if(!fr_reserve_ready)$fatal(1,"forward bank observer capacity budget exceeded");
        fr_written=0;fr_read=0;fr_qualified=0;fr_reservations=fr_reservations+1;
        fr_expected_descriptor=dut.owners[0].result_guard.job_descriptor;
      end
      if(fr_capture)begin
        if(!fr_capture_ready || fr_written>=512)$fatal(1,"forward bank observer lost raw word");
        fr_expected[fr_written]={dut.core_output_data[41:24],dut.core_output_data[17:0]};
        fr_expected_exponent=dut.core_output_user[20:16];fr_written=fr_written+1;
      end
      if(fr_seal)begin
        if(fr_written!=512)$fatal(1,"forward bank observer sealed incomplete capture");
        fr_qualified=1;fr_seals=fr_seals+1;
      end
      if(fr_valid)begin
        if(!fr_qualified || fr_read>=512 || fr_data!==fr_expected[fr_read] ||
           fr_position!==9'(fr_read) || fr_last!==(fr_read==511) ||
           fr_exponent!==fr_expected_exponent || fr_descriptor!==fr_expected_descriptor)
          $fatal(1,"forward bank observer replay differs from actual FFT");
        if(fr_ready)begin fr_read=fr_read+1;fr_words=fr_words+1;end
        else fr_stalls=fr_stalls+1;
      end
      if(fr_done)begin
        if(fr_read!=512)$fatal(1,"forward bank observer incomplete drain");
        fr_blocks=fr_blocks+1;
      end
    end
  end
  task automatic report_forward_return_observer;
    begin
      if(fr_blocks<18 || fr_words<9216 || fr_reservations<18 || fr_seals<18 || fr_stalls<100)
        $fatal(1,"forward bank actual coverage incomplete");
      $display("FORWARD_RETURN_ACTUAL_PASS blocks=%0d words=%0d reservations=%0d seals=%0d stalls=%0d runtime_unchanged=1 observer_only=1",fr_blocks,fr_words,fr_reservations,fr_seals,fr_stalls);
    end
  endtask
  // END FORWARD RETURN ACTUAL OBSERVER
