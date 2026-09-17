#!/bin/bash
#-----------------------------------------------------------------------------
# nanoSoC-M0 QuickStart — dependency repository environment
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# SOCLABS_PROJECT_DIR is set by soctools_flow/bin/project_setup.sh and points at
# the root of this repository.
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# nanoSoC-M0 technologies
#-----------------------------------------------------------------------------

# SoC: chip RTL, interconnect config, arch tech
export SOCLABS_NANOSOC_SOC_DIR="$SOCLABS_PROJECT_DIR/nanosoc_m0_soc"

# Architecture tech (submodule inside nanosoc_m0_soc)
export SOCLABS_NANOSOC_ARCH_TECH_DIR="$SOCLABS_NANOSOC_SOC_DIR/nanosoc_arch_tech"

# Generation tool (soc_model, glue logic RTL, component library)
export SOCLABS_NANOSOC_GEN_DIR="$SOCLABS_NANOSOC_ARCH_TECH_DIR/nanosoc_gen"

# Firmware (software, toolchain configs, build system)
export SOCLABS_NANOSOC_FIRMWARE_TECH_DIR="$SOCLABS_NANOSOC_ARCH_TECH_DIR/firmware"

#-----------------------------------------------------------------------------
# IP submodules, nested inside nanosoc_arch_tech/rtl/
#-----------------------------------------------------------------------------

export SOCLABS_SOCDEBUG_TECH_DIR="$SOCLABS_NANOSOC_ARCH_TECH_DIR/rtl/socdebug_tech"
export SOCLABS_SLCOREM0_TECH_DIR="$SOCLABS_NANOSOC_ARCH_TECH_DIR/rtl/slcorem0_tech"
export SOCLABS_HOSTIO4_TECH_DIR="$SOCLABS_NANOSOC_ARCH_TECH_DIR/rtl/hostio4"

# No SLDMA230 / SLDMA350: this SoC builds with DMAC_0_TYPE = 0 and the Quickstart
# Corstone-101 bundle ships no PL230 RTL. See docs/ip-setup.md.

#-----------------------------------------------------------------------------
# Support libraries
#-----------------------------------------------------------------------------

export SOCLABS_PRIMITIVES_TECH_DIR="$SOCLABS_PROJECT_DIR/rtl_primitives_tech"
export SOCLABS_FPGA_LIB_TECH_DIR="$SOCLABS_PROJECT_DIR/fpga_lib_tech"
export SOCLABS_GENERIC_LIB_TECH_DIR="$SOCLABS_PROJECT_DIR/generic_lib_tech"

# No ASIC_LIB / ASIC_FLOW: this project targets simulation and FPGA.

#-----------------------------------------------------------------------------
# Flows
#-----------------------------------------------------------------------------

export SOCLABS_SOCTOOLS_FLOW_DIR="$SOCLABS_PROJECT_DIR/soctools_flow"
export SOCLABS_CHIPKIT_FLOW_DIR="$SOCLABS_SOCTOOLS_FLOW_DIR/tools/chipkit_flow"
