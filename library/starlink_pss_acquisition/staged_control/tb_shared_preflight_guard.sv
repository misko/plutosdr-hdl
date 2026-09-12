`timescale 1ns/1ps
module tb;
reg  clk=0;
reg  resetn=0;
reg  job_valid=0;
reg  private_descriptor_offer=0;
reg [69:0] job_descriptor=0;
reg  input_bank_reserved=0;
reg  output_bank_reserved=0;
reg  certified_input_beat=0;
reg  certified_input_complete=0;
reg  offered_input_beat=0;
reg  offered_input_complete=0;
reg  final_fence_certified=0;
reg  external_fault_now=0;
reg  phase_input_fault_now=0;
reg  completed_input_certified=0;
reg  completed_input_fault_now=0;
reg  core_event_frame_started=0;
reg [47:0] core_output_tdata=0;
reg [23:0] core_output_tuser=0;
reg  core_output_tvalid=0;
reg  core_output_tlast=0;
reg [7:0] core_status_tdata=0;
reg  core_status_tvalid=0;
reg  mailbox_input_ready=0;
reg  mailbox_input_fault=0;
reg  inverse_phase=0;
reg  forward_mailbox_fault=0;
reg [5:0] preflight_events_now=0;
wire preflight_fault_evidence_now=|preflight_events_now;
reg [5:0] shared_preflight_history;
always @(posedge clk or negedge resetn)
 if(!resetn)shared_preflight_history<=0;
 else shared_preflight_history<=shared_preflight_history|preflight_events_now;
starlink_pss_result_guard_owner_view #(.CERTIFIED_PRIVATE_ADMISSION(1),.PRIVATE_ACK_RETIREMENT(1),.PRIVATE_QUARANTINE_OFFER(1),.USE_PRIVATE_DESCRIPTOR_OFFER(1),.ENABLE_OFFERED_FAULT_SUMMARY(1),.REQUIRE_KNOWN_COMPLETED_INPUT(1),.USE_PHASE_INPUT_FAULT(0),.USE_COMPLETED_INPUT_FAULT(1),.USE_PREFLIGHT_REASON_ONLY(1),.USE_FORWARD_RETIREMENT(1)) original (
.clk(clk),
.resetn(resetn),
.job_valid(job_valid),
.private_descriptor_offer(private_descriptor_offer),
.job_ready(),
.admission_capacity(),
.job_descriptor(job_descriptor),
.input_bank_reserved(input_bank_reserved),
.output_bank_reserved(output_bank_reserved),
.certified_input_beat(certified_input_beat),
.certified_input_complete(certified_input_complete),
.offered_input_beat(offered_input_beat),
.offered_input_complete(offered_input_complete),
.offered_local_fault_now(),
.offered_local_faults_now(),
.final_fence_certified(final_fence_certified),
.external_fault_now(external_fault_now),
.phase_input_fault_now(phase_input_fault_now),
.completed_input_certified(completed_input_certified),
.completed_input_fault_now(completed_input_fault_now),
.preflight_fault_evidence_now(preflight_fault_evidence_now),
.core_event_frame_started(core_event_frame_started),
.core_output_tdata(core_output_tdata),
.core_output_tuser(core_output_tuser),
.core_output_tvalid(core_output_tvalid),
.core_output_tlast(core_output_tlast),
.core_status_tdata(core_status_tdata),
.core_status_tvalid(core_status_tvalid),
.mailbox_input_valid(),
.mailbox_private_valid(),
.mailbox_commit_valid(),
.mailbox_input_ready(mailbox_input_ready),
.mailbox_input_fault(mailbox_input_fault),
.inverse_phase(inverse_phase),
.forward_mailbox_fault(forward_mailbox_fault),
.forward_retirement_valid(),
.forward_private_offer(),
.mailbox_input_data(),
.mailbox_input_position(),
.mailbox_input_last(),
.mailbox_input_metadata(),
.busy(),
.commit_pulse(),
.protocol_fault(),
.fault_reasons(),
.owner_active(),
.owner_awaiting_ack(),
.owner_fault_now(),
.owner_ack_accept());
starlink_pss_result_guard_shared_preflight #(.CERTIFIED_PRIVATE_ADMISSION(1),.PRIVATE_ACK_RETIREMENT(1),.PRIVATE_QUARANTINE_OFFER(1),.USE_PRIVATE_DESCRIPTOR_OFFER(1),.ENABLE_OFFERED_FAULT_SUMMARY(1),.REQUIRE_KNOWN_COMPLETED_INPUT(1),.USE_PHASE_INPUT_FAULT(0),.USE_COMPLETED_INPUT_FAULT(1),.USE_PREFLIGHT_REASON_ONLY(1),.USE_FORWARD_RETIREMENT(1),.USE_SHARED_PREFLIGHT_HISTORY(__MODE__)) dut (
.clk(clk),
.resetn(resetn),
.job_valid(job_valid),
.private_descriptor_offer(private_descriptor_offer),
.job_ready(),
.admission_capacity(),
.job_descriptor(job_descriptor),
.input_bank_reserved(input_bank_reserved),
.output_bank_reserved(output_bank_reserved),
.certified_input_beat(certified_input_beat),
.certified_input_complete(certified_input_complete),
.offered_input_beat(offered_input_beat),
.offered_input_complete(offered_input_complete),
.offered_local_fault_now(),
.offered_local_faults_now(),
.final_fence_certified(final_fence_certified),
.external_fault_now(external_fault_now),
.phase_input_fault_now(phase_input_fault_now),
.completed_input_certified(completed_input_certified),
.completed_input_fault_now(completed_input_fault_now),
.preflight_fault_evidence_now(preflight_fault_evidence_now),
.core_event_frame_started(core_event_frame_started),
.core_output_tdata(core_output_tdata),
.core_output_tuser(core_output_tuser),
.core_output_tvalid(core_output_tvalid),
.core_output_tlast(core_output_tlast),
.core_status_tdata(core_status_tdata),
.core_status_tvalid(core_status_tvalid),
.mailbox_input_valid(),
.mailbox_private_valid(),
.mailbox_commit_valid(),
.mailbox_input_ready(mailbox_input_ready),
.mailbox_input_fault(mailbox_input_fault),
.inverse_phase(inverse_phase),
.forward_mailbox_fault(forward_mailbox_fault),
.forward_retirement_valid(),
.forward_private_offer(),
.mailbox_input_data(),
.mailbox_input_position(),
.mailbox_input_last(),
.mailbox_input_metadata(),
.busy(),
.commit_pulse(),
.protocol_fault(),
.fault_reasons(),
.owner_active(),
.owner_awaiting_ack(),
.owner_fault_now(),
.owner_ack_accept(),
.shared_preflight_history(shared_preflight_history));
integer checks=0,n,j,b,seed=32'h432234aa;
function automatic four(input integer v);case(v%4)0:four=0;1:four=1;2:four=1'bx;3:four=1'bz;endcase endfunction
task compare;begin
 if(dut.job_ready !== original.job_ready)$fatal(1,"guard mismatch job_ready check=%0d",checks);
 if(dut.admission_capacity !== original.admission_capacity)$fatal(1,"guard mismatch admission_capacity check=%0d",checks);
 if(dut.offered_local_fault_now !== original.offered_local_fault_now)$fatal(1,"guard mismatch offered_local_fault_now check=%0d",checks);
 if(dut.offered_local_faults_now !== original.offered_local_faults_now)$fatal(1,"guard mismatch offered_local_faults_now check=%0d",checks);
 if(dut.mailbox_input_valid !== original.mailbox_input_valid)$fatal(1,"guard mismatch mailbox_input_valid check=%0d",checks);
 if(dut.mailbox_private_valid !== original.mailbox_private_valid)$fatal(1,"guard mismatch mailbox_private_valid check=%0d",checks);
 if(dut.mailbox_commit_valid !== original.mailbox_commit_valid)$fatal(1,"guard mismatch mailbox_commit_valid check=%0d",checks);
 if(dut.forward_retirement_valid !== original.forward_retirement_valid)$fatal(1,"guard mismatch forward_retirement_valid check=%0d",checks);
 if(dut.forward_private_offer !== original.forward_private_offer)$fatal(1,"guard mismatch forward_private_offer check=%0d",checks);
 if(dut.mailbox_input_data !== original.mailbox_input_data)$fatal(1,"guard mismatch mailbox_input_data check=%0d",checks);
 if(dut.mailbox_input_position !== original.mailbox_input_position)$fatal(1,"guard mismatch mailbox_input_position check=%0d",checks);
 if(dut.mailbox_input_last !== original.mailbox_input_last)$fatal(1,"guard mismatch mailbox_input_last check=%0d",checks);
 if(dut.mailbox_input_metadata !== original.mailbox_input_metadata)$fatal(1,"guard mismatch mailbox_input_metadata check=%0d",checks);
 if(dut.busy !== original.busy)$fatal(1,"guard mismatch busy check=%0d",checks);
 if(dut.commit_pulse !== original.commit_pulse)$fatal(1,"guard mismatch commit_pulse check=%0d",checks);
 if(dut.protocol_fault !== original.protocol_fault)$fatal(1,"guard mismatch protocol_fault check=%0d",checks);
 if(dut.fault_reasons !== original.fault_reasons)$fatal(1,"guard mismatch fault_reasons check=%0d",checks);
 if(dut.owner_active !== original.owner_active)$fatal(1,"guard mismatch owner_active check=%0d",checks);
 if(dut.owner_awaiting_ack !== original.owner_awaiting_ack)$fatal(1,"guard mismatch owner_awaiting_ack check=%0d",checks);
 if(dut.owner_fault_now !== original.owner_fault_now)$fatal(1,"guard mismatch owner_fault_now check=%0d",checks);
 if(dut.owner_ack_accept !== original.owner_ack_accept)$fatal(1,"guard mismatch owner_ack_accept check=%0d",checks);
 if(dut.active_private !== original.active_private)$fatal(1,"guard mismatch active_private check=%0d",checks);
 if(dut.awaiting_ack !== original.awaiting_ack)$fatal(1,"guard mismatch awaiting_ack check=%0d",checks);
 if(dut.descriptor !== original.descriptor)$fatal(1,"guard mismatch descriptor check=%0d",checks);
 if(dut.input_count !== original.input_count)$fatal(1,"guard mismatch input_count check=%0d",checks);
 if(dut.output_count !== original.output_count)$fatal(1,"guard mismatch output_count check=%0d",checks);
 if(dut.input_complete_seen !== original.input_complete_seen)$fatal(1,"guard mismatch input_complete_seen check=%0d",checks);
 if(dut.frame_seen !== original.frame_seen)$fatal(1,"guard mismatch frame_seen check=%0d",checks);
 if(dut.status_seen !== original.status_seen)$fatal(1,"guard mismatch status_seen check=%0d",checks);
 if(dut.exponent_seen !== original.exponent_seen)$fatal(1,"guard mismatch exponent_seen check=%0d",checks);
 if(dut.status_exponent !== original.status_exponent)$fatal(1,"guard mismatch status_exponent check=%0d",checks);
 if(dut.output_exponent !== original.output_exponent)$fatal(1,"guard mismatch output_exponent check=%0d",checks);
 if(dut.age !== original.age)$fatal(1,"guard mismatch age check=%0d",checks);
 if(dut.return_occupied !== original.return_occupied)$fatal(1,"guard mismatch return_occupied check=%0d",checks);
 if(dut.return_last !== original.return_last)$fatal(1,"guard mismatch return_last check=%0d",checks);
 if(dut.return_data !== original.return_data)$fatal(1,"guard mismatch return_data check=%0d",checks);
 if(dut.return_position !== original.return_position)$fatal(1,"guard mismatch return_position check=%0d",checks);
 if(dut.return_exponent !== original.return_exponent)$fatal(1,"guard mismatch return_exponent check=%0d",checks);
 checks=checks+1;end endtask
task tick;begin #1;compare;clk=1;#1;compare;clk=0;#1;end endtask
task clear_inputs;begin
job_valid=0;
private_descriptor_offer=0;
job_descriptor=0;
input_bank_reserved=0;
output_bank_reserved=0;
certified_input_beat=0;
certified_input_complete=0;
offered_input_beat=0;
offered_input_complete=0;
final_fence_certified=0;
external_fault_now=0;
phase_input_fault_now=0;
completed_input_certified=0;
completed_input_fault_now=0;
core_event_frame_started=0;
core_output_tdata=0;
core_output_tuser=0;
core_output_tvalid=0;
core_output_tlast=0;
core_status_tdata=0;
core_status_tvalid=0;
mailbox_input_ready=0;
mailbox_input_fault=0;
inverse_phase=0;
forward_mailbox_fault=0;
preflight_events_now=0;end endtask
task restart;begin clear_inputs;resetn=0;tick;resetn=1;tick;end endtask
initial begin
 restart;
 // Every four-state six-cause vector, with independent controls and recovery.
 for(n=0;n<4096;n=n+1)begin
  restart;
  for(b=0;b<6;b=b+1)preflight_events_now[b]=four(n>>(2*b));
  tick;
  for(j=0;j<4;j=j+1)begin external_fault_now=four(j);mailbox_input_fault=four(n+j);tick;end
  preflight_events_now=0;external_fault_now=0;mailbox_input_fault=0;tick;
 end
 // General inputs, preflight changes and synchronous/asynchronous reset overlap.
 restart;
 for(n=0;n<20000;n=n+1)begin
  if(n%37==0)restart;
job_valid=four($unsigned($random(seed))%4);
private_descriptor_offer=four($unsigned($random(seed))%4);
job_descriptor={$random(seed),$random(seed),$random(seed)};
input_bank_reserved=four($unsigned($random(seed))%4);
output_bank_reserved=four($unsigned($random(seed))%4);
certified_input_beat=four($unsigned($random(seed))%4);
certified_input_complete=four($unsigned($random(seed))%4);
offered_input_beat=four($unsigned($random(seed))%4);
offered_input_complete=four($unsigned($random(seed))%4);
final_fence_certified=four($unsigned($random(seed))%4);
external_fault_now=four($unsigned($random(seed))%4);
phase_input_fault_now=four($unsigned($random(seed))%4);
completed_input_certified=four($unsigned($random(seed))%4);
completed_input_fault_now=four($unsigned($random(seed))%4);
core_event_frame_started=four($unsigned($random(seed))%4);
core_output_tdata={$random(seed),$random(seed),$random(seed)};
core_output_tuser={$random(seed),$random(seed),$random(seed)};
core_output_tvalid=four($unsigned($random(seed))%4);
core_output_tlast=four($unsigned($random(seed))%4);
core_status_tdata={$random(seed),$random(seed),$random(seed)};
core_status_tvalid=four($unsigned($random(seed))%4);
mailbox_input_ready=four($unsigned($random(seed))%4);
mailbox_input_fault=four($unsigned($random(seed))%4);
inverse_phase=four($unsigned($random(seed))%4);
forward_mailbox_fault=four($unsigned($random(seed))%4);
  preflight_events_now=$random(seed);if(n%7==0)preflight_events_now[n%6]=four(n);
  tick;
 end
 restart;force original.fault_reasons=8'h04;force dut.private_fault_reasons=8'h04;tick;
 release original.fault_reasons;release dut.private_fault_reasons;tick;
 restart;
 if(checks<50000)$fatal(1,"vacuous full guard comparison");
 $display("SHARED_PREFLIGHT_COMPONENT_PASS checks=%0d four_state_causes=4096 random_cycles=20000",checks);$finish;
end
endmodule
