// Additive observation only: no signal drives either independent island.
`timescale 1ns/1fs
module starlink_pss_exact_control_actual_compare #(
  parameter integer WIDTH = 1
) (
  input wire clk,
  input wire [WIDTH-1:0] actual_public,
  input wire [WIDTH-1:0] reference_public,
  input wire actual_consume, reference_consume,
  input wire [63:0] actual_scratch, reference_scratch,
  input wire active_job, final_slot, current_fault,
  input wire owned_bank, stalled_bank, running,
  output integer checks = 0,
  output integer active_checks = 0,
  output integer consumed_identities = 0,
  output integer private_differences = 0,
  output integer final_fault_edges = 0,
  output integer owned_stall_edges = 0,
  output integer reset_owned_edges = 0
);
  // Before the active edge, compare the actual identity being consumed,
  // including malformed input. Do not infer it from an expected healthy row.
  always @(posedge clk) begin
    if (actual_consume !== reference_consume)
      $fatal(1, "EXACT_ACTUAL_CONSUME_MISMATCH");
    if (actual_consume) begin
      consumed_identities = consumed_identities + 1;
      if (actual_scratch !== reference_scratch)
        $fatal(1, "EXACT_ACTUAL_SCRATCH_CONSUMED_MISMATCH");
    end
    if (active_job && final_slot && current_fault) final_fault_edges = final_fault_edges + 1;
    if (owned_bank && stalled_bank) owned_stall_edges = owned_stall_edges + 1;
    if (!running && owned_bank) reset_owned_edges = reset_owned_edges + 1;
  end
  always @(posedge clk or negedge clk) begin
    // Existing stimulus uses1ps tick/force settlements. Observe after both
    // independently driven copies have settled, without delaying either one.
    #0.002;
    if (actual_public !== reference_public) begin
      tb_starlink_pss_fft_bank_owned_slice.exact_diagnose_mismatch();
      $fatal(1, "EXACT_ACTUAL_PUBLIC_REASON_OWNERSHIP_MISMATCH actual=%h old=%h", actual_public, reference_public);
    end
    tb_starlink_pss_fft_bank_owned_slice.exact_status_account();
    checks = checks + 1;
    if (active_job) active_checks = active_checks + 1;
    if (actual_scratch !== reference_scratch) private_differences = private_differences + 1;
  end
endmodule
