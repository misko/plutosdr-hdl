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

# Keep the historical tracker path available, let blind acquisition omit it,
# and make the deterministic injector a separate qualification-only profile.
# The result-only detector profile keeps both PSS stages but omits the raw RX
# DMA/DDR copy and expansion-header AXI SPI/IIC controllers, none of which is
# part of either detector. It is rate-parameterized at 15/30/60 MS/s; PS SPI0
# and IIO control of the AD9361 remain. The default preserves existing builds.
STARLINK_PSS_PROFILE ?= full
export STARLINK_PSS_PROFILE

# Experimental single 200 MHz transform island; defaults remain unchanged.
STARLINK_PSS_SHARED_XFFT ?= 0
export STARLINK_PSS_SHARED_XFFT

M_DEPS += ../../library/common/ad_iobuf.v
M_DEPS += ../../library/axi_ad9361/axi_ad9361_delay.tcl
M_DEPS += shared_xfft_impl_gate.tcl

LIB_DEPS += axi_ad9361
LIB_DEPS += axi_dmac
LIB_DEPS += axi_starlink_pss_acquisition
LIB_DEPS += axi_starlink_pilot_capture
LIB_DEPS += axi_starlink_pss_periodic_injector
LIB_DEPS += axi_starlink_pss_tracker
LIB_DEPS += util_pack/util_cpack2

include ../scripts/project-xilinx.mk
