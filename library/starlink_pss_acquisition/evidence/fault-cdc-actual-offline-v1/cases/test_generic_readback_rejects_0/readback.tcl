set exact_generics {REGISTERED_SCHEDULING=1 DISTRIBUTED_FAST_FAULT=1 PRIVATE_NEXT_START_SCRATCH=1 EXACT_EXTRA_EPOCHS=1 FAST_MHZ=175 QUICK_MUTATION=0 PER_CAUSE_FAULT_CDC=1}
proc get_filesets {args} {return sim_1}
proc get_property {args} {return {REGISTERED_SCHEDULING=1 DISTRIBUTED_FAST_FAULT=1 PRIVATE_NEXT_START_SCRATCH=1 EXACT_EXTRA_EPOCHS=1 FAST_MHZ=175 QUICK_MUTATION=0 PER_CAUSE_FAULT_CDC=1}}
if {[lsort [get_property GENERIC [get_filesets sim_1]]] ne [lsort $exact_generics]} {
  error "CDC actual generic readback mismatch"
}
puts "READBACK_VERIFIED"
