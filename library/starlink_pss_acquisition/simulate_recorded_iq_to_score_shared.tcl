# Isolated recorded-CI16 replay through actual realtime512/BFP18 XFFT + scores.
# Usage: vivado -mode batch -source simulate_recorded_iq_to_score_shared.tcl \
#        -tclargs NEW_OUTPUT RECORDED_VECTOR_DIRECTORY
# Python3 is used only for bounded stdlib JSON/hash admission, never arithmetic.
proc pss_verify_recorded_output {log_path first_hex} {
  if {![regexp {^[0-9a-f]{16}$} $first_hex]} { error "invalid recorded verdict origin" }
  if {![file isfile $log_path]} { error "missing recorded simulation log" }
  set channel [open $log_path r]
  set log_text [read $channel]
  close $channel
  if {[regexp -nocase -line {^[ \t]*RECORDED_SCORE_FAIL([ \t]|$)} $log_text]} {
    error "recorded simulation contains FAIL evidence"
  }
  require_realtime_probe_pass $log_path [list \
    "RECORDED_SCORE_ORIGIN first_canonical_index=$first_hex sample_count=1406" \
    {RECORDED_SCORE_FAULT_RECOVERY_PASS injected_checker_fault=1 explicit_recovery=1} \
    {RECORDED_SCORE_FFT_RESET_PASS sticky_quarantine=1 explicit_recovery=1} \
    {RECORDED_SCORE_REPLAY_PASS samples=1406 blocks=3 forward=1536 product=1536 inverse=1536 scores=1341 exact_metadata=1 score_stalls=1 NO_PSS_DETECTION_OR_CAPACITY_CLAIM} \
  ] RECORDED_SCORE_COUNTS 1
}
if {$argc != 2} { error "expected NEW_OUTPUT RECORDED_VECTOR_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir] || ![catch {file type $output_dir}]} {
  error "refusing to overwrite recorded replay evidence"
}
set manifest_path [file join $vector_dir recorded_fixture.json]
set admission_validator {
import hashlib, json, pathlib, re, sys
directory = pathlib.Path(sys.argv[1])
manifest = directory / "recorded_fixture.json"
def require(condition, message):
    if not condition:
        raise ValueError(message)
def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate fixture manifest key")
        result[key] = value
    return result
require(manifest.is_file(), "missing recorded fixture manifest")
require(manifest.stat().st_size <= 16384, "oversize recorded fixture manifest")
document = json.loads(manifest.read_text(), object_pairs_hook=unique)
require(type(document) is dict and set(document) == {
    "schema", "source_kind", "input_rate_hz", "first_canonical_index", "vectors"
}, "unexpected recorded fixture manifest keys")
require(document["schema"] == "starlink-recorded-score-fixture-v1", "wrong recorded fixture schema")
require(document["source_kind"] == "conditioned-recorded-ci16", "wrong fixture source kind")
require(type(document["input_rate_hz"]) is int and document["input_rate_hz"] == 15000000,
        "wrong recorded fixture rate")
first = document["first_canonical_index"]
require(type(first) is int and 0 <= first <= (1 << 64) - 1406, "invalid recorded sample origin")
geometry = {"samples_ci16": (1406, 8), "forward_q17": (1536, 9),
    "product_q17": (1536, 9), "inverse_q17": (1536, 9),
    "forward_exponents": (3, 2), "inverse_exponents": (3, 2), "scores_u8": (1341, 2)}
vectors = document["vectors"]
require(type(vectors) is dict and set(vectors) == set(geometry), "unexpected recorded vector names")
for name, (rows, width) in geometry.items():
    receipt = vectors[name]
    require(type(receipt) is dict and set(receipt) == {"rows", "hex_digits", "sha256"},
            "unexpected recorded vector receipt keys")
    require(type(receipt["rows"]) is int and receipt["rows"] == rows and
            type(receipt["hex_digits"]) is int and receipt["hex_digits"] == width,
            "incorrect recorded vector geometry")
    require(type(receipt["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", receipt["sha256"]),
            "invalid recorded vector hash")
    path = directory / (name + ".mem")
    require(path.is_file(), "missing recorded vector " + name)
    require(path.stat().st_size <= rows * (width + 2), "oversize recorded vector " + name)
    data = path.read_bytes()
    require(hashlib.sha256(data).hexdigest() == receipt["sha256"], "recorded vector hash mismatch " + name)
    lines = data.decode("ascii").splitlines()
    require(len(lines) == rows and all(re.fullmatch("[0-9a-fA-F]{%d}" % width, row)
                                     for row in lines), "malformed recorded vector " + name)
    if name.endswith("exponents"):
        require(all(int(row, 16) <= 31 for row in lines), "recorded exponent outside five-bit contract")
print(first)
print(f"{first:016x}")
}
set admission [exec python3 -c $admission_validator $vector_dir]
set first_index [lindex [split [string trim $admission] "\n"] 0]
set first_hex [lindex [split [string trim $admission] "\n"] 1]
if {![regexp {^[0-9]+$} $first_index] || ![regexp {^[0-9a-f]{16}$} $first_hex]} {
  error "invalid recorded admission result"
}
set bench_name tb_starlink_pss_recorded_iq_to_score_shared
set rtl_names {
  starlink_pss_overlap_scheduler starlink_pss_energy_cache starlink_pss_xfft_block_adapter
  starlink_pss_kernel_rom starlink_pss_forward_kernel_join starlink_pss_spectrum_product
  starlink_pss_transform_fifo starlink_pss_ifft_qualifier starlink_pss_raw_result_fifo
  starlink_pss_energy_join starlink_pss_score_prepare starlink_pss_score_divider
  starlink_pss_score_divider_radix4 starlink_pss_score_lanes starlink_pss_candidate_score_path
  starlink_pss_block_mailbox starlink_pss_shared_xfft_service starlink_pss_iq_to_score_shared
  starlink_pss_shared_realtime_xfft_service starlink_pss_realtime_input_guard
  starlink_pss_realtime_result_guard
}
set vector_names {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents scores_u8}
set input_paths [list [info script] $manifest_path \
  [file join $script_dir create_shared_realtime_xfft_ip.tcl] \
  [file join $script_dir verify_realtime_probe_result.tcl] \
  [file join $script_dir tb ${bench_name}.sv] \
  [file join $script_dir tb upper_edge_pss_kernel_q17.mem] \
  [file normalize [file join $script_dir ../../../tests/test_starlink_recorded_score_runner_policy.py]]]
foreach name $rtl_names { lappend input_paths [file join $script_dir ${name}.v] }
foreach name $vector_names { lappend input_paths [file join $vector_dir ${name}.mem] }
foreach path $input_paths {
  if {![file isfile $path]} { error "missing recorded replay source $path" }
  set source_hash($path) [lindex [exec sha256sum $path] 0]
}
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
foreach path $input_paths { file copy $path $source_dir }
# Compare every frozen input to its pre-copy hash, then revalidate the copied
# manifest/vector binding and origin before creating the simulation project.
foreach path $input_paths {
  set frozen_hash [lindex [exec sha256sum [file join $source_dir [file tail $path]]] 0]
  if {$source_hash($path) ne $frozen_hash} { error "recorded replay source changed while freezing" }
}
if {[exec python3 -c $admission_validator $source_dir] ne $admission} {
  error "recorded fixture origin changed while freezing"
}
source [file join $source_dir create_shared_realtime_xfft_ip.tcl]
source [file join $source_dir verify_realtime_probe_result.tcl]
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=recorded_conditioned_ci16_actual_realtime_xfft_and_score_numeric_replay"
puts $channel "first_canonical_index=$first_index first_canonical_index_hex=$first_hex"
puts $channel "samples=1406 blocks=3 forward=1536 product=1536 inverse=1536 scores=1341"
puts $channel "slow_clock_ns=10 fft_clock_ns=5 fft_phase_ns=1.3 source_msps=15"
puts $channel "score_stalls=true checker_fault_injected_after_numeric_replay=true independent_fft_reset_after_numeric_replay=true"
puts $channel "source_kind_is_manifest_provenance_not_independently_authenticated_capture=true"
puts $channel "pss_detection_capacity_receiver_physical_or_rf_qualified=false"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "working_tree_status=[exec git -C $script_dir status --short]"
puts $channel "frozen_source_hashes=[exec sha256sum {*}[lsort [glob [file join $source_dir *]]]]"
close $channel
set project_name recorded_iq_to_score_shared
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
  starlink_pss_fft512_bfp18_rt_candidate synth starlink_pss_fft512_bfp18_rt_candidate.vhd]
# Existing helper pins and verifies the same32 numerical/interface generics.
pss_create_shared_realtime_xfft_ip $wrapper_path
foreach name $rtl_names { add_files -norecurse [file join $source_dir ${name}.v] }
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]
add_files -fileset sim_1 -norecurse [file join $source_dir upper_edge_pss_kernel_q17.mem]
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem] }
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
# Decimal avoids Vivado 2022.2's broken nested shell quoting for HDL apostrophe
# literals in generated elaborate.sh. The bench's parameter stays 64 bits and
# its independently checked full-width origin marker detects truncation.
set_property generic "FIRST_SAMPLE_INDEX=$first_index" [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
set channel [open [file join $output_dir generated_ip.txt] w]
puts $channel "generated_wrapper_sha256=[exec sha256sum $wrapper_path]"
close $channel
launch_simulation -simset sim_1 -mode behavioral
close_sim
set log_path [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log]
pss_verify_recorded_output $log_path $first_hex
close_project
puts "RECORDED_SCORE_SIMULATION_VERIFIED first_canonical_index=$first_index realtime=1 exact_scores=1341 exact_stages=1536 NO_CAPTURE_AUTHENTICATION_OR_TIMING_CLAIM"
