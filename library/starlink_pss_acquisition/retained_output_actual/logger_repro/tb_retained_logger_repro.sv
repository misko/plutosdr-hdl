// Minimal simulator/logger compatibility probe. No DUT, FFT, clocks or runtime.
`timescale 1ns/1fs
module tb;
  parameter integer CASE=0;
  localparam FAMILY=CASE/6, MODE=(CASE%6)/2, PHASE=CASE%2;
  integer words_log=0,context_id=0,fast_cycles=939,slow_edges=536;
  reg actual_inverse=0;
  // This task is byte-identical to the frozen actual witness's task body.
task automatic actual_word(input string stream,input integer job,input integer pos,
  input reg[47:0]data,input reg[63:0]start,input reg[9:0]exponent);
  $fdisplay(words_log,"%0d,%s,%0d,%0d,%012h,%016h,%03h,%0d,%0d,%0.0f",
    context_id,stream,job,pos,data,start,exponent,fast_cycles,slow_edges,$realtime*1000000.0);
endtask
  initial begin
    if(CASE<0||CASE>11)$fatal(1,"logger probe exact twelve cases only");
    words_log=$fopen("logger_rows.csv","w");if(!words_log)$fatal(1,"logger open");
    $fdisplay(words_log,"context,stream,job,position,data,start,exponent,fast,slow,time_fs");
    #1;actual_inverse=PHASE;
    #1;actual_word("source",0,0,48'h123456789abc,64'd1000,10'd3);
    $fflush(words_log);
    $display("LOGGER_REPRO_SOURCE case=%0d family=%0d mode=%0d phase=%0d",CASE,FAMILY,MODE,PHASE);
    #1;
    if(FAMILY==0)begin
      case(MODE)
        0:begin
          if(PHASE)actual_word("inputI",0,0,48'h123456789abc,64'd1000,10'd3);
          else actual_word("inputF",0,0,48'h123456789abc,64'd1000,10'd3);
        end
        1:actual_word(actual_inverse?"inputI":"inputF",0,0,48'h123456789abc,64'd1000,10'd3);
        2:begin
          if(actual_inverse)actual_word("inputI",0,0,48'h123456789abc,64'd1000,10'd3);
          else actual_word("inputF",0,0,48'h123456789abc,64'd1000,10'd3);
        end
      endcase
    end else begin
      case(MODE)
        0:begin
          if(PHASE)actual_word("rawI",0,0,48'h123456789abc,64'd1000,10'd3);
          else actual_word("rawF",0,0,48'h123456789abc,64'd1000,10'd3);
        end
        1:actual_word(actual_inverse?"rawI":"rawF",0,0,48'h123456789abc,64'd1000,10'd3);
        2:begin
          if(actual_inverse)actual_word("rawI",0,0,48'h123456789abc,64'd1000,10'd3);
          else actual_word("rawF",0,0,48'h123456789abc,64'd1000,10'd3);
        end
      endcase
    end
    $fclose(words_log);
    $display("LOGGER_REPRO_COMPLETED case=%0d rows=2 NOT_FFT_OR_RUNTIME_QUALIFICATION",CASE);
    $finish;
  end
endmodule
