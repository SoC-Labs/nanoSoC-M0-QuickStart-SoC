# Build plan — nanoSoC-M0 QuickStart SoC

**Goal:** a nanoSoC that builds, simulates and debugs using only Arm Quickstart IP plus
SoC Labs RTL, and that OpenOCD can drive over HOSTIO as well as SWD.

**Principle:** Quickstart is not a mode. There is no `QUICKSTART` switch, no `_qs` flist
duality and no AAA fallback in this repo. One flist chain, one testbench, two path
variables.

---

## Where the QS path stands today (surveyed 2026-09-17)

The upstream `nanosoc_arch_tech` already contains most of a Quickstart build, in a shape
that cannot work:

- `makefile:44` declares `QUICKSTART ?= no`, and `makefile:228-233` branches on it to set
  `ARM_CORTEX_M0_DIR` / `ARM_CORSTONE_101_DIR`, select `flist/project/top_qs.flist` and
  set `TB_TOP = nanosoc_tb_qs`.
- **`top_qs.flist` does not exist** in any project, so the switch is broken end to end.
- Both IP root variables are declared and `export`ed — and **no flist reads them.** Every
  flist hardcodes `$(ARM_IP_LIBRARY_PATH)/latest/...`. That single omission is the entire
  reason six duplicate `_qs` flists exist.
- `nanosoc_tb_qs.v` is not a lagging copy of `nanosoc_tb.v`. It differs by 937 lines and
  its DUT path is `...u_system.u_ss_cpu...` where the live testbench uses
  `...u_system.u_nanosoc.u_ss_cpu...`. It predates the generator refactor and cannot bind
  to today's design. It gets deleted, not repaired.

So the cleanup and the enablement are the same job: make the flists honour the two
variables that already exist, then delete everything the duplication was covering for.

**Deletions this buys:** six `_qs` flists, `nanosoc_tb_qs.v`, the `QUICKSTART` branch, the
`TB_TOP` duality and the phantom `top_qs.flist`.

---

## Where the work lands

| Change | Repo |
|---|---|
| Flists honour `ARM_CORTEX_M0_DIR` / `ARM_CORSTONE_101_DIR` | `nanosoc_arch_tech` |
| Delete `_qs` flists, `nanosoc_tb_qs.v`, `QUICKSTART` branch | `nanosoc_arch_tech` |
| `nanosoc_dbg_slv_mux.v`, `nanosoc_dbg_ahb_bridge` fixes | `nanosoc_arch_tech` |
| `CORE_DBG_WINDOW_PRESENT` sys_desc param (default 0) | `nanosoc_arch_tech` |
| HAPS-SX FPGA target | `nanosoc_arch_tech` |
| Project config, flist selection, OpenOCD configs, docs, CI | this repo |

Upstream changes are additive and default to today's behaviour, so the AAA project keeps
building unchanged.

---

## Phase A — It builds with no AAA

1. Repo skeleton: config, submodules, `set_env.sh`, `flist/project/top.flist`. *(done)*
2. Upstream: repoint the flists at `$(ARM_CORTEX_M0_DIR)` / `$(ARM_CORSTONE_101_DIR)`.
3. Upstream: delete the `_qs` duplicates, `nanosoc_tb_qs.v` and the `QUICKSTART` branch.
4. Confirm DMA stays out — `DMAC_0_TYPE` already defaults to 0 and the controller is
   inside `generate if (DMAC_0_TYPE > 0)`, so no RTL work is needed.

**Gate A:** a firmware test runs to completion with `ARM_IP_LIBRARY_PATH` unset and only
`ARM_QS_IP_DIR` set. Prove it can fail: unset `ARM_QS_IP_DIR` and confirm the build breaks
rather than silently resolving files elsewhere.

**Estimate:** 1 day.

## Phase B — It debugs over SWD

1. `mem_ap` target. No RTL: the M0 DAP's AP is a conformant AHB-AP, `IDR 0x04770021`.
2. `cortex_m` target. Also no RTL — the M0 DAP reaches the PPB through the core's `SLV`
   port natively.
3. Ship both configs, ported from the `haps-openocd` `dap-only.cfg` pattern.

**Gate B:** `dap apid 0` returns `0x04770021` and `mdw 0xE000ED00` reads CPUID
`0x410CC200` — read from the log line, not from "connect succeeded".

**Estimate:** half a day.

## Phase C — It debugs over HOSTIO

1. Fix the bridge first. `nanosoc_dbg_ahb_bridge.v:189` hardwires `HRESP = 1'b0` and never
   reads `DBGAHB_SLVRESP`, so a failed PPB access returns OKAY with stale `rdata_q`. Add
   the ADP bus timeout — `socdebug_adp_control.v` spins on `adp_bus_done` with no escape.
2. `mem_ap` over HOSTIO. Driver only, no RTL: a `mem_ap` target never touches the PPB.
   This proves the ADP transport end to end.
3. `nanosoc_dbg_slv_mux.v` plus the debug window at `0xA0000000`, debug initiator only.
   `CORTEXM0DAP` moves up into `nanosoc_ss_cpu.v`; `slcorem0` stays at `EXTERNAL_DAP=1`.
   cocotb bench adapted from `cocotb/slcorem0_external_dap/`.
4. `cortex_m` over HOSTIO. The driver emulates a MEM-AP: `TAR[31:28]==0xE` routes to the
   window, everything else goes direct over ADP.

**Gate C:** halt the core from OpenOCD over HOSTIO, read R0-R15, set a breakpoint, resume.
Prove it can fail: point the driver at a wrong window base and confirm it errors instead of
returning stale data. That check is why step 1 comes first.

**Estimate:** 1.5-2 weeks.

## Phase D — FPGA

Targets, in order of existing support:

1. **PYNQ-Z2** — target exists upstream (`fpga/fpga/targets/pynq_z2`), Vivado 2021.1.
2. **KR260** — target exists (`targets/pynq_kr260`), Vivado 2021.1 and 2024.1.
3. **HAPS-SX** — **new work.** No HAPS target exists upstream; port from
   `HAPS-work/fpga/haps-sx`, which already carries constraints, HOSTIO and OpenOCD
   plumbing for this bench.

**Gate D:** per board, firmware runs from boot ROM and OpenOCD attaches over SWD.

**Estimate:** 2 days for the two PYNQ-family boards, 3-4 days for HAPS-SX.

---

## Risks

1. **HAPS-SX is a new target, not a port of an existing one.** The largest unknown left.
2. **No cocotb harness in this project lineage.** Phase C step 3 needs one stood up or
   borrowed from the multicore repo.
3. **The bridge has no `dbgen`/`spiden` gate.** Adding the window gives HOSTIO
   unauthenticated full debug. Acceptable for a research chip, but it should be a recorded
   decision, not an accident.
4. **Upstream changes are shared with the AAA project.** Every one must default to
   today's behaviour.
