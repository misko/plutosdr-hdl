// Disabled wrapper is compared unconditionally to the unchanged baseline.
`timescale 1ns/1fs
module tb;
  parameter integer PROFILE=1;
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #1.3;forever #5 clk=~clk;end
  retained_clock_witness clocks(.fast_clk(fft_clk),.slow_clk(clk),.slow_clock_enabled(1'b1));
  reg input_valid=0,input_last=0;reg[35:0]input_data=0;reg[8:0]input_position=0;
  reg[63:0]input_block_start=0;wire input_ready,output_valid,output_last,fault;
  reg output_ready=0;wire[35:0]output_data;wire[8:0]output_position;wire[74:0]output_metadata;
  wire old_input_ready,old_output_valid,old_output_last,old_fault;
  wire[35:0]old_output_data;wire[8:0]old_output_position;wire[74:0]old_output_metadata;
  starlink_pss_fft_bank_owned_retained_output_probe #(.REGISTERED_SCHEDULING(PROFILE),
    .BOUNDARY_ROUND_SAT(PROFILE),.REGISTER_OPERANDS(PROFILE),.LOCAL_FIRST_ADMISSION(PROFILE)) dut(.*);
  starlink_pss_fft_bank_owned_local_admission_probe #(.REGISTERED_SCHEDULING(PROFILE),
    .BOUNDARY_ROUND_SAT(PROFILE),.REGISTER_OPERANDS(PROFILE),.LOCAL_FIRST_ADMISSION(PROFILE)) original(
    .input_ready(old_input_ready),.output_valid(old_output_valid),.output_last(old_output_last),
    .output_data(old_output_data),.output_position(old_output_position),.output_metadata(old_output_metadata),
    .fault(old_fault),.*);
  `define D dut.unchanged.island
  integer checks=0,slow_cycles=0,reads=0,block_index,k;
  reg[31:0]samples[0:1405];reg[35:0]inverses[0:1535];
  task compare;
    begin
      if({input_ready,output_valid,output_last,output_data,output_position,output_metadata,fault}!==
        {old_input_ready,old_output_valid,old_output_last,old_output_data,old_output_position,old_output_metadata,old_fault})
        $fatal(1,"unconditional default public equality");
      if({`D.state,`D.core_input_data,`D.core_input_valid,`D.core_input_last,`D.core_aresetn,
        `D.core_output_data,`D.core_output_user,`D.core_output_valid,`D.core_status_valid,
        `D.source_bank.request_toggle,`D.product_bank.request_toggle,`D.output_bank.request_toggle,
        `D.output_bank.read_payload}!==
        {original.state,original.core_input_data,original.core_input_valid,original.core_input_last,original.core_aresetn,
        original.core_output_data,original.core_output_user,original.core_output_valid,original.core_status_valid,
        original.source_bank.request_toggle,original.product_bank.request_toggle,original.output_bank.request_toggle,
        original.output_bank.read_payload})$fatal(1,"unconditional default internal equality");
      checks=checks+1;
    end
  endtask
  always @(posedge fft_clk or negedge fft_clk or posedge clk or negedge clk)begin compare;#0.001;compare;end
  always @(negedge clk)begin slow_cycles=slow_cycles+1;output_ready=slow_cycles%17<13;end
  always @(posedge clk)if(output_valid&&output_ready)begin
    if(output_data!==inverses[reads]||output_position!==9'(reads%512))$fatal(1,"default numeric unchanged");
    reads=reads+1;
  end
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("inverse_q17.mem",inverses);
    repeat(10)@(negedge fft_clk);resetn=1;fft_resetn=1;
    for(block_index=0;block_index<3;block_index=block_index+1)begin
      for(k=0;k<512;k=k+1)begin
        @(negedge clk);input_valid=1;input_last=k==511;input_position=9'(k);input_block_start=1000+block_index*447;
        input_data={samples[block_index*447+k][31:16],2'b0,samples[block_index*447+k][15:0],2'b0};
        do @(posedge clk);while(input_ready!==1);#0.001;
      end
      @(negedge clk);input_valid=0;
    end
    wait(reads==1536);repeat(10)@(negedge clk);
    if(fault!==0||checks<10000)$fatal(1,"default inventory");
    $display("OFFLINE_PASS default unchanged profile=%0d unconditional_checks=%0d reads=%0d",PROFILE,checks,reads);$finish;
  end
  initial begin #150000;$fatal(1,"default bounded timeout");end
  `undef D
endmodule
