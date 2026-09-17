#-----------------------------------------------------------------------------
# nanoSoC-M0 QuickStart — top-level makefile
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Delegates every flow target to the arch_tech makefile. Simulation, FPGA, lint
# and software targets are all reachable from here.
#-----------------------------------------------------------------------------

include $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/makefile
