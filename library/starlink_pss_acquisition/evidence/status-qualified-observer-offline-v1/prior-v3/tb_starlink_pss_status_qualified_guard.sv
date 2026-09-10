// Real guard RTL, independent frozen dec20 guard, synthetic core events.
// No vendor FFT or receiver numerical/physical qualification is claimed.
`timescale 1ns/1fs
`define STATUS_SNAPSHOT(D) {D.active_private,D.awaiting_ack,D.descriptor, \
 D.input_count,D.output_count,D.input_complete_seen,D.frame_seen,D.status_seen, \
 D.exponent_seen,D.status_exponent,D.output_exponent,D.age,D.return_occupied, \
 D.return_last,D.return_data,D.return_position,D.return_exponent,D.fault_reasons, \
 D.faults_now,D.status_error,D.output_error,D.completed_output_error, \
 D.final_qualified,D.final_fault_now,D.completed_final_fault_now,D.idle_fault_now}
module status_guard_probe #(parameter integer GOLDEN=0, MODE=0)(
 input wire clk,resetn,job_valid,input_bank_reserved,output_bank_reserved,
 input wire [69:0] job_descriptor,
 input wire certified_input_beat,certified_input_complete,final_fence_certified,
 input wire external_fault_now,core_event_frame_started,
 input wire [47:0] core_output_tdata,
 input wire [23:0] core_output_tuser,
 input wire core_output_tvalid,core_output_tlast,
 input wire [7:0] core_status_tdata,
 input wire core_status_tvalid,mailbox_input_ready,
 output wire [136:0] public_tuple,output wire [511:0] state_tuple,
 output wire [7:0] reasons,output wire public_valid,output wire commit_valid);
 wire job_ready,mailbox_input_valid,mailbox_private_valid,mailbox_commit_valid;
 wire [35:0] mailbox_input_data;wire[8:0]mailbox_input_position;
 wire mailbox_input_last;wire[74:0]mailbox_input_metadata;
 wire busy,commit_pulse,protocol_fault,forward_retirement_valid;
 wire[7:0]fault_reasons;
 wire phase_input_fault_now=0,completed_input_fault_now=0;
 wire completed_input_certified=final_fence_certified;
 wire preflight_fault_evidence_now=0,mailbox_input_fault=0;
 wire inverse_phase=0,forward_mailbox_fault=0;
 generate if(GOLDEN)begin:g_old
  starlink_pss_realtime_result_guard_dec20d63_golden #(
   .USE_COMPLETED_INPUT_FAULT(1),.USE_FORWARD_RETIREMENT(MODE),
   .USE_PREFLIGHT_REASON_ONLY(MODE)) dut(.*);
  assign state_tuple=`STATUS_SNAPSHOT(dut);
 end else begin:g_new
  starlink_pss_realtime_result_guard #(
   .USE_COMPLETED_INPUT_FAULT(1),.USE_FORWARD_RETIREMENT(MODE),
   .USE_PREFLIGHT_REASON_ONLY(MODE)) dut(.*);
  assign state_tuple=`STATUS_SNAPSHOT(dut);
 end endgenerate
 assign public_tuple={job_ready,mailbox_input_valid,mailbox_private_valid,mailbox_commit_valid,
  mailbox_input_data,mailbox_input_position,mailbox_input_last,mailbox_input_metadata,
  busy,commit_pulse,protocol_fault,fault_reasons,forward_retirement_valid};
 assign reasons=fault_reasons;assign public_valid=mailbox_input_valid;
 assign commit_valid=mailbox_commit_valid;
