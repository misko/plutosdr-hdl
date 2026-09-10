# Additive waveform evidence only. No force, reset, clock or checker changes.
# Preserve the generated default top-level display/logging and run-all behavior.
set curr_wave [current_wave_config]
if {[string length $curr_wave] == 0} {
  if {[llength [get_objects]] > 0} {
    add_wave /
    set_property needs_save false [current_wave_config]
  }
}
set diagnostic_objects {}
array set diagnostic_counts {monitor 0 reference_overflow 0 wrapper_overflow 0 inner_overflow 0 transport_overflow 0}
set shadow_fields {clk resetn flush product_enable output_ready product_outputs p_ready p_valid p_i p_q p_position p_exponent p_last p_start p_overflow p_overflow_pulse available occupied}
set product_fields {clk resetn flush input_ready output_ready output_valid output_i output_q output_bin_index output_block_exponent output_last output_block_start_index output_overflow overflow_pulse product_valid sum_valid}
set transport_fields {product_valid product_overflow product_position product_start product_exponent product_last fast_fault external_fault_now completed_input_fault_now product_bank_framing_fault_now product_bank_ready product_commit_authorized forward_handoff_ack}
foreach object [get_objects -r *] {
  set leaf [lindex [split $object /] end]
  set selected 0
  if {[regexp {/(payload_shadow|forward_chain_shadow)/} $object] && $leaf in $shadow_fields} {
    set selected 1
    if {$leaf eq "product_outputs"} { incr diagnostic_counts(monitor) }
    if {$leaf eq "p_overflow"} { incr diagnostic_counts(reference_overflow) }
  }
  if {[string match */dut/product/* $object] && $leaf in $product_fields} { set selected 1 }
  if {[regexp {/dut/[^/]+$} $object] && $leaf in $transport_fields} { set selected 1 }
  if {[string match */dut/product/output_overflow $object]} { incr diagnostic_counts(wrapper_overflow) }
  if {[string match */dut/product/arithmetic/output_overflow $object]} { incr diagnostic_counts(inner_overflow) }
  if {[string match */dut/product_overflow $object]} { incr diagnostic_counts(transport_overflow) }
  if {$selected} { lappend diagnostic_objects $object }
}
if {$diagnostic_counts(monitor) != 4 || $diagnostic_counts(reference_overflow) != 2 ||
    $diagnostic_counts(wrapper_overflow) != 1 || $diagnostic_counts(inner_overflow) != 1 ||
    $diagnostic_counts(transport_overflow) != 1 || [llength $diagnostic_objects] > 256} {
  error "ARITHMETIC_WAVE_DIAGNOSTIC_INVENTORY_MISMATCH [array get diagnostic_counts]"
}
log_wave $diagnostic_objects
set diagnostic_channel [open arithmetic_diagnostic_signals.txt {WRONLY CREAT EXCL}]
foreach object $diagnostic_objects { puts $diagnostic_channel $object }
close $diagnostic_channel
puts "ARITHMETIC_WAVE_DIAGNOSTICS_ENABLED objects=[llength $diagnostic_objects] monitors=4 references=2 wrapper=1 inner=1 transport=1"
run all
