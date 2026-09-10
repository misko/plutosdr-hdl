# PREPARATION ONLY until separately authorized. No bank/receiver qualification.
# A/B changes only REGISTER_OPERANDS; DATA_WIDTH18 and ROUND1 remain fixed.
if {$argc != 2 || [lindex $argv 1] ni {0 1}} {
  error "expected NEW_OUTPUT and literal REGISTER_OPERANDS 0|1"
}
if {[version -short] ne "2022.2"} { error "Vivado2022.2 required" }
set output_dir [file normalize [lindex $argv 0]]
set register_option [lindex $argv 1]
if {[file exists $output_dir]} { error "refusing to overwrite evidence" }
set script_dir [file dirname [file normalize [info script]]]
set fw_dir [file normalize [file join $script_dir ../../..]]
set files [list \
  [file join $script_dir starlink_pss_spectrum_product.v] \
  [file join $script_dir starlink_pss_spectrum_product_operand_register.v] \
  [file join $script_dir starlink_pss_spectrum_operand_register_ooc.xdc] \
  [file join $script_dir tb tb_starlink_spectrum_operand_parameters.sv] \
  [file normalize [info script]] \
  [file join $fw_dir tests test_starlink_spectrum_operand_physical_policy.py]]
set names {}
foreach path $files {
  if {![file isfile $path]} { error "missing preflight source $path" }
  if {[file tail $path] in $names} { error "duplicate frozen basename" }
  lappend names [file tail $path]
}
foreach {name expected} {
  starlink_pss_spectrum_product.v 4f9046d0efc395d68caa9b63911fcf5c18ab335b1f2707ad19d3794e0cc2329b
  starlink_pss_spectrum_product_operand_register.v dfb04b76e5ba9069565a8671794a365adcd2d516013d4f588eda8581f037b69d
} {
  if {[lindex [exec sha256sum [file join $script_dir $name]] 0] ne $expected} {
    error "unreviewed arithmetic/operand source $name"
  }
}
file mkdir [file join $output_dir frozen_sources]
set frozen [file join $output_dir frozen_sources]
set inventory [dict create]
set hashes [open [file join $output_dir input_sources.sha256] w]
foreach path $files {
  set name [file tail $path]
  file copy $path [file join $frozen $name]
  set hash [lindex [exec sha256sum [file join $frozen $name]] 0]
  dict set inventory $name $hash
  puts $hashes "$hash  $name"
}
close $hashes
set scope [open [file join $output_dir scope.txt] w]
puts $scope "scope=isolated_operand_AB_not_bank_BRAM_path_or_receiver"
puts $scope "register_operands=$register_option data_width=18 boundary_round_sat=1"
puts $scope "part=xc7z010clg400-1 clock_ns=5.714 threads=2"
puts $scope "input_max_min_ns=1.000,0.500 output_max_min_ns=0.500,0.000 no_exceptions=1"
puts $scope "parameter_proof=Icarus_elaborated_hierarchy synthesized_port_widths_checked_separately"
puts $scope "hdl_commit=[exec git -C [file join $fw_dir hdl] rev-parse HEAD]"
puts $scope "fw_commit=[exec git -C $fw_dir rev-parse HEAD]"
puts $scope "hdl_status=[exec git -C [file join $fw_dir hdl] status --porcelain --untracked-files=normal]"
puts $scope "fw_status=[exec git -C $fw_dir status --porcelain --untracked-files=normal]"
close $scope

proc operand_verify_sources {frozen inventory} {
  set actual [lsort [glob -nocomplain -tails -directory $frozen *]]
  if {$actual ne [lsort [dict keys $inventory]]} { error "frozen source inventory changed" }
  dict for {name expected} $inventory {
    if {![file isfile [file join $frozen $name]] ||
        [lindex [exec sha256sum [file join $frozen $name]] 0] ne $expected} {
      error "frozen source hash changed $name"
    }
  }
}

