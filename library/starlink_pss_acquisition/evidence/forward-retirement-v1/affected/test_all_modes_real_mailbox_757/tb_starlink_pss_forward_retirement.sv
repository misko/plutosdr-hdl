`timescale 1ns/1fs
// FAST snapshot/predicate study, not actual FFT or bank-lifecycle proof.
// Both guards receive identical deliberately arbitrary internal snapshots.
// The CURRENT fault is nevertheless computed by the REAL mailbox and exact
// production private_valid && inverse_phase wiring, never a presumed bit.
module tb_starlink_pss_forward_retirement #(
  parameter integer ENABLED = 1, COMPLETED = 1, PHASE_INPUT = 0,
  parameter integer BROKEN_CALLER = 0, WRONG_PHASE_WIRING = 0
);
  reg clk = 0, resetn = 0;
  reg job_valid = 0;
  reg [69:0] job_descriptor = 70'h123456789abcdef123;
  reg input_bank_reserved = 1, output_bank_reserved = 1;
  reg certified_input_beat = 0, certified_input_complete = 0, final_fence_certified = 1;
  reg external_fault_now = 0, phase_input_fault_now = 0;
  reg completed_input_certified = 1, completed_input_fault_now = 0;
  reg preflight_fault_evidence_now = 0, core_event_frame_started = 0;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = {3'b0,5'd6,7'b0,9'd18};
  reg core_output_tvalid = 0, core_output_tlast = 0;
  reg [7:0] core_status_tdata = 8'd6;
  reg core_status_tvalid = 0, mailbox_input_ready = 1, inverse_phase = 0;
  wire mailbox_input_fault, forward_mailbox_fault, mailbox_current_fault_now;
  wire job_ready, mailbox_input_valid, mailbox_private_valid, mailbox_commit_valid;
  wire mailbox_input_last, busy, commit_pulse, protocol_fault, forward_retirement_valid;
  wire [35:0] mailbox_input_data;
  wire [8:0] mailbox_input_position;
  wire [74:0] mailbox_input_metadata;
  wire [7:0] fault_reasons;
  reg snapshot_active = 1, snapshot_ack = 0, snapshot_occupied = 1, snapshot_last = 0;
  reg snapshot_complete = 1, snapshot_frame = 1, snapshot_status = 0, snapshot_exponent = 1;
  reg [9:0] snapshot_inputs = 512, snapshot_outputs = 18;
  reg [12:0] snapshot_age = 0;
  reg [7:0] snapshot_reasons = 0;
  reg [8:0] bank_cursor = 17;
  reg bank_blocked = 0, bank_sticky = 0;
  reg [74:0] bank_held = 75'h123456789abcdef1234;
  reg [74:0] raw_metadata = 75'h123456789abcdef1234;
  reg [35:0] raw_data = 0;
  reg [8:0] raw_position = 17;
  reg raw_last = 0;
  wire bank_ready, bank_current, bank_fault;
  wire old_valid, old_private_valid;
  wire [31:0] checks, forward_cycles, inverse_current_faults, sticky_forward_faults;
  integer rows = 0, bit_rows = 0, position_rows = 0;
  integer phase, state_kind, ready_kind, cause, bit_index, cursor_kind, position_kind, last_kind;
  reg [7:0] expected_reasons;
  starlink_pss_realtime_result_guard #(.USE_FORWARD_RETIREMENT(ENABLED),
    .USE_COMPLETED_INPUT_FAULT(COMPLETED), .USE_PHASE_INPUT_FAULT(PHASE_INPUT),
    .USE_PREFLIGHT_REASON_ONLY(1)) dut (
    .inverse_phase(WRONG_PHASE_WIRING ? !inverse_phase : inverse_phase), .*
  );
  assign forward_mailbox_fault = bank_fault;
  assign mailbox_current_fault_now = BROKEN_CALLER ? 1'b1 : bank_current;
  assign mailbox_input_fault = bank_fault || mailbox_current_fault_now;
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .EXPLICIT_COMMIT(1),
    .RESET_RELEASE_EXTERNAL(1)) bank (
    .input_clk(clk), .input_resetn(resetn),
    .input_valid(mailbox_private_valid && inverse_phase), .input_ready(bank_ready),
    .input_commit_authorized(mailbox_commit_valid && inverse_phase),
    .input_data(raw_data), .input_position(raw_position), .input_last(raw_last),
    .input_metadata(raw_metadata), .input_fault(bank_fault), .input_framing_fault_now(bank_current),
    .output_clk(clk), .output_resetn(resetn), .output_ready(1'b0),
    .output_valid(), .output_data(), .output_position(), .output_last(), .output_metadata()
  );
  starlink_pss_forward_retirement_shadow #(.ENABLED(ENABLED), .COMPLETED(COMPLETED),
    .PHASE_INPUT(PHASE_INPUT), .PREFLIGHT(1)) shadow (
    .actual_public({job_ready, mailbox_input_valid, mailbox_private_valid, mailbox_commit_valid,
      mailbox_input_data, mailbox_input_position, mailbox_input_last, mailbox_input_metadata,
      busy, commit_pulse, protocol_fault, fault_reasons}),
    .actual_forward_valid(forward_retirement_valid), .*
  );
  initial begin
    force dut.active_private = snapshot_active; force shadow.old_guard.active_private = snapshot_active;
    force dut.awaiting_ack = snapshot_ack; force shadow.old_guard.awaiting_ack = snapshot_ack;
    force dut.return_occupied = snapshot_occupied; force shadow.old_guard.return_occupied = snapshot_occupied;
    force dut.return_last = snapshot_last; force shadow.old_guard.return_last = snapshot_last;
    force dut.input_count = snapshot_inputs; force shadow.old_guard.input_count = snapshot_inputs;
    force dut.output_count = snapshot_outputs; force shadow.old_guard.output_count = snapshot_outputs;
    force dut.input_complete_seen = snapshot_complete; force shadow.old_guard.input_complete_seen = snapshot_complete;
    force dut.frame_seen = snapshot_frame; force shadow.old_guard.frame_seen = snapshot_frame;
    force dut.status_seen = snapshot_status; force shadow.old_guard.status_seen = snapshot_status;
    force dut.exponent_seen = snapshot_exponent; force shadow.old_guard.exponent_seen = snapshot_exponent;
    force dut.status_exponent = 5'd6; force shadow.old_guard.status_exponent = 5'd6;
    force dut.output_exponent = 5'd6; force shadow.old_guard.output_exponent = 5'd6;
    force dut.age = snapshot_age; force shadow.old_guard.age = snapshot_age;
    force dut.fault_reasons = snapshot_reasons; force shadow.old_guard.fault_reasons = snapshot_reasons;
    force bank.write_position = bank_cursor; force bank.metadata_in_hold = bank_held;
    force bank.request_toggle = bank_blocked; force bank.acknowledge_sync = 2'b0;
    force bank.input_fault = bank_sticky;
  end
  task check;
    reg expected_current;
    begin
      #0.01;
      expected_current = mailbox_private_valid && inverse_phase && bank_ready &&
        !(raw_position == bank_cursor && raw_last == (bank_cursor == 511) &&
          (bank_cursor == 0 || raw_metadata == bank_held));
      if (bank_current !== expected_current)
        $fatal(1, "FORWARD_REAL_MAILBOX_RAW_PREDICATE_MISMATCH");
      shadow.check(); rows = rows + 1;
    end
  endtask
  task defaults;
    begin
      input_bank_reserved=1; output_bank_reserved=1; certified_input_beat=0;
      certified_input_complete=0; final_fence_certified=1; external_fault_now=0;
      phase_input_fault_now=0; completed_input_certified=1; completed_input_fault_now=0;
      preflight_fault_evidence_now=0; core_event_frame_started=0;
      core_output_tdata=0; core_output_tuser={3'b0,5'd6,7'b0,9'd18};
      core_output_tvalid=0; core_output_tlast=0; core_status_tdata=6; core_status_tvalid=0;
      snapshot_active=1; snapshot_ack=0; snapshot_occupied=1; snapshot_last=0;
      snapshot_inputs=512; snapshot_outputs=18; snapshot_complete=1; snapshot_frame=1;
      snapshot_status=0; snapshot_exponent=1; snapshot_age=0; snapshot_reasons=0;
      bank_sticky=0; raw_position=bank_cursor; raw_last=(bank_cursor==511); raw_metadata=bank_held;
    end
  endtask
  task tick; begin #0.1; clk=1; #0.1; clk=0; #0.1; end endtask
  initial begin
    tick(); resetn=1;
    // All guard branches and arbitrary input/event faults, including events
    // inconsistent with the completed-input caller premise: old outputs still
    // stay literal, and new output mirrors the SAME selected old predicate.
    for (phase=0; phase<2; phase=phase+1)
      for (state_kind=0; state_kind<8; state_kind=state_kind+1)
        for (ready_kind=0; ready_kind<2; ready_kind=ready_kind+1)
          for (cause=0; cause<20; cause=cause+1) begin
            defaults(); inverse_phase=phase; mailbox_input_ready=ready_kind; bank_blocked=!ready_kind;
            case(state_kind)
              0: begin snapshot_active=0; snapshot_occupied=0; end
              1: begin snapshot_inputs=511; snapshot_complete=0; snapshot_occupied=0; end
              2: begin end
              3: begin snapshot_last=1; snapshot_outputs=512; end
              4: begin snapshot_last=1; snapshot_outputs=512; snapshot_status=1; end
              5: begin snapshot_active=0; snapshot_ack=1; snapshot_occupied=0; end
              6: begin snapshot_occupied=0; end
              7: begin snapshot_reasons=8'h81; end
            endcase
            case(cause)
              1: bank_sticky=1;
              2: begin raw_metadata=bank_held^75'd1; raw_position=raw_position^9'd1; raw_last=!raw_last; end
              3: external_fault_now=1;
              4: completed_input_fault_now=1;
              5: phase_input_fault_now=1;
              6: output_bank_reserved=0;
              7: input_bank_reserved=0;
              8: core_event_frame_started=1;
              9: core_status_tvalid=1;
              10: begin core_status_tvalid=1; core_status_tdata=8'h87; end
              11: core_output_tvalid=1;
              12: begin core_output_tvalid=1; core_output_tuser=24'hffffff; core_output_tlast=1; end
              13: certified_input_beat=1;
              14: certified_input_complete=1;
              15: final_fence_certified=0;
              16: completed_input_certified=0;
              17: snapshot_age=8191;
              18: begin
                core_output_tdata='x; core_output_tuser='x; core_status_tdata='x;
                core_output_tlast=1'bx; raw_data='x;
                if (!snapshot_occupied) begin raw_metadata='x; raw_position='x; raw_last=1'bx; end
              end
              19: begin
                external_fault_now=1; completed_input_fault_now=1; phase_input_fault_now=1;
                core_event_frame_started=1; core_status_tvalid=1; core_status_tdata=8'h87;
                core_output_tvalid=1; core_output_tuser=24'hffffff; certified_input_beat=1;
                certified_input_complete=1; output_bank_reserved=0; snapshot_age=8191;
                raw_metadata=~bank_held;
              end
            endcase
            check();
          end
    // Every 75-bit metadata/header bit, first/interior/final mailbox cursor,
    // both phases and ownership READY states. No valid-word assumption.
    for(phase=0;phase<2;phase=phase+1)
      for(cursor_kind=0;cursor_kind<3;cursor_kind=cursor_kind+1)
        for(ready_kind=0;ready_kind<2;ready_kind=ready_kind+1)
          for(bit_index=0;bit_index<75;bit_index=bit_index+1) begin
            bank_cursor=cursor_kind==0 ? 0 : cursor_kind==1 ? 17 : 511;
            defaults(); inverse_phase=phase; bank_blocked=!ready_kind; mailbox_input_ready=ready_kind;
            raw_metadata=bank_held^(75'd1<<bit_index); raw_data=36'(bit_index*137);
            check(); bit_rows=bit_rows+1;
          end
    // Exhaust every raw 9-bit position and both TLAST values, independently
    // of the first/interior/final private cursor and the phase/READY guards.
    for(phase=0;phase<2;phase=phase+1)
      for(cursor_kind=0;cursor_kind<3;cursor_kind=cursor_kind+1)
        for(ready_kind=0;ready_kind<2;ready_kind=ready_kind+1)
          for(position_kind=0;position_kind<512;position_kind=position_kind+1)
            for(last_kind=0;last_kind<2;last_kind=last_kind+1) begin
              bank_cursor=cursor_kind==0 ? 0 : cursor_kind==1 ? 17 : 511;
              defaults(); inverse_phase=phase; bank_blocked=!ready_kind; mailbox_input_ready=ready_kind;
              raw_position=9'(position_kind); raw_last=last_kind;
              raw_data=36'(position_kind*7919+last_kind); check(); position_rows=position_rows+1;
            end
    // Release only reason registers: exact same-edge and next-edge sticky
    // reason capture under intentionally fixed private snapshots, then reset.
    release dut.fault_reasons; release shadow.old_guard.fault_reasons;
    for(phase=0;phase<2;phase=phase+1) begin
      resetn=0; tick(); defaults(); inverse_phase=phase; bank_blocked=0; mailbox_input_ready=1;
      resetn=1; bank_sticky=1; core_status_tvalid=1; core_status_tdata=8'h87;
      core_event_frame_started=1; core_output_tvalid=1; core_output_tuser=24'hffffff;
      #0.01; expected_reasons=dut.faults_now;
      if ((expected_reasons & 8'h39) != 8'h39) $fatal(1,"FORWARD_REASON_STIMULUS_MISSING");
      tick(); check();
      if (fault_reasons !== expected_reasons || !protocol_fault || mailbox_input_valid ||
          forward_retirement_valid || mailbox_commit_valid)
        $fatal(1,"FORWARD_SAME_EDGE_REASONS_LOST");
      inverse_phase=!inverse_phase; bank_sticky=0; external_fault_now=1;
      core_status_tvalid=1; core_output_tvalid=1; core_event_frame_started=1;
      #0.01; expected_reasons=expected_reasons|dut.faults_now; tick(); check();
      if(fault_reasons !== expected_reasons || mailbox_input_valid || forward_retirement_valid || job_ready)
        $fatal(1,"FORWARD_NEXT_EDGE_ORPHAN_REASONS_LOST");
    end
    resetn=0; tick(); check();
    if(fault_reasons || mailbox_input_valid || mailbox_private_valid || forward_retirement_valid)
      $fatal(1,"FORWARD_EPOCH_RESET_NOT_PURGED");
    if(rows<13828 || bit_rows!=900 || position_rows!=12288 ||
        !forward_cycles || !inverse_current_faults || !sticky_forward_faults)
      $fatal(1,"FORWARD_SNAPSHOT_COVERAGE_MISSING rows=%0d",rows);
    $display("FORWARD_RETIREMENT_PASS enabled=%0d completed=%0d phase_input=%0d rows=%0d bit_rows=%0d position_rows=%0d checks=%0d real_mailbox_raw_wiring=1 frozen_full_old_outputs=1 snapshot_not_fft=1",ENABLED,COMPLETED,PHASE_INPUT,rows,bit_rows,position_rows,checks);
    $finish;
  end
endmodule
