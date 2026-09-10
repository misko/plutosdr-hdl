// Read-only sampled core interface and event-indexed receipt; no vendor internals.
integer actual_inputs=0,actual_raw=0,actual_status=0,actual_frames=0,actual_config=0;
integer actual_jobs=0,actual_commits=0,actual_aborts=0,actual_input_total=0;
integer actual_raw_total=0,actual_status_total=0,actual_fixture=0;
integer actual_admit=0,actual_first_input=0,actual_last_input=0,actual_first_raw=0;
integer actual_reset_low=0,actual_frame_cycle=0;
reg actual_inverse=0,actual_active=0,actual_previous_resetn=0;
reg[63:0]actual_start=0;
reg[35:0]actual_expected;
reg[4:0]actual_exponent;
task automatic actual_word(input string stream,input integer job,input integer pos,
  input reg[47:0]data,input reg[63:0]start,input reg[9:0]exponent);
  $fdisplay(words_log,"%0d,%s,%0d,%0d,%012h,%016h,%03h,%0d,%0d,%0.0f",
    context_id,stream,job,pos,data,start,exponent,fast_cycles,slow_edges,$realtime*1000000.0);
endtask
always @(posedge fft_clk)begin
  #0; // inactive region before NBA; source stimulus is driven on falling edges.
  if(`D.fast_running)begin
    if((^({`D.core_aresetn,`D.job_accept,`D.config_valid,`D.config_ready,
      `D.core_input_valid,`D.core_input_ready,`D.core_output_valid,`D.core_status_valid,
      `D.event_frame,`D.event_last_unexpected,`D.event_last_missing,`D.event_input_halt,
      `D.certified_input_beat,`D.certified_input_complete}))===1'bx)
      $fatal(1,"unknown actual core protocol control");
    if(!`D.core_aresetn)actual_reset_low=actual_reset_low+1;
    if(`D.core_aresetn&&!actual_previous_resetn)begin
      if(actual_reset_low<2)$fatal(1,"actual sampled reset shorter than two cycles");
      $display("RACT_RESET_RELEASE context=%0d cycle=%0d sampled_low=%0d",context_id,fast_cycles,actual_reset_low);
      actual_reset_low=0;
    end
    actual_previous_resetn=`D.core_aresetn;
    if(`D.job_accept)begin
      if(actual_active)$fatal(1,"actual overlapping core owners");
      actual_start=`D.engine_metadata[68:5];
      if(actual_start<1000||(actual_start-1000)%447!=0||(actual_start-1000)/447>2)
        $fatal(1,"actual independent source identity");
      actual_fixture=(actual_start-1000)/447;actual_inverse=`D.next_inverse;
      actual_inputs=0;actual_raw=0;actual_status=0;actual_frames=0;actual_config=0;
      actual_admit=fast_cycles;actual_active=1;actual_jobs=actual_jobs+1;
      $display("RACT_ADMIT context=%0d job=%0d inverse=%0d start=%0d cycle=%0d source_valid=%b source_start=%0d retained=%b",
        context_id,actual_jobs,actual_inverse,actual_start,fast_cycles,`D.source_valid,`D.source_metadata[68:5],`D.retained_published);
    end
    if(`D.config_valid&&`D.config_ready)begin
      if(!actual_active||actual_config!=0||fast_cycles-actual_admit!=3||
        `D.shared_xfft.s_axis_config_tdata!==(actual_inverse?8'h00:8'h01))$fatal(1,"actual config handshake/timing");
      actual_config=actual_config+1;
    end
    if(`D.certified_input_beat!==(`D.core_input_valid&&`D.core_input_ready))
      $fatal(1,"physical/certified core input mismatch");
    if(`D.core_input_valid&&`D.core_input_ready)begin
      if(!actual_active||actual_config!=1||actual_inputs>=512)$fatal(1,"unowned actual core input");
      actual_expected=actual_inverse?products[actual_fixture*512+actual_inputs]:
        {samples[actual_fixture*447+actual_inputs][31:16],2'b0,samples[actual_fixture*447+actual_inputs][15:0],2'b0};
      if(`D.core_input_data!=={6'b0,actual_expected[35:18],6'b0,actual_expected[17:0]}||
         `D.core_input_last!==(actual_inputs==511))
        $fatal(1,"actual48 input context=%0d job=%0d ordinal=%0d actual=%h expected=%h",context_id,actual_jobs,actual_inputs,`D.core_input_data,{6'b0,actual_expected[35:18],6'b0,actual_expected[17:0]});
      if(actual_inputs==0)actual_first_input=fast_cycles;
      actual_last_input=fast_cycles;
      if(actual_inverse)actual_word("inputI",actual_fixture,actual_inputs,`D.core_input_data,actual_start,0);
      else actual_word("inputF",actual_fixture,actual_inputs,`D.core_input_data,actual_start,0);
      actual_inputs=actual_inputs+1;actual_input_total=actual_input_total+1;
      if(`D.certified_input_complete!==(actual_inputs==512))$fatal(1,"actual physical final certification");
    end else if(`D.certified_input_complete)$fatal(1,"completion without physical final input");
    if(`D.event_frame)begin
      if(!actual_active||actual_frames!=0||actual_inputs!=1)$fatal(1,"actual fresh frame ordinal");
      actual_frames=actual_frames+1;actual_frame_cycle=fast_cycles;
    end
    actual_exponent=actual_inverse?ie[actual_fixture]:fe[actual_fixture];
    if(`D.core_status_valid)begin
      if(!actual_active||actual_inputs!=512||actual_status!=0||actual_raw!=2||
         `D.core_status_data!=={3'b0,actual_exponent})$fatal(1,"actual status join/ordinal/exponent");
      actual_status=actual_status+1;actual_status_total=actual_status_total+1;
      $display("RACT_STATUS context=%0d job=%0d ordinal=%0d cycle=%0d",context_id,actual_jobs,actual_raw,fast_cycles);
    end
    if(`D.core_output_valid)begin
      if(!actual_active||actual_inputs!=512||actual_frames!=1||actual_raw>=512)
        $fatal(1,"unowned actual raw output");
      actual_expected=actual_inverse?inverses[actual_fixture*512+actual_raw]:forwards[actual_fixture*512+actual_raw];
      // PG109 May4 2022 printed p21: output TDATA sign-extends to byte boundaries.
      if(`D.core_output_data!=={{6{actual_expected[35]}},actual_expected[35:18],{6{actual_expected[17]}},actual_expected[17:0]}||
         `D.core_output_user!=={3'b0,actual_exponent,7'b0,9'(actual_raw)}||
         `D.core_output_last!==(actual_raw==511))$fatal(1,"actual raw packed payload/index/exponent");
      if(actual_raw==0)begin
        actual_first_raw=fast_cycles;
        if(fast_cycles-actual_last_input!=781)$fatal(1,"actual raw first absolute service");
      end
      if(actual_raw==511&&fast_cycles-actual_admit!=1809)$fatal(1,"actual raw last absolute service");
      if(actual_inverse)actual_word("rawI",actual_fixture,actual_raw,`D.core_output_data,actual_start,{5'b0,actual_exponent});
      else actual_word("rawF",actual_fixture,actual_raw,`D.core_output_data,actual_start,{5'b0,actual_exponent});
      actual_raw=actual_raw+1;actual_raw_total=actual_raw_total+1;
    end
    if(`D.return_commit_valid&&`D.result_destination_ready)begin
      if(!actual_active||actual_inputs!=512||actual_raw!=512||actual_status!=1||actual_frames!=1||
         actual_config!=1||actual_last_input-actual_first_input+1!=513||fast_cycles-actual_admit!=1810)
        $fatal(1,"actual complete transform absolute service/inventory");
      $display("RACT_JOB context=%0d job=%0d inverse=%0d fixture=%0d admit=%0d config_delta=3 input_first=%0d input_last=%0d raw_first=%0d publication=%0d inputs=512 raw=512 status=1 frame=1",
        context_id,actual_jobs,actual_inverse,actual_fixture,actual_admit,actual_first_input,actual_last_input,actual_first_raw,fast_cycles);
      actual_commits=actual_commits+1;actual_active=0;
    end
    if(`D.product_valid&&`D.product_bank_ready)
      actual_word("product",actual_fixture,`D.product_position,{12'b0,`D.product_q,`D.product_i},actual_start,{5'b0,`D.product_exponent});
    if(`D.guard_private_out[1]&&`D.output_bank_ready)
      actual_word("privateI",actual_fixture,`D.guard_return_position[1],{12'b0,`D.guard_return_data[1]},actual_start,`D.guard_return_metadata[1][9:0]);
    if(`D.guard_commit_out[1]&&`D.output_bank_ready)
      $display("RACT_SOURCE_ELIGIBILITY context=%0d cycle=%0d source_valid=%b source_start=%0d",context_id,fast_cycles,`D.source_valid,`D.source_metadata[68:5]);
  end else begin actual_previous_resetn=0;actual_reset_low=0;end
end
always @(negedge resetn or negedge fft_resetn)begin
  if(actual_active)begin
    if(context_id<5||actual_inverse||actual_fixture!=1||actual_inputs<64||actual_inputs>=512||
       actual_raw!=0||actual_status!=0||actual_config!=1||actual_frames!=1)
      $fatal(1,"unexpected reset of actual core owner");
    $display("RACT_ABORT context=%0d job=%0d fixture=%0d inputs=%0d first=%0d last=%0d raw=0 status=0 cycle=%0d",
      context_id,actual_jobs,actual_fixture,actual_inputs,actual_first_input,actual_last_input,fast_cycles);
    actual_aborts=actual_aborts+1;actual_active=0;
  end
end
always @(posedge clk)begin
  #0;
  if(input_valid&&input_ready)actual_word("source",int'((input_block_start-1000)/447),input_position,{12'b0,input_data},input_block_start,0);
  if(output_valid&&output_ready)actual_word("read",int'((output_metadata[73:10]-1000)/447),output_position,{12'b0,output_data},output_metadata[73:10],output_metadata[9:0]);
end
