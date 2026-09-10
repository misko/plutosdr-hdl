// Additive protocol observations. The old 155-bit guard and both 119-bit
// arithmetic monitors remain unconditional and unchanged. This monitor does
// not retime, force, drive or replace any original fault stimulus.
wire inverse_take = dut.sealed_inverse_output.output_bank.private_take;
wire inverse_certificate = dut.sealed_inverse_output.output_bank.certificate_take;
wire inverse_seal = dut.sealed_inverse_output.output_bank.bank.checked_seal;
wire inverse_publication = dut.sealed_inverse_output.output_bank.publication;
wire inverse_reader_ack = dut.sealed_inverse_output.output_bank.reader_ack;
wire inverse_release = dut.sealed_inverse_output.output_bank.lease_release;
wire [1:0] inverse_lease = dut.sealed_inverse_output.output_bank.lease_reference;
integer inverse_protocol_trace;
integer inverse_protocol_takes = 0, inverse_protocol_publications = 0;
integer inverse_protocol_releases = 0, inverse_protocol_reservations = 0;
integer inverse_protocol_current_vetoes = 0, inverse_protocol_held_finals = 0;
integer inverse_protocol_admit = -1, inverse_protocol_words = 0;
integer inverse_protocol_pub = -1, inverse_protocol_ack = -1;
integer inverse_protocol_release = -1, inverse_protocol_final = -1;
integer inverse_protocol_qualified = -1;
reg [1:0] inverse_protocol_lease = 0;
reg [63:0] inverse_protocol_start = 0;
reg inverse_protocol_owned = 0, inverse_protocol_ack_seen = 0;
reg inverse_protocol_reuse_seen = 0;
initial begin
  inverse_protocol_trace = $fopen("inverse_sealed_protocol.csv", "w");
  $fdisplay(inverse_protocol_trace, "event,epoch,fast_cycle,slow_cycle,start,lease,position,data,metadata");
  #0.01;
  if (E !== 1 || L !== 1 || R !== 1 || B !== 1 || O !== 1 || FAST_MHZ !== 175 ||
      dut.SEALED_INVERSE_OUTPUT !== E || dut.LOCAL_FIRST_ADMISSION !== L ||
      dut.sealed_inverse_output.output_bank.bank.SEALED_PUBLICATION !== 1)
    $fatal(1, "INVERSE_SEALED_ACTUAL_PARAMETER_BINDING");
end
task automatic inverse_protocol_event(input [63:0] name);
  $fdisplay(inverse_protocol_trace, "%0s,%0d,%0d,%0d,%0d,%0d,%0d,%09h,%019h",
    name, epoch, fast_cycle, slow_cycle, inverse_protocol_start,
    inverse_lease, dut.return_position, dut.return_data, dut.return_metadata);
