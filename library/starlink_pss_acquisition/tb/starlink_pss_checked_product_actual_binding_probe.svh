// Additive actual-preparation seam probes, using the FROZEN controller actor.
// Not vendor FFT, not changed actual acceptance, and not a runtime edit.
// Injected immediately inside the existing hazards initial block. The old
// bench is restored byte-for-byte by removing this exact include expansion.
      if(kind==65)begin
        wait(dut.state==dut.ACK_DRAIN && !dut.result_busy &&
             dut.forward_handoff_ack && !dut.any_fast_fault);
        #0.001;
        $display("ACTUAL_BINDING_ACK_CAPACITY ready=%b capacity=%b receipt=%b guard_busy=%b actual_ack=%b state=%0d actor_only=1",
          dut.result_destination_ready,dut.product_handoff_capacity,dut.forward_handoff_ack,
          dut.result_busy,dut.product_guard_ack_event,dut.state);
        if(dut.result_destination_ready!==1'b0 || dut.product_handoff_capacity!==1'b0 ||
           dut.forward_handoff_ack!==1'b1 || dut.result_busy!==1'b0 ||
           dut.product_guard_ack_event!==1'b0 || dut.state!=dut.ACK_DRAIN ||
           !dut.checked_product_bank.adapter.published_reference ||
           !dut.checked_product_bank.adapter.reader_reference || dut.input_job_start)
          $fatal(1,"ACTUAL_BINDING_ACK_CAPACITY_SOURCE_CHANGED");
        if($test$plusargs("REQUIRE_OLD_INTERFACE") &&
           dut.result_destination_ready!==dut.forward_handoff_ack)
          $fatal(1,"ACTUAL_BINDING_OLD_DRAIN_READY_EQUALS_RECEIPT_DIFFERS");
        $display("ACTUAL_BINDING_ACK_CAPACITY_PASS ready=0 capacity=0 receipt=1 guard_busy=0 actual_ack=0 actor_only=1");
        $finish;
      end
      if(kind>=60 && kind<=64)begin
        if(kind==62 || kind==64)wait(dut.state==dut.VERIFY_LEASE && dut.held_phase);
        else wait(dut.state==dut.VERIFY_LEASE && !dut.held_phase);
        @(negedge fft_clk);
        if(dut.input_job_start || dut.config_valid || dut.product_bank_read_ready ||
           dut.preflight_events_now || !dut.preparation_valid)
          $fatal(1,"ACTUAL_BINDING_PROBE_NOT_CLEAN_PREFLIGHT kind=%0d",kind);
        case(kind)
          60:force dut.product_bank_ready=1'b0;
          61:force dut.product_reservation=1'b0;
          62,64:begin
            changed_lease=dut.checked_product_bank.adapter.lease_reference;
            force dut.product_bank_position=9'd7;
          end
          63:force dut.source_position=9'd7;
        endcase
        #0.001;
        $display("ACTUAL_BINDING_PROBE kind=%0d phase=%b ready=%b reservation=%b valid=%b position=%0d bound=%b start_binding=%b current=%h input_start=%b config=%b core_take=%b actor_only=1",
          kind,dut.held_phase,dut.product_bank_ready,dut.product_reservation,
          dut.preflight_valid,dut.preflight_position,dut.product_bound_receipt,
          dut.product_start_binding,dut.preflight_events_now,dut.input_job_start,
          dut.config_valid,dut.checked_product_bank.core_take);
        // These are independently declared source-level expectations, not
        // changes to the immutable original actual test's single-bit masks.
        if((kind==60 && (dut.product_bank_ready!==1'b0 || dut.product_reservation!==1'b1 || dut.preflight_events_now!==6'h00)) ||
           (kind==61 && (dut.product_bank_ready!==1'b1 || dut.product_reservation!==1'b0 || dut.preflight_events_now!==6'h10)) ||
           ((kind==62 || kind==64) && (dut.preflight_position!==9'd7 || dut.product_start_binding!==1'b0 || dut.preflight_events_now!==6'h0a)) ||
           (kind==63 && (dut.preflight_position!==9'd7 || dut.preflight_events_now!==6'h02)))
          $fatal(1,"ACTUAL_BINDING_PROBE_SOURCE_EXPECTATION_CHANGED kind=%0d",kind);
        if(dut.input_job_start || dut.config_valid || dut.checked_product_bank.core_take)
          $fatal(1,"ACTUAL_BINDING_PROBE_EARLY_PUBLIC_ACTION kind=%0d",kind);
        if(kind==64)begin
          @(negedge fft_clk);release dut.product_bank_position;
          repeat(8)@(negedge fft_clk);
          $display("ACTUAL_BINDING_RETAINED_OWNER live_valid=%b published=%b reader=%b reader_owned=%b lease=%h original_lease=%h consumed=%0d release=%b start=%b state=%0d actor_only=1",
            dut.product_bank_valid,dut.checked_product_bank.adapter.published_reference,
            dut.checked_product_bank.adapter.reader_reference,dut.checked_product_bank.adapter.reader.owned,
            dut.checked_product_bank.adapter.lease_reference,changed_lease,
            dut.checked_product_bank.adapter.reader.consumed,dut.checked_product_bank.lease_release,
            dut.input_job_start,dut.state);
          if(dut.product_bank_valid!==1'b0 || dut.checked_product_bank.adapter.published_reference!==1'b1 ||
             dut.checked_product_bank.adapter.reader_reference!==1'b1 || dut.checked_product_bank.adapter.reader.owned!==1'b1 ||
             dut.checked_product_bank.adapter.lease_reference!==changed_lease ||
             dut.checked_product_bank.adapter.reader.consumed!==10'd0 ||
             dut.checked_product_bank.lease_release || dut.input_job_start || dut.config_valid ||
             dut.checked_product_bank.core_take || !dut.fast_fault || dut.state!=dut.QUARANTINE)
            $fatal(1,"ACTUAL_BINDING_RETAINED_OWNER_CHANGED");
          if($test$plusargs("REQUIRE_OLD_INTERFACE") && !dut.product_bank_valid)
            $fatal(1,"ACTUAL_BINDING_OLD_LIVE_VALID_AS_OWNER_DIFFERS");
          $display("ACTUAL_BINDING_RETAINED_OWNER_PASS live_valid=0 published=1 reader=1 consumed=0 released=0 actor_only=1");
          $finish;
        end
        if($test$plusargs("REQUIRE_OLD_INTERFACE"))begin
          if(kind==60 && dut.preflight_events_now!==6'h10)
            $fatal(1,"ACTUAL_BINDING_OLD_READY_RESERVATION_CONTRACT_DIFFERS");
          if(kind==62 && dut.preflight_events_now!==6'h02)
            $fatal(1,"ACTUAL_BINDING_OLD_SINGLE_FRAMING_MASK_DIFFERS");
        end
        $display("ACTUAL_BINDING_PROBE_PASS kind=%0d current=%h no_old_actual_scope_claim=1 actor_only=1",kind,dut.preflight_events_now);
        $finish;
      end