proc operand_dsp_inventory {stage} {
  set file [open "dsp_${stage}.tsv" w]
  puts $file "cell\tAREG\tBREG\tMREG\tPREG\tCREG\tACASCREG\tBCASCREG"
  set pins [open "dsp_ce_${stage}.tsv" w]
  puts $pins "cell\tpin\tnets\tdriver_pins"
  set dsps [lsort [get_cells -hier -filter {REF_NAME == DSP48E1}]]
  if {[llength $dsps] == 0} { error "no mapped DSP48E1 in $stage" }
  foreach cell $dsps {
    set values [list $cell]
    foreach property {AREG BREG MREG PREG CREG ACASCREG BCASCREG} {
      set value [get_property $property $cell]
      if {$value eq ""} { error "missing DSP property $property" }
      lappend values $value
    }
    puts $file [join $values "\t"]
    foreach required {CEA1 CEA2 CEB1 CEB2 CEM CEP} {
      if {[llength [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == $required"]] != 1} {
        error "missing DSP CE pin $cell/$required"
      }
    }
    foreach pin [lsort [get_pins -of_objects $cell -filter {REF_PIN_NAME =~ CE*}]] {
      set nets [lsort [get_nets -quiet -of_objects $pin]]
      set drivers [get_pins -quiet -of_objects $nets -filter {DIRECTION == OUT}]
      puts $pins "$cell\t[get_property REF_PIN_NAME $pin]\t[join $nets ,]\t[join [lsort $drivers] ,]"
    }
  }
  close $file; close $pins
  return [llength $dsps]
}

proc operand_timing {stage} {
  report_timing_summary -delay_type min_max -max_paths 30 -file "timing_${stage}.rpt"
  report_timing -delay_type max -max_paths 30 -path_type full_clock_expanded -file "setup_${stage}.rpt"
  report_timing -delay_type min -max_paths 30 -path_type full_clock_expanded -file "hold_${stage}.rpt"
  check_timing -verbose -file "check_timing_${stage}.rpt"
  set result [open "timing_${stage}.txt" w]
  set registers [all_registers]
  foreach {mode label} {max setup min hold} {
    set all [get_timing_paths -quiet -delay_type $mode -max_paths 1]
    set internal [get_timing_paths -quiet -from $registers -to $registers -delay_type $mode -max_paths 1]
    if {[llength $all] != 1 || [llength $internal] != 1} { error "missing $stage $label constrained path" }
    puts $result "${label}_slack_ns=[get_property SLACK $all]"
    puts $result "internal_${label}_slack_ns=[get_property SLACK $internal]"
    report_timing -from $registers -to $registers -delay_type $mode -max_paths 30 \
      -path_type full_clock_expanded -file "internal_${label}_${stage}.rpt"
    set failed [get_timing_paths -quiet -delay_type $mode -slack_lesser_than 0 -nworst 1 -max_paths 10000]
    if {[llength $failed] >= 10000} { error "failed-endpoint inventory cap reached" }
    set table [open "failing_${label}_${stage}.tsv" w]
    puts $table "startpoint\tendpoint\tslack_ns\tstart_is_top_port"
    set ports 0
    foreach path $failed {
      set start [get_property STARTPOINT_PIN $path]
      set is_port [expr {[string first / $start] < 0}]
      incr ports $is_port
      puts $table "$start\t[get_property ENDPOINT_PIN $path]\t[get_property SLACK $path]\t$is_port"
    }
    close $table
    puts $result "failing_${label}_endpoints=[llength $failed] from_top_ports=$ports"
  }
  close $result
}

proc operand_measure {frozen option} {
  set_param general.maxThreads 2
  # Actual elaborated parameter values, not an assertion about requested argv.
  set compile_status [catch {exec iverilog -g2012 -s tb_starlink_spectrum_operand_parameters \
    -Ptb_starlink_spectrum_operand_parameters.REGISTER=$option -o parameter_probe.vvp \
    [file join $frozen starlink_pss_spectrum_product.v] \
    [file join $frozen starlink_pss_spectrum_product_operand_register.v] \
    [file join $frozen tb_starlink_spectrum_operand_parameters.sv] 2>@1} compile compile_options]
  set file [open parameter_compile.log w]; puts $file $compile; close $file
  if {$compile_status} { return -options $compile_options $compile }
  set probe_status [catch {exec vvp parameter_probe.vvp 2>@1} probe probe_options]
  set file [open parameter_probe.log w]; puts $file $probe; close $file
  if {$probe_status} { return -options $probe_options $probe }
  if {$probe ne "OPERAND_PARAMETERS_VERIFIED width=18 round=1 registered=$option child_width=18 child_round=1 clocks=0"} {
    error "parameter probe did not exactly qualify"
  }
  read_verilog [file join $frozen starlink_pss_spectrum_product.v]
  read_verilog [file join $frozen starlink_pss_spectrum_product_operand_register.v]
  synth_design -mode out_of_context -flatten_hierarchy rebuilt \
    -directive AreaOptimized_high -top starlink_pss_spectrum_product_operand_register \
    -part xc7z010clg400-1 -generic [list DATA_WIDTH=18 REGISTER_OPERANDS=$option BOUNDARY_ROUND_SAT=1]
  foreach {port width} {input_i 18 input_q 18 kernel_i 18 kernel_q 18 output_i 18 output_q 18
                       input_bin_index 9 output_bin_index 9 input_block_exponent 5 output_block_exponent 5
                       input_block_start_index 64 output_block_start_index 64} {
    if {[llength [get_ports [format {%s[*]} $port]]] != $width} { error "wrong synthesized port width $port" }
  }
  foreach port {clk resetn flush input_valid input_ready input_last output_valid output_ready output_last output_overflow overflow_pulse} {
    if {[llength [get_ports $port]] != 1} { error "wrong synthesized scalar port $port" }
  }
  read_xdc [file join $frozen starlink_pss_spectrum_operand_register_ooc.xdc]
  if {[get_property PERIOD [get_clocks product_clk]] != 5.714} { error "wrong physical clock" }
  write_checkpoint "operand${option}_synth.dcp"
  report_utilization -hierarchical -file utilization_synth.rpt
  operand_dsp_inventory synth
  operand_timing synth
  opt_design -directive ExploreArea
  write_checkpoint "operand${option}_opt.dcp"
  report_utilization -hierarchical -file utilization_opt.rpt
  place_design
  phys_opt_design
  route_design
  write_checkpoint "operand${option}_route.dcp"
  report_utilization -hierarchical -file utilization_route.rpt
  operand_dsp_inventory route
  operand_timing route
  report_methodology -file methodology.rpt
  report_route_status -file route_status.rpt
  set hashes [open checkpoints.sha256 w]
  foreach stage {synth opt route} { puts $hashes [exec sha256sum "operand${option}_${stage}.dcp"] }
  close $hashes
  close_design
}

cd $output_dir
set status [catch {operand_measure $frozen $register_option} message options]
set integrity [catch {operand_verify_sources $frozen $inventory} integrity_message]
set result [open result.txt w]
puts $result "scope=isolated_operand_AB_MEASUREMENT_NOT_TIMING_PASS_OR_BANK_QUALIFICATION"
puts $result "register_operands=$register_option data_width=18 boundary_round_sat=1"
puts $result "tool_error=$status source_integrity_error=$integrity"
puts $result "tool_message=$message source_integrity_message=$integrity_message"
close $result
if {$integrity} { error $integrity_message }
if {$status} { return -options $options $message }
puts "OPERAND_BOUNDARY_PHYSICAL_MEASURED registered=$register_option width=18 round=1 NOT_BANK_OR_TIMING_QUALIFICATION"
