####################################################################################
## Experimental RX-only exact PSS tracker. DO NOT MERGE TO HDL MAIN.
####################################################################################

LIBRARY_NAME := axi_starlink_pss_tracker

GENERIC_DEPS += ../common/up_axi.v
GENERIC_DEPS += ../common/ad_mem.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_async_fifo.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_sat_add48.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_candidate_scheduler.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_capture_bridge.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_sliding_correlator.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_tracking_core.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_exact_reducer.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_result_store.v
GENERIC_DEPS += ../starlink_pss_raw_correlator/starlink_pss_reduced_tracking_core.v
GENERIC_DEPS += starlink_pss_injection_mux.v
GENERIC_DEPS += axi_starlink_pss_tracker.v

XILINX_DEPS += axi_starlink_pss_tracker_constr.xdc
XILINX_DEPS += axi_starlink_pss_tracker_ip.tcl

include ../scripts/library.mk
