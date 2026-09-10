# Future actual-core execution entry. OFFLINE preparation does not source this.
# Requires separate authorization; no synthesis/place/route or production use.
# BEGIN EXACT_CONTROL_RECEIPTS
proc exact_verify_receipts {log registered distributed scratch extras} {
  set lines [regexp -all -inline -line {^EXACT_CONTROL_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} { error "expected exactly one candidate terminal" }
  set pattern {^EXACT_CONTROL_ACTUAL_PASS registered=([01]) distributed=([01]) scratch=([01]) extra=([01]) checks=([0-9]+) active=([0-9]+) consumed=([0-9]+) private_differences=([0-9]+) final_fault_edges=([0-9]+) owned_stalls=([0-9]+) reset_owned_edges=([0-9]+) independent_actual_core=1$}
  if {![regexp $pattern [lindex $lines 0] unused r d s e checks active consumed differences final_faults stalls resets]} {
    error "malformed candidate settings/count receipt"
  }
  if {$r != $registered || $d != $distributed || $s != $scratch || $e != $extras} {
    error "candidate receipt does not match explicit run settings"
  }
  if {$checks <= 0 || $active <= 0 || $consumed <= 0} {
    error "candidate active/public/identity coverage missing"
  }
  set extra_lines [regexp -all -inline -line {^EXACT_CONTROL_EXTRA_EPOCHS_PASS[^\n]*$} $log]
  if {$extras} {
    # Candidate and independently driven reference each execute/assert their
    # own four extra epochs before printing this exact receipt. The candidate
    # cannot finish until reference_done; neither bench shares these counters.
    if {$final_faults < 2 || $stalls < 3 || [llength $extra_lines] != 2} {
      error "extra epoch active evidence or independent receipt missing"
    }
    foreach line $extra_lines {
      if {$line ne "EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=2 healthy_recoveries=4"} {
        error "extra epoch counts differ from frozen expectations"
      }
    }
  } elseif {[llength $extra_lines] != 0} {
    error "extra epochs ran without explicit selection"
  }
  return "EXACT_CONTROL_RECEIPTS_VERIFIED"
}
# END EXACT_CONTROL_RECEIPTS
# BEGIN FAULT_CDC_RECEIPTS
proc fault_cdc_verify_receipt {log enabled} {
  set lines [regexp -all -inline -line {^FAULT_CDC_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected exactly one CDC terminal"}
  set pattern {^FAULT_CDC_ACTUAL_PASS enabled=([01]) checks=([0-9]+) stage0_high=([0-9]+) stage1_high=([0-9]+) reset_samples=([0-9]+) current_fault_edges=([0-9]+) final_fault_edges=([0-9]+) private_core_reset_samples=([0-9]+) scalar_source=actual_fast_fault reference_reset=slow_running$}
  if {![regexp $pattern [lindex $lines 0] unused c checks first second resets current final private]} {
    error "malformed CDC settings/count receipt"
  }
  if {$c != $enabled || $checks <= 0 || $first <= 0 || $second <= 0 ||
      $resets <= 0 || $current <= 0 || $final < 2} {error "CDC setting/coverage mismatch"}
  return "FAULT_CDC_RECEIPT_VERIFIED"
}
# END FAULT_CDC_RECEIPTS
# BEGIN ROM_INPUT_SHADOW_RECEIPT
proc rom_verify_receipt {log word metadata} {
  set lines [regexp -all -inline -line {^ROM_READ_AHEAD_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected exactly one ROM terminal"}
  set pattern {^ROM_READ_AHEAD_ACTUAL_PASS word=([01]) metadata=([01]) pre=([0-9]+) post=([0-9]+) accepts=([0-9]+) first=([0-9]+) last=([0-9]+) stalls=([0-9]+) resets=([0-9]+) current_fault_edges=([0-9]+) final_fault_edges=([0-9]+) private_reset_edges=([0-9]+) old_source=C1 input_ports_only=1 unconditional_old_state=1$}
  if {![regexp $pattern [lindex $lines 0] unused k m pre post accepts first last stalls resets current final private]} {
    error "malformed ROM receipt"
  }
  if {$k != $word || $m != $metadata || $pre <= 0 || $post != $pre ||
      $accepts < 512 || $first <= 0 || $last <= 0 || $stalls <= 0 ||
      $resets <= 0 || $current <= 0 || $final < 2 || $private <= 0} {error "ROM settings/coverage mismatch"}
  return "ROM_INPUT_SHADOW_RECEIPT_VERIFIED"
}
# END ROM_INPUT_SHADOW_RECEIPT
# BEGIN PRODUCT_FINAL_RECEIPT
proc product_final_verify_receipt {log enabled} {
  set lines [regexp -all -inline -line {^PRODUCT_FINAL_FENCE_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected one product final receipt"}
  set pattern {^PRODUCT_FINAL_FENCE_ACTUAL_PASS enabled=([01]) pre=([0-9]+) post=([0-9]+) sampled=([0-9]+) authorized=([0-9]+) vetoed=([0-9]+) unknown=([0-9]+) malformed=([0-9]+) nonsampled_private=([0-9]+) closed=([0-9]+) resets=([0-9]+) inverse_owned=([0-9]+) owned_stalls=([0-9]+) current_faults=([0-9]+) private_reset=([0-9]+) public_overlap=([0-9]+) source=real_controller old_public_shadow=unchanged_dec20 qualified_status_only=1$}
  if {![regexp $pattern [lindex $lines 0] unused e pre post sampled authorized vetoed unknown malformed private closed resets inverse stalls faults core overlap]} {
    error "malformed product final receipt"
  }
  if {$e != $enabled || $pre <= 0 || $post != $pre || $sampled <= 0 ||
      $authorized <= 0 || $sampled != $authorized+$vetoed+$unknown ||
      $closed <= 0 || $closed > $sampled || $resets <= 0 || $inverse <= 0 ||
      $stalls <= 0 || $faults < 2 || $core <= 0} {error "product final coverage mismatch"}
  return "PRODUCT_FINAL_RECEIPT_VERIFIED"
}
# END PRODUCT_FINAL_RECEIPT
if {$argc != 1} { error "expected unique PREPARED_OUTPUT directory" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set_param general.maxThreads 2
set output_dir [file normalize [lindex $argv 0]]
set source_dir [file join $output_dir frozen_sources]
set project_dir [file join $output_dir project]
if {[file exists $project_dir]} { error "refusing to overwrite/retry actual evidence" }
set old_directory [pwd]
cd $output_dir
exec sha256sum -c SHA256SUMS --quiet
source settings.tcl
cd $old_directory
if {[llength $exact_generics] != 11} { error "unexpected option inventory" }
foreach key {REGISTERED_SCHEDULING DISTRIBUTED_FAST_FAULT PRIVATE_NEXT_START_SCRATCH EXACT_EXTRA_EPOCHS PER_CAUSE_FAULT_CDC PRIVATE_ROM_READ_AHEAD PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE CHECKED_PRODUCT_BANK} {
  set found [lsearch -all -inline -glob $exact_generics ${key}=*]
  if {[llength $found] != 1 || [lindex $found 0] ni [list ${key}=0 ${key}=1]} {
    error "invalid explicit option $key"
  }
}
if {[lsearch -exact $exact_generics FAST_MHZ=175] < 0 ||
    [lsearch -exact $exact_generics QUICK_MUTATION=0] < 0} { error "clock/stimulus gate changed" }
set registered [expr {[lsearch -exact $exact_generics REGISTERED_SCHEDULING=1] >= 0}]
set distributed [expr {[lsearch -exact $exact_generics DISTRIBUTED_FAST_FAULT=1] >= 0}]
set scratch [expr {[lsearch -exact $exact_generics PRIVATE_NEXT_START_SCRATCH=1] >= 0}]
set extras [expr {[lsearch -exact $exact_generics EXACT_EXTRA_EPOCHS=1] >= 0}]
set per_cause [expr {[lsearch -exact $exact_generics PER_CAUSE_FAULT_CDC=1] >= 0}]
if {!$registered || !$distributed || !$scratch || !$extras} {error "requires passing111 extra baseline"}
if {!$per_cause} {error "requires accepted C1 option"}
set rom_word [expr {[lsearch -exact $exact_generics PRIVATE_ROM_READ_AHEAD=1] >= 0}]
set rom_metadata [expr {[lsearch -exact $exact_generics PRIVATE_BLOCK_METADATA_READ_AHEAD=1] >= 0}]
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B [file join $output_dir prepare_checked_product_actual_run.py] --verify-prepared $output_dir]
set producer_final [expr {[lsearch -exact $exact_generics PRODUCER_LOCAL_FINAL_FENCE=1] >= 0}]
if {[lsearch -exact $exact_generics CHECKED_PRODUCT_BANK=1] < 0} {error "requires reviewed checked-product option"}
set project_name exact_control_actual
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
set wrapper [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper
add_files -fileset sim_1 -norecurse [glob [file join $source_dir *.v] [file join $source_dir *.sv]]
add_files -fileset sim_1 -norecurse [glob [file join $source_dir *.mem]]
set_property include_dirs [list $source_dir] [get_filesets sim_1]
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top tb_starlink_pss_fft_bank_owned_slice [get_filesets sim_1]
set_property generic $exact_generics [get_filesets sim_1]
if {[lsort [get_property GENERIC [get_filesets sim_1]]] ne [lsort $exact_generics]} {
  error "CDC actual generic readback mismatch"
}
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simulation_dir [file join $project_dir ${project_name}.sim sim_1 behav xsim]
set logfile [file join $simulation_dir simulate.log]
set channel [open $logfile r]; set log [read $channel]; close $channel
if {[regexp -nocase {fatal:|error:} $log]} { error "actual shadow failed; retain $logfile" }
# Changed-latency candidate: no old paired raw217/CSV pass is asserted.
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B [file join $output_dir prepare_checked_product_actual_run.py] --verify-result $output_dir]
cd $output_dir
exec sha256sum -c SHA256SUMS --quiet
cd $old_directory
close_project
puts "CHECKED_PRODUCT_ACTUAL_VENDOR_VERIFIED_CHANGED_LATENCY_NO_RAW217_NO_PHYSICAL_OR_RF_CLAIM"
