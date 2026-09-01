####################################################################################
## Experimental RX-only Starlink candidate monitor. DO NOT MERGE TO HDL MAIN.
####################################################################################

LIBRARY_NAME := axi_starlink_pss_monitor

GENERIC_DEPS += ../common/up_axi.v
GENERIC_DEPS += starlink_pss_delay_candidate.v
GENERIC_DEPS += starlink_pss_event_cdc.v
GENERIC_DEPS += axi_starlink_pss_monitor.v

XILINX_DEPS += axi_starlink_pss_monitor_constr.xdc
XILINX_DEPS += axi_starlink_pss_monitor_ip.tcl

include ../scripts/library.mk
