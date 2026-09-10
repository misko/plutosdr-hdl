// Paired canonical bank/publication-only bank. No vendor or top model.
`timescale 1ns/1ps
module tb_starlink_pss_publication_bank #(parameter integer OPTION=1);
  reg clk=0,resetn=0,peer_resetn=0;
  always #5 clk=~clk;
  reg input_valid=0,input_offer_new=0,input_last=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [74:0] input_metadata=75'h123456789abcd;
  reg rearm_valid=0,certificate_valid=0,certificate_offer_new=0,lease_release_valid=0;
  reg [7:0] live_faults=0,publication_faults=0;
  reg [1:0] input_lease=0,certificate_lease=0,lease_release_tag=0;
  wire [1:0] ready,out_valid,out_last,cert_ready,release_ready,active,rearm_ready;
  wire [1:0] private_take,checked_seal,publish,lease_release,sealed,published,bank_fault,framing,fault_token;
  wire [35:0] data[0:1];
  wire [8:0] position[0:1],fault_position[0:1];
  wire [74:0] metadata[0:1];
  wire [1:0] lease[0:1],fault_lease[0:1];
  wire [15:0] reasons[0:1];
`define BANK_PORTS(I) \
    .clk(clk),.input_resetn(resetn),.output_resetn(peer_resetn), \
    .input_valid(input_valid),.input_offer_new(input_offer_new),.input_ready(ready[I]), \
    .input_data(input_data),.input_position(input_position),.input_last(input_last), \
    .input_metadata(input_metadata),.input_commit_authorized(1'b0), \
    .input_fault(bank_fault[I]),.input_framing_fault_now(framing[I]), \
    .output_valid(out_valid[I]),.output_ready(output_ready),.output_data(data[I]), \
    .output_position(position[I]),.output_last(out_last[I]),.output_metadata(metadata[I]), \
    .rearm_valid(rearm_valid),.engine_reset_held(1'b1),.producer_epoch_idle(1'b1), \
    .certificate_epoch_idle(1'b1),.consumer_epoch_idle(1'b1),.rearm_ready(rearm_ready[I]),.epoch_active(active[I]), \
    .input_lease(input_lease),.current_lease(lease[I]),.certificate_valid(certificate_valid), \
    .certificate_offer_new(certificate_offer_new),.certificate_ready(cert_ready[I]), \
    .certificate_lease(certificate_lease),.certificate_metadata(input_metadata),.certificate_good(1'b1), \
    .lease_release_valid(lease_release_valid),.lease_release_ready(release_ready[I]),.lease_release_tag(lease_release_tag), \
    .live_faults(live_faults),.fault_reasons(reasons[I]),.fault_token_valid(fault_token[I]), \
    .fault_token_position(fault_position[I]),.fault_token_lease(fault_lease[I]), \
    .private_take(private_take[I]),.checked_seal(checked_seal[I]),.publish(publish[I]), \
    .lease_release(lease_release[I]),.sealed(sealed[I]),.published(published[I])
  starlink_pss_epoch_sealed_bank #(.SEALED_PUBLICATION(1)) reference_bank (`BANK_PORTS(0));
  starlink_pss_epoch_sealed_publication_bank #(.SEALED_PUBLICATION(1),.PUBLICATION_ONLY_FAULTS(OPTION)) dut (
    `BANK_PORTS(1),.publication_faults(publication_faults));
`undef BANK_PORTS
  integer kind=0,bit_index=0,target=0,cycles=0,checks=0,reads=0,reset_side=-1;
  reg compare_enabled=0;
  reg saved_toggle=0;
  // Every original register except RAM is visible here, including invalid data.
