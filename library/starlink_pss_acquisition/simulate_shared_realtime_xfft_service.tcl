# Isolated synthesizable realtime candidate, never a production IP/default edit.
# Usage: vivado ... -tclargs NEW_OUTPUT FROZEN_VECTOR_DIRECTORY
if {$argc != 2} { error "expected NEW_OUTPUT FROZEN_VECTOR_DIRECTORY" }
if {[version -short] ne "2022.2"} { error "requires Vivado 2022.2" }
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file normalize [lindex $argv 0]]
set vector_dir [file normalize [lindex $argv 1]]
if {[file exists $output_dir]} { error "refusing to overwrite realtime service evidence" }
set vector_names {samples_ci16 forward_q17 product_q17 inverse_q17 forward_exponents inverse_exponents}
foreach name $vector_names {
  if {![file isfile [file join $vector_dir ${name}.mem]]} { error "missing vector $name" }
}
set bench_name tb_starlink_pss_shared_realtime_xfft_service
set rtl_names {starlink_pss_shared_realtime_xfft_service.v starlink_pss_realtime_input_guard.v starlink_pss_realtime_result_guard.v starlink_pss_block_mailbox.v}
foreach name [concat $rtl_names {verify_realtime_probe_result.tcl}] {
  if {![file isfile [file join $script_dir $name]]} { error "missing isolated source $name" }
}
file mkdir $output_dir
set source_dir [file join $output_dir frozen_sources]
file mkdir $source_dir
file copy [info script] [file join $source_dir probe_runner.tcl]
file copy [file join $script_dir tb ${bench_name}.sv] $source_dir
file copy [file join $script_dir tb starlink_pss_realtime_result_guard_ff4229_golden.v] $source_dir
file copy [file join $script_dir tb starlink_pss_realtime_input_guard_0a1af893_golden.v] $source_dir
foreach name [concat $rtl_names {verify_realtime_probe_result.tcl}] {
  file copy [file join $script_dir $name] $source_dir
}
foreach name $vector_names { file copy [file join $vector_dir ${name}.mem] $source_dir }
source [file join $source_dir verify_realtime_probe_result.tcl]

set project_name shared_realtime_xfft_service
set project_dir [file join $output_dir project]
create_project $project_name $project_dir -part xc7z010clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set module_name starlink_pss_fft512_bfp18_rt_candidate
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name $module_name
set_property -dict [list \
  CONFIG.channels {1} CONFIG.transform_length {512} \
  CONFIG.target_clock_frequency {200} CONFIG.implementation_options {automatically_select} \
  CONFIG.target_data_throughput {40} CONFIG.run_time_configurable_transform_length {false} \
  CONFIG.data_format {fixed_point} CONFIG.input_width {18} CONFIG.phase_factor_width {16} \
  CONFIG.scaling_options {block_floating_point} CONFIG.rounding_modes {convergent_rounding} \
  CONFIG.aresetn {true} CONFIG.xk_index {true} CONFIG.throttle_scheme {realtime} \
  CONFIG.output_ordering {natural_order} CONFIG.cyclic_prefix_insertion {false} \
  CONFIG.memory_options_data {block_ram} CONFIG.memory_options_phase_factors {block_ram} \
  CONFIG.memory_options_reorder {block_ram} CONFIG.complex_mult_type {use_mults_resources} \
  CONFIG.butterfly_type {use_xtremedsp_slices} \
] [get_ips $module_name]
generate_target all [get_ips $module_name]
set wrapper_path [file join $project_dir ${project_name}.gen sources_1 ip \
  $module_name synth ${module_name}.vhd]
set channel [open $wrapper_path r]
set wrapper [read $channel]
close $channel
set required_generics {
  C_S_AXIS_CONFIG_TDATA_WIDTH 8 C_S_AXIS_DATA_TDATA_WIDTH 48
  C_M_AXIS_DATA_TDATA_WIDTH 48 C_M_AXIS_DATA_TUSER_WIDTH 24 C_M_AXIS_STATUS_TDATA_WIDTH 8
  C_THROTTLE_SCHEME 0 C_CHANNELS 1 C_NFFT_MAX 9 C_ARCH 1 C_HAS_NFFT 0
  C_USE_FLT_PT 0 C_INPUT_WIDTH 18 C_TWIDDLE_WIDTH 16 C_OUTPUT_WIDTH 18
  C_HAS_SCALING 1 C_HAS_BFP 1 C_HAS_ROUNDING 1 C_HAS_ACLKEN 0 C_HAS_ARESETN 1
  C_HAS_OVFLO 0 C_HAS_NATURAL_INPUT 1 C_HAS_NATURAL_OUTPUT 1 C_HAS_CYCLIC_PREFIX 0
  C_HAS_XK_INDEX 1 C_DATA_MEM_TYPE 1 C_TWIDDLE_MEM_TYPE 1 C_BRAM_STAGES 0
  C_REORDER_MEM_TYPE 1 C_USE_HYBRID_RAM 0 C_OPTIMIZE_GOAL 0 C_CMPY_TYPE 1 C_BFLY_TYPE 1
}
foreach {name value} $required_generics {
  if {![regexp "${name} => ${value}(,|\n)" $wrapper]} { error "unexpected generated generic $name" }
}
set entity [string range $wrapper [string first "ENTITY $module_name IS" $wrapper] \
  [string first "END $module_name;" $wrapper]]
