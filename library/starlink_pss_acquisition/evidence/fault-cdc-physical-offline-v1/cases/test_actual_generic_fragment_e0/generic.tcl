set registered 1; set distributed 1; set scratch 1; set per_cause 1; set source_dir /offline
proc get_filesets {args} {return sources_1}
proc set_property {name value object} {set ::bound $value}
proc get_property {name object} {return $::bound}
set_property generic [list KERNEL_ROM_FILE=[file join $source_dir upper_edge_pss_kernel_q17.mem] \
  REGISTERED_SCHEDULING=$registered DISTRIBUTED_FAST_FAULT=$distributed \
  PRIVATE_NEXT_START_SCRATCH=$scratch PER_CAUSE_FAULT_CDC=$per_cause] [get_filesets sources_1]
set physical_generics [get_property GENERIC [get_filesets sources_1]]
foreach {name value} [list REGISTERED_SCHEDULING $registered DISTRIBUTED_FAST_FAULT $distributed PRIVATE_NEXT_START_SCRATCH $scratch PER_CAUSE_FAULT_CDC $per_cause] {
  if {[lsearch -exact $physical_generics ${name}=$value] < 0} { error "missing physical parameter $name" }
}
if {[lsearch -all -inline -glob $physical_generics PER_CAUSE_FAULT_CDC=*] ne [list PER_CAUSE_FAULT_CDC=1]} {
  error "requires exactly one explicit C1 physical parameter"
}
puts "EXACT_C1_BOUND=$bound"