`define BANK_STATE(B) {B.staged.reset_release,B.staged.armed,B.staged.lease, \
    B.staged.full,B.staged.seal_q,B.staged.published_q,B.staged.certificate_seen, \
    B.staged.reasons,B.staged.metadata_in_hold,B.staged.metadata_out_hold, \
    B.staged.write_position,B.staged.request_toggle,B.staged.acknowledge_toggle, \
    B.staged.request_sync,B.staged.acknowledge_sync,B.staged.reading, \
    B.staged.read_all_loaded,B.staged.read_valid,B.staged.read_address, \
    B.staged.read_output_position,B.staged.read_payload,B.staged.equal_leaves, \
    B.staged.equal_groups,B.staged.check_valid,B.staged.check_last,B.staged.check_bad, \
    B.staged.check_lease0,B.staged.check_lease1,B.staged.check_position0,B.staged.check_position1, \
    B.staged.fault_token_q,B.staged.fault_position_q,B.staged.fault_lease_q}
`define BANK_OUTPUTS(I) {ready[I],out_valid[I],out_last[I],cert_ready[I],release_ready[I],active[I],rearm_ready[I], \
    private_take[I],checked_seal[I],publish[I],lease_release[I],sealed[I],published[I],bank_fault[I],framing[I], \
    fault_token[I],data[I],position[I],fault_position[I],metadata[I],lease[I],fault_lease[I],reasons[I]}
  task compare_all;
    begin
      if(compare_enabled && (`BANK_STATE(dut) !== `BANK_STATE(reference_bank) ||
          `BANK_OUTPUTS(0) !== `BANK_OUTPUTS(1))) $fatal(1,"PUBLICATION_DEFAULT_OR_PREFENCE_MISMATCH");
      if(compare_enabled)checks=checks+1;
    end
  endtask
  always @(posedge clk)begin
    cycles=cycles+1;if(cycles>4000)$fatal(1,"PUBLICATION_BANK_WATCHDOG");
    compare_all();
    if(out_valid[1] && output_ready)reads=reads+1;
    #0.001;compare_all();
  end
  task tick;begin @(posedge clk);#0.002;end endtask
  task inject;
    begin
      publication_faults=0;
      case(target)
        0:publication_faults[bit_index]=1;
        1:publication_faults[bit_index]=1'bx;
        2:publication_faults[bit_index]=1'bz;
      endcase
    end
  endtask
  task reset_epoch;
    begin
      @(negedge clk);resetn=0;peer_resetn=0;compare_enabled=0;
      input_valid=0;input_offer_new=0;input_last=0;output_ready=0;
      certificate_valid=0;certificate_offer_new=0;lease_release_valid=0;
      rearm_valid=0;publication_faults=0;live_faults=0;
      repeat(3)tick();@(negedge clk);resetn=1;peer_resetn=1;
      repeat(3)tick();compare_enabled=1;
      @(negedge clk);rearm_valid=1;
      if(kind==5)inject();
      tick();@(negedge clk);rearm_valid=0;publication_faults=0;
      if(!active[1] || reasons[1])$fatal(1,"PUBLICATION_REARM_WINDOW_CHANGED");
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",kind))kind=0;
    if(!$value$plusargs("BIT=%d",bit_index))bit_index=0;
    if(!$value$plusargs("TARGET=%d",target))target=0;
    if(!$value$plusargs("RESET_SIDE=%d",reset_side))reset_side=-1;
    reset_epoch();
    if(kind==5)begin
      $display("PUBLICATION_BANK_REARM_PASS option=%0d phase=%0d bit=%0d value=%0d checks=%0d",OPTION,kind,bit_index,target,checks);$finish;
    end
    for(integer n=0;n<512;n=n+1)begin
      input_valid=1;input_offer_new=1;input_position=n;input_last=n==511;input_data=36'h456700+n;
      if(n==1 && kind==3)begin
        certificate_valid=1;certificate_offer_new=1;
      end
      if(n==2 && kind!=3)begin certificate_valid=1;certificate_offer_new=1;end
      if(n==3)begin certificate_valid=0;certificate_offer_new=0;end
      if(kind==3 && n==1)begin
        compare_enabled=OPTION==0;inject();#0.001;
        if(!cert_ready[1] || !dut.staged.certificate_take || reasons[1])$fatal(1,"PUBLICATION_CERT_CURRENT_CHANGED");
        tick();
        if(!dut.staged.certificate_seen || (OPTION && reasons[1] !== (16'b1 << (8+bit_index))))
          $fatal(1,"PUBLICATION_CERT_OR_REASON_MISSING");
        $display("PUBLICATION_BANK_CERT_PASS option=%0d phase=%0d bit=%0d value=%0d checks=%0d",OPTION,kind,bit_index,target,checks);$finish;
      end
      if(OPTION==0 && kind==6)begin
        publication_faults=(n%3==0)?8'bx:((n%3==1)?8'bz:8'hff);
      end
      tick();@(negedge clk);
    end
    input_valid=0;input_offer_new=0;input_last=0;
    if(kind==0)wait(checked_seal[0]);
    else if(kind==1)wait(publish[0]);
    else begin
      wait(out_valid[0]);
      if(kind==4 || kind==6)begin
        @(negedge clk);output_ready=1;wait(reads==512);
        @(negedge clk);output_ready=0;wait(release_ready[0]);
      end
    end
    // Target pulses are established away from the sampling edge.
    @(negedge clk);saved_toggle=dut.staged.request_toggle;
    compare_enabled=OPTION==0;if(kind==4 || kind==6)lease_release_valid=1;inject();#0.001;
    if(reasons[1])$fatal(1,"PUBLICATION_FAULT_WAS_NOT_CURRENT");
    if(OPTION && (checked_seal[1] || publish[1]))$fatal(1,"PUBLICATION_CURRENT_VETO_MISSING");
    if(kind==2)begin
      output_ready=1;#0.001;
      if(!out_valid[1] || !dut.staged.output_accept)$fatal(1,"PUBLICATION_READ_CURRENT_CHANGED");
    end
    if(kind==4 && !lease_release[1])$fatal(1,"PUBLICATION_RELEASE_CURRENT_CHANGED");
    tick();
    if(OPTION)begin
      if(reasons[1] !== (16'b1 << (8+bit_index)))$fatal(1,"PUBLICATION_REASON_CAPTURE_MISSING");
      if(kind==0 && dut.staged.seal_q)$fatal(1,"PUBLICATION_INTERNAL_SEAL_BYPASS");
      if(kind==1 && (dut.staged.published_q || dut.staged.request_toggle!==saved_toggle))
        $fatal(1,"PUBLICATION_INTERNAL_PUBLISH_BYPASS");
      if(kind==2 && (reads!=1 || out_valid[1]))$fatal(1,"PUBLICATION_READ_EDGE_OR_QUARANTINE_MISSING");
      if(kind==4 && lease[1]!==2'd1)$fatal(1,"PUBLICATION_RELEASE_EDGE_MISSING");
      repeat(3)tick();if(!bank_fault[1] || out_valid[1] || publish[1])$fatal(1,"PUBLICATION_STICKY_QUARANTINE_MISSING");
    end
    if(reset_side>=0)begin
      @(negedge clk);if(reset_side==0)resetn=0;else peer_resetn=0;
      publication_faults=0;input_valid=0;certificate_valid=0;lease_release_valid=0;
      #0.001;if(active[1] || publish[1] || out_valid[1] || lease_release[1] || reasons[1])
        $fatal(1,"PUBLICATION_ONE_SIDED_RESET_FAILED");
      repeat(3)tick();@(negedge clk);resetn=1;peer_resetn=1;
      repeat(5)tick();if(active[1])$fatal(1,"PUBLICATION_RESET_REARM_BYPASS");
      @(negedge clk);rearm_valid=1;tick();
      if(!active[1] || reasons[1])$fatal(1,"PUBLICATION_RESET_RECOVERY_FAILED");
      $display("PUBLICATION_BANK_RESET_PASS side=%0d",reset_side);
    end
    $display("PUBLICATION_BANK_PASS option=%0d phase=%0d bit=%0d value=%0d checks=%0d reads=%0d reasons=%h",OPTION,kind,bit_index,target,checks,reads,reasons[1]);
    $finish;
  end
endmodule
