`timescale 1ns/1ps
module tb_epoch_sealed_legacy;
  reg clk=0;
  always #5 clk=~clk;
  reg resetn=0, peer_resetn=0, valid=0, ready=0, last=0, commit=0;
  reg [35:0] data=0;
  reg [8:0] position=0;
  reg [74:0] metadata=0;
  wire ar, af, ac, av, al, br, bf, bc, bv, bl, cr, cf, cc, cv, cl;
  wire [35:0] ad, bd, cd;
  wire [8:0] ap, bp, cp;
  wire [74:0] am, bm, cm;
  integer checks=0, outputs=0, block_count=0, index=0;
  starlink_pss_epoch_sealed_bank omitted (
    .clk(clk), .input_resetn(resetn), .output_resetn(peer_resetn),
    .input_valid(valid), .input_ready(ar), .input_data(data), .input_position(position),
    .input_last(last), .input_metadata(metadata), .input_commit_authorized(commit),
    .input_fault(af), .input_framing_fault_now(ac), .output_valid(av), .output_ready(ready),
    .output_data(ad), .output_position(ap), .output_last(al), .output_metadata(am),
    .live_faults(8'hff), .input_offer_new(1'bx), .certificate_offer_new(1'bx),
    .rearm_valid(1'b1), .engine_reset_held(1'b0), .certificate_valid(1'b1)
  );
  starlink_pss_epoch_sealed_bank #(.SEALED_PUBLICATION(0)) explicit_zero (
    .clk(clk), .input_resetn(resetn), .output_resetn(peer_resetn),
    .input_valid(valid), .input_ready(cr), .input_data(data), .input_position(position),
    .input_last(last), .input_metadata(metadata), .input_commit_authorized(commit),
    .input_fault(cf), .input_framing_fault_now(cc), .output_valid(cv), .output_ready(ready),
    .output_data(cd), .output_position(cp), .output_last(cl), .output_metadata(cm)
  );
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .EXPLICIT_COMMIT(1)) independent_original (
    .input_clk(clk), .input_resetn(resetn), .input_valid(valid), .input_ready(br),
    .input_data(data), .input_position(position), .input_last(last), .input_metadata(metadata),
    .input_commit_authorized(commit), .input_fault(bf), .input_framing_fault_now(bc),
    .output_clk(clk), .output_resetn(peer_resetn), .output_valid(bv), .output_ready(ready),
    .output_data(bd), .output_position(bp), .output_last(bl), .output_metadata(bm)
  );
  always @(posedge clk or negedge clk) begin
    #0.001;
    if({ar,af,ac,av,ad,ap,al,am} !== {br,bf,bc,bv,bd,bp,bl,bm} ||
       {cr,cf,cc,cv,cd,cp,cl,cm} !== {br,bf,bc,bv,bd,bp,bl,bm})
      $fatal(1,"default public passthrough mismatch");
    checks=checks+1;
  end
  always @(posedge clk) if(av && ready) begin
    outputs=outputs+1;
    if(ad !== (36'h987650000 + ap)) $fatal(1,"default RAM mismatch");
  end
  initial begin
    repeat(3) @(negedge clk); resetn=1; peer_resetn=1;
    repeat(6) @(negedge clk);
    for(block_count=0;block_count<2;block_count=block_count+1) begin
      for(index=0;index<512;index=index+1) begin
        @(negedge clk); valid=1; position=index; last=(index==511);
        data=36'h987650000+index; metadata=75'h43210000000+block_count;
        @(posedge clk); if(!ar) $fatal(1,"default capacity missing");
      end
      repeat(50) @(negedge clk); // legacy rewrites final while status absent
      commit=1;
      @(negedge clk); valid=0; commit=0;
      repeat(6) @(negedge clk); ready=1;
      while(outputs<(block_count+1)*512) begin
        @(negedge clk); ready=(checks%7!=0);
      end
      ready=0;
      repeat(8) @(negedge clk);
    end
    // Corruption and one-sided reset remain byte-exact legacy behavior.
    valid=1; position=7; last=0; metadata='x;
    @(negedge clk); valid=0;
    repeat(3) @(negedge clk); peer_resetn=0;
    repeat(3) @(negedge clk); peer_resetn=1;
    repeat(6) @(negedge clk);
    if(omitted.SEALED_PUBLICATION!==0 || explicit_zero.SEALED_PUBLICATION!==0 ||
       omitted.legacy.original.METADATA_WIDTH!==75 || omitted.legacy.original.EXPLICIT_COMMIT!==1)
      $fatal(1,"default parameter binding wrong");
    $display("SEALED_LEGACY_PASS checks=%0d words=%0d",checks,outputs);
    $finish(0);
  end
endmodule
