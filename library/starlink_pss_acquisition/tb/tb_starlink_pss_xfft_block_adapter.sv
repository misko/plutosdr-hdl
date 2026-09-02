`timescale 1ns/1ps

module tb_starlink_pss_xfft_block_adapter;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_i = 0;
  reg signed [23:0] input_q = 0;
  reg [8:0] input_position = 0;
  reg [63:0] input_block_start_index = 0;
  reg input_last = 1'b0;
  reg output_ready = 1'b1;
  reg core_config_tready = 1'b0;
  reg inverse_config_tready = 1'b0;
  reg core_input_tready = 1'b1;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = 0;
  reg core_output_tvalid = 1'b0;
  reg core_output_tlast = 1'b0;
  reg [7:0] core_status_tdata = 0;
  reg core_status_tvalid = 1'b0;
  reg core_event_frame_started = 1'b0;
  reg core_event_tlast_unexpected = 1'b0;
  reg core_event_tlast_missing = 1'b0;
  reg core_event_status_channel_halt = 1'b0;
  reg core_event_data_in_channel_halt = 1'b0;
  reg core_event_data_out_channel_halt = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_i;
  wire signed [23:0] output_q;
  wire [8:0] output_position;
  wire [4:0] output_block_exponent;
  wire [63:0] output_block_start_index;
  wire output_last;
  wire core_aresetn;
  wire [7:0] core_config_tdata;
  wire core_config_tvalid;
  wire [47:0] core_input_tdata;
  wire core_input_tvalid;
  wire core_input_tlast;
  wire core_output_tready;
  wire core_status_tready;
  wire configured_pulse;
  wire input_block_complete_pulse;
  wire output_block_complete_pulse;
  wire protocol_error_pulse;
  wire input_framing_error_pulse;
  wire output_metadata_error_pulse;
  wire status_error_pulse;
  wire core_tlast_error_pulse;
  wire core_data_in_halt_pulse;
  wire core_data_out_halt_pulse;
  wire protocol_fault;
  wire inverse_core_aresetn;
  wire [7:0] inverse_config_tdata;
  wire inverse_config_tvalid;
  wire inverse_protocol_fault;

  integer cycle_count = 0;
  integer core_input_count = 0;
  integer published_count = 0;
  integer configured_count = 0;
  integer input_blocks = 0;
  integer output_blocks = 0;
  integer protocol_errors = 0;
  integer input_framing_errors = 0;
  integer output_metadata_errors = 0;
  integer status_errors = 0;
  integer core_tlast_errors = 0;
  integer data_in_halts = 0;
  integer data_out_halts = 0;
  integer position;
  integer published_before_fault;
  reg stalled_last_cycle = 1'b0;
  reg [150:0] stalled_payload = 0;

  always #5 clk = ~clk;

  starlink_pss_xfft_block_adapter #(
    .FORWARD_TRANSFORM (1)
  ) dut (
    .clk                            (clk),
    .resetn                         (resetn),
    .flush                          (flush),
    .input_valid                    (input_valid),
    .input_ready                    (input_ready),
    .input_i                        (input_i),
    .input_q                        (input_q),
    .input_position                 (input_position),
    .input_block_start_index        (input_block_start_index),
    .input_last                     (input_last),
    .output_valid                   (output_valid),
    .output_ready                   (output_ready),
    .output_i                       (output_i),
    .output_q                       (output_q),
    .output_position                (output_position),
    .output_block_exponent          (output_block_exponent),
    .output_block_start_index       (output_block_start_index),
    .output_last                    (output_last),
    .core_aresetn                   (core_aresetn),
    .core_config_tdata              (core_config_tdata),
    .core_config_tvalid             (core_config_tvalid),
    .core_config_tready             (core_config_tready),
    .core_input_tdata               (core_input_tdata),
    .core_input_tvalid              (core_input_tvalid),
    .core_input_tready              (core_input_tready),
    .core_input_tlast               (core_input_tlast),
    .core_output_tdata              (core_output_tdata),
    .core_output_tuser              (core_output_tuser),
    .core_output_tvalid             (core_output_tvalid),
    .core_output_tready             (core_output_tready),
    .core_output_tlast              (core_output_tlast),
    .core_status_tdata              (core_status_tdata),
    .core_status_tvalid             (core_status_tvalid),
    .core_status_tready             (core_status_tready),
    .core_event_frame_started       (core_event_frame_started),
    .core_event_tlast_unexpected    (core_event_tlast_unexpected),
    .core_event_tlast_missing       (core_event_tlast_missing),
    .core_event_status_channel_halt (core_event_status_channel_halt),
    .core_event_data_in_channel_halt(core_event_data_in_channel_halt),
    .core_event_data_out_channel_halt(core_event_data_out_channel_halt),
    .configured_pulse               (configured_pulse),
    .input_block_complete_pulse     (input_block_complete_pulse),
    .output_block_complete_pulse    (output_block_complete_pulse),
    .protocol_error_pulse           (protocol_error_pulse),
    .input_framing_error_pulse      (input_framing_error_pulse),
    .output_metadata_error_pulse    (output_metadata_error_pulse),
    .status_error_pulse             (status_error_pulse),
    .core_tlast_error_pulse         (core_tlast_error_pulse),
    .core_data_in_halt_pulse        (core_data_in_halt_pulse),
    .core_data_out_halt_pulse       (core_data_out_halt_pulse),
    .protocol_fault                 (protocol_fault)
  );

  // A minimal second instance proves that the same source binds an inverse
  // core with FWD/INV=0.  The exhaustive data-path checks remain on the
  // forward instance above because direction does not alter adapter framing.
  starlink_pss_xfft_block_adapter #(
    .FORWARD_TRANSFORM (0)
  ) inverse_config_dut (
    .clk                            (clk),
    .resetn                         (resetn),
    .flush                          (flush),
    .input_valid                    (1'b0),
    .input_ready                    (),
    .input_i                        (24'sd0),
    .input_q                        (24'sd0),
    .input_position                 (9'd0),
    .input_block_start_index        (64'd0),
    .input_last                     (1'b0),
    .output_valid                   (),
    .output_ready                   (1'b0),
    .output_i                       (),
    .output_q                       (),
    .output_position                (),
    .output_block_exponent          (),
    .output_block_start_index       (),
    .output_last                    (),
    .core_aresetn                   (inverse_core_aresetn),
    .core_config_tdata              (inverse_config_tdata),
    .core_config_tvalid             (inverse_config_tvalid),
    .core_config_tready             (inverse_config_tready),
    .core_input_tdata               (),
    .core_input_tvalid              (),
    .core_input_tready              (1'b0),
    .core_input_tlast               (),
    .core_output_tdata              (48'd0),
    .core_output_tuser              (24'd0),
    .core_output_tvalid             (1'b0),
    .core_output_tready             (),
    .core_output_tlast              (1'b0),
    .core_status_tdata              (8'd0),
    .core_status_tvalid             (1'b0),
    .core_status_tready             (),
    .core_event_frame_started       (1'b0),
    .core_event_tlast_unexpected    (1'b0),
    .core_event_tlast_missing       (1'b0),
    .core_event_status_channel_halt (1'b0),
    .core_event_data_in_channel_halt(1'b0),
    .core_event_data_out_channel_halt(1'b0),
    .configured_pulse               (),
    .input_block_complete_pulse     (),
    .output_block_complete_pulse    (),
    .protocol_error_pulse           (),
    .input_framing_error_pulse      (),
    .output_metadata_error_pulse    (),
    .status_error_pulse             (),
    .core_tlast_error_pulse         (),
    .core_data_in_halt_pulse        (),
    .core_data_out_halt_pulse       (),
    .protocol_fault                 (inverse_protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("XFFT_ADAPTER_FAIL %0s cycle=%0d input=%0d output=%0d faults=%0d",
               message, cycle_count, core_input_count, published_count,
               protocol_errors);
      $fatal(1);
    end
  endtask

  task automatic configure_core;
    begin
      while (!core_config_tvalid)
        @(negedge clk);
      if (core_config_tdata !== 8'h01)
        fail("forward-transform configuration word mismatch");
      if (!inverse_config_tvalid || inverse_config_tdata !== 8'h00)
        fail("inverse-transform configuration word mismatch");
      if (input_ready)
        fail("application input opened before configuration handshake");
      core_config_tready = 1'b1;
      inverse_config_tready = 1'b1;
      @(negedge clk);
      core_config_tready = 1'b0;
      inverse_config_tready = 1'b0;
      repeat (2) @(negedge clk);
      if (inverse_protocol_fault || inverse_core_aresetn !== core_aresetn)
        fail("inverse configuration-only adapter lifecycle mismatch");
    end
  endtask

  task automatic common_flush_and_configure;
    begin
      input_valid = 1'b0;
      core_output_tvalid = 1'b0;
      core_status_tvalid = 1'b0;
      core_event_frame_started = 1'b0;
      core_event_tlast_unexpected = 1'b0;
      core_event_tlast_missing = 1'b0;
      core_event_status_channel_halt = 1'b0;
      @(negedge clk);
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      if (core_aresetn)
        fail("core reset released with flush deassertion");
      @(posedge clk);
      if (core_aresetn)
        fail("core reset was not stretched through release cycle one");
      @(posedge clk);
      configure_core();
      if (protocol_fault)
        fail("flush did not clear sticky protocol fault");
    end
  endtask

  task automatic send_input_sample(
    input [8:0] sample_position,
    input [63:0] block_start,
    input sample_last
  );
    begin
      @(negedge clk);
      input_i = $signed(24'sd1000 + sample_position);
      input_q = -$signed(24'sd2000 + sample_position);
      input_position = sample_position;
      input_block_start_index = block_start;
      input_last = sample_last;
      input_valid = 1'b1;
      if (sample_position == 0)
        core_event_frame_started = 1'b1;
      core_input_tready = (sample_position % 11) != 3;
      begin : wait_for_input_accept
        forever begin
          @(posedge clk);
          if (input_ready)
            disable wait_for_input_accept;
          @(negedge clk);
          core_input_tready = 1'b1;
        end
      end
      @(negedge clk);
      input_valid = 1'b0;
      core_event_frame_started = 1'b0;
      core_input_tready = 1'b1;
    end
  endtask

  task automatic send_complete_input_block(input [63:0] block_start);
    begin
      for (position = 0; position < 512; position = position + 1) begin
        send_input_sample(position[8:0], block_start, position == 511);
      end
    end
  endtask

  task automatic send_output_sample(
    input [8:0] sample_position,
    input [4:0] block_exponent,
    input sample_last
  );
    begin
      @(negedge clk);
      core_output_tdata = {
        -$signed(24'sd4000 + sample_position),
        $signed(24'sd3000 + sample_position)
      };
      core_output_tuser = {3'b000, block_exponent, 7'b0000000,
                           sample_position};
      core_output_tlast = sample_last;
      core_output_tvalid = 1'b1;
      if ((sample_position % 17) == 5) begin
        output_ready = 1'b0;
        repeat (2) @(negedge clk);
        output_ready = 1'b1;
      end
      begin : wait_for_output_accept
        forever begin
          @(posedge clk);
          if (core_output_tready)
            disable wait_for_output_accept;
        end
      end
      @(negedge clk);
      core_output_tvalid = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 30000)
      fail("simulation watchdog expired");

    if (configured_pulse)
      configured_count <= configured_count + 1;
    if (input_block_complete_pulse)
      input_blocks <= input_blocks + 1;
    if (output_block_complete_pulse)
      output_blocks <= output_blocks + 1;
    if (protocol_error_pulse) begin
      protocol_errors <= protocol_errors + 1;
      $display("XFFT_ADAPTER_FAULT cycle=%0d input_position=%0d core_output_position=%0d expected_output_position=%0d input_framing=%0b output_metadata=%0b status=%0b core_tlast=%0b",
               cycle_count, input_position, core_output_tuser[8:0],
               dut.expected_output_position, input_framing_error_pulse,
               output_metadata_error_pulse, status_error_pulse,
               core_tlast_error_pulse);
    end
    if (input_framing_error_pulse)
      input_framing_errors <= input_framing_errors + 1;
    if (output_metadata_error_pulse)
      output_metadata_errors <= output_metadata_errors + 1;
    if (status_error_pulse)
      status_errors <= status_errors + 1;
    if (core_tlast_error_pulse)
      core_tlast_errors <= core_tlast_errors + 1;
    if (core_data_in_halt_pulse)
      data_in_halts <= data_in_halts + 1;
    if (core_data_out_halt_pulse)
      data_out_halts <= data_out_halts + 1;

    if (core_input_tvalid && core_input_tready) begin
      if (core_input_tdata !== {input_q, input_i})
        fail("input complex-lane packing mismatch");
      if (core_input_tlast !== (input_position == 511))
        fail("core input TLAST mismatch");
      core_input_count <= core_input_count + 1;
    end

    if (stalled_last_cycle) begin
      if (!output_valid ||
          {output_last, output_block_start_index, output_block_exponent,
           output_position, output_q, output_i} !== stalled_payload)
        fail("published output changed while stalled");
    end
    stalled_last_cycle <= output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_last, output_block_start_index, output_block_exponent,
        output_position, output_q, output_i
      };

    if (output_valid && output_ready) begin
      if (output_position !== (published_count % 512))
        fail("published XFFT index mismatch");
      if (output_block_start_index !== 64'd1000)
        fail("published block identity mismatch");
      if (output_block_exponent !== 5'd5)
        fail("published block exponent mismatch");
      if (output_i !== $signed(24'sd3000 + (published_count % 512)) ||
          output_q !== -$signed(24'sd4000 + (published_count % 512)))
        fail("published complex output mismatch");
      if (output_last !== ((published_count % 512) == 511))
        fail("published output TLAST mismatch");
      published_count <= published_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_xfft_block_adapter.vcd");
    $dumpvars(0, tb_starlink_pss_xfft_block_adapter);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    if (core_aresetn)
      fail("core reset released immediately with resetn");
    configure_core();

    // Complete forward block with input and output backpressure.  Present the
    // first result before status and prove it cannot escape until BLK_EXP is
    // captured from the always-ready per-frame status channel.
    send_complete_input_block(64'd1000);
    core_event_data_in_channel_halt = 1'b1;
    core_event_data_out_channel_halt = 1'b1;
    @(negedge clk);
    core_event_data_in_channel_halt = 1'b0;
    core_event_data_out_channel_halt = 1'b0;

    @(negedge clk);
    core_output_tdata = {-24'sd4000, 24'sd3000};
    core_output_tuser = {3'b000, 5'd5, 7'b0000000, 9'd0};
    core_output_tlast = 1'b0;
    core_output_tvalid = 1'b1;
    repeat (2) begin
      @(posedge clk);
      if (core_output_tready || output_valid)
        fail("data escaped before frame status arrived");
    end
    @(negedge clk);
    core_status_tdata = {3'b000, 5'd5};
    core_status_tvalid = 1'b1;
    @(posedge clk);
    if (!core_status_tready || !core_output_tready || !output_valid)
      fail("status and first output did not retire together");
    @(negedge clk);
    core_status_tvalid = 1'b0;
    core_output_tvalid = 1'b0;
    for (position = 1; position < 512; position = position + 1)
      send_output_sample(position[8:0], 5'd5, position == 511);
    repeat (3) @(negedge clk);
    if (published_count != 512 || input_blocks != 1 || output_blocks != 1)
      fail("complete-block accounting mismatch");
    if (protocol_fault || data_in_halts != 1 || data_out_halts != 1)
      fail("nonfatal halt telemetry handling mismatch");

    // Bad application TLAST is consumed at the adapter but never reaches the
    // generated core.
    common_flush_and_configure();
    published_before_fault = published_count;
    @(negedge clk);
    input_position = 0;
    input_block_start_index = 64'd2000;
    input_last = 1'b1;
    input_valid = 1'b1;
    @(posedge clk);
    if (!input_ready || core_input_tvalid)
      fail("bad application frame was not consumed fail-closed");
    @(negedge clk);
    input_valid = 1'b0;
    if (!protocol_fault || published_count != published_before_fault)
      fail("bad application TLAST did not quarantine output");

    // Status without an in-flight block is an identity error.
    common_flush_and_configure();
    @(negedge clk);
    core_status_tdata = {3'b000, 5'd2};
    core_status_tvalid = 1'b1;
    @(negedge clk);
    core_status_tvalid = 1'b0;
    if (!protocol_fault)
      fail("orphan status did not quarantine output");

    // XFFT TLAST events and status-channel halt are hard protocol faults.
    common_flush_and_configure();
    @(negedge clk);
    core_event_tlast_missing = 1'b1;
    @(negedge clk);
    core_event_tlast_missing = 1'b0;
    if (!protocol_fault)
      fail("XFFT missing-TLAST event did not quarantine output");

    common_flush_and_configure();
    @(negedge clk);
    core_event_status_channel_halt = 1'b1;
    @(negedge clk);
    core_event_status_channel_halt = 1'b0;
    if (!protocol_fault)
      fail("XFFT status halt did not quarantine output");

    // A complete second input frame with a malformed XFFT output index is
    // consumed by the core-side interface but is never published.
    common_flush_and_configure();
    send_complete_input_block(64'd2000);
    @(negedge clk);
    core_status_tdata = {3'b000, 5'd3};
    core_status_tvalid = 1'b1;
    @(negedge clk);
    core_status_tvalid = 1'b0;
    published_before_fault = published_count;
    @(negedge clk);
    core_output_tdata = {-24'sd4000, 24'sd3000};
    core_output_tuser = {3'b000, 5'd3, 7'b0000000, 9'd1};
    core_output_tlast = 1'b0;
    core_output_tvalid = 1'b1;
    @(posedge clk);
    if (!core_output_tready || output_valid)
      fail("bad XFFT output metadata was not consumed fail-closed");
    @(negedge clk);
    core_output_tvalid = 1'b0;
    if (!protocol_fault || published_count != published_before_fault)
      fail("bad XFFT output index did not quarantine publication");

    repeat (3) @(negedge clk);
    if (configured_count != 6 || protocol_errors != 5 ||
        input_framing_errors != 1 || output_metadata_errors != 1 ||
        status_errors != 2 || core_tlast_errors != 1)
      fail("fault pulse accounting mismatch");

    $display("XFFT_ADAPTER_PASS input_blocks=%0d output_blocks=%0d published=%0d directions=forward_inverse reset_stretch=2 config_before_data=1 status_before_output=1 stalls=1 input_faults=%0d output_faults=%0d status_faults=%0d core_tlast_faults=%0d flush_recovery=1",
             input_blocks, output_blocks, published_count,
             input_framing_errors, output_metadata_errors, status_errors,
             core_tlast_errors);
    $finish;
  end

endmodule
