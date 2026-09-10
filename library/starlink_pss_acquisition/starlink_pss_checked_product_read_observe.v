// SPDX-License-Identifier: GPL-2.0
// OFFLINE ONLY. Three private slots, two-edge offered-word check evidence.
// Default is inert, not a substitute for any production caller. No RAM/FFT.
// The common epoch, NEVER a per-transform core reset, owns this state.
`timescale 1ns/1ps
module starlink_pss_checked_product_read_observe #(
  parameter integer CHECKED_PRODUCT_READ = 0
) (
  input wire clk, resetn,
  input wire admit_valid,
  output wire admit_ready,
  input wire [1:0] admit_lease,
  input wire [74:0] admit_metadata,
  input wire raw_valid,
  output wire raw_ready,
  input wire [35:0] raw_data,
  input wire [8:0] raw_position,
  input wire raw_last,
  input wire [74:0] raw_metadata,
  input wire [1:0] raw_lease,
  input wire core_enable, core_ready,
  output wire core_valid,
  output wire [35:0] core_data,
  output wire [8:0] core_position,
  output wire core_last,
  output wire [74:0] core_metadata,
  // Independent real input guard's final certificate, not RAM prefetch ACK.
  input wire consumer_complete,
  input wire release_valid,
  input wire [1:0] release_lease,
  output wire release_ready, released,
  input wire [7:0] live_faults,
  output wire active, prefetched, final_consumed, drained,
  output wire private_take, core_take,
  // Narrow current checker evidence, excluding release-request validation to
  // avoid a release-valid feedback loop. The issuer must fence handoff too.
  output wire validation_fault_now,
  output wire token_fault_now, offer_fault_now,
  output wire head_valid,
  // Observation only: no current live/offer/READY dependency. A caller must
  // still check the separately exported current token and raw fault fences.
  output wire head_owned_good,
  output wire [1:0] head_lease,
  output wire [15:0] fault_events_now,
  output wire [15:0] fault_reasons,
  output wire fault_token_valid,
  output wire [8:0] fault_token_position,
  output wire [1:0] fault_token_lease
);
  initial if (CHECKED_PRODUCT_READ !== 0 && CHECKED_PRODUCT_READ !== 1)
    $fatal(1, "CHECKED_PRODUCT_READ must be zero or one");
  reg owned, complete;
  reg [74:0] descriptor;
  reg [1:0] lease;
  reg [9:0] issued, consumed;
  reg [1:0] head, tail;
  reg [2:0] count;
  reg [35:0] data_slot [0:2];
  reg [8:0] position_slot [0:2];
  reg last_slot [0:2];
  reg [1:0] lease_slot [0:2];
  reg [2:0] occupied, good;
  reg [24:0] equal_leaves;
  reg [4:0] equal_groups;
  reg [1:0] observed, taken;
  reg [2:0] bad0, bad1;
  reg [1:0] tag0, tag1, lease0, lease1;
  reg [8:0] position0, position1;
  reg [15:0] reasons;
  reg first_bad;
  reg [8:0] first_position;
  reg [1:0] first_lease;
  wire enabled = CHECKED_PRODUCT_READ && resetn;
  wire clean = reasons == 0;
  wire live_clean = live_faults === 8'b0;
  wire pipe_empty = observed == 0;
  wire [24:0] leaves_now;
  wire [4:0] groups_next;
  for (genvar i=0; i<25; i=i+1) begin : leaves
    assign leaves_now[i] = raw_metadata[3*i +: 3] === descriptor[3*i +: 3];
  end
  for (genvar i=0; i<5; i=i+1) begin : groups
    localparam integer N = i==4 ? 1 : 6;
    assign groups_next[i] = &equal_leaves[6*i +: N];
  end
  assign admit_ready = enabled && clean && !owned && count==0 && pipe_empty;
  wire admission = admit_valid === 1'b1 && admit_ready;
  wire admission_bad = admit_valid === 1'b1 &&
    (!admit_ready || ^{admit_metadata,admit_lease} === 1'bx);
  wire observed_now = enabled && owned && raw_valid === 1'b1;
  wire verdict_bad = observed[1] && ((|bad1) || !(&equal_groups));
  wire tag_bad = observed[1] && taken[1] && (tag1>2 || !occupied[tag1] ||
    good[tag1] || position_slot[tag1] !== position1 || lease_slot[tag1] !== lease1);
  wire head_bad = owned && count!=0 && (head>2 || !occupied[head] ||
    (good[head] && (position_slot[head] !== consumed[8:0] ||
      last_slot[head] !== (consumed==511) || lease_slot[head] !== lease)));
  wire closed_offer = raw_valid === 1'b1 && (!owned || issued==512);
  wire uncertain = owned && ((raw_valid !== 1'b0 && raw_valid !== 1'b1) ||
    (core_enable !== 1'b0 && core_enable !== 1'b1) ||
    (core_enable === 1'b1 && core_ready !== 1'b0 && core_ready !== 1'b1));
  wire [15:0] errors_now;
  assign errors_now[0] = observed[1] && bad1[0];
  assign errors_now[1] = observed[1] && bad1[1];
  assign errors_now[2] = observed[1] && !(&equal_groups);
  assign errors_now[3] = observed[1] && bad1[2];
  assign errors_now[4] = admission_bad;
  assign errors_now[5] = closed_offer;
  assign errors_now[6] = tag_bad || head_bad || count>3 ||
    (release_valid === 1'b1 && (!drained || release_lease !== lease));
  assign errors_now[7] = uncertain;
  for (genvar i=0; i<8; i=i+1) begin : live
    assign errors_now[i+8] = owned && live_faults[i] !== 1'b0;
  end
  wire current_clean = errors_now == 0;
  assign fault_events_now = errors_now;
  // Token evidence depends only on held/checker state. Offered-bus diagnostics
  // remain current too, but must not be fed back into the producer of raw_valid.
  assign token_fault_now = verdict_bad || tag_bad || head_bad || count>3;
  assign offer_fault_now = uncertain || closed_offer || admission_bad;
  assign validation_fault_now = token_fault_now || offer_fault_now;
  assign active = enabled && owned;
  assign raw_ready = enabled && owned && clean && live_clean && issued<512 &&
    (count<3 || core_take);
  assign private_take = raw_valid === 1'b1 && raw_ready;
  assign head_valid = enabled && owned && clean && live_clean && current_clean &&
    count!=0 && occupied[head] && good[head];
  assign head_owned_good = enabled && owned && clean &&
    count!=0 && occupied[head] && good[head];
  assign head_lease = lease_slot[head];
  assign core_valid = head_valid && core_enable;
  assign core_take = core_valid && core_ready === 1'b1;
  assign core_data = data_slot[head];
  assign core_position = position_slot[head];
  assign core_last = last_slot[head];
  // Only GOOD tokens may consume this canonical descriptor: the actual raw
  // word has already supplied its own all75-bit evidence, tagged to this slot.
  assign core_metadata = descriptor;
  assign prefetched = enabled && owned && count==3 && &good;
  assign final_consumed = enabled && complete;
  assign drained = enabled && owned && complete && consumer_complete && consumed==512 && issued==512 &&
    count==0 && pipe_empty;
  assign release_ready = drained && clean && live_clean && current_clean;
  assign released = release_valid === 1'b1 && release_ready && release_lease === lease;
  assign fault_reasons = reasons;
  assign fault_token_valid = first_bad;
  assign fault_token_position = first_position;
  assign fault_token_lease = first_lease;
  function [1:0] advance;
    input [1:0] p;
    begin advance = p==2 ? 0 : p+1'b1; end
  endfunction
  integer j;
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      owned<=0; complete<=0; descriptor<=0; lease<=0; issued<=0; consumed<=0;
      head<=0; tail<=0; count<=0; occupied<=0; good<=0;
      equal_leaves<=0; equal_groups<=0; observed<=0; taken<=0;
      bad0<=0; bad1<=0; tag0<=0; tag1<=0; lease0<=0; lease1<=0;
      position0<=0; position1<=0; reasons<=0; first_bad<=0;
      first_position<=0; first_lease<=0;
      for(j=0;j<3;j=j+1) begin
        data_slot[j]<=0; position_slot[j]<=0; last_slot[j]<=0; lease_slot[j]<=0;
      end
    end else if (CHECKED_PRODUCT_READ) begin
      reasons <= reasons | errors_now;
      // Observe every presented word, including full-queue stalls. Taken/tag
      // distinguish fault-only observations from verdicts owning payload slots.
      observed <= {observed[0], observed_now};
      taken <= {taken[0], private_take};
      if (observed_now) begin
        equal_leaves <= leaves_now;
        bad0 <= {raw_lease !== lease, raw_last !== (issued==511),
          raw_position !== issued[8:0]};
        tag0<=tail; lease0<=raw_lease; position0<=raw_position;
      end
      if (observed[0]) begin
        equal_groups<=groups_next; bad1<=bad0; tag1<=tag0;
        lease1<=lease0; position1<=position0;
      end
      if (verdict_bad && !first_bad) begin
        first_bad<=1; first_position<=position1; first_lease<=lease1;
      end
      if (observed[1] && taken[1] && !verdict_bad && !tag_bad && clean)
        good[tag1]<=1;
      if (admission && !admission_bad && live_clean) begin
        owned<=1; complete<=0; descriptor<=admit_metadata; lease<=admit_lease;
        issued<=0; consumed<=0; head<=0; tail<=0; count<=0; occupied<=0; good<=0;
      end
      if (core_take) begin
        occupied[head]<=0; good[head]<=0; head<=advance(head);
        consumed<=consumed+1'b1;
        if (core_last) complete<=1;
      end
      if (private_take) begin
        data_slot[tail]<=raw_data; position_slot[tail]<=raw_position;
        last_slot[tail]<=raw_last; lease_slot[tail]<=raw_lease;
        occupied[tail]<=1; good[tail]<=0; tail<=advance(tail); issued<=issued+1'b1;
      end
      case ({private_take,core_take})
        2'b10: count<=count+1'b1;
        2'b01: count<=count-1'b1;
        default: ;
      endcase
      if (released) owned<=0;
    end
  end
endmodule
