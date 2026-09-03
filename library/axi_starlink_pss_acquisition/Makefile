####################################################################################
## Copyright (c) 2026 Analog Devices, Inc.
### SPDX short identifier: BSD-1-Clause
####################################################################################

LIBRARY_NAME := axi_starlink_pss_acquisition

ACQ_DIR := ../starlink_pss_acquisition
MAP_DIR := ../axi_starlink_pss_phase_map

GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_sample_cdc.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_x2_ddc.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_overlap_scheduler.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_energy_cache.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_xfft_block_adapter.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_xfft_intermediate_buffer.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_kernel_rom.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_forward_kernel_join.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_spectrum_product.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_ifft_qualifier.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_raw_result_fifo.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_energy_join.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_score_prepare.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_score_divider.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_score_divider_radix4.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_score_lanes.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_candidate_score_path.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_iq_to_score.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_score_phase_tagger.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_phase_map_bank.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_phase_map.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_acquisition_health.v
GENERIC_DEPS += $(ACQ_DIR)/starlink_pss_iq_to_phase_map.v
GENERIC_DEPS += $(ACQ_DIR)/tb/upper_edge_pss_kernel_q17.mem
GENERIC_DEPS += $(ACQ_DIR)/tb/upper_edge_pss30_x2_ddc_kernel_q17.mem
GENERIC_DEPS += $(ACQ_DIR)/tb/upper_edge_pss60_x4_ddc_kernel_q17.mem
GENERIC_DEPS += $(MAP_DIR)/starlink_pss_axi_lite.v
GENERIC_DEPS += axi_starlink_pss_phase_map_sync.v
GENERIC_DEPS += axi_starlink_pss_acquisition.v

XILINX_DEPS += axi_starlink_pss_acquisition_ip.tcl
XILINX_DEPS += axi_starlink_pss_acquisition_constr.xdc
XILINX_DEPS += $(ACQ_DIR)/starlink_pss_sample_cdc_constr.xdc

include ../scripts/library.mk
