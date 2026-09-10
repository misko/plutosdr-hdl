// Additive observer and binding only; no original stimulus/check retiming.
starlink_pss_local_admission_actual_observer #(.L(L)) local_guard_observer (
  .clk(dut.input_guard.clk), .resetn(dut.input_guard.resetn),
  .job_start(dut.input_guard.job_start), .job_descriptor(dut.input_guard.job_descriptor),
  .input_enable(dut.input_guard.input_enable), .input_valid(dut.input_guard.input_valid),
  .input_data(dut.input_guard.input_data), .input_position(dut.input_guard.input_position),
  .input_last(dut.input_guard.input_last), .input_metadata(dut.input_guard.input_metadata),
  .core_input_tready(dut.input_guard.core_input_tready),
  .actual_view({dut.input_guard.input_ready,dut.input_guard.input_transport_ready,dut.input_guard.core_input_tdata,
    dut.input_guard.core_input_tvalid,dut.input_guard.core_input_tlast,dut.input_guard.certified_input_beat,dut.input_guard.certified_input_complete,
    dut.input_guard.input_complete,dut.input_guard.fault_now,dut.input_guard.duplicate_start_fault_now,dut.input_guard.fault_events_now,
    dut.input_guard.protocol_fault,dut.input_guard.fault_reasons,dut.input_guard.job_started,dut.input_guard.input_started,dut.input_guard.descriptor,dut.input_guard.expected_position,
    dut.input_guard.slot_open,dut.input_guard.eligible,dut.input_guard.metadata_valid,dut.input_guard.identity_matches,dut.input_guard.errors_now,
    dut.input_guard.framing_error,dut.input_guard.delivery_error,dut.input_guard.duplicate_start})
);
initial begin
  #0.01;
  if ((L !== 0 && L !== 1) || R !== 1 || B !== 1 || O !== 1 || FAST_MHZ !== 175 ||
      QUICK_MUTATION !== 0 || dut.LOCAL_FIRST_ADMISSION !== L ||
      dut.input_guard.LOCAL_FIRST_ADMISSION !== L ||
      dut.input_guard.CHECK_INPUT_BLOCK_IDENTITY !== 1 ||
      dut.input_guard.BALANCED_IDENTITY_EQ !== 1 ||
      local_guard_observer.L !== L || local_guard_observer.default_guard.LOCAL_FIRST_ADMISSION !== 0)
    $fatal(1,"LOCAL_ADMISSION_ACTUAL_INSTANCE_BINDING_MISMATCH");
end
