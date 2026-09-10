// Read-only low-register capture witness; no new AXI transaction or delay.
// All values below derive from the frozen ideal60/100MHz clock/AXI contract.
  localparam integer N60_CONTROL_FS = 10000000, N60_SOURCE_FS = 16666666;
  localparam integer N60_OFFER_TO_ACCEPT_FS = 8333333, N60_GRAY_STAGES = 2;
  localparam integer N60_READ_CYCLES = 2*24;
  localparam integer N60_CAPTURE_LAG =
      (N60_GRAY_STAGES*N60_CONTROL_FS + N60_OFFER_TO_ACCEPT_FS + N60_SOURCE_FS-1)/N60_SOURCE_FS;
  localparam integer N60_RETURN_LAG = N60_CAPTURE_LAG +
      (N60_READ_CYCLES*N60_CONTROL_FS + N60_SOURCE_FS-1)/N60_SOURCE_FS;
  integer native_index_capture_count = 0, native_index_capture_cycle = -1;
  reg [63:0] native_index_witness = 0, native_index_live_at_capture = 0;
  wire native_low_register_capture = native.up_rreq && !native.register_read_pending &&
      !native.result_read_pending && !native.telemetry_read_pending && native.up_raddr == 6'h06;
  always @(posedge clk) if (resetn && native_configured) begin
    if ((^{native.up_rreq, native.register_read_pending, native.result_read_pending,
        native.telemetry_read_pending}) === 1'bx ||
        (native.up_rreq === 1'b1 && (^native.up_raddr) === 1'bx))
      fail("native60 unknown low-register request/pending/address flags");
    if (native_low_register_capture === 1'b1) begin
      if (native_index_capture_count != 0 || native_trigger_cycle < 0 ||
          native_command_issued !== 1'b0 || {source_enable, sample_strobe} !== 2'b11 ||
          (^{native.current_sample_index, sample_index}) === 1'bx)
        fail("native60 duplicate/unknown/ineligible low-register witness");
      native_index_capture_count = native_index_capture_count + 1;
      native_index_capture_cycle = cycles;
      native_index_witness = native.current_sample_index;
      native_index_live_at_capture = sample_index;
      if (native_index_witness > native_index_live_at_capture ||
          native_index_witness < RAW_FIRST ||
          native_index_live_at_capture - native_index_witness > N60_CAPTURE_LAG)
        fail("native60 low-register witness is future/stale versus offered source");
    end
  end
  task automatic check_native_snapshot(input [63:0] public_index);
    if (native_index_capture_count != 1 || native_index_capture_cycle < native_trigger_cycle ||
        cycles < native_index_capture_cycle || cycles-native_index_capture_cycle > N60_READ_CYCLES ||
        public_index !== native_index_witness || native.current_index_snapshot !== native_index_witness ||
        (^{public_index, sample_index}) === 1'bx || {source_enable, sample_strobe} !== 2'b11 ||
        sample_index < native_index_live_at_capture || public_index > sample_index ||
        sample_index-public_index > N60_RETURN_LAG)
      fail("native60 public64 readback missing/incoherent/unknown/future/stale");
    $display("NATIVE60_SNAPSHOT count=%0d capture_cycle=%0d return_cycle=%0d captured_index=%0d live_at_capture=%0d public_index=%0d retained_index=%0d live_at_return=%0d capture_lag=%0d return_lag=%0d maximum_capture_lag=%0d maximum_return_lag=%0d maximum_return_cycles=%0d",
      native_index_capture_count, native_index_capture_cycle, cycles, native_index_witness,
      native_index_live_at_capture, public_index, native.current_index_snapshot, sample_index,
      native_index_live_at_capture-native_index_witness, sample_index-public_index,
      N60_CAPTURE_LAG, N60_RETURN_LAG, N60_READ_CYCLES);
  endtask
