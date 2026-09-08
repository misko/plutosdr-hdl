`timescale 1ns/1ps
module tb_starlink_pilot_pacer_memory;
  parameter integer ADDRESS_WIDTH = 7;
  localparam integer DEPTH = 1 << ADDRESS_WIDTH;
  reg clk = 0;
  always #5 clk = !clk;
  reg write_enable = 0, read_enable = 0;
  reg [ADDRESS_WIDTH-1:0] write_address = 0, read_address = 0;
  reg [32:0] write_data = 0;
  wire [32:0] read_data;
  reg [32:0] reference_memory [0:DEPTH-1];
  reg [32:0] expected_read = 0;
  reg have_read = 0;
  integer position, iteration, checked_reads = 0, held_reads = 0;
  starlink_pilot_pacer_memory #(.ADDRESS_WIDTH(ADDRESS_WIDTH)) dut (.*);

  task automatic cycle(input bit we, input integer wa, input [32:0] wd,
                       input bit re, input integer ra);
    begin
      @(negedge clk);
      write_enable = we;
      write_address = wa;
      write_data = wd;
      read_enable = re;
      read_address = ra;
      // A simultaneous read/write to the same address MUST return old data.
      if (re) begin
        expected_read = reference_memory[ra & (DEPTH-1)];
        have_read = 1;
        checked_reads = checked_reads + 1;
      end else if (have_read) held_reads = held_reads + 1;
      if (we) reference_memory[wa & (DEPTH-1)] = wd;
      @(posedge clk);
      #1;
      if (have_read && read_data !== expected_read)
        $fatal(1, "pacer RAM mismatch we=%0d wa=%0d re=%0d ra=%0d got=%h expected=%h",
               we, wa, re, ra, read_data, expected_read);
    end
  endtask

  initial begin
    for (position = 0; position < DEPTH; position = position + 1)
      cycle(1, position, 33'h123456789 ^ position, 0, 0);
    for (iteration = 0; iteration < 4; iteration = iteration + 1) begin
      for (position = 0; position < DEPTH; position = position + 1) begin
        cycle(1, position, 33'h1abcdef01 ^ (iteration * 65537) ^ position, 1, position);
        cycle(0, 0, 0, 1, position);
        cycle(1, position ^ (DEPTH-1), 33'hfedcba98 ^ position, 0, position);
        cycle(1, position, 33'h16543210f ^ position, 1, position ^ (DEPTH-1));
      end
    end
    $display("PILOT_PACER_MEMORY_PASS depth=%0d reads=%0d held=%0d collision_read_first=1 latency_cycles=1",
             DEPTH, checked_reads, held_reads);
    $finish(0);
  end
endmodule
