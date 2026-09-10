// Direct three-port test master, no hierarchy writes. A fixed<=24-cycle
// transaction admission bound contributes to the frozen native source budget.
  integer maximum_axi_cycles = 0;
  task automatic transaction_end(input integer port, input integer first_cycle);
    integer elapsed;
    elapsed = cycles - first_cycle;
    if (elapsed > 24) fail("public AXI transaction exceeded frozen24-cycle bound");
    if (elapsed > maximum_axi_cycles) maximum_axi_cycles = elapsed;
    if (port == 2 && native_capture_end_cycle >= 0) begin
      native_readout_transactions = native_readout_transactions + 1;
      if (native_readout_transactions > 140) fail("native readout exceeded140 transactions");
    end
  endtask
  task automatic write_reg(input integer port, input [7:0] address, input [31:0] value);
    integer timeout, first_cycle;
    @(negedge clk); first_cycle = cycles; awaddr[port] = address; wdata[port] = value;
    awvalid[port] = 1; wvalid[port] = 1; bready[port] = 1; timeout = 0;
    while (!(awready[port] && wready[port]) && timeout < 24) begin
      @(posedge clk); timeout = timeout + 1;
    end
    if (timeout == 24) fail("AXI address/data timeout");
    @(negedge clk); awvalid[port] = 0; wvalid[port] = 0; timeout = 0;
    while (!bvalid[port] && timeout < 24) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 24 || bresp[port] !== 0) fail("AXI write response");
    @(negedge clk); bready[port] = 0; transaction_end(port, first_cycle);
  endtask
  task automatic read_reg(input integer port, input [7:0] address, output [31:0] value);
    integer timeout, first_cycle;
    @(negedge clk); first_cycle = cycles; araddr[port] = address;
    arvalid[port] = 1; rready[port] = 1; timeout = 0;
    while (!arready[port] && timeout < 24) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 24) fail("AXI read address timeout");
    @(negedge clk); arvalid[port] = 0; timeout = 0;
    while (!rvalid[port] && timeout < 24) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 24 || rresp[port] !== 0) fail("AXI read response");
    value = rdata[port]; @(negedge clk); rready[port] = 0;
    transaction_end(port, first_cycle);
  endtask
  task automatic expect_reg(input integer port, input [7:0] address, input [31:0] expected);
    reg [31:0] actual;
    read_reg(port, address, actual);
    if (actual !== expected) begin
      $display("HIGH_RATE_REGISTER port=%0d address=%02x actual=%08x expected=%08x", port, address, actual, expected);
      fail("public register value mismatch");
    end
  endtask
