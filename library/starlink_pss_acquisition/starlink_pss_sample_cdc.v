// Loss-detecting asynchronous ingress for the Starlink PSS acquisition path.
//
// The RX stream is intentionally non-backpressured.  Each accepted CI16 beat
// is copied with its absolute sample index into a dual-clock FIFO.  If the
// FIFO fills, the missing beat is counted and the first beat accepted after
// space returns is tagged as a discontinuity.  The detector can therefore
// restart its overlap-save history instead of correlating across lost data.
//
// Each reset input is independently synchronized into both domains.  The
// resulting local reset levels synchronously purge both pointer domains.  This
// prevents one side from observing stale pointers or stale RAM words after an
// independent source/destination reset.  The first beat after every reset
// epoch is also gap tagged.

`timescale 1ns/1ps

module starlink_pss_sample_cdc #(
  parameter integer FIFO_ADDRESS_WIDTH = 7
) (
  input  wire                    source_clk,
  input  wire                    source_resetn,
  input  wire                    source_sample_valid,
  input  wire                    source_sample_gap,
  input  wire signed [15:0]      source_sample_i,
  input  wire signed [15:0]      source_sample_q,
  input  wire [63:0]             source_sample_index,
  output wire                    source_fifo_full,

  input  wire                    acquisition_clk,
  input  wire                    acquisition_resetn,
  output reg                     acquisition_sample_valid,
  output wire                    acquisition_sample_gap,
  output wire signed [15:0]      acquisition_sample_i,
  output wire signed [15:0]      acquisition_sample_q,
  output wire [63:0]             acquisition_sample_index,

  // These telemetry outputs are coherent in the acquisition clock domain.
  output wire [31:0]             dropped_sample_count,
  output wire                    overflow_sticky,
  output wire [FIFO_ADDRESS_WIDTH:0] fifo_level,
  output reg  [FIFO_ADDRESS_WIDTH:0] maximum_fifo_level
);

  localparam integer POINTER_WIDTH = FIFO_ADDRESS_WIDTH + 1;
  localparam integer FIFO_DEPTH = 1 << FIFO_ADDRESS_WIDTH;
  localparam integer PAYLOAD_WIDTH = 97;

  function automatic [POINTER_WIDTH-1:0] binary_to_gray;
    input [POINTER_WIDTH-1:0] value;
    begin
      binary_to_gray = (value >> 1) ^ value;
    end
  endfunction

  function automatic [POINTER_WIDTH-1:0] gray_to_binary;
    input [POINTER_WIDTH-1:0] value;
    integer bit_index;
    begin
      gray_to_binary[POINTER_WIDTH-1] = value[POINTER_WIDTH-1];
      for (bit_index = POINTER_WIDTH - 2;
           bit_index >= 0;
           bit_index = bit_index - 1)
        gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^
                                    value[bit_index];
    end
  endfunction

  function automatic [31:0] binary_to_gray_32;
    input [31:0] value;
    begin
      binary_to_gray_32 = (value >> 1) ^ value;
    end
  endfunction

  function automatic [31:0] gray_to_binary_32;
    input [31:0] value;
    integer bit_index;
    begin
      gray_to_binary_32[31] = value[31];
      for (bit_index = 30; bit_index >= 0; bit_index = bit_index - 1)
        gray_to_binary_32[bit_index] = gray_to_binary_32[bit_index + 1] ^
                                       value[bit_index];
    end
  endfunction

  initial begin
    if (FIFO_ADDRESS_WIDTH < 2) begin
      $fatal(1, "FIFO_ADDRESS_WIDTH must be at least two");
    end
  end

  (* ASYNC_REG = "TRUE" *) reg [1:0] source_reset_source_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] acquisition_reset_source_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] source_reset_acquisition_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] acquisition_reset_acquisition_sync;
  wire source_domain_resetn;
  wire acquisition_domain_resetn;

  assign source_domain_resetn = source_reset_source_sync[1] &&
                                acquisition_reset_source_sync[1];
  assign acquisition_domain_resetn = source_reset_acquisition_sync[1] &&
                                     acquisition_reset_acquisition_sync[1];

  // Each reset input is asynchronously asserted only at dedicated reset
  // synchronizers.  Their locally synchronous outputs are ANDed only into
  // synchronous state resets, avoiding a glitch-prone LUT on an async clear.
  always @(posedge source_clk or negedge source_resetn) begin
    if (!source_resetn)
      source_reset_source_sync <= 2'b00;
    else
      source_reset_source_sync <= {source_reset_source_sync[0], 1'b1};
  end

  always @(posedge source_clk or negedge acquisition_resetn) begin
    if (!acquisition_resetn)
      acquisition_reset_source_sync <= 2'b00;
    else
      acquisition_reset_source_sync <= {
        acquisition_reset_source_sync[0], 1'b1};
  end

  always @(posedge acquisition_clk or negedge source_resetn) begin
    if (!source_resetn)
      source_reset_acquisition_sync <= 2'b00;
    else
      source_reset_acquisition_sync <= {
        source_reset_acquisition_sync[0], 1'b1};
  end

  always @(posedge acquisition_clk or negedge acquisition_resetn) begin
    if (!acquisition_resetn)
      acquisition_reset_acquisition_sync <= 2'b00;
    else
      acquisition_reset_acquisition_sync <= {
        acquisition_reset_acquisition_sync[0], 1'b1};
  end

  (* ram_style = "block" *) reg [PAYLOAD_WIDTH-1:0]
    fifo_memory [0:FIFO_DEPTH-1];

  reg [POINTER_WIDTH-1:0] source_pointer_binary;
  reg [POINTER_WIDTH-1:0] source_pointer_gray;
  reg                     source_full;
  reg                     source_gap_pending;
  reg [31:0]              source_dropped_sample_count;
  reg [31:0]              source_dropped_count_gray;

  reg [POINTER_WIDTH-1:0] acquisition_pointer_binary;
  reg [POINTER_WIDTH-1:0] acquisition_pointer_gray;
  reg                     acquisition_empty;
  reg [PAYLOAD_WIDTH-1:0] acquisition_payload;

  (* ASYNC_REG = "TRUE" *) reg [POINTER_WIDTH-1:0]
    read_pointer_gray_sync_1;
  (* ASYNC_REG = "TRUE" *) reg [POINTER_WIDTH-1:0]
    read_pointer_gray_sync_2;
  (* ASYNC_REG = "TRUE" *) reg [POINTER_WIDTH-1:0]
    write_pointer_gray_sync_1;
  (* ASYNC_REG = "TRUE" *) reg [POINTER_WIDTH-1:0]
    write_pointer_gray_sync_2;

  (* ASYNC_REG = "TRUE" *) reg [31:0] dropped_count_gray_sync_1;
  (* ASYNC_REG = "TRUE" *) reg [31:0] dropped_count_gray_sync_2;
  reg [31:0] acquisition_dropped_sample_count;

  wire source_write;
  wire source_drop;
  wire [POINTER_WIDTH-1:0] source_pointer_binary_next;
  wire [POINTER_WIDTH-1:0] source_pointer_gray_next;
  wire [POINTER_WIDTH-1:0] full_compare_pointer;
  wire source_full_next;
  wire [PAYLOAD_WIDTH-1:0] source_payload;
  wire [31:0] source_dropped_sample_count_next;

  wire acquisition_read;
  wire [POINTER_WIDTH-1:0] acquisition_pointer_binary_next;
  wire [POINTER_WIDTH-1:0] acquisition_pointer_gray_next;
  wire acquisition_empty_next;
  wire [POINTER_WIDTH-1:0] synchronized_write_pointer_binary;
  wire [POINTER_WIDTH-1:0] acquisition_fifo_level;

  assign source_fifo_full = source_full;
  assign source_write = source_sample_valid && !source_full;
  assign source_drop = source_sample_valid && source_full;
  assign source_pointer_binary_next = source_pointer_binary + source_write;
  assign source_pointer_gray_next = binary_to_gray(
      source_pointer_binary_next);
  // Inverting the two most-significant synchronized Gray bits is the standard
  // full comparison for a power-of-two asynchronous FIFO.
  assign full_compare_pointer = {
    ~read_pointer_gray_sync_2[POINTER_WIDTH-1:POINTER_WIDTH-2],
    read_pointer_gray_sync_2[POINTER_WIDTH-3:0]
  };
  assign source_full_next = source_pointer_gray_next ==
                            full_compare_pointer;
  assign source_payload = {
    source_sample_gap || source_gap_pending,
    source_sample_index,
    source_sample_q,
    source_sample_i
  };
  assign source_dropped_sample_count_next = source_drop &&
      !(&source_dropped_sample_count) ?
      source_dropped_sample_count + 1'b1 : source_dropped_sample_count;

  assign acquisition_read = !acquisition_empty;
  assign acquisition_pointer_binary_next = acquisition_pointer_binary +
                                            acquisition_read;
  assign acquisition_pointer_gray_next = binary_to_gray(
      acquisition_pointer_binary_next);
  assign acquisition_empty_next = acquisition_pointer_gray_next ==
                                  write_pointer_gray_sync_2;
  assign synchronized_write_pointer_binary = gray_to_binary(
      write_pointer_gray_sync_2);
  assign acquisition_fifo_level = synchronized_write_pointer_binary -
                                  acquisition_pointer_binary;
  assign fifo_level = acquisition_fifo_level;
  assign dropped_sample_count = acquisition_dropped_sample_count;
  assign overflow_sticky = |dropped_sample_count;
  assign acquisition_sample_i = acquisition_payload[15:0];
  assign acquisition_sample_q = acquisition_payload[31:16];
  assign acquisition_sample_index = acquisition_payload[95:32];
  assign acquisition_sample_gap = acquisition_payload[96];

  // Simple dual-port, dual-clock RAM: one source-domain write site and one
  // acquisition-domain registered read site.
  always @(posedge source_clk) begin
    if (source_domain_resetn && source_write)
      fifo_memory[source_pointer_binary[FIFO_ADDRESS_WIDTH-1:0]] <=
        source_payload;
  end

  // Keep the entire payload behind one registered read port so synthesis can
  // infer a true dual-clock block RAM instead of 97 independent LUTRAM paths.
  always @(posedge acquisition_clk) begin
    if (acquisition_read)
      acquisition_payload <= fifo_memory[
        acquisition_pointer_binary[FIFO_ADDRESS_WIDTH-1:0]];
  end

  always @(posedge acquisition_clk) begin
    if (!acquisition_domain_resetn)
      acquisition_sample_valid <= 1'b0;
    else
      acquisition_sample_valid <= acquisition_read;
  end

  always @(posedge source_clk) begin
    if (!source_domain_resetn) begin
      source_pointer_binary <= {POINTER_WIDTH{1'b0}};
      source_pointer_gray <= {POINTER_WIDTH{1'b0}};
      source_full <= 1'b0;
      source_gap_pending <= 1'b1;
      source_dropped_sample_count <= 32'd0;
      source_dropped_count_gray <= 32'd0;
    end else begin
      source_pointer_binary <= source_pointer_binary_next;
      source_pointer_gray <= source_pointer_gray_next;
      source_full <= source_full_next;
      source_dropped_sample_count <= source_dropped_sample_count_next;
      // Register the Gray value in the source domain.  Deriving a CDC value
      // combinationally from the binary counter would permit carry-chain
      // glitches even though successive stable Gray words differ by one bit.
      source_dropped_count_gray <= binary_to_gray_32(
          source_dropped_sample_count_next);

      if (source_drop) begin
        source_gap_pending <= 1'b1;
      end else if (source_write) begin
        source_gap_pending <= 1'b0;
      end
    end
  end

  always @(posedge acquisition_clk) begin
    if (!acquisition_domain_resetn) begin
      acquisition_pointer_binary <= {POINTER_WIDTH{1'b0}};
      acquisition_pointer_gray <= {POINTER_WIDTH{1'b0}};
      acquisition_empty <= 1'b1;
      acquisition_dropped_sample_count <= 32'd0;
      maximum_fifo_level <= {(POINTER_WIDTH){1'b0}};
    end else begin
      acquisition_pointer_binary <= acquisition_pointer_binary_next;
      acquisition_pointer_gray <= acquisition_pointer_gray_next;
      acquisition_empty <= acquisition_empty_next;
      // Register the Gray decode before it reaches the AXI health snapshot.
      // This removes a 32-bit XOR chain from the peripheral boundary.
      acquisition_dropped_sample_count <= gray_to_binary_32(
          dropped_count_gray_sync_2);
      if (acquisition_fifo_level > maximum_fifo_level)
        maximum_fifo_level <= acquisition_fifo_level;
    end
  end

  always @(posedge source_clk) begin
    if (!source_domain_resetn) begin
      read_pointer_gray_sync_1 <= {POINTER_WIDTH{1'b0}};
      read_pointer_gray_sync_2 <= {POINTER_WIDTH{1'b0}};
    end else begin
      read_pointer_gray_sync_1 <= acquisition_pointer_gray;
      read_pointer_gray_sync_2 <= read_pointer_gray_sync_1;
    end
  end

  always @(posedge acquisition_clk) begin
    if (!acquisition_domain_resetn) begin
      write_pointer_gray_sync_1 <= {POINTER_WIDTH{1'b0}};
      write_pointer_gray_sync_2 <= {POINTER_WIDTH{1'b0}};
      dropped_count_gray_sync_1 <= 32'd0;
      dropped_count_gray_sync_2 <= 32'd0;
    end else begin
      write_pointer_gray_sync_1 <= source_pointer_gray;
      write_pointer_gray_sync_2 <= write_pointer_gray_sync_1;
      dropped_count_gray_sync_1 <= source_dropped_count_gray;
      dropped_count_gray_sync_2 <= dropped_count_gray_sync_1;
    end
  end

endmodule
