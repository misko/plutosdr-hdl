`timescale 1ns/1ps
// OFFLINE guard-only comparison. No FFT model, physical timing or RF claim.
module tb_starlink_pss_local_admission;
  parameter integer CHECK_IDENTITY=1, BALANCED=1;
  reg clk=0;
  always #5 clk=~clk;
  reg resetn=0, job_start=0, input_enable=0, input_valid=0;
  reg [69:0] job_descriptor=0, input_metadata=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg input_last=0, core_input_tready=0;
  integer cycles=0, phase=0, reachable_checks=0, arbitrary_checks=0;
  integer healthy_blocks=0, metadata_probes=0, position_probes=0;
  integer duplicate_probes=0, data_xz_probes=0, snapshots=0;
  integer descriptor_capture_bits=0;

`define CONNECTIONS \
    .clk(clk),.resetn(resetn),.job_start(job_start),.job_descriptor(job_descriptor), \
    .input_enable(input_enable),.input_valid(input_valid),.input_data(input_data), \
    .input_position(input_position),.input_last(input_last),.input_metadata(input_metadata), \
    .core_input_tready(core_input_tready)
  local_admission_original_guard #(.CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY),
    .BALANCED_IDENTITY_EQ(BALANCED)) reference_guard (`CONNECTIONS);
  starlink_pss_realtime_input_guard_local_admission #(.CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY),
    .BALANCED_IDENTITY_EQ(BALANCED)) default_guard (`CONNECTIONS);
  starlink_pss_realtime_input_guard_local_admission #(.CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY),
    .BALANCED_IDENTITY_EQ(BALANCED),.LOCAL_FIRST_ADMISSION(1)) candidate (`CONNECTIONS);
`undef CONNECTIONS

`define VIEW(g) {g.input_ready,g.input_transport_ready,g.core_input_tdata, \
  g.core_input_tvalid,g.core_input_tlast,g.certified_input_beat,g.certified_input_complete, \
  g.input_complete,g.fault_now,g.duplicate_start_fault_now,g.fault_events_now, \
  g.protocol_fault,g.fault_reasons,g.job_started,g.input_started,g.descriptor,g.expected_position, \
  g.slot_open,g.eligible,g.metadata_valid,g.identity_matches,g.errors_now}
  wire [255:0] reference_view=`VIEW(reference_guard);
  wire [255:0] default_view=`VIEW(default_guard);
  wire [255:0] candidate_view=`VIEW(candidate);

  task compare;
    begin
      if (reference_view !== default_view || reference_view !== candidate_view) begin
        $display("LOCAL_ADMISSION_MISMATCH phase=%0d cycle=%0d reference=%h default=%h candidate=%h",phase,cycles,reference_view,default_view,candidate_view);
        $fatal(1,"full unconditional guard/state comparison");
      end
      if (phase==0) reachable_checks=reachable_checks+1;
      else arbitrary_checks=arbitrary_checks+1;
    end
  endtask
  always @(posedge clk) begin
    cycles=cycles+1;
    compare();
    #1; compare();
  end
  task tick;
    begin @(negedge clk); #1; compare(); end
  endtask
  task reset_epoch;
    begin
      resetn=0; job_start=0; input_enable=0; input_valid=0;
      core_input_tready=0; input_position=0; input_last=0;
      tick(); tick(); resetn=1; tick();
    end
  endtask
  task admit(input [69:0] descriptor_value);
    begin
      reset_epoch(); job_descriptor=descriptor_value; input_metadata=descriptor_value;
      input_position=0; input_last=0; job_start=1;
      tick(); job_start=0; input_enable=1;
      if (candidate.descriptor !== descriptor_value || candidate.job_started !== 1)
        $fatal(1,"first descriptor admission missing");
    end
  endtask
  task healthy(input [69:0] descriptor_value);
    integer n;
    begin
      admit(descriptor_value);
      for(n=0;n<512;n=n+1) begin
        input_position=n; input_last=(n==511); input_data={18'(n),18'(~n)};
        // Legal bounded core stalls may carry invalid/unknown bubbles.
        if(n%7==0) begin
          core_input_tready=0; input_valid=0; input_metadata=70'bx; tick();
          input_valid=1; input_metadata=descriptor_value; tick();
        end
        input_valid=1; input_metadata=descriptor_value; core_input_tready=1; tick();
      end
      if(candidate.input_complete!==1 || candidate.protocol_fault!==0)
        $fatal(1,"healthy block did not complete exactly");
      // N+1 presentation after closure cannot reopen or overwrite N.
      input_metadata=~descriptor_value; job_descriptor=~descriptor_value;
      input_position=0; input_last=0; tick(); tick();
      if(candidate.descriptor!==descriptor_value || candidate.protocol_fault!==0)
        $fatal(1,"closed slot descriptor overwritten");
      job_start=1; tick(); duplicate_probes=duplicate_probes+1;
      if(candidate.protocol_fault!==1 || candidate.descriptor!==descriptor_value)
        $fatal(1,"duplicate completed-slot start not rejected");
      healthy_blocks=healthy_blocks+1;
    end
  endtask

  function automatic logic four(input integer value);
    case(value&3) 0:four=0; 1:four=1; 2:four=1'bx; 3:four=1'bz; endcase
  endfunction
  reg snap_started, snap_input_started, snap_complete;
  reg [2:0] snap_reasons;
  reg [69:0] snap_descriptor;
  reg [8:0] snap_position;
`define FORCE_STATE(g) \
    force g.job_started=snap_started; force g.input_started=snap_input_started; \
    force g.input_complete=snap_complete; force g.fault_reasons=snap_reasons; \
    force g.descriptor=snap_descriptor; force g.expected_position=snap_position;
`define RELEASE_STATE(g) \
    release g.job_started; release g.input_started; release g.input_complete; \
    release g.fault_reasons; release g.descriptor; release g.expected_position;
  integer k, direction, bit_index, corruption;
  reg [69:0] tag;
  initial begin
    if($bits(`VIEW(reference_guard))>256) $fatal(1,"comparison truncation");
    #1; reset_epoch();
    healthy(70'h00000000123456789a);
    healthy(70'h20000000fedcba9876);
    for(bit_index=0;bit_index<70;bit_index=bit_index+1) begin
      admit(70'b1<<bit_index);
      descriptor_capture_bits=descriptor_capture_bits+1;
    end
    for(direction=0;direction<2;direction=direction+1) begin
      tag=70'h123456789abcdef01; tag[69]=direction;
      for(bit_index=0;bit_index<70;bit_index=bit_index+1) begin
        for(corruption=0;corruption<3;corruption=corruption+1) begin
          admit(tag); input_valid=1; core_input_tready=1;
          input_metadata=tag;
          input_metadata[bit_index]=corruption==0 ? ~tag[bit_index] : four(corruption+1);
          tick();
          if(CHECK_IDENTITY && corruption==0 && candidate.protocol_fault!==1)
            $fatal(1,"same-edge metadata fault missing");
          // Unknown-valued original signals are compared literally, not
          // relabeled as known sticky faults or sanitized into valid tokens.
          if(CHECK_IDENTITY && corruption!=0 && candidate.certified_input_beat===1)
            $fatal(1,"unknown metadata falsely certified");
          metadata_probes=metadata_probes+1;
        end
      end
      for(bit_index=0;bit_index<9;bit_index=bit_index+1) begin
        for(corruption=0;corruption<3;corruption=corruption+1) begin
          admit(tag); input_valid=1; core_input_tready=1;
          input_position[bit_index]=corruption==0 ? 1'b1 : four(corruption+1);
          tick();
          if(corruption==0 && candidate.protocol_fault!==1) $fatal(1,"same-edge position fault missing");
          if(corruption!=0 && candidate.certified_input_beat===1) $fatal(1,"unknown position falsely certified");
          position_probes=position_probes+1;
        end
      end
      admit(tag); input_valid=1; core_input_tready=1; input_last=1; tick();
      if(candidate.protocol_fault!==1) $fatal(1,"current TLAST fault missing");
      admit(tag); input_valid=1; core_input_tready=1; tick();
      input_valid=0; tick();
      if(candidate.protocol_fault!==1) $fatal(1,"current demand fault missing");
      admit(tag); job_descriptor=~tag; job_start=1; input_valid=1; core_input_tready=1; tick();
      if(candidate.protocol_fault!==1 || candidate.descriptor!==tag)
        $fatal(1,"open-slot duplicate overwritten");
      duplicate_probes=duplicate_probes+1;
      admit(tag); input_valid=1; core_input_tready=0;
      input_data=36'bx; tick(); input_data=36'bz; tick(); data_xz_probes=data_xz_probes+2;
      // Unknown first-admission descriptor is captured identically, not sanitized.
      admit(70'bx); reset_epoch(); admit(70'bz); reset_epoch();
    end

    // Explicitly NONREACHABLE arbitrary-state gate snapshots. These are not
    // counted as healthy epochs; all seven control dimensions take 0/1/X/Z.
    phase=1;
    for(k=0;k<16384;k=k+1) begin
      snap_started=four(k); job_start=four(k>>2); snap_reasons={3{four(k>>4)}};
      snap_complete=four(k>>6); snap_input_started=four(k>>8);
      core_input_tready=four(k>>10); resetn=four(k>>12);
      snap_descriptor=70'h3abcdef01234567890; job_descriptor=~snap_descriptor;
      snap_position={9{four(k>>4)}}; input_position={9{four(k>>8)}};
      input_enable=four(k>>6); input_valid=four(k>>10); input_last=four(k>>2);
      input_metadata={70{four(k>>12)}}; input_data={36{four(k)}};
      `FORCE_STATE(reference_guard) `FORCE_STATE(default_guard) `FORCE_STATE(candidate)
      #1; compare();
      `RELEASE_STATE(reference_guard) `RELEASE_STATE(default_guard) `RELEASE_STATE(candidate)
      tick(); snapshots=snapshots+1;
    end
    phase=0; reset_epoch(); healthy(70'h0123456789abcdef01);
    if(healthy_blocks!=3 || metadata_probes!=420 || position_probes!=54 ||
       duplicate_probes!=5 || data_xz_probes!=4 || snapshots!=16384 || descriptor_capture_bits!=70)
      $fatal(1,"incomplete directed coverage");
    $display("LOCAL_ADMISSION_OFFLINE_PASS check_identity=%0d balanced=%0d healthy_blocks=%0d metadata_bits=%0d position_bits=%0d duplicates=%0d data_xz=%0d descriptor_capture_bits=%0d arbitrary_snapshots=%0d reachable_checks=%0d arbitrary_checks=%0d cycles=%0d",CHECK_IDENTITY,BALANCED,healthy_blocks,metadata_probes,position_probes,duplicate_probes,data_xz_probes,descriptor_capture_bits,snapshots,reachable_checks,arbitrary_checks,cycles);
    $finish(0);
  end
  initial begin #1000000; $fatal(1,"offline watchdog"); end
endmodule
