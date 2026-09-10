// Actual FFT-clock core consumption, not slow source-bank acceptance. Every
// visible healthy/provisional prefix is checked; no assumed seven-job drain.
`define H60_IQ dut.acquisition.bank_transform.iq_to_score
`define H60_ISLAND dut.acquisition.bank_transform.iq_to_score.island
`define H60_PREP dut.acquisition.bank_transform.iq_to_score.candidate_score_path.score_prepare
  reg [35:0] fft_inputs[0:3583],forwards[0:3583],products[0:3583],inverses[0:3583];
  reg [4:0] forward_exps[0:6],inverse_exps[0:6];
  reg [37:0] energies[0:3128];
  reg [68:0] numerators[0:3128],denominators[0:3128];
  reg [6:0] power_shifts[0:6];
  reg saturations[0:3128];
  reg [7:0] scores[0:3128];
  reg [15:0] map_words[0:446];
  integer forward_input_count=0,inverse_input_count=0,forward_count=0,product_count=0;
  integer inverse_count=0,prepare_count=0,ratio_count=0,score_count=0;
  integer fast_pos,fast_block,slow_pos,slow_block,quiet_cycles=0;
  reg [35:0] expected_fft_input;
  wire native_fft_active=`H60_ISLAND.core_input_valid && `H60_ISLAND.core_input_ready;
  wire native_coarse_pilot_active=`H60_IQ.pipeline_active && pilot_enable;
  task automatic load_fft_vectors;
    $readmemh("fft_input_q17.mem",fft_inputs); $readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products); $readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",forward_exps); $readmemh("inverse_exponents.mem",inverse_exps);
    $readmemh("energies_u38.mem",energies); $readmemh("numerators_u69.mem",numerators);
    $readmemh("denominators_u69.mem",denominators); $readmemh("power_shift_u7.mem",power_shifts);
    $readmemh("saturated_u1.mem",saturations); $readmemh("scores_u8.mem",scores);
    $readmemh("map_447x2_u16.mem",map_words);
  endtask
  always @(posedge fft_clk) if (resetn) begin
    if ((^{`H60_ISLAND.joiner.input_valid,`H60_ISLAND.joiner.input_ready,
           `H60_ISLAND.product_valid,`H60_ISLAND.fast_fault,`H60_ISLAND.product_bank_ready,
           `H60_ISLAND.product_overflow,`H60_ISLAND.fast_running})===1'bx)
      fail("unknown forward/product handshake protocol");
    if (`H60_ISLAND.fast_running===1'b1 &&
        (^{`H60_ISLAND.core_input_valid,`H60_ISLAND.core_output_valid})===1'bx)
      fail("unknown active FFT-core valid protocol");
    if (`H60_ISLAND.core_input_valid===1'b1 && (^{`H60_ISLAND.core_input_ready,`H60_ISLAND.next_inverse})===1'bx)
      fail("unknown actual FFT input handshake/direction");
    if (`H60_ISLAND.core_input_valid===1'b1 && `H60_ISLAND.core_input_ready===1'b1 &&
        native.capture_active===1'b1) begin
      native_capture_fft_overlap=native_capture_fft_overlap+1;
      if(native_admissions!=1 || native_capture_count>=520)
        fail("FFT capture overlap outside actual admitted native capture");
    end
    if (`H60_ISLAND.core_input_valid && `H60_ISLAND.core_input_ready) begin
      if (`H60_ISLAND.next_inverse) begin
        if (inverse_input_count>=3584) fail("inverse input exceeded frozen support");
        fast_pos=inverse_input_count%512; fast_block=inverse_input_count/512;
        expected_fft_input=products[inverse_input_count]; inverse_input_count=inverse_input_count+1;
      end else begin
        if (forward_input_count>=3584) fail("forward input exceeded frozen support");
        fast_pos=forward_input_count%512; fast_block=forward_input_count/512;
        expected_fft_input=fft_inputs[forward_input_count]; forward_input_count=forward_input_count+1;
      end
      if (`H60_ISLAND.selected_data!==expected_fft_input || `H60_ISLAND.selected_position!==fast_pos ||
          `H60_ISLAND.core_input_data!=={6'b0,expected_fft_input[35:18],6'b0,expected_fft_input[17:0]} ||
          `H60_ISLAND.engine_metadata[68:5]!==FIRST+447*fast_block ||
          `H60_ISLAND.core_input_last!==(fast_pos==511)) begin
        $display("HIGH_RATE60_CORE_DETAIL inverse=%b selected=%09x expected=%09x wire=%012x position=%0d expected_position=%0d start=%0d expected_start=%0d",`H60_ISLAND.next_inverse,`H60_ISLAND.selected_data,expected_fft_input,`H60_ISLAND.core_input_data,`H60_ISLAND.selected_position,fast_pos,`H60_ISLAND.engine_metadata[68:5],FIRST+447*fast_block);
        fail("actual own-clock FFT input/ABI/index/last mismatch");
      end
    end
    if (`H60_ISLAND.joiner.input_valid && `H60_ISLAND.joiner.input_ready) begin
      fast_pos=forward_count%512; fast_block=forward_count/512;
      if (forward_count>=3584 || `H60_ISLAND.return_data!==forwards[forward_count] ||
          `H60_ISLAND.return_position!==fast_pos || `H60_ISLAND.return_metadata[4:0]!==forward_exps[fast_block] ||
          `H60_ISLAND.return_metadata[73:10]!==FIRST+447*fast_block || `H60_ISLAND.return_last!==(fast_pos==511))
        fail("forward output word/BFP/index/last mismatch");
      forward_count=forward_count+1;
    end
    if (`H60_ISLAND.product_valid && !`H60_ISLAND.fast_fault && `H60_ISLAND.product_bank_ready) begin
      fast_pos=product_count%512; fast_block=product_count/512;
      if (product_count>=3584 || {`H60_ISLAND.product_q,`H60_ISLAND.product_i}!==products[product_count] ||
          `H60_ISLAND.product_position!==fast_pos || `H60_ISLAND.product_exponent!==forward_exps[fast_block] ||
          `H60_ISLAND.product_start!==FIRST+447*fast_block || `H60_ISLAND.product_last!==(fast_pos==511) ||
          `H60_ISLAND.product_overflow!==0) fail("product word/BFP/index/last/overflow mismatch");
      product_count=product_count+1;
    end
    #0.001;
    if (coarse_stopped && !`H60_IQ.pipeline_active) begin
      quiet_cycles=quiet_cycles+1;
      if (quiet_cycles>=8 && (`H60_ISLAND.fast_running!==0 || `H60_ISLAND.core_aresetn!==0 ||
          `H60_ISLAND.config_valid!==0 || `H60_ISLAND.core_input_valid!==0 || `H60_ISLAND.core_output_valid!==0))
        fail("bank-only teardown did not close fast core");
    end else if (quiet_cycles) fail("bank reactivated after healthy STOP teardown");
  end
  always @(posedge clk) if (resetn) begin
    if ((^{`H60_IQ.inverse_output_ready,`H60_PREP.input_valid,`H60_PREP.input_ready,
           `H60_PREP.output_valid,`H60_PREP.output_ready})===1'bx)
      fail("unknown inverse/energy/normalization handshake protocol");
    if ((^{dut.acquisition.score_valid,`H60_IQ.inverse_output_valid})===1'bx)
      fail("unknown score/inverse visible protocol");
    if (quiet_cycles>=8 && {dut.acquisition.score_valid,`H60_IQ.inverse_output_valid}!==0)
      fail("stale score/inverse after bank-local quarantine");
    if (`H60_IQ.inverse_output_valid && `H60_IQ.inverse_output_ready) begin
      slow_pos=inverse_count%512; slow_block=inverse_count/512;
      if (inverse_count>=3584 || {`H60_IQ.inverse_output_q,`H60_IQ.inverse_output_i}!==inverses[inverse_count] ||
          `H60_IQ.inverse_output_position!==slow_pos || `H60_IQ.inverse_forward_exponent!==forward_exps[slow_block] ||
          `H60_IQ.inverse_output_exponent!==inverse_exps[slow_block] ||
          `H60_IQ.inverse_output_block_start!==FIRST+447*slow_block || `H60_IQ.inverse_output_last!==(slow_pos==511))
        fail("inverse word/BFP/index/last mismatch");
      inverse_count=inverse_count+1;
    end
    if (`H60_PREP.input_valid && `H60_PREP.input_ready) begin
      slow_pos=prepare_count%447; slow_block=prepare_count/447;
      if (prepare_count>=3129 || `H60_PREP.input_sample_energy!==energies[prepare_count] ||
          {`H60_PREP.input_correlation_q,`H60_PREP.input_correlation_i}!==inverses[slow_block*512+slow_pos+65] ||
          `H60_PREP.input_forward_exponent!==forward_exps[slow_block] ||
          `H60_PREP.input_inverse_exponent!==inverse_exps[slow_block] || `H60_PREP.input_start_index!==FIRST+prepare_count)
        fail("score-preparation energy/correlation/BFP/index mismatch");
      prepare_count=prepare_count+1;
    end
    if (`H60_PREP.output_valid && `H60_PREP.output_ready) begin
      if (ratio_count>=3129 || `H60_PREP.output_numerator!==numerators[ratio_count] ||
          `H60_PREP.output_denominator!==denominators[ratio_count] ||
          `H60_PREP.output_power_shift!==power_shifts[ratio_count/447] ||
          `H60_PREP.output_numerator_saturated!==saturations[ratio_count] ||
          `H60_PREP.output_denominator_zero!==0 || `H60_PREP.output_start_index!==FIRST+ratio_count)
        fail("normalized69-bit numerator/denominator/flags/index mismatch");
      ratio_count=ratio_count+1;
    end
    if (dut.acquisition.score_valid) begin
      // Frozen bound permits at most one complete already-computed tail block,
      // but every visible tail remains exact and map admission stays894.
      if (score_count>=1341 || dut.acquisition.score_value!==scores[score_count] ||
          dut.acquisition.score_start_index!==FIRST+score_count ||
          dut.acquisition.score_phase!==score_count%447 || dut.acquisition.score_denominator_zero!==0)
        fail("every visible score/index/phase or bounded post-fence tail mismatch");
      score_count=score_count+1;
    end
  end
`undef H60_IQ
`undef H60_ISLAND
`undef H60_PREP
