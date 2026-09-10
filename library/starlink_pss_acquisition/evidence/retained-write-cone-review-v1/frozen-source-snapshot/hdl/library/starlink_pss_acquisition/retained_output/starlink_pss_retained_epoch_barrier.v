// SPDX-License-Identifier: GPL-2.0
// Additive common-epoch startup barrier. Never connect a local core reset.
`timescale 1ns/1ps
module starlink_pss_retained_epoch_barrier (
  input wire slow_clk, fast_clk, resetn, fft_resetn,
  input wire outer_slow_running, outer_fast_running,
  input wire slow_mailboxes_reset_idle, fast_mailboxes_reset_idle,
  output wire slow_running, fast_running
);
  // Nine state bits. The four historical outer synchronizers remain in top.
  wire raw_epoch_ok = resetn === 1'b1 && fft_resetn === 1'b1;
  reg [1:0] slow_purge_count, fast_purge_count;
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_purge_fast, fast_release_slow;
  reg fast_release;
  wire slow_purged = slow_purge_count == 2;
  assign fast_running = raw_epoch_ok && outer_fast_running && fast_release;
  assign slow_running = raw_epoch_ok && outer_slow_running && fast_release_slow[1];
  always @(posedge slow_clk or negedge raw_epoch_ok) begin
    if (!raw_epoch_ok) begin slow_purge_count <= 0; fast_release_slow <= 0; end
    else begin
      fast_release_slow <= {fast_release_slow[0], fast_release};
      if (!outer_slow_running) slow_purge_count <= 0;
      else if (!slow_purged && slow_mailboxes_reset_idle === 1'b1)
        slow_purge_count <= slow_purge_count + 1'b1;
    end
  end
  always @(posedge fast_clk or negedge raw_epoch_ok) begin
    if (!raw_epoch_ok) begin
      fast_purge_count <= 0; slow_purge_fast <= 0; fast_release <= 0;
    end else begin
      slow_purge_fast <= {slow_purge_fast[0], slow_purged};
      if (!outer_fast_running) fast_purge_count <= 0;
      else if (fast_purge_count != 2 && fast_mailboxes_reset_idle === 1'b1)
        fast_purge_count <= fast_purge_count + 1'b1;
      if (outer_fast_running && fast_purge_count == 2 && slow_purge_fast[1])
        fast_release <= 1;
    end
  end
endmodule