endmodule
`undef STATUS_SNAPSHOT

module tb_starlink_pss_fft_bank_owned_slice;
 parameter integer MODE=0;
 reg clk=0;always #3 clk=!clk;
 reg resetn=0,job_valid=0,input_bank_reserved=1,output_bank_reserved=1;
 reg[69:0]job_descriptor=70'h123456789abcdef;
 reg certified_input_beat=0,certified_input_complete=0,final_fence_certified=0;
 reg external_fault_now=0,core_event_frame_started=0;
 reg[47:0]core_output_tdata=48'h123456789abc;
 reg[23:0]core_output_tuser=0;
 reg core_output_tvalid=0,core_output_tlast=0,core_status_tvalid=0,mailbox_input_ready=1;
 reg[7:0]candidate_status=5,reference_status=5;
 wire[136:0]c_public,r_public;wire[511:0]c_state,r_state;
 wire[7:0]c_reasons,r_reasons;wire c_valid,r_valid,c_commit,r_commit;
 status_guard_probe #(.MODE(MODE)) candidate(
  .core_status_tdata(candidate_status),.public_tuple(c_public),.state_tuple(c_state),
  .reasons(c_reasons),.public_valid(c_valid),.commit_valid(c_commit),.*);
 status_guard_probe #(.MODE(MODE),.GOLDEN(1)) reference_guard(
  .core_status_tdata(reference_status),.public_tuple(r_public),.state_tuple(r_state),
  .reasons(r_reasons),.public_valid(r_valid),.commit_valid(r_commit),.*);
 integer checks=0,phase_id=0,kind=0,rows=0,known_reasons=0,invalid_rows=0;
 always @(posedge clk or negedge clk)begin
  #0.002;
  if(c_public!==r_public || c_state!==r_state)
   $fatal(1,"STATUS_GUARD_TRACE_MISMATCH phase=%0d kind=%0d public=%h/%h state=%h/%h",
    phase_id,kind,c_public,r_public,c_state,r_state);
  checks=checks+1;
 end
 task tick;@(posedge clk);#0.01;endtask
 task quiet;
  job_valid=0;certified_input_beat=0;certified_input_complete=0;
  core_event_frame_started=0;core_output_tvalid=0;core_output_tlast=0;
  core_status_tvalid=0;candidate_status=5;reference_status=5;external_fault_now=0;
 endtask
 task prepare_phase(input integer phase_number);
  integer n;
  @(negedge clk);quiet();resetn=0;final_fence_certified=0;mailbox_input_ready=1;
  repeat(2)tick();@(negedge clk);resetn=1;tick();
  if(phase_number>0)begin
   @(negedge clk);job_valid=1;tick();@(negedge clk);job_valid=0;
   for(n=0;n<512;n=n+1)begin
    certified_input_beat=1;certified_input_complete=(n==511);
    core_event_frame_started=(n==0);tick();@(negedge clk);
   end
   quiet();final_fence_certified=1;
   if(phase_number>=2)begin
    for(n=0;n<(phase_number==2?1:512);n=n+1)begin
     core_output_tvalid=1;core_output_tlast=(n==511);
     core_output_tuser={3'b0,5'd5,7'b0,9'(n)};
     core_status_tvalid=(phase_number>=4 && n==0);
     tick();@(negedge clk);
    end
    quiet();
    if(phase_number>=3)mailbox_input_ready=0;
    if(phase_number==5)begin
     mailbox_input_ready=1;tick();@(negedge clk);mailbox_input_ready=0;
    end
   end
  end
 endtask
 initial begin
  for(phase_id=0;phase_id<6;phase_id=phase_id+1)begin
   for(kind=0;kind<12;kind=kind+1)begin
    prepare_phase(phase_id);
    core_status_tvalid=1;
    case(kind)
     0:begin core_status_tvalid=0;candidate_status=8'bxx100101;reference_status=5;end
     1:candidate_status=8'h25;
     2:candidate_status=8'h45;
     3:candidate_status=8'h85;
     4:candidate_status=8'h04;
     5:candidate_status=8'bxx100101;
     6:candidate_status=8'b0x000101;
     7:candidate_status=8'b00000x01;
     8:candidate_status=8'b00000z01;
     9:begin candidate_status=8'h25;core_status_tvalid=1'bx;end
     10:begin candidate_status=8'h25;core_status_tvalid=1'bz;end
     11:candidate_status=8'h05;
    endcase
    if(kind!=0)reference_status=candidate_status;
    #0.02;
    if(kind==0)invalid_rows=invalid_rows+1;
    // Known reserved-bit errors must veto that current edge and latch bit4.
    if(kind==1 || kind==2 || kind==3 || kind==5)begin
     if(c_valid===1 || c_commit===1)$fatal(1,"STATUS_RESERVED_CURRENT_VETO_MISSING");
    end
    tick();
    if(kind==1 || kind==2 || kind==3 || kind==5)begin
     if(c_reasons[4]!==1)$fatal(1,"STATUS_RESERVED_STICKY_REASON_MISSING");
     known_reasons=known_reasons+1;
    end
    @(negedge clk);quiet();repeat(2)tick();rows=rows+1;
   end
  end
  $display("STATUS_REAL_GUARD_PASS mode=%0d rows=%0d phases=6 invalid_payload_rows=%0d known_reserved_reasons=%0d checks=%0d synthetic_core_not_fft=1",
   MODE,rows,invalid_rows,known_reasons,checks);$finish;
 end
endmodule
