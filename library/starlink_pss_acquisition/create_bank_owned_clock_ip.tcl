# Separate candidate clock: never change the board's AD9361 200 MHz reference.
# An already buffered 100 MHz input feeds a dedicated MMCM/BUFG 175 MHz output.
proc pss_create_bank_owned_clock_ip {generated_directory} {
  if {[version -short] ne "2022.2"} { error "bank clock requires Vivado 2022.2" }
  set module_name starlink_bank_clock175_candidate
  if {[llength [get_ips -quiet $module_name]]} { error "refusing existing bank clock IP" }
  create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name $module_name
  set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {175.000} CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIMITIVE {MMCM} CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} CONFIG.CLKOUT1_DRIVES {BUFG}] [get_ips $module_name]
  generate_target all [get_ips $module_name]
  set primitive_file [file join $generated_directory ${module_name}_clk_wiz.v]
  set channel [open $primitive_file r]; set primitive [read $channel]; close $channel
  foreach {name expected} {
    DIVCLK_DIVIDE 2 CLKFBOUT_MULT_F 20.125 CLKOUT0_DIVIDE_F 5.750 CLKIN1_PERIOD 10.000
  } {
    set pattern [format {\.%s\s*\(\s*([0-9.]+)\s*\)} $name]
    set matches [regexp -all -inline $pattern $primitive]
    if {[llength $matches] != 2 || [lindex $matches 1] ne $expected} {
      error "unexpected bank clock primitive parameter $name"
    }
  }
  if {[regexp -all {\mMMCME2_ADV\M} $primitive] != 1 ||
      [regexp -all {\mBUFG\M} $primitive] != 2 ||
      ![regexp {assign\s+reset_high\s*=\s*~resetn\s*;} $primitive] ||
      ![regexp {assign\s+clk_in1_starlink_bank_clock175_candidate\s*=\s*clk_in1\s*;} $primitive]} {
    error "bank clock primitive/buffer/reset contract differs"
  }
  return [list [file join $generated_directory ${module_name}.v] $primitive_file]
}
