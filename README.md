# nanoSoC-M0 QuickStart SoC

A Cortex-M0 nanoSoC that builds, simulates and debugs using **Arm Quickstart IP only** —
no Arm Academic Access licence, no CoreSight SoC-400, no PL230.

The Quickstart Cortex-M0 bundle ships everything this SoC needs: the core, its
`CORTEXM0DAP` debug access port, the integration wrapper, and the full Corstone-101
CMSDK peripheral and bus library. Point `ARM_QS_IP_DIR` at your unpacked download and
build.

## What you get

| | |
|---|---|
| CPU | Arm Cortex-M0 (Quickstart), SoC Labs `slcorem0` wrapper |
| Debug | SWD via the core's own `CORTEXM0DAP` — OpenOCD `mem_ap` and `cortex_m` targets |
| Host port | HOSTIO/ADP, an AHB master for firmware load and memory access |
| Peripherals | CMSDK UART, timers, dual timers, watchdog, GPIO |
| Memory | boot ROM, instruction and data memory, two expansion SRAM banks |
| FPGA targets | HAPS-SX, KR260, PYNQ-Z2 |

## Getting started

```bash
export ARM_QS_IP_DIR=/path/to/your/Cortex-M0-QS
source set_env.sh
make sim
```

`ARM_QS_IP_DIR` must contain `Cortex-M0-logical/` and `Corstone-101-logical/`.
See [docs/ip-setup.md](docs/ip-setup.md) if your download is laid out differently.

## Design notes

- [docs/PLAN.md](docs/PLAN.md) — build plan and current status
- [docs/ip-setup.md](docs/ip-setup.md) — pointing the build at your Quickstart IP

## Licence

The RTL in this repository and its SoC Labs submodules is SoC Labs' own work. **No Arm
IP is included or redistributed here.** You supply your own Quickstart deliverable under
your own licence with Arm.
