# Pointing the build at your Quickstart IP

The build reads exactly one path variable. Everything else is derived from it.

```bash
export ARM_QS_IP_DIR=/path/to/Cortex-M0-QS
```

That directory must contain two trees:

```
Cortex-M0-QS/
├── Cortex-M0-logical/
│   ├── cortexm0/verilog/            core RTL
│   ├── cortexm0_dap/verilog/        CORTEXM0DAP — the debug access port
│   ├── cortexm0_integration/verilog/
│   └── models/                      cells and wrappers
└── Corstone-101-logical/
    ├── cmsdk_ahb_*/                 bus infrastructure
    ├── cmsdk_apb_*/                 UART, timers, watchdog
    └── models/                      memories, protocol checkers
```

If your download nests these differently, override the two derived variables directly
in `nanosoc.config` instead of `ARM_QS_IP_DIR`:

```make
ARM_CORTEX_M0_DIR    ?= /somewhere/Cortex-M0-logical
ARM_CORSTONE_101_DIR ?= /elsewhere/Corstone-101-logical
```

## What is deliberately not here

- **PL230 / DMA-230.** The Quickstart Corstone-101 tree ships an *empty* `pl230_udma/`
  directory — the RTL is not in the bundle. This SoC builds with `DMAC_0_TYPE = 0`, and
  the DMA controller sits inside a `generate` guard, so nothing is instantiated and
  nothing is missing.
- **CoreSight SoC-400.** Not needed for a single core. `CORTEXM0DAP` is in the
  Quickstart bundle and reaches both the system bus and the core's PPB.
- **ASIC libraries.** This repo targets simulation and FPGA. Foundry collateral is not
  a submodule here.
