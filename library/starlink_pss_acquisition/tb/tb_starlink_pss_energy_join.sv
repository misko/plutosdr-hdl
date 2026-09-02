`timescale 1ns/1ps

module tb_starlink_pss_energy_join;

  localparam integer STREAM_ITEMS = 1000;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_correlation_i = 0;
  reg signed [23:0] input_correlation_q = 0;
  reg [4:0] input_forward_exponent = 0;
  reg [4:0] input_inverse_exponent = 0;
  reg [63:0] input_start_index = 0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire cache_lookup_valid;
  wire cache_lookup_ready;
  wire [63:0] cache_lookup_start_index;
  reg cache_output_valid = 1'b0;
  wire cache_output_ready;
  reg [37:0] cache_output_energy = 0;
  reg [63:0] cache_output_start_index = 0;
  reg cache_output_found = 1'b0;
  wire output_valid;
  wire signed [23:0] output_correlation_i;
  wire signed [23:0] output_correlation_q;
  wire [37:0] output_sample_energy;
  wire [4:0] output_forward_exponent;
  wire [4:0] output_inverse_exponent;
  wire [63:0] output_start_index;
  wire accepted_pulse;
  wire joined_pulse;
  wire cache_miss_pulse;
  wire index_mismatch_pulse;
  wire orphan_response_pulse;
  wire protocol_fault;

  reg inject_miss = 1'b0;
  reg inject_mismatch = 1'b0;
  reg inject_orphan = 1'b0;
  reg monitor_stream = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [159:0] stalled_payload;
  integer cycle_count = 0;
  integer lookup_count = 0;
  integer output_count = 0;
  integer miss_count = 0;
  integer mismatch_count = 0;
  integer orphan_count = 0;
  integer first_lookup_cycle = -1;
  integer last_lookup_cycle = -1;
  integer ordinal;
  integer timeout;

  always #5 clk = ~clk;

  function automatic [37:0] encoded_energy(input [63:0] index);
    reg [101:0] wide_value;
    begin
      wide_value = index * 31337 + 7;
      encoded_energy = wide_value[37:0];
    end
  endfunction

  function automatic signed [23:0] encoded_i(input integer item);
    encoded_i = item * 7919 + 17;
  endfunction

  function automatic signed [23:0] encoded_q(input integer item);
    encoded_q = -(item * 3571 + 23);
  endfunction

  assign cache_lookup_ready = resetn && !flush &&
                              (!cache_output_valid || cache_output_ready);

  starlink_pss_energy_join dut (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (input_valid),
    .input_ready              (input_ready),
    .input_correlation_i      (input_correlation_i),
    .input_correlation_q      (input_correlation_q),
    .input_forward_exponent   (input_forward_exponent),
    .input_inverse_exponent   (input_inverse_exponent),
    .input_start_index        (input_start_index),
    .cache_lookup_valid       (cache_lookup_valid),
    .cache_lookup_ready       (cache_lookup_ready),
    .cache_lookup_start_index (cache_lookup_start_index),
    .cache_output_valid       (cache_output_valid),
    .cache_output_ready       (cache_output_ready),
    .cache_output_energy      (cache_output_energy),
    .cache_output_start_index (cache_output_start_index),
    .cache_output_found       (cache_output_found),
    .output_valid             (output_valid),
    .output_ready             (output_ready),
    .output_correlation_i     (output_correlation_i),
    .output_correlation_q     (output_correlation_q),
    .output_sample_energy     (output_sample_energy),
    .output_forward_exponent  (output_forward_exponent),
    .output_inverse_exponent  (output_inverse_exponent),
    .output_start_index       (output_start_index),
    .accepted_pulse           (accepted_pulse),
    .joined_pulse             (joined_pulse),
    .cache_miss_pulse         (cache_miss_pulse),
    .index_mismatch_pulse     (index_mismatch_pulse),
    .orphan_response_pulse    (orphan_response_pulse),
    .protocol_fault           (protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("ENERGY_JOIN_FAIL %0s cycle=%0d lookups=%0d outputs=%0d fault=%b",
               message, cycle_count, lookup_count, output_count,
               protocol_fault);
      $fatal(1);
    end
  endtask

  task automatic set_item(input integer item, input [63:0] base_index);
    begin
      input_correlation_i = encoded_i(item);
      input_correlation_q = encoded_q(item);
      input_forward_exponent = item % 32;
      input_inverse_exponent = (item * 7 + 3) % 32;
      input_start_index = base_index + item;
    end
  endtask

  task automatic send_one(input integer item, input [63:0] base_index);
    begin
      @(negedge clk);
      set_item(item, base_index);
      input_valid = 1'b1;
      begin : wait_for_accept
        forever begin
          @(posedge clk);
          if (input_ready)
            disable wait_for_accept;
        end
      end
      @(negedge clk);
      input_valid = 1'b0;
    end
  endtask

  task automatic pulse_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      inject_miss = 1'b0;
      inject_mismatch = 1'b0;
      inject_orphan = 1'b0;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      #1;
    end
  endtask

  // One-entry elastic cache-response model. It normally returns the exact
  // requested index and deterministic energy one cycle after lookup.
  always @(posedge clk) begin
    if (!resetn || flush) begin
      cache_output_valid <= 1'b0;
      cache_output_energy <= 0;
      cache_output_start_index <= 0;
      cache_output_found <= 1'b0;
    end else if (!cache_output_valid || cache_output_ready) begin
      if (inject_orphan) begin
        cache_output_valid <= 1'b1;
        cache_output_energy <= encoded_energy(64'd777777);
        cache_output_start_index <= 64'd777777;
        cache_output_found <= 1'b1;
      end else begin
        cache_output_valid <= cache_lookup_valid && cache_lookup_ready;
        if (cache_lookup_valid && cache_lookup_ready) begin
          cache_output_energy <= encoded_energy(cache_lookup_start_index);
          cache_output_start_index <= cache_lookup_start_index +
                                      inject_mismatch;
          cache_output_found <= !inject_miss;
        end
      end
    end
  end

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 20000)
      fail("simulation watchdog expired");

    if (cache_lookup_valid && cache_lookup_ready) begin
      if (first_lookup_cycle < 0)
        first_lookup_cycle <= cycle_count;
      last_lookup_cycle <= cycle_count;
      lookup_count <= lookup_count + 1;
    end
    if (cache_miss_pulse)
      miss_count <= miss_count + 1;
    if (index_mismatch_pulse)
      mismatch_count <= mismatch_count + 1;
    if (orphan_response_pulse)
      orphan_count <= orphan_count + 1;

    if (resetn && monitor_stream && stalled_last_cycle) begin
      if (!output_valid ||
          {output_start_index, output_inverse_exponent,
           output_forward_exponent, output_sample_energy,
           output_correlation_q, output_correlation_i} !== stalled_payload)
        fail("output payload changed while stalled");
    end
    stalled_last_cycle <= resetn && monitor_stream &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_start_index, output_inverse_exponent,
        output_forward_exponent, output_sample_energy,
        output_correlation_q, output_correlation_i
      };

    if (resetn && monitor_stream && output_valid && output_ready) begin
      if (output_start_index !== 64'd100000 + output_count ||
          output_correlation_i !== encoded_i(output_count) ||
          output_correlation_q !== encoded_q(output_count) ||
          output_forward_exponent !== output_count % 32 ||
          output_inverse_exponent !== (output_count * 7 + 3) % 32 ||
          output_sample_energy !==
            encoded_energy(64'd100000 + output_count))
        fail("joined payload or ordering mismatch");
      output_count <= output_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_energy_join.vcd");
    $dumpvars(0, tb_starlink_pss_energy_join);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    output_ready = 1'b1;
    monitor_stream = 1'b1;

    // Sustained traffic must accept one lookup on every clock after startup.
    @(negedge clk);
    input_valid = 1'b1;
    for (ordinal = 0; ordinal < STREAM_ITEMS; ordinal = ordinal + 1) begin
      set_item(ordinal, 64'd100000);
      #1;
      if (!input_ready || !cache_lookup_valid)
        fail("steady stream lost one-request-per-clock readiness");
      @(negedge clk);
    end
    input_valid = 1'b0;

    timeout = 0;
    while (output_count < STREAM_ITEMS && timeout < 100) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    repeat (3) @(negedge clk);
    if (lookup_count != STREAM_ITEMS || output_count != STREAM_ITEMS)
      fail("steady stream did not join exactly");
    if (last_lookup_cycle - first_lookup_cycle != STREAM_ITEMS - 1)
      fail("steady stream was not one lookup per clock");
    if (protocol_fault)
      fail("good steady stream raised a fault");

    // Hold a joined result for several cycles and verify complete stability.
    pulse_flush();
    monitor_stream = 1'b0;
    output_ready = 1'b0;
    send_one(1, 64'd200000);
    timeout = 0;
    while (!output_valid && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!output_valid)
      fail("stalled output did not arrive");
    monitor_stream = 1'b1;
    repeat (5) @(negedge clk);
    monitor_stream = 1'b0;
    output_ready = 1'b1;
    @(negedge clk);

    // A cache miss must block a simultaneous replacement and emit no result.
    pulse_flush();
    inject_miss = 1'b1;
    send_one(2, 64'd300000);
    @(negedge clk);
    inject_miss = 1'b0;
    set_item(3, 64'd300000);
    input_valid = 1'b1;
    #1;
    if (input_ready || cache_lookup_valid)
      fail("miss response allowed a replacement request");
    @(negedge clk);
    input_valid = 1'b0;
    if (!protocol_fault || miss_count != 1 || output_valid)
      fail("cache miss was not quarantined without output");
    if (input_ready || cache_output_ready)
      fail("cache miss did not hold interfaces quarantined");

    // An identity mismatch follows the same fail-closed rule.
    pulse_flush();
    inject_mismatch = 1'b1;
    send_one(4, 64'd400000);
    @(negedge clk);
    inject_mismatch = 1'b0;
    repeat (2) @(negedge clk);
    if (!protocol_fault || mismatch_count != 1 || output_valid)
      fail("cache identity mismatch was not quarantined");

    // A response with no corresponding metadata must also fault and vanish.
    pulse_flush();
    inject_orphan = 1'b1;
    @(negedge clk);
    inject_orphan = 1'b0;
    repeat (2) @(negedge clk);
    if (!protocol_fault || orphan_count != 1 || output_valid)
      fail("orphan cache response was not quarantined");

    pulse_flush();
    if (protocol_fault || output_valid || !input_ready)
      fail("final flush did not return join to idle");

    $display("ENERGY_JOIN_PASS stream=1000 one_per_clock=1 exact_order=1 stalls=1 miss=1 mismatch=1 orphan=1 quarantine=1 flush=1");
    $finish;
  end

endmodule