endtask
always @(posedge fft_clk) begin
  if (!dut.fast_running) begin
    inverse_protocol_owned = 0; inverse_protocol_admit = -1;
    inverse_protocol_words = 0; inverse_protocol_pub = -1;
    inverse_protocol_ack = -1; inverse_protocol_release = -1;
    inverse_protocol_qualified = -1; inverse_protocol_ack_seen = 0;
    inverse_protocol_reuse_seen = 0; inverse_protocol_final = -1;
  end else if (dut.fast_running === 1'b1) begin
    // These are real possible publication-edge vetoes, including fault epochs.
    if (dut.sealed_inverse_output.output_bank.certificate_lost ||
        dut.sealed_inverse_output.output_bank.raw_orphan || dut.any_fast_fault) begin
      if (inverse_publication || inverse_release)
        $fatal(1, "INVERSE_SEALED_CURRENT_PUBLICATION_RELEASE_VETO");
      inverse_protocol_current_vetoes = inverse_protocol_current_vetoes + 1;
    end
    if (dut.sealed_inverse_output.output_bank.final_taken &&
        dut.sealed_inverse_output.output_bank.guard_private_valid) begin
      inverse_protocol_held_finals = inverse_protocol_held_finals + 1;
      if (inverse_take) $fatal(1, "INVERSE_SEALED_HELD_FINAL_RETAKEN");
    end
    if (dut.sealed_inverse_output.output_bank.bank.input_valid !==
        (dut.return_private_valid && dut.next_inverse &&
         dut.sealed_inverse_output.output_bank.producer_reference))
      $fatal(1, "INVERSE_SEALED_PRIVATE_PRODUCER_BINDING");
    // The full ordered healthy ledger is independent of old global cycle
    // equality. Original fault expectations/checkers remain active elsewhere.
    if ((epoch == 1 || epoch == 2) && !expected_fault) begin
      if (dut.job_accept && dut.next_inverse) begin
        if (inverse_protocol_owned || !dut.output_bank_ready || !dut.inverse_destination_reserved)
          $fatal(1, "INVERSE_SEALED_ADMISSION_WITHOUT_FREE_RESERVATION");
        inverse_protocol_owned = 1; inverse_protocol_admit = fast_cycle;
        inverse_protocol_words = 0; inverse_protocol_pub = -1;
        inverse_protocol_ack = -1; inverse_protocol_release = -1;
        inverse_protocol_qualified = -1; inverse_protocol_ack_seen = 0;
        inverse_protocol_reuse_seen = 0; inverse_protocol_final = -1;
        inverse_protocol_start = dut.engine_metadata[68:5];
        inverse_protocol_lease = dut.sealed_inverse_output.output_bank.bank_lease;
        // The event tag is captured at actual admission, not inferred from
        // whichever metadata/source bank is live when a later return arrives.
        $fdisplay(inverse_protocol_trace, "ADMIT,%0d,%0d,%0d,%0d,%0d,0,0,0",
          epoch,fast_cycle,slow_cycle,inverse_protocol_start,inverse_protocol_lease);
      end
      if (inverse_protocol_owned && inverse_protocol_pub < 0 &&
          fast_cycle > inverse_protocol_admit) begin
        if (inverse_lease !== inverse_protocol_lease)
          $fatal(1, "INVERSE_SEALED_ADMITTED_LEASE_CHANGED");
        if (fast_cycle <= inverse_protocol_admit+2) begin
          if (dut.output_bank_ready || !dut.inverse_destination_reserved ||
              !dut.sealed_inverse_output.output_bank.producer_reference)
            $fatal(1, "INVERSE_SEALED_OWNED_VS_FREE_RESERVATION");
          inverse_protocol_reservations = inverse_protocol_reservations + 1;
        end
      end
      if (dut.return_commit_valid && dut.next_inverse && inverse_protocol_qualified < 0) begin
        inverse_protocol_qualified = fast_cycle; inverse_protocol_event("QUALIFY");
      end
      if (inverse_take) begin
        if (!inverse_protocol_owned || inverse_protocol_words >= 512 ||
            dut.return_position !== 9'(inverse_protocol_words) ||
            dut.return_last !== (inverse_protocol_words == 511) ||
            dut.return_metadata[73:10] !== inverse_protocol_start ||
            inverse_lease !== inverse_protocol_lease)
          $fatal(1, "INVERSE_SEALED_PRIVATE_TOKEN_OWNER_IDENTITY");
        inverse_protocol_event("TAKE");
        inverse_protocol_words = inverse_protocol_words + 1;
        inverse_protocol_takes = inverse_protocol_takes + 1;
        if (inverse_protocol_words == 512) inverse_protocol_final = fast_cycle;
      end
      if (inverse_certificate) inverse_protocol_event("CERT");
      if (inverse_seal) inverse_protocol_event("SEAL");
      if (inverse_publication) begin
        if (!inverse_protocol_owned || inverse_protocol_words != 512 ||
            inverse_protocol_qualified != inverse_protocol_admit+1810 ||
            fast_cycle != inverse_protocol_final+3 || fast_cycle != inverse_protocol_admit+1813 ||
            !dut.return_commit_valid || !dut.output_destination_ready)
          $fatal(1, "INVERSE_SEALED_ACTUAL_QUALIFICATION_PUBLICATION_ORDER");
        inverse_protocol_pub = fast_cycle; inverse_protocol_event("PUB");
        inverse_protocol_publications = inverse_protocol_publications + 1;
      end
      if (inverse_reader_ack && !inverse_protocol_ack_seen) begin
        inverse_protocol_ack_seen = 1; inverse_protocol_ack = fast_cycle;
        inverse_protocol_event("ACK");
      end
      if (inverse_release) begin
        if (inverse_protocol_ack < 0 || fast_cycle != inverse_protocol_ack+1 ||
            dut.result_busy || !inverse_protocol_owned)
          $fatal(1, "INVERSE_SEALED_ACTUAL_ACK_RELEASE_ORDER");
        inverse_protocol_release = fast_cycle; inverse_protocol_event("REL");
        inverse_protocol_releases = inverse_protocol_releases + 1;
      end
      if (inverse_protocol_release >= 0 && dut.output_bank_ready && !inverse_protocol_reuse_seen) begin
        if (fast_cycle != inverse_protocol_release+1)
          $fatal(1, "INVERSE_SEALED_ACTUAL_RELEASE_REUSE_ORDER");
        inverse_protocol_event("REUSE"); inverse_protocol_reuse_seen = 1;
        inverse_protocol_owned = 0;
      end
    end
  end
end
task automatic inverse_protocol_final_receipt;
  if (inverse_protocol_takes != 19456 || inverse_protocol_publications != 38 ||
      inverse_protocol_releases != 38 || inverse_protocol_reservations != 76 ||
      !inverse_protocol_current_vetoes || !inverse_protocol_held_finals)
    $fatal(1, "INVERSE_SEALED_ACTUAL_PROTOCOL_INCOMPLETE");
  $fclose(inverse_protocol_trace);
  $display("INVERSE_SEALED_ACTUAL_PASS E=1 L=1 R=1 B=1 O=1 fast_mhz=175 takes=19456 publications=38 releases=38 owned_reservation_edges=76 public_commit_delta=1813 current_veto_checks=%0d held_final_checks=%0d",inverse_protocol_current_vetoes,inverse_protocol_held_finals);
endtask
