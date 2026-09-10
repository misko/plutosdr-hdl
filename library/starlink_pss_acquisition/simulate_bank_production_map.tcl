# Actual bank scorer -> periodic synthetic map; additive explicit opt-in only.
# Full production requires a reviewed aggregate source digest, after smoke.
if {$argc ni {3 4}} { error "expected NEW_OUTPUT VECTOR_DIRECTORY smoke|production ?REVIEWED_SOURCE_SHA256?" }
set mode [lindex $argv 2]
if {$mode ni {smoke production} || ($mode eq "smoke" && $argc != 3)} {
  error "requires literal smoke or production mode; review digest only for production"
}
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set fw_dir [file normalize [file join $script_dir ../../..]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite production-map evidence" }
set rtl_names {
  starlink_pss_overlap_scheduler starlink_pss_energy_cache starlink_pss_xfft_block_adapter
  starlink_pss_kernel_rom starlink_pss_forward_kernel_join starlink_pss_spectrum_product
  starlink_pss_transform_fifo starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo
  starlink_pss_energy_join starlink_pss_score_prepare starlink_pss_score_divider
  starlink_pss_score_divider_radix4 starlink_pss_score_lanes starlink_pss_candidate_score_path
  starlink_pss_iq_to_score starlink_pss_block_mailbox starlink_pss_shared_xfft_service
  starlink_pss_iq_to_score_shared starlink_pss_shared_realtime_xfft_service
  starlink_pss_realtime_input_guard starlink_pss_realtime_result_guard
  starlink_pss_score_phase_tagger starlink_pss_phase_map_bank starlink_pss_phase_map
  starlink_pss_acquisition_health starlink_pss_iq_to_phase_map
  starlink_pss_iq_to_score_bank_owned starlink_pss_fft_bank_owned_slice
}
set bench_name tb_starlink_pss_bank_production_map
set input_paths [list [info script] [file join $script_dir create_shared_realtime_xfft_ip.tcl] \
  [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir verify_bank_production_map_result.tcl] \
  [file join $script_dir run_bank_map_no_waves.tcl] \
  [file join $script_dir tb ${bench_name}.sv] \
  [file join $script_dir tb upper_edge_pss_kernel_q17.mem] \
  [file join $fw_dir tools generate_starlink_periodic_map_vectors.py] \
  [file join $fw_dir tests starlink_oracle xfft_bitacc.py] \
  [file join $fw_dir tests test_starlink_bank_production_map_policy.py] \
  [file join $vector_dir periodic_vectors.json]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach name {__init__.py fixed.py waveforms.py numerology.py acquisition.py ddc.py search.py} {
  lappend input_paths [file join $fw_dir tests starlink_oracle $name]
}
set vector_geometry {period_ci16 447 8 forward_q17 512 9 product_q17 512 9 inverse_q17 512 9
  forward_exponents 1 2 inverse_exponents 1 2 scores_u8 447 2 energies_u38 447 10
  numerators_u69 447 18 denominators_u69 447 18 saturated_u1 447 1 power_shift_u7 1 2
  map_smoke_u16 343 4 map_production_u16 20000 4}
set vector_names {}
foreach {name rows width} $vector_geometry {
  set path [file join $vector_dir ${name}.mem]
  if {![file isfile $path]} { error "missing vector $name" }
  if {[file size $path] > $rows*($width+2)+2} { error "oversized vector $name" }
  set channel [open $path r]; set data [split [string trim [read $channel]] "\n"]; close $channel
  if {[llength $data] != $rows} { error "unexpected vector row count $name" }
  foreach row $data {
    if {![regexp "^\[0-9a-fA-F\]{$width}$" $row]} { error "malformed vector row $name" }
    scan $row %x value
    if {($name eq "saturated_u1" && $value > 1) ||
        ([string match *_exponents $name] && $value > 31) ||
        ($name eq "power_shift_u7" && $value > 127) ||
        ($name eq "energies_u38" && $value >= 274877906944) ||
        ([string match *_u69 $name] && [string index $row 0] ni {0 1})} {
      error "out-of-range vector row $name"
    }
  }
  lappend input_paths $path; lappend vector_names ${name}.mem
}
foreach path $input_paths { if {![file isfile $path]} { error "missing production-map source $path" } }
# The production override must remain identical to the actual runtime defaults.
set channel [open [file join $script_dir starlink_pss_iq_to_phase_map.v] r]
set runtime_source [read $channel]; close $channel
foreach {name expected} {PHASE_BINS 20000 PHASE_INDEX_WIDTH 15 TILE_FRAMES 64 TILE_FRAME_WIDTH 6
  MAP_WIDTH 16 MAP_SEGMENT_ADDRESS_WIDTH 11 MAP_SEGMENT_COUNT 10 MAP_SEGMENT_INDEX_WIDTH 4} {
  if {![regexp "parameter integer $name = $expected," $runtime_source]} {
    error "frozen production default drift: $name"
  }
}
# Standard-library-only verifier: bounded receipt, exact file inventory and
# geometry, original bootstrap proof, frozen kernel equality and payload hashes.
set verifier {
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]); k=pathlib.Path(sys.argv[2]); g=pathlib.Path(sys.argv[3])
r=p/'periodic_vectors.json'
assert r.stat().st_size < 65536, 'oversized vector receipt'
j=json.loads(r.read_text())
assert j['schema']=='starlink-periodic-bank-map-v1' and j['kernel_byte_match'] is True
assert j['bootstrap']=={'original_blocks':3,'forward_product_inverse_words_each':1536,'scores':1341}
assert j['production']=={'selected_scores':1280000,'blocks':2864,'full_block_scores':1280208,'fft_source_samples':1280273,'direct_tap_support_samples':1280065,'potential_tail_scores':208,'last_block_selected':239}
assert len(j['files'])==14 and set(j['files'])==set(sys.argv[4:]), 'receipt inventory mismatch'
for name,entry in j['files'].items():
    assert hashlib.sha256((p/name).read_bytes()).hexdigest()==entry['sha256'], 'vector hash mismatch: '+name
for source in [k,g]:
    hashes=[h for n,h in j['inputs'].items() if pathlib.Path(n).name==source.name]
    assert hashes==[hashlib.sha256(source.read_bytes()).hexdigest()], 'oracle/kernel source hash mismatch'
}
if {[catch {exec python3 -c $verifier $vector_dir \
    [file join $script_dir tb upper_edge_pss_kernel_q17.mem] \
    [file join $fw_dir tools generate_starlink_periodic_map_vectors.py] {*}$vector_names} error_text]} {
  error "periodic vector receipt verification failed: $error_text"
}
set signature_payload ""
foreach path [lsort $input_paths] {
  append signature_payload "[file tail $path] [lindex [exec sha256sum $path] 0]\n"
}
set source_signature [lindex [exec sha256sum << $signature_payload] 0]
if {$mode eq "production" && ($argc != 4 || [lindex $argv 3] ne $source_signature)} {
  error "production requires REVIEWED_SOURCE_SHA256=$source_signature after smoke and independent review"
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
source [file join $source_dir verify_bank_production_map_result.tcl]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=actual_bank_scorer_periodic_map_geometry_arithmetic mode=$mode"
puts $channel "source_signature=$source_signature"
puts $channel "source_msps=15 slow_mhz=100 fft_mhz=175 ideal_clocks_not_MMCM_or_physical_timing=true"
puts $channel "all_visible_source_core_input_forward_product_inverse_energy_ratio_score_index_prefixes_checked=true"
puts $channel "production_bins=20000 frames=64 selected_scores=1280000 blocks=2864 full_scores=1280208 fft_source_samples=1280273 direct_tap_support=1280065 potential_tail=208 residue=239"
puts $channel "smoke_two_complete_maps_then_fresh447_abort=true production_one_complete_map_then_fresh447_abort=true"
puts $channel "not_full_production_map_recovery_not_RF_accuracy_not_paired_fine_or_capacity=true"
puts $channel "host=[exec uname -a]"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "firmware_commit=[exec git -C $fw_dir rev-parse HEAD]"
puts $channel "working_tree_status=[exec git -C $script_dir status --short]"
puts $channel "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $source_dir *]]]]"
close $channel
set_param general.maxThreads 2
set project_name bank_production_map
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
pss_create_shared_realtime_xfft_ip $wrapper_path
foreach name $rtl_names { add_files -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]
foreach name [concat $vector_names {upper_edge_pss_kernel_q17.mem}] {
  add_files -fileset sim_1 -norecurse [file join $source_dir $name]
}
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
set production [expr {$mode eq "production"}]
set_property generic "PRODUCTION=$production" [get_filesets sim_1]
set_property xsim.simulate.custom_tcl [file join $source_dir run_bank_map_no_waves.tcl] [get_filesets sim_1]
set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel "generated_wrapper_sha256=[exec sha256sum $wrapper_path]"
close $channel
set started [clock milliseconds]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set channel [open [file join $output_dir runtime.txt] w]
puts $channel "launch_compile_elaborate_simulation_wall_ms=[expr {[clock milliseconds]-$started}]"
close $channel
set log_path [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
require_bank_production_map_pass $log_path $production
close_project
puts "BANK_PRODUCTION_MAP_SIMULATION_VERIFIED mode=$mode source_signature=$source_signature"
