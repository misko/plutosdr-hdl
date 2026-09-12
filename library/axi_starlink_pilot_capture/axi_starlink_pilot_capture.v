// SPDX-License-Identifier: GPL-2.0
// Experimental fixed-frequency paired pilot capture. See CAPTURE_ABI.md.
`timescale 1ns/1ps
module axi_starlink_pilot_capture #(
  parameter integer INPUT_RATE_MSPS = 15,
  parameter integer OUTPUT_FIFO_BITS = 5,
  // Distinct C251 ABI: already centered 2.5 MS/s, no hidden DDC/filter.
  // Wider source profiles must not use this bypass without a qualified filter.
  parameter integer COARSE25_BYPASS = 0
) (
  input wire s_axi_aclk,
  input wire s_axi_aresetn,
  input wire s_axi_awvalid,
  input wire [7:0] s_axi_awaddr,
  output wire s_axi_awready,
  input wire [31:0] s_axi_wdata,
  input wire [3:0] s_axi_wstrb,
  input wire s_axi_wvalid,
  output wire s_axi_wready,
  output wire s_axi_bvalid,
  output wire [1:0] s_axi_bresp,
  input wire s_axi_bready,
  input wire s_axi_arvalid,
  input wire [7:0] s_axi_araddr,
  output wire s_axi_arready,
  output wire s_axi_rvalid,
  output wire [31:0] s_axi_rdata,
  output wire [1:0] s_axi_rresp,
  input wire s_axi_rready,
  input wire [2:0] s_axi_awprot,
  input wire [2:0] s_axi_arprot,
  input wire canonical_valid,
  input wire canonical_gap,
  input wire canonical_flush,
  input wire signed [15:0] canonical_i,
  input wire signed [15:0] canonical_q,
  input wire [63:0] canonical_index,
  output wire pilot_enable,
  output wire m_axis_tvalid,
  output wire [31:0] m_axis_tdata,
  input wire m_axis_tready,
  output wire irq
);
  localparam integer FIFO_DEPTH = 1 << OUTPUT_FIFO_BITS;
  localparam integer INDEX_STEP = COARSE25_BYPASS ? 1 : 6;
  localparam integer SOURCE_RATE_HZ = COARSE25_BYPASS ? 2500000 : INPUT_RATE_MSPS * 1000000;
  generate
    if (COARSE25_BYPASS != 0 && COARSE25_BYPASS != 1) begin : g_bad_mode
      initial $fatal(1, "COARSE25_BYPASS must be 0 or 1");
    end
    if (INPUT_RATE_MSPS != 15 && INPUT_RATE_MSPS != 30 && INPUT_RATE_MSPS != 60) begin : g_bad_rate
      initial $fatal(1, "pilot source rate must be 15/30/60");
    end
    if (OUTPUT_FIFO_BITS < 2 || OUTPUT_FIFO_BITS > 8) begin : g_bad_fifo
      initial $fatal(1, "pilot output FIFO bits must be 2..8");
    end
  endgenerate

  wire wreq, rreq;
  wire [5:0] waddr, raddr;
  wire [31:0] wdata;
  wire [3:0] wstrb;
  reg wack, rack;
  reg [31:0] rdata;
  starlink_pss_axi_lite bus (
    .clk(s_axi_aclk), .resetn(s_axi_aresetn),
    .s_axi_awvalid(s_axi_awvalid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awready(s_axi_awready),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wready(s_axi_wready), .s_axi_bvalid(s_axi_bvalid), .s_axi_bresp(s_axi_bresp),
    .s_axi_bready(s_axi_bready), .s_axi_arvalid(s_axi_arvalid), .s_axi_araddr(s_axi_araddr),
    .s_axi_arready(s_axi_arready), .s_axi_rvalid(s_axi_rvalid), .s_axi_rresp(s_axi_rresp),
    .s_axi_rdata(s_axi_rdata), .s_axi_rready(s_axi_rready),
    .up_wreq(wreq), .up_waddr(waddr), .up_wdata(wdata), .up_wstrb(wstrb), .up_wack(wack),
    .up_rreq(rreq), .up_raddr(raddr), .up_rdata(rdata), .up_rack(rack)
  );

  reg active, used;
  reg [31:0] visit_id, sample_limit, faults;
  reg [63:0] admitted, delivered, unsupported, first_index, last_index, lost_index;
  reg [OUTPUT_FIFO_BITS-1:0] wr_pointer, rd_pointer;
  reg [OUTPUT_FIFO_BITS:0] fifo_count, fifo_high_water;
  (* ram_style = "distributed" *) reg [31:0] fifo [0:FIFO_DEPTH-1];
  wire empty = fifo_count == 0;
  // Decode the slow control word BEFORE the capture/DDC admission boundary.
  // Otherwise a 32-bit command comparison feeds several levels of immediate
  // fault/flush checks and every downstream RAM write enable in one cycle.
  // The AXI helper is single-outstanding and holds wdata until our delayed
  // acknowledgement, so configuration payloads need no second 32-bit copy.
  wire command = waddr == 6'h02 && wstrb == 4'hf;
  reg write_pending;
  reg arm_request, stop_request, clear_request;
  // Local replication only: the full receiver measured 649 loads and 12.649 ns
  // of wire delay on this snapshot-enable net. Copies retain the same decode,
  // reset and capture edge; no pipeline stage or relaxed timing is introduced.
  (* max_fanout = 32 *) reg snapshot_request;
  reg visit_request, limit_request;
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      write_pending <= 0;
      arm_request <= 0;
      stop_request <= 0;
      clear_request <= 0;
      snapshot_request <= 0;
      visit_request <= 0;
      limit_request <= 0;
    end else begin
      write_pending <= wreq;
      arm_request <= wreq && command && wdata == 1;
      stop_request <= wreq && command && wdata == 2;
      clear_request <= wreq && command && wdata == 4;
      snapshot_request <= wreq && command && wdata == 8;
      visit_request <= wreq && waddr == 6'h08 && wstrb == 4'hf;
      limit_request <= wreq && waddr == 6'h27 && wstrb == 4'hf;
    end
  end
  // Decide legality at the original command edge, but execute an accepted
  // CLEAR from a registered token. The FIFO-empty comparator must not drive
  // the DDC's high-fanout reset/run/flush tree combinationally. The AXI helper
  // holds this write outstanding until commit; inactive + empty therefore
  // stays quiescent and no ARM/configuration/SNAPSHOT can interleave.
  wire clear_admit = clear_request && !active && empty;
  reg clear_ok;
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) clear_ok <= 0;
    else clear_ok <= clear_admit;
  end
  wire arm_ok = arm_request && !active && !used && empty && faults == 0 && visit_id != 0;
  wire visit_write = visit_request && !active && !used && empty;
  wire limit_write = limit_request && !active && !used && empty;
  wire bad_write = write_pending && !(arm_ok || stop_request || clear_admit || snapshot_request || visit_write || limit_write);
  // During capture only STOP and SNAPSHOT are legal. Keep that small decode
  // separate from inactive ARM eligibility (sticky faults, visit, FIFO, used),
  // which must not feed through DDC flush into every active output admission.
  // bad_write still supplies the complete sticky diagnostic in every state.
  wire active_bad_write = write_pending && !(stop_request || snapshot_request);
  wire ddc_valid, ddc_support, ddc_halted;
  wire signed [15:0] ddc_i, ddc_q;
  wire [63:0] ddc_index, ddc_accepted, ddc_emitted;
  wire [31:0] ddc_visit, ddc_clips;
  wire [7:0] ddc_fault, ddc_high_water;

  // Separate the DDC's same-cycle fail-closed validation from capture FIFO
  // admission. Register the complete observation, not just its valid bit:
  // the absolute source coordinate and support/visit tags travel with the IQ.
  // Payload is speculative and needs no reset/enable tree; only the token
  // makes it meaningful. This adds one fabric clock, not one signal sample.
  reg capture_valid, capture_support;
  reg [31:0] capture_data, capture_visit;
  reg [63:0] capture_index;
  always @(posedge s_axi_aclk) begin
    capture_data <= {ddc_q, ddc_i};
    capture_index <= ddc_index;
    capture_visit <= ddc_visit;
    capture_support <= ddc_support;
    if (!s_axi_aresetn || clear_ok) capture_valid <= 0;
    else capture_valid <= ddc_valid;
  end

  // Valid/data stay asserted and stable under backpressure, including STOP or
  // fault. Those operations stop admission, not an already promised AXIS beat.
  assign m_axis_tvalid = s_axi_aresetn && !empty;
  assign m_axis_tdata = fifo[rd_pointer];
  wire pop = m_axis_tvalid && m_axis_tready;
  // Termination discards an unpromised staged word. Do not diagnose its FIFO,
  // index or counter eligibility after STOP/source cancellation has won.
  // These are short current control gates, not a return through DDC validation.
  wire observation_run = source_run && !canonical_gap && !ddc_halted;
  wire eligible = observation_run && capture_valid && capture_support;
  wire overflow = eligible && fifo_count == FIFO_DEPTH && !pop;
  wire bad_index = eligible && ((admitted != 0 &&
      (last_index > 64'hffffffffffffffff - INDEX_STEP ||
       capture_index != last_index + INDEX_STEP)) ||
      capture_visit != visit_id);
  wire exhausted = (eligible && (&admitted)) || (pop && (&delivered)) ||
      (observation_run && capture_valid && !capture_support && (&unsupported));
  wire [31:0] faults_now = {25'd0, exhausted, bad_write,
      active && canonical_flush, bad_index, overflow,
      active && canonical_gap, active && ddc_halted};
  wire active_fault_now = exhausted || active_bad_write || canonical_flush ||
      bad_index || overflow || canonical_gap || ddc_halted;
  wire running = active && !active_fault_now && !stop_request;
  wire push = running && capture_valid && capture_support;
  // Do not feed output-derived faults combinationally back into DDC flush:
  // DDC valid itself is qualified by flush. Latch those faults on this edge.
  wire source_run = active && !stop_request && !canonical_flush && !active_bad_write;
  assign pilot_enable = active;
  assign irq = faults != 0;

  generate if (!COARSE25_BYPASS) begin : g_pilot_ddc
  starlink_pilot_ddc ddc (
    .clk(s_axi_aclk), .resetn(s_axi_aresetn && !clear_ok), .flush(!source_run),
    .edge_upper(1'b1), .visit_id(visit_id), .input_valid(canonical_valid && source_run),
    .input_gap(canonical_gap && active), .input_i(canonical_i), .input_q(canonical_q),
    .input_index(canonical_index), .input_support_valid(1'b1),
    .output_valid(ddc_valid), .output_i(ddc_i), .output_q(ddc_q),
    .output_index(ddc_index), .output_visit_id(ddc_visit), .output_support_valid(ddc_support),
    .accepted_sample_count(ddc_accepted), .emitted_sample_count(ddc_emitted),
    .saturation_event_count(ddc_clips), .fifo_high_water(ddc_high_water),
    .sticky_fault(ddc_fault), .halted(ddc_halted)
  );
  end else begin : g_coarse_bypass
    reg [63:0] accepted;
    always @(posedge s_axi_aclk) begin
      if (!s_axi_aresetn || clear_ok) accepted <= 0;
      else if (ddc_valid && !(&accepted)) accepted <= accepted + 1'b1;
    end
    assign ddc_valid = canonical_valid && source_run;
    assign ddc_i = canonical_i;
    assign ddc_q = canonical_q;
    assign ddc_index = canonical_index;
    assign ddc_visit = visit_id;
    assign ddc_support = 1'b1;
    assign ddc_accepted = accepted;
    assign ddc_emitted = accepted;
    assign ddc_clips = 0;
    assign ddc_high_water = 0;
    assign ddc_fault = 0;
    assign ddc_halted = 0;
  end endgenerate

  // The detector consumes the identical FIFO-admitted prefix, never AXIS
  // delivery cadence. Its calculation cannot backpressure or gate IQ capture.
  // Register the fanout to avoid extending FIFO admission through the detector.
  wire [31:0] coarse_rdata;
  generate if (COARSE25_BYPASS) begin : g_coarse
    reg coarse_valid, coarse_reset;
    reg [31:0] coarse_data;
    reg [63:0] coarse_index;
    always @(posedge s_axi_aclk) begin
      coarse_valid <= s_axi_aresetn && push;
      coarse_data <= capture_data;
      coarse_index <= admitted;
      coarse_reset <= !s_axi_aresetn || clear_ok || arm_ok || faults != 0;
    end
    starlink_coarse25_registers detector (
      .clk(s_axi_aclk), .reset(!s_axi_aresetn || clear_ok),
      .arithmetic_reset(coarse_reset), .sample_valid(coarse_valid),
      .sample_i(coarse_data[15:0]), .sample_q(coarse_data[31:16]),
      .sample_index(coarse_index), .snapshot_request(snapshot_request),
      .read_address(raddr), .read_data(coarse_rdata)
    );
  end else begin : g_no_coarse
    assign coarse_rdata = 0;
  end endgenerate

  always @(posedge s_axi_aclk) begin
    if (push) fifo[wr_pointer] <= capture_data;
    if (!s_axi_aresetn || clear_ok) begin
      active <= 0;
      used <= 0;
      faults <= 0;
      admitted <= 0;
      delivered <= 0;
      unsupported <= 0;
      first_index <= 0;
      last_index <= 0;
      lost_index <= 0;
      wr_pointer <= 0;
      rd_pointer <= 0;
      fifo_count <= 0;
      fifo_high_water <= 0;
    end else begin
      if (arm_ok) begin active <= 1; used <= 1; end
      if (stop_request || faults_now != 0) active <= 0;
      faults <= faults | faults_now;
      if (faults == 0 && faults_now != 0)
        lost_index <= capture_valid ? capture_index : canonical_index;
      if (running && capture_valid && !capture_support) unsupported <= unsupported + 1'b1;
      if (push) begin
        wr_pointer <= wr_pointer + 1'b1;
        admitted <= admitted + 1'b1;
        if (admitted == 0) first_index <= capture_index;
        last_index <= capture_index;
        if (sample_limit != 0 && admitted == {32'd0, sample_limit} - 1'b1) active <= 0;
      end
      if (pop) begin
        rd_pointer <= rd_pointer + 1'b1;
        if (!(&delivered)) delivered <= delivered + 1'b1;
      end
      case ({push, pop})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: ;
      endcase
      if (push && !pop && fifo_count + 1'b1 > fifo_high_water)
        fifo_high_water <= fifo_count + 1'b1;
    end
    if (!s_axi_aresetn) begin visit_id <= 0; sample_limit <= 0; end
    else begin
      if (visit_write) visit_id <= wdata;
      if (limit_write) sample_limit <= wdata;
    end
  end

  // Snapshot reads never mix cycles across high/low words. Generation is zero
  // until explicitly latched; CLEAR invalidates it. Snapshot is pre-edge state,
  // so a transfer on that same edge belongs to the next snapshot.
  // Retain snapshot semantics but put the hold mux on D. Replicated snapshot
  // enables must not create a separate slice control set for each copy.
  (* extract_enable = "no" *) reg [31:0] snapshot [0:25];
  reg [31:0] snapshot_generation;
  wire [31:0] status = {27'd0, used, admitted != 0, faults != 0, !empty, active};
  integer n;
  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn || clear_ok) begin
      snapshot_generation <= 0;
      for (n = 0; n < 26; n = n + 1) snapshot[n] <= 0;
    end else if (snapshot_request) begin
      snapshot_generation <= snapshot_generation == 32'hffffffff ? 32'd1 : snapshot_generation + 1'b1;
      snapshot[0] <= first_index[31:0]; snapshot[1] <= first_index[63:32];
      snapshot[2] <= last_index[31:0]; snapshot[3] <= last_index[63:32];
      snapshot[4] <= admitted[31:0]; snapshot[5] <= admitted[63:32];
      snapshot[6] <= delivered[31:0]; snapshot[7] <= delivered[63:32];
      snapshot[8] <= unsupported[31:0]; snapshot[9] <= unsupported[63:32];
      snapshot[10] <= lost_index[31:0]; snapshot[11] <= lost_index[63:32];
      snapshot[12] <= ddc_accepted[31:0]; snapshot[13] <= ddc_accepted[63:32];
      snapshot[14] <= ddc_emitted[31:0]; snapshot[15] <= ddc_emitted[63:32];
      snapshot[16] <= ddc_clips; snapshot[17] <= {16'd0, ddc_high_water, ddc_fault};
      snapshot[18] <= faults; snapshot[19] <= status;
      snapshot[20] <= visit_id; snapshot[21] <= fifo_high_water;
      snapshot[22] <= fifo_count;
      snapshot[23] <= 0; snapshot[24] <= 0; snapshot[25] <= 0;
    end
  end
  always @(posedge s_axi_aclk) begin
    // Respond only after the registered request has taken effect. AXI BVALID
    // must never promise completion while a STOP/CLEAR/configuration is pending.
    // Invalid CLEAR still faults/responds at its original rejection edge.
    // Only an accepted CLEAR waits the extra clock for the common reset edge.
    wack <= (write_pending && !clear_admit) || clear_ok;
    rack <= rreq;
    if (!s_axi_aresetn) begin wack <= 0; rack <= 0; rdata <= 0; end
    else if (rreq) begin
      rdata <= 0;
      case (raddr)
        6'h00: rdata <= COARSE25_BYPASS ? 32'h43323531 : 32'h50494c31; // C251 / PIL1
        6'h01: rdata <= 32'h00010000;
        6'h03: rdata <= status;
        6'h04: rdata <= faults;
        6'h05: rdata <= SOURCE_RATE_HZ;
        6'h06: rdata <= 2500000;
        6'h07: rdata <= SOURCE_RATE_HZ / 2500000;
        6'h08: rdata <= visit_id;
        6'h09: rdata <= COARSE25_BYPASS ? 0 : 1; // zero=centered, no internal NCO
        6'h0a: rdata <= COARSE25_BYPASS ? 0 : 269;
        6'h0b: rdata <= COARSE25_BYPASS ? 0 : 538;
        6'h26: rdata <= snapshot_generation;
        6'h27: rdata <= sample_limit;
        default: begin
          if (raddr >= 6'h0c && raddr < 6'h26) rdata <= snapshot[raddr - 6'h0c];
          else if (raddr >= 6'h28) rdata <= coarse_rdata;
        end
      endcase
    end
  end
endmodule