foreach forbidden {m_axis_data_tready m_axis_status_tready event_status_channel_halt event_data_out_channel_halt} {
  if {[string first $forbidden $entity] >= 0} { error "unexpected realtime entity port $forbidden" }
}
set channel [open [file join $output_dir scope.txt] w]
puts $channel "scope=isolated_synthesizable_realtime_fft_service_actual_core_two_mailboxes"
puts $channel "hdl_commit=[exec git -C $script_dir rev-parse HEAD]"
puts $channel "actual_fft_simulation_clock_period_ns=5"
puts $channel "actual_slow_simulation_clock_period_ns=10"
puts $channel "mailbox_and_result_reset=common_service_epoch_only"
puts $channel "per_job_reset=input_checker_and_fft_only_after_actual_slow_ACK"
puts $channel "cause_coverage_fence_independent_review_required=true"
puts $channel "production_service_integrated=false"
puts $channel "sustained_service_capacity_qualified=false"
puts $channel "physical_timing_or_CDC_qualified=false"
puts $channel "no_synthesis_or_implementation_run=true"
puts $channel "source_hashes=[exec sha256sum {*}[glob [file join $source_dir *]] $wrapper_path]"
puts $channel "required_generics=$required_generics"
puts $channel "generated_entity=$entity"
close $channel
report_property [get_ips $module_name] -file [file join $output_dir ip_properties.rpt]
foreach name $rtl_names { add_files -fileset sim_1 -norecurse [file join $source_dir $name] }
add_files -fileset sim_1 -norecurse [file join $source_dir ${bench_name}.sv]
add_files -fileset sim_1 -norecurse [file join $source_dir starlink_pss_realtime_result_guard_ff4229_golden.v]
add_files -fileset sim_1 -norecurse [file join $source_dir starlink_pss_realtime_input_guard_0a1af893_golden.v]
foreach name $vector_names { add_files -fileset sim_1 -norecurse [file join $source_dir ${name}.mem] }
set_property file_type {Memory Initialization Files} [get_files -of_objects [get_filesets sim_1] *.mem]
set_property top $bench_name [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
close_sim
require_realtime_probe_pass [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log] \
  [list {RETIRED_SERVICE_SHADOW_PASS public_golden=1 original_fence=1 actual_input_checker=1 actual_FFT=1 idle_final_and_ACK_premises=1} \
    {INPUT_CURSOR_SERVICE_SHADOW_PASS actual_mailbox_and_core=1 public_pins=1 no_internal_deposits=1} \
    {RETIRED_SERVICE_DUPLICATE_PASS final=1 ACK=1 same_edge_veto=1 actual_checker_fault=1} \
    {REALTIME_SERVICE_CANDIDATE_PASS healthy_jobs=26 exact_words=13312 starvation_cases=6 final_veto_cases=3 malformed_bank_cases=2 independent_reset_cases=6 configure_reset_cases=2 partial_input_reset_cases=2 postcommit_ACK_fault_cases=1 CAUSE_FENCE_REVIEW_REQUIRED CAPACITY_AND_PHYSICAL_UNQUALIFIED}] \
  RT_SERVICE_RESULT 26
require_realtime_probe_pass [file join $project_dir ${project_name}.sim sim_1 behav xsim simulate.log] \
  [list {IDLE_MAILBOX_SERVICE_PREMISE_PASS actual_mailbox_and_FFT=1 inactive_and_ACK=1 private_writes_active=1 public_golden=1}] \
  RT_SERVICE_RESULT 26
close_project
puts "REALTIME_SERVICE_CANDIDATE_SIMULATION_VERIFIED CAPACITY_AND_PHYSICAL_UNQUALIFIED"
