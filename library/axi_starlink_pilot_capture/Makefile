# SPDX-License-Identifier: GPL-2.0
LIBRARY_NAME := axi_starlink_pilot_capture
PILOT_DIR := ../starlink_pss_acquisition
GENERIC_DEPS += axi_starlink_pilot_capture.v
GENERIC_DEPS += ../axi_starlink_pss_phase_map/starlink_pss_axi_lite.v
GENERIC_DEPS += $(PILOT_DIR)/starlink_pilot_ddc.v
GENERIC_DEPS += $(PILOT_DIR)/starlink_pilot_halfband2.v
GENERIC_DEPS += $(PILOT_DIR)/starlink_pilot_fir3.v
GENERIC_DEPS += $(PILOT_DIR)/pilot_mixer_q16.mem
GENERIC_DEPS += $(PILOT_DIR)/pilot_halfband2_q17.mem
GENERIC_DEPS += $(PILOT_DIR)/pilot_fir3_q17.mem
XILINX_DEPS += axi_starlink_pilot_capture_ip.tcl
include ../scripts/library.mk
