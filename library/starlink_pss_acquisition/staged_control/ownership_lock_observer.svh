  // Original completion-driven register is the independent lifetime oracle.
  reg ownership_old_lock=0;
  integer ownership_checks=0,ownership_accepts=0,ownership_releases=0;
  integer ownership_bridge=0,ownership_fault_holds=0;
  task automatic check_ownership_lock;
    begin
      if(dut.fast_running===1)begin
        ownership_checks=ownership_checks+1;
        if(dut.output_descriptor_locked!==ownership_old_lock)
          $fatal(1,"ownership lock differs from original completion-driven register");
        if(!dut.output_publication_busy && dut.retained_published)
          ownership_bridge=ownership_bridge+1;
        if(ownership_old_lock && dut.fast_fault)ownership_fault_holds=ownership_fault_holds+1;
      end
    end
  endtask
  always @(posedge fft_clk)begin
    check_ownership_lock;
    if(!dut.fast_running)ownership_old_lock<=0;
    else begin
      if(dut.output_complete_accept)begin
        ownership_old_lock<=1;ownership_accepts=ownership_accepts+1;
      end
      if(dut.output_released_valid)begin
        ownership_old_lock<=0;ownership_releases=ownership_releases+1;
      end
    end
    #0.001;check_ownership_lock;
  end
  task automatic report_ownership_lock;
    begin
      if(ownership_checks<10000 || ownership_accepts<18 ||
         ownership_releases<18 || ownership_bridge<18)
        $fatal(1,"vacuous ownership lock proof");
      $display("OWNERSHIP_LOCK_PASS checks=%0d accepts=%0d releases=%0d bridge=%0d fault_holds=%0d original_lock_exact=1",ownership_checks,ownership_accepts,ownership_releases,ownership_bridge,ownership_fault_holds);
    end
  endtask
