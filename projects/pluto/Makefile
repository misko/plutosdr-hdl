####################################################################################
## Copyright (c) 2018 - 2023 Analog Devices, Inc.
### SPDX short identifier: BSD-1-Clause
## Auto-generated, do not modify!
####################################################################################

PROJECT_NAME := pluto

# One knob selects matching tracker and acquisition geometries. The 30/60 MS/s
# builds keep DMA/tracking at source rate and decimate only the continuous
# acquisition branch back to its canonical 15 MS/s shared-XFFT rate.
STARLINK_PSS_RATE_MSPS ?= 15
export STARLINK_PSS_RATE_MSPS

M_DEPS += ../../library/common/ad_iobuf.v
M_DEPS += ../../library/axi_ad9361/axi_ad9361_delay.tcl

LIB_DEPS += axi_ad9361
LIB_DEPS += axi_dmac
LIB_DEPS += axi_starlink_pss_acquisition
LIB_DEPS += axi_starlink_pss_tracker
LIB_DEPS += util_pack/util_cpack2

include ../scripts/project-xilinx.mk
