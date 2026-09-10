`timescale 1ns/1fs
module diagnostic_reference; reg[7:0] injected_status=9; integer test_kind=11,fast_cycle=29,slow_cycle=17,epoch=11;
reg clk=0,fft_clk=0,resetn=1,fft_resetn=1;
 endmodule
module tb_starlink_pss_fft_bank_owned_slice;
reg[7:0] injected_status=5; integer test_kind=11,fast_cycle=29,slow_cycle=17,epoch=11;
reg clk=0,fft_clk=0,resetn=1,fft_resetn=1;

always #3 clk=!clk;
diagnostic_reference exact_reference();
reg[69:0] a[0:216],b[0:216]; reg force_equal_low=0;
wire[216:0] matched;
genvar g; generate for(g=0;g<217;g=g+1) begin
assign matched[g]=(a[g]===b[g]); end endgenerate
wire equal_all=(&matched)&&!force_equal_low;
wire exact_public_equal=equal_all;
wire[31:0] checks,active_checks,consumed,differences,final_faults,stalls,resets;
starlink_pss_exact_control_actual_compare #(.WIDTH(1)) monitor(
.clk(clk),.actual_public(equal_all),.reference_public(1'b1),
.actual_consume(1'b0),.reference_consume(1'b0),.actual_scratch(64'b0),.reference_scratch(64'b0),
.active_job(1'b0),.final_slot(1'b0),.current_fault(1'b0),.owned_bank(1'b0),.stalled_bank(1'b0),.running(1'b0),
.checks(checks),.active_checks(active_checks),.consumed_identities(consumed),.private_differences(differences),
.final_fault_edges(final_faults),.owned_stall_edges(stalls),.reset_owned_edges(resets));
  // BEGIN EXACT_CONTROL_NAMED_DIAGNOSTIC
  task automatic exact_diagnose_mismatch;
    integer diagnostic_count;
    diagnostic_count = 0;
    $display("EXACT_DIAGNOSTIC_CONTEXT time=%0t fields=217", $realtime);
    $display("EXACT_DIAGNOSTIC_CONTEXT injected_status candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      injected_status, exact_reference.injected_status, injected_status, exact_reference.injected_status);
    $display("EXACT_DIAGNOSTIC_CONTEXT test_kind candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      test_kind, exact_reference.test_kind, test_kind, exact_reference.test_kind);
    $display("EXACT_DIAGNOSTIC_CONTEXT clk candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      clk, exact_reference.clk, clk, exact_reference.clk);
    $display("EXACT_DIAGNOSTIC_CONTEXT fft_clk candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      fft_clk, exact_reference.fft_clk, fft_clk, exact_reference.fft_clk);
    $display("EXACT_DIAGNOSTIC_CONTEXT fast_cycle candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      fast_cycle, exact_reference.fast_cycle, fast_cycle, exact_reference.fast_cycle);
    $display("EXACT_DIAGNOSTIC_CONTEXT slow_cycle candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      slow_cycle, exact_reference.slow_cycle, slow_cycle, exact_reference.slow_cycle);
    $display("EXACT_DIAGNOSTIC_CONTEXT epoch candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      epoch, exact_reference.epoch, epoch, exact_reference.epoch);
    $display("EXACT_DIAGNOSTIC_CONTEXT resetn candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      resetn, exact_reference.resetn, resetn, exact_reference.resetn);
    $display("EXACT_DIAGNOSTIC_CONTEXT fft_resetn candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
      fft_resetn, exact_reference.fft_resetn, fft_resetn, exact_reference.fft_resetn);
    if (a[0] !== b[0]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=resetn candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[0]), $bits(b[0]), a[0], b[0], a[0], b[0]);
    end
    if (a[1] !== b[1]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=fft_resetn candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[1]), $bits(b[1]), a[1], b[1], a[1], b[1]);
    end
    if (a[2] !== b[2]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[2]), $bits(b[2]), a[2], b[2], a[2], b[2]);
    end
    if (a[3] !== b[3]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[3]), $bits(b[3]), a[3], b[3], a[3], b[3]);
    end
    if (a[4] !== b[4]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[4]), $bits(b[4]), a[4], b[4], a[4], b[4]);
    end
    if (a[5] !== b[5]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[5]), $bits(b[5]), a[5], b[5], a[5], b[5]);
    end
    if (a[6] !== b[6]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_block_start candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[6]), $bits(b[6]), a[6], b[6], a[6], b[6]);
    end
    if (a[7] !== b[7]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[7]), $bits(b[7]), a[7], b[7], a[7], b[7]);
    end
    if (a[8] !== b[8]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[8]), $bits(b[8]), a[8], b[8], a[8], b[8]);
    end
    if (a[9] !== b[9]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[9]), $bits(b[9]), a[9], b[9], a[9], b[9]);
    end
    if (a[10] !== b[10]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[10]), $bits(b[10]), a[10], b[10], a[10], b[10]);
    end
    if (a[11] !== b[11]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[11]), $bits(b[11]), a[11], b[11], a[11], b[11]);
    end
    if (a[12] !== b[12]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[12]), $bits(b[12]), a[12], b[12], a[12], b[12]);
    end
    if (a[13] !== b[13]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=output_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[13]), $bits(b[13]), a[13], b[13], a[13], b[13]);
    end
    if (a[14] !== b[14]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[14]), $bits(b[14]), a[14], b[14], a[14], b[14]);
    end
    if (a[15] !== b[15]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=epoch candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[15]), $bits(b[15]), a[15], b[15], a[15], b[15]);
    end
    if (a[16] !== b[16]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=profile candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[16]), $bits(b[16]), a[16], b[16], a[16], b[16]);
    end
    if (a[17] !== b[17]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=expected_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[17]), $bits(b[17]), a[17], b[17], a[17], b[17]);
    end
    if (a[18] !== b[18]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=expected_results candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[18]), $bits(b[18]), a[18], b[18], a[18], b[18]);
    end
    if (a[19] !== b[19]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=injecting_readiness candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[19]), $bits(b[19]), a[19], b[19], a[19], b[19]);
    end
    if (a[20] !== b[20]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=reader_enable candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[20]), $bits(b[20]), a[20], b[20], a[20], b[20]);
    end
    if (a[21] !== b[21]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=allow_inverse_commit_before_late_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[21]), $bits(b[21]), a[21], b[21], a[21], b[21]);
    end
    if (a[22] !== b[22]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=allow_provisional_prefix_after_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[22]), $bits(b[22]), a[22], b[22], a[22], b[22]);
    end
    if (a[23] !== b[23]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.fast_running candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[23]), $bits(b[23]), a[23], b[23], a[23], b[23]);
    end
    if (a[24] !== b[24]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.slow_running candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[24]), $bits(b[24]), a[24], b[24], a[24], b[24]);
    end
    if (a[25] !== b[25]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.fast_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[25]), $bits(b[25]), a[25], b[25], a[25], b[25]);
    end
    if (a[26] !== b[26]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.state candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[26]), $bits(b[26]), a[26], b[26], a[26], b[26]);
    end
    if (a[27] !== b[27]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_release candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[27]), $bits(b[27]), a[27], b[27], a[27], b[27]);
    end
    if (a[28] !== b[28]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_job_start_private candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[28]), $bits(b[28]), a[28], b[28], a[28], b[28]);
    end
    if (a[29] !== b[29]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_job_start candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[29]), $bits(b[29]), a[29], b[29], a[29], b[29]);
    end
    if (a[30] !== b[30]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.next_inverse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[30]), $bits(b[30]), a[30], b[30], a[30], b[30]);
    end
    if (a[31] !== b[31]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.engine_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[31]), $bits(b[31]), a[31], b[31], a[31], b[31]);
    end
    if (a[32] !== b[32]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.engine_input_reserved candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[32]), $bits(b[32]), a[32], b[32], a[32], b[32]);
    end
    if (a[33] !== b[33]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.engine_output_reserved candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[33]), $bits(b[33]), a[33], b[33], a[33], b[33]);
    end
    if (a[34] !== b[34]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.forward_committed candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[34]), $bits(b[34]), a[34], b[34], a[34], b[34]);
    end
    if (a[35] !== b[35]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.held_phase candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[35]), $bits(b[35]), a[35], b[35], a[35], b[35]);
    end
    if (a[36] !== b[36]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.held_lease candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[36]), $bits(b[36]), a[36], b[36], a[36], b[36]);
    end
    if (a[37] !== b[37]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_consume_generation candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[37]), $bits(b[37]), a[37], b[37], a[37], b[37]);
    end
    if (a[38] !== b[38]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_consume_generation candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[38]), $bits(b[38]), a[38], b[38], a[38], b[38]);
    end
    if (a[39] !== b[39]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.descriptor_certified candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[39]), $bits(b[39]), a[39], b[39], a[39], b[39]);
    end
    if (a[40] !== b[40]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.admission_receipt candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[40]), $bits(b[40]), a[40], b[40], a[40], b[40]);
    end
    if (a[41] !== b[41]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.completion_receipt candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[41]), $bits(b[41]), a[41], b[41], a[41], b[41]);
    end
    if (a[42] !== b[42]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.expected_product_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[42]), $bits(b[42]), a[42], b[42], a[42], b[42]);
    end
    if (a[43] !== b[43]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.preparation_age candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[43]), $bits(b[43]), a[43], b[43], a[43], b[43]);
    end
    if (a[44] !== b[44]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.epoch_input_reasons candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[44]), $bits(b[44]), a[44], b[44], a[44], b[44]);
    end
    if (a[45] !== b[45]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.epoch_preflight_reasons candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[45]), $bits(b[45]), a[45], b[45], a[45], b[45]);
    end
    if (a[46] !== b[46]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_aresetn candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[46]), $bits(b[46]), a[46], b[46], a[46], b[46]);
    end
    if (a[47] !== b[47]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.config_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[47]), $bits(b[47]), a[47], b[47], a[47], b[47]);
    end
    if (a[48] !== b[48]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.config_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[48]), $bits(b[48]), a[48], b[48], a[48], b[48]);
    end
    if (a[49] !== b[49]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.engine_input_enable candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[49]), $bits(b[49]), a[49], b[49], a[49], b[49]);
    end
    if (a[50] !== b[50]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.job_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[50]), $bits(b[50]), a[50], b[50], a[50], b[50]);
    end
    if (a[51] !== b[51]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.job_accept candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[51]), $bits(b[51]), a[51], b[51], a[51], b[51]);
    end
    if (a[52] !== b[52]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_busy candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[52]), $bits(b[52]), a[52], b[52], a[52], b[52]);
    end
    if (a[53] !== b[53]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_commit candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[53]), $bits(b[53]), a[53], b[53], a[53], b[53]);
    end
    if (a[54] !== b[54]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[54]), $bits(b[54]), a[54], b[54], a[54], b[54]);
    end
    if (a[55] !== b[55]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[55]), $bits(b[55]), a[55], b[55], a[55], b[55]);
    end
    if (a[56] !== b[56]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_read_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[56]), $bits(b[56]), a[56], b[56], a[56], b[56]);
    end
    if (a[57] !== b[57]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[57]), $bits(b[57]), a[57], b[57], a[57], b[57]);
    end
    if (a[58] !== b[58]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[58]), $bits(b[58]), a[58], b[58], a[58], b[58]);
    end
    if (a[59] !== b[59]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[59]), $bits(b[59]), a[59], b[59], a[59], b[59]);
    end
    if (a[60] !== b[60]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[60]), $bits(b[60]), a[60], b[60], a[60], b[60]);
    end
    if (a[61] !== b[61]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[61]), $bits(b[61]), a[61], b[61], a[61], b[61]);
    end
    if (a[62] !== b[62]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_read_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[62]), $bits(b[62]), a[62], b[62], a[62], b[62]);
    end
    if (a[63] !== b[63]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[63]), $bits(b[63]), a[63], b[63], a[63], b[63]);
    end
    if (a[64] !== b[64]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[64]), $bits(b[64]), a[64], b[64], a[64], b[64]);
    end
    if (a[65] !== b[65]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[65]), $bits(b[65]), a[65], b[65], a[65], b[65]);
    end
    if (a[66] !== b[66]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[66]), $bits(b[66]), a[66], b[66], a[66], b[66]);
    end
    if (a[67] !== b[67]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.checked_input_complete candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[67]), $bits(b[67]), a[67], b[67], a[67], b[67]);
    end
    if (a[68] !== b[68]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.certified_input_beat candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[68]), $bits(b[68]), a[68], b[68], a[68], b[68]);
    end
    if (a[69] !== b[69]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.certified_input_complete candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[69]), $bits(b[69]), a[69], b[69], a[69], b[69]);
    end
    if (a[70] !== b[70]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[70]), $bits(b[70]), a[70], b[70], a[70], b[70]);
    end
    if (a[71] !== b[71]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[71]), $bits(b[71]), a[71], b[71], a[71], b[71]);
    end
    if (a[72] !== b[72]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_fault_events_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[72]), $bits(b[72]), a[72], b[72], a[72], b[72]);
    end
    if (a[73] !== b[73]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.duplicate_start_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[73]), $bits(b[73]), a[73], b[73], a[73], b[73]);
    end
    if (a[74] !== b[74]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_input_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[74]), $bits(b[74]), a[74], b[74], a[74], b[74]);
    end
    if (a[75] !== b[75]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_input_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[75]), $bits(b[75]), a[75], b[75], a[75], b[75]);
    end
    if (a[76] !== b[76]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[76]), $bits(b[76]), a[76], b[76], a[76], b[76]);
    end
    if (a[77] !== b[77]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_input_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[77]), $bits(b[77]), a[77], b[77], a[77], b[77]);
    end
    if (a[78] !== b[78]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_output_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[78]), $bits(b[78]), a[78], b[78], a[78], b[78]);
    end
    if (a[79] !== b[79]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_output_user candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[79]), $bits(b[79]), a[79], b[79], a[79], b[79]);
    end
    if (a[80] !== b[80]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[80]), $bits(b[80]), a[80], b[80], a[80], b[80]);
    end
    if (a[81] !== b[81]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_output_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[81]), $bits(b[81]), a[81], b[81], a[81], b[81]);
    end
    if (a[82] !== b[82]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_status_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[82]), $bits(b[82]), a[82], b[82], a[82], b[82]);
    end
    if (a[83] !== b[83]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.core_status_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[83]), $bits(b[83]), a[83], b[83], a[83], b[83]);
    end
    if (a[84] !== b[84]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.event_frame candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[84]), $bits(b[84]), a[84], b[84], a[84], b[84]);
    end
    if (a[85] !== b[85]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.event_last_unexpected candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[85]), $bits(b[85]), a[85], b[85], a[85], b[85]);
    end
    if (a[86] !== b[86]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.event_last_missing candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[86]), $bits(b[86]), a[86], b[86], a[86], b[86]);
    end
    if (a[87] !== b[87]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.event_input_halt candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[87]), $bits(b[87]), a[87], b[87], a[87], b[87]);
    end
    if (a[88] !== b[88]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[88]), $bits(b[88]), a[88], b[88], a[88], b[88]);
    end
    if (a[89] !== b[89]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_private_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[89]), $bits(b[89]), a[89], b[89], a[89], b[89]);
    end
    if (a[90] !== b[90]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_commit_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[90]), $bits(b[90]), a[90], b[90], a[90], b[90]);
    end
    if (a[91] !== b[91]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[91]), $bits(b[91]), a[91], b[91], a[91], b[91]);
    end
    if (a[92] !== b[92]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[92]), $bits(b[92]), a[92], b[92], a[92], b[92]);
    end
    if (a[93] !== b[93]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[93]), $bits(b[93]), a[93], b[93], a[93], b[93]);
    end
    if (a[94] !== b[94]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.return_metadata candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[94]), $bits(b[94]), a[94], b[94], a[94], b[94]);
    end
    if (a[95] !== b[95]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.forward_retirement_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[95]), $bits(b[95]), a[95], b[95], a[95], b[95]);
    end
    if (a[96] !== b[96]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.external_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[96]), $bits(b[96]), a[96], b[96], a[96], b[96]);
    end
    if (a[97] !== b[97]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.any_fast_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[97]), $bits(b[97]), a[97], b[97], a[97], b[97]);
    end
    if (a[98] !== b[98]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.preflight_events_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[98]), $bits(b[98]), a[98], b[98], a[98], b[98]);
    end
    if (a[99] !== b[99]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.preparation_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[99]), $bits(b[99]), a[99], b[99], a[99], b[99]);
    end
    if (a[100] !== b[100]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.final_fence candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[100]), $bits(b[100]), a[100], b[100], a[100], b[100]);
    end
    if (a[101] !== b[101]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.completed_input_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[101]), $bits(b[101]), a[101], b[101], a[101], b[101]);
    end
    if (a[102] !== b[102]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.forward_handoff_ack candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[102]), $bits(b[102]), a[102], b[102], a[102], b[102]);
    end
    if (a[103] !== b[103]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.forward_handoff_identity candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[103]), $bits(b[103]), a[103], b[103], a[103], b[103]);
    end
    if (a[104] !== b[104]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.handoff_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[104]), $bits(b[104]), a[104], b[104], a[104], b[104]);
    end
    if (a[105] !== b[105]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_destination_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[105]), $bits(b[105]), a[105], b[105], a[105], b[105]);
    end
    if (a[106] !== b[106]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_commit_authorized candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[106]), $bits(b[106]), a[106], b[106], a[106], b[106]);
    end
    if (a[107] !== b[107]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[107]), $bits(b[107]), a[107], b[107], a[107], b[107]);
    end
    if (a[108] !== b[108]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[108]), $bits(b[108]), a[108], b[108], a[108], b[108]);
    end
    if (a[109] !== b[109]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank_framing_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[109]), $bits(b[109]), a[109], b[109], a[109], b[109]);
    end
    if (a[110] !== b[110]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[110]), $bits(b[110]), a[110], b[110], a[110], b[110]);
    end
    if (a[111] !== b[111]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[111]), $bits(b[111]), a[111], b[111], a[111], b[111]);
    end
    if (a[112] !== b[112]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank_framing_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[112]), $bits(b[112]), a[112], b[112], a[112], b[112]);
    end
    if (a[113] !== b[113]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_overflow candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[113]), $bits(b[113]), a[113], b[113], a[113], b[113]);
    end
    if (a[114] !== b[114]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.active_private candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[114]), $bits(b[114]), a[114], b[114], a[114], b[114]);
    end
    if (a[115] !== b[115]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.awaiting_ack candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[115]), $bits(b[115]), a[115], b[115], a[115], b[115]);
    end
    if (a[116] !== b[116]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.descriptor candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[116]), $bits(b[116]), a[116], b[116], a[116], b[116]);
    end
    if (a[117] !== b[117]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.input_count candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[117]), $bits(b[117]), a[117], b[117], a[117], b[117]);
    end
    if (a[118] !== b[118]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.output_count candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[118]), $bits(b[118]), a[118], b[118], a[118], b[118]);
    end
    if (a[119] !== b[119]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.input_complete_seen candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[119]), $bits(b[119]), a[119], b[119], a[119], b[119]);
    end
    if (a[120] !== b[120]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.frame_seen candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[120]), $bits(b[120]), a[120], b[120], a[120], b[120]);
    end
    if (a[121] !== b[121]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.status_seen candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[121]), $bits(b[121]), a[121], b[121], a[121], b[121]);
    end
    if (a[122] !== b[122]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.exponent_seen candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[122]), $bits(b[122]), a[122], b[122], a[122], b[122]);
    end
    if (a[123] !== b[123]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.status_exponent candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[123]), $bits(b[123]), a[123], b[123], a[123], b[123]);
    end
    if (a[124] !== b[124]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.output_exponent candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[124]), $bits(b[124]), a[124], b[124], a[124], b[124]);
    end
    if (a[125] !== b[125]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.age candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[125]), $bits(b[125]), a[125], b[125], a[125], b[125]);
    end
    if (a[126] !== b[126]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.return_occupied candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[126]), $bits(b[126]), a[126], b[126], a[126], b[126]);
    end
    if (a[127] !== b[127]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.return_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[127]), $bits(b[127]), a[127], b[127], a[127], b[127]);
    end
    if (a[128] !== b[128]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.return_data candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[128]), $bits(b[128]), a[128], b[128], a[128], b[128]);
    end
    if (a[129] !== b[129]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.return_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[129]), $bits(b[129]), a[129], b[129], a[129], b[129]);
    end
    if (a[130] !== b[130]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.return_exponent candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[130]), $bits(b[130]), a[130], b[130], a[130], b[130]);
    end
    if (a[131] !== b[131]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.fault_reasons candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[131]), $bits(b[131]), a[131], b[131], a[131], b[131]);
    end
    if (a[132] !== b[132]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.result_guard.faults_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[132]), $bits(b[132]), a[132], b[132], a[132], b[132]);
    end
    if (a[133] !== b[133]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.job_started candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[133]), $bits(b[133]), a[133], b[133], a[133], b[133]);
    end
    if (a[134] !== b[134]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.input_started candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[134]), $bits(b[134]), a[134], b[134], a[134], b[134]);
    end
    if (a[135] !== b[135]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.descriptor candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[135]), $bits(b[135]), a[135], b[135], a[135], b[135]);
    end
    if (a[136] !== b[136]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.expected_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[136]), $bits(b[136]), a[136], b[136], a[136], b[136]);
    end
    if (a[137] !== b[137]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.input_complete candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[137]), $bits(b[137]), a[137], b[137], a[137], b[137]);
    end
    if (a[138] !== b[138]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.fault_reasons candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[138]), $bits(b[138]), a[138], b[138], a[138], b[138]);
    end
    if (a[139] !== b[139]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.slot_open candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[139]), $bits(b[139]), a[139], b[139], a[139], b[139]);
    end
    if (a[140] !== b[140]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.fault_events_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[140]), $bits(b[140]), a[140], b[140], a[140], b[140]);
    end
    if (a[141] !== b[141]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.core_input_tvalid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[141]), $bits(b[141]), a[141], b[141], a[141], b[141]);
    end
    if (a[142] !== b[142]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.certified_input_beat candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[142]), $bits(b[142]), a[142], b[142], a[142], b[142]);
    end
    if (a[143] !== b[143]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.input_guard.certified_input_complete candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[143]), $bits(b[143]), a[143], b[143], a[143], b[143]);
    end
    if (a[144] !== b[144]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.expected_bin_index candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[144]), $bits(b[144]), a[144], b[144], a[144], b[144]);
    end
    if (a[145] !== b[145]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.block_exponent candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[145]), $bits(b[145]), a[145], b[145], a[145], b[145]);
    end
    if (a[146] !== b[146]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.block_start_index candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[146]), $bits(b[146]), a[146], b[146], a[146], b[146]);
    end
    if (a[147] !== b[147]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.have_previous_block candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[147]), $bits(b[147]), a[147], b[147], a[147], b[147]);
    end
    if (a[148] !== b[148]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_kernel_word candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[148]), $bits(b[148]), a[148], b[148], a[148], b[148]);
    end
    if (a[149] !== b[149]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[149]), $bits(b[149]), a[149], b[149], a[149], b[149]);
    end
    if (a[150] !== b[150]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_bin_index candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[150]), $bits(b[150]), a[150], b[150], a[150], b[150]);
    end
    if (a[151] !== b[151]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_block_exponent candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[151]), $bits(b[151]), a[151], b[151], a[151], b[151]);
    end
    if (a[152] !== b[152]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_last candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[152]), $bits(b[152]), a[152], b[152], a[152], b[152]);
    end
    if (a[153] !== b[153]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.output_block_start_index candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[153]), $bits(b[153]), a[153], b[153], a[153], b[153]);
    end
    if (a[154] !== b[154]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.accepted_pulse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[154]), $bits(b[154]), a[154], b[154], a[154], b[154]);
    end
    if (a[155] !== b[155]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.emitted_pulse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[155]), $bits(b[155]), a[155], b[155], a[155], b[155]);
    end
    if (a[156] !== b[156]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.input_block_complete_pulse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[156]), $bits(b[156]), a[156], b[156], a[156], b[156]);
    end
    if (a[157] !== b[157]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.sequence_error_pulse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[157]), $bits(b[157]), a[157], b[157], a[157], b[157]);
    end
    if (a[158] !== b[158]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.metadata_error_pulse candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[158]), $bits(b[158]), a[158], b[158], a[158], b[158]);
    end
    if (a[159] !== b[159]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.protocol_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[159]), $bits(b[159]), a[159], b[159], a[159], b[159]);
    end
    if (a[160] !== b[160]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[160]), $bits(b[160]), a[160], b[160], a[160], b[160]);
    end
    if (a[161] !== b[161]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.input_accept candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[161]), $bits(b[161]), a[161], b[161], a[161], b[161]);
    end
    if (a[162] !== b[162]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.joiner.kernel_rom.protocol_error_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[162]), $bits(b[162]), a[162], b[162], a[162], b[162]);
    end
    if (a[163] !== b[163]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.request_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[163]), $bits(b[163]), a[163], b[163], a[163], b[163]);
    end
    if (a[164] !== b[164]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.acknowledge_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[164]), $bits(b[164]), a[164], b[164], a[164], b[164]);
    end
    if (a[165] !== b[165]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.request_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[165]), $bits(b[165]), a[165], b[165], a[165], b[165]);
    end
    if (a[166] !== b[166]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.acknowledge_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[166]), $bits(b[166]), a[166], b[166], a[166], b[166]);
    end
    if (a[167] !== b[167]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.metadata_in_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[167]), $bits(b[167]), a[167], b[167], a[167], b[167]);
    end
    if (a[168] !== b[168]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.metadata_out_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[168]), $bits(b[168]), a[168], b[168], a[168], b[168]);
    end
    if (a[169] !== b[169]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.write_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[169]), $bits(b[169]), a[169], b[169], a[169], b[169]);
    end
    if (a[170] !== b[170]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.reading candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[170]), $bits(b[170]), a[170], b[170], a[170], b[170]);
    end
    if (a[171] !== b[171]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.read_all_loaded candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[171]), $bits(b[171]), a[171], b[171], a[171], b[171]);
    end
    if (a[172] !== b[172]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.read_address candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[172]), $bits(b[172]), a[172], b[172], a[172], b[172]);
    end
    if (a[173] !== b[173]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.read_output_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[173]), $bits(b[173]), a[173], b[173], a[173], b[173]);
    end
    if (a[174] !== b[174]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.read_payload candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[174]), $bits(b[174]), a[174], b[174], a[174], b[174]);
    end
    if (a[175] !== b[175]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.read_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[175]), $bits(b[175]), a[175], b[175], a[175], b[175]);
    end
    if (a[176] !== b[176]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[176]), $bits(b[176]), a[176], b[176], a[176], b[176]);
    end
    if (a[177] !== b[177]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.input_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[177]), $bits(b[177]), a[177], b[177], a[177], b[177]);
    end
    if (a[178] !== b[178]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.input_framing_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[178]), $bits(b[178]), a[178], b[178], a[178], b[178]);
    end
    if (a[179] !== b[179]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[179]), $bits(b[179]), a[179], b[179], a[179], b[179]);
    end
    if (a[180] !== b[180]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.source_bank.output_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[180]), $bits(b[180]), a[180], b[180], a[180], b[180]);
    end
    if (a[181] !== b[181]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.request_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[181]), $bits(b[181]), a[181], b[181], a[181], b[181]);
    end
    if (a[182] !== b[182]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.acknowledge_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[182]), $bits(b[182]), a[182], b[182], a[182], b[182]);
    end
    if (a[183] !== b[183]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.request_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[183]), $bits(b[183]), a[183], b[183], a[183], b[183]);
    end
    if (a[184] !== b[184]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.acknowledge_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[184]), $bits(b[184]), a[184], b[184], a[184], b[184]);
    end
    if (a[185] !== b[185]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.metadata_in_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[185]), $bits(b[185]), a[185], b[185], a[185], b[185]);
    end
    if (a[186] !== b[186]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.metadata_out_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[186]), $bits(b[186]), a[186], b[186], a[186], b[186]);
    end
    if (a[187] !== b[187]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.write_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[187]), $bits(b[187]), a[187], b[187], a[187], b[187]);
    end
    if (a[188] !== b[188]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.reading candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[188]), $bits(b[188]), a[188], b[188], a[188], b[188]);
    end
    if (a[189] !== b[189]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.read_all_loaded candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[189]), $bits(b[189]), a[189], b[189], a[189], b[189]);
    end
    if (a[190] !== b[190]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.read_address candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[190]), $bits(b[190]), a[190], b[190], a[190], b[190]);
    end
    if (a[191] !== b[191]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.read_output_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[191]), $bits(b[191]), a[191], b[191], a[191], b[191]);
    end
    if (a[192] !== b[192]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.read_payload candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[192]), $bits(b[192]), a[192], b[192], a[192], b[192]);
    end
    if (a[193] !== b[193]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.read_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[193]), $bits(b[193]), a[193], b[193], a[193], b[193]);
    end
    if (a[194] !== b[194]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[194]), $bits(b[194]), a[194], b[194], a[194], b[194]);
    end
    if (a[195] !== b[195]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.input_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[195]), $bits(b[195]), a[195], b[195], a[195], b[195]);
    end
    if (a[196] !== b[196]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.input_framing_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[196]), $bits(b[196]), a[196], b[196], a[196], b[196]);
    end
    if (a[197] !== b[197]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[197]), $bits(b[197]), a[197], b[197], a[197], b[197]);
    end
    if (a[198] !== b[198]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.product_bank.output_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[198]), $bits(b[198]), a[198], b[198], a[198], b[198]);
    end
    if (a[199] !== b[199]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.request_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[199]), $bits(b[199]), a[199], b[199], a[199], b[199]);
    end
    if (a[200] !== b[200]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.acknowledge_toggle candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[200]), $bits(b[200]), a[200], b[200], a[200], b[200]);
    end
    if (a[201] !== b[201]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.request_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[201]), $bits(b[201]), a[201], b[201], a[201], b[201]);
    end
    if (a[202] !== b[202]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.acknowledge_sync candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[202]), $bits(b[202]), a[202], b[202], a[202], b[202]);
    end
    if (a[203] !== b[203]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.metadata_in_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[203]), $bits(b[203]), a[203], b[203], a[203], b[203]);
    end
    if (a[204] !== b[204]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.metadata_out_hold candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[204]), $bits(b[204]), a[204], b[204], a[204], b[204]);
    end
    if (a[205] !== b[205]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.write_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[205]), $bits(b[205]), a[205], b[205], a[205], b[205]);
    end
    if (a[206] !== b[206]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.reading candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[206]), $bits(b[206]), a[206], b[206], a[206], b[206]);
    end
    if (a[207] !== b[207]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.read_all_loaded candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[207]), $bits(b[207]), a[207], b[207], a[207], b[207]);
    end
    if (a[208] !== b[208]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.read_address candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[208]), $bits(b[208]), a[208], b[208], a[208], b[208]);
    end
    if (a[209] !== b[209]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.read_output_position candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[209]), $bits(b[209]), a[209], b[209], a[209], b[209]);
    end
    if (a[210] !== b[210]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.read_payload candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[210]), $bits(b[210]), a[210], b[210], a[210], b[210]);
    end
    if (a[211] !== b[211]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.read_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[211]), $bits(b[211]), a[211], b[211], a[211], b[211]);
    end
    if (a[212] !== b[212]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.input_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[212]), $bits(b[212]), a[212], b[212], a[212], b[212]);
    end
    if (a[213] !== b[213]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.input_fault candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[213]), $bits(b[213]), a[213], b[213], a[213], b[213]);
    end
    if (a[214] !== b[214]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.input_framing_fault_now candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[214]), $bits(b[214]), a[214], b[214], a[214], b[214]);
    end
    if (a[215] !== b[215]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.output_valid candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[215]), $bits(b[215]), a[215], b[215], a[215], b[215]);
    end
    if (a[216] !== b[216]) begin
      diagnostic_count = diagnostic_count + 1;
      $display("EXACT_DIAGNOSTIC_FIELD name=dut.output_bank.output_ready candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",
        $bits(a[216]), $bits(b[216]), a[216], b[216], a[216], b[216]);
    end
    $display("EXACT_DIAGNOSTIC_TERMINAL mismatches=%0d original_equal=%b fresh_equal=%b",
      diagnostic_count, exact_public_equal, ({a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27], a[28], a[29], a[30], a[31], a[32], a[33], a[34], a[35], a[36], a[37], a[38], a[39], a[40], a[41], a[42], a[43], a[44], a[45], a[46], a[47], a[48], a[49], a[50], a[51], a[52], a[53], a[54], a[55], a[56], a[57], a[58], a[59], a[60], a[61], a[62], a[63], a[64], a[65], a[66], a[67], a[68], a[69], a[70], a[71], a[72], a[73], a[74], a[75], a[76], a[77], a[78], a[79], a[80], a[81], a[82], a[83], a[84], a[85], a[86], a[87], a[88], a[89], a[90], a[91], a[92], a[93], a[94], a[95], a[96], a[97], a[98], a[99], a[100], a[101], a[102], a[103], a[104], a[105], a[106], a[107], a[108], a[109], a[110], a[111], a[112], a[113], a[114], a[115], a[116], a[117], a[118], a[119], a[120], a[121], a[122], a[123], a[124], a[125], a[126], a[127], a[128], a[129], a[130], a[131], a[132], a[133], a[134], a[135], a[136], a[137], a[138], a[139], a[140], a[141], a[142], a[143], a[144], a[145], a[146], a[147], a[148], a[149], a[150], a[151], a[152], a[153], a[154], a[155], a[156], a[157], a[158], a[159], a[160], a[161], a[162], a[163], a[164], a[165], a[166], a[167], a[168], a[169], a[170], a[171], a[172], a[173], a[174], a[175], a[176], a[177], a[178], a[179], a[180], a[181], a[182], a[183], a[184], a[185], a[186], a[187], a[188], a[189], a[190], a[191], a[192], a[193], a[194], a[195], a[196], a[197], a[198], a[199], a[200], a[201], a[202], a[203], a[204], a[205], a[206], a[207], a[208], a[209], a[210], a[211], a[212], a[213], a[214], a[215], a[216]} === {b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15], b[16], b[17], b[18], b[19], b[20], b[21], b[22], b[23], b[24], b[25], b[26], b[27], b[28], b[29], b[30], b[31], b[32], b[33], b[34], b[35], b[36], b[37], b[38], b[39], b[40], b[41], b[42], b[43], b[44], b[45], b[46], b[47], b[48], b[49], b[50], b[51], b[52], b[53], b[54], b[55], b[56], b[57], b[58], b[59], b[60], b[61], b[62], b[63], b[64], b[65], b[66], b[67], b[68], b[69], b[70], b[71], b[72], b[73], b[74], b[75], b[76], b[77], b[78], b[79], b[80], b[81], b[82], b[83], b[84], b[85], b[86], b[87], b[88], b[89], b[90], b[91], b[92], b[93], b[94], b[95], b[96], b[97], b[98], b[99], b[100], b[101], b[102], b[103], b[104], b[105], b[106], b[107], b[108], b[109], b[110], b[111], b[112], b[113], b[114], b[115], b[116], b[117], b[118], b[119], b[120], b[121], b[122], b[123], b[124], b[125], b[126], b[127], b[128], b[129], b[130], b[131], b[132], b[133], b[134], b[135], b[136], b[137], b[138], b[139], b[140], b[141], b[142], b[143], b[144], b[145], b[146], b[147], b[148], b[149], b[150], b[151], b[152], b[153], b[154], b[155], b[156], b[157], b[158], b[159], b[160], b[161], b[162], b[163], b[164], b[165], b[166], b[167], b[168], b[169], b[170], b[171], b[172], b[173], b[174], b[175], b[176], b[177], b[178], b[179], b[180], b[181], b[182], b[183], b[184], b[185], b[186], b[187], b[188], b[189], b[190], b[191], b[192], b[193], b[194], b[195], b[196], b[197], b[198], b[199], b[200], b[201], b[202], b[203], b[204], b[205], b[206], b[207], b[208], b[209], b[210], b[211], b[212], b[213], b[214], b[215], b[216]}));
  endtask
  // END EXACT_CONTROL_NAMED_DIAGNOSTIC

integer i;
initial begin
for(i=0;i<217;i=i+1) begin a[i]=0;b[i]=0;end
#7; a[82]=70'b1<<69;
#20;$display("DIAGNOSTIC_HEALTHY_FIXTURE_PASS no_fft=1");$finish;
end
endmodule
