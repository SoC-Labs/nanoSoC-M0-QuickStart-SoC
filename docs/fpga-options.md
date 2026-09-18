# FPGA options after the SPI/QSPI removal

**Scope:** what removing the Arm PL022 SSP and the `qspi_flash_ahb` XiP
controller broke in the FPGA flow, what repairing it costs, whether the
published nanoSoC FPGA Toolkit can be adopted instead, and which to do.

**Status:** scoping only. Nothing in this survey changed any RTL, Tcl, XDC,
YAML or makefile, and no EDA tool was launched. Every figure below is measured
or cited; where a claim is an inference it says so.

**Date:** 2026-09-18.

---

## Summary

There are **three** FPGA paths in this tree, not two. One is inert.

| | Path | Reached by | Ever built a bitstream? |
|---|---|---|---|
| **A** | `nanosoc_m0_soc/pynq/` | its own `Makefile` — **not** by this project's top-level `make` | **Yes**, a real nanoSoC on a PYNQ-Z2 — but in a *different checkout* |
| **B** | `nanosoc_arch_tech/fpga/fpga/targets/pynq_z2/` | `Makefile:10` → `arch_tech/makefile:274` → `flows/makefile.fpga` | **Not here.** Yes, in an unrelated project, 2025 |
| **C** | `nanosoc_gen --fpga-wrapper` / `--emit-vivado-bd` | nothing | **No.** Inert in this project |

Neither A nor B has ever produced a bitstream *in this repository*.

**Recommendation: both, in sequence.** Repair A's board collateral now
(1.5–2.5 days) to get a bitstream, then adopt the toolkit (4–8 days more)
pointing at that same collateral rather than copying it. The repair is not
throwaway: the toolkit's consumers *point at* existing target collateral, and
flow A's block-design script is already in the exact shape the toolkit wants.
Section 3 gives the reasoning, the ranking and the risks.

---

## Q1 — What is broken, and what does repairing it cost?

### 1.1 Which flow is live

**Neither is dead, and they are not alternatives at the same level.** They
integrate the SoC at *different hierarchy levels* and have different entry
points.

**Flow B is the one this project's own build system reaches.** The top-level
makefile is a single `include`:

- `Makefile:10` — `include $(SOCLABS_NANOSOC_ARCH_TECH_DIR)/makefile`
- `nanosoc_m0_soc/nanosoc_arch_tech/makefile:274` — `include .../flows/makefile.fpga`
- `flows/makefile.fpga:13` — `include .../fpga/fpga/makefile.targets`

So `make build_fpga FPGA=z2` is reachable from the repo root today
(`flows/makefile.fpga:143`). Flow B packages **`nanosoc_chip`** — the pad-level
chip — as a Vivado IP (`flows/makefile.fpga:23`) and drops it into a PS7 block
design alongside the SoC Labs debug socket.

**Flow A is not reachable from the top-level makefile at all.** It is a
self-contained flow under the submodule, run as `make -C nanosoc_m0_soc/pynq`.
`pynq/Makefile:31` derives its own root and never includes the project
makefile. It packages **`nanosoc`** — the generated core top, one level *below*
the chip — through a hand-written FPGA wrapper
(`pynq/vivado_ip/nanosoc_vivado_wrapper.v:180`, `package_nanosoc_ip.tcl:35`).

**Flow A is a fork, not a shared component.** `diff -rq` against
`/home/dam1n19/SoCLabs/nanosoc-multicore-system/pynq` shows `Makefile`,
`README.md`, `filelist.tcl` and `fpgahub.toml` all differ, and each side has
files the other lacks. It is a fourth copy of a pattern this tree copies about
twenty times over.

### 1.2 Has either ever produced a bitstream?

**Not in this repository.** This superproject is 18 commits old
(`24a9531`, 2026-09-17) and has no `imp/` directory at all. The hook flow B
needs did not exist until yesterday:

- `flist/project/top_FPGA.flist` was added in `7597136`, 2026-09-17, although
  `arch_tech/makefile:247` has referenced it as `DESIGN_VC_FPGA` since March.
- `docs/PLAN.md:144-147` records the same finding independently.

**Flow A has built a real nanoSoC on a PYNQ-Z2 — elsewhere.** In the standalone
checkout `/home/dam1n19/SoCLabs/nanosoc_m0_soc` (the same submodule repo,
checked out on its own):

```
imp/fpga/output/pynq-z2/nanosoc_design_wrapper.bit   4 045 682 B   2026-07-06
imp/fpga/output/pynq-z2/nanosoc_design.xsa             532 472 B   2026-07-06
imp/fpga/run/build_design.log:  Vivado v2024.1 (64-bit)
imp/fpga/run/build_design.log:  WNS = 16.834, TNS = 0.000    (25 MHz)
```

Wall clock from `package_ip.log` (16:34) to the `.bit` (16:47) is **13 minutes**.
Written up in `nanosoc_m0_soc/doc/reports/pynq_z2_build.md`.

**Flow B has built a bitstream — in a different project, a year ago.**
`/home/dam1n19/SoCLabs/support_requests/bharti/March-9-2026/aes128_project/imp/fpga/targets/pynq_z2/pynq_z2.runs/impl_1/nanosoc_design_wrapper.bit`,
dated 2025-08-29. The `imp/fpga/targets/<board>/` layout is flow B's
(`flows/makefile.fpga:33`), not flow A's.

### 1.3 The third flow

`nanosoc_gen` can emit an FPGA wrapper and a Vivado block design directly:

- `nanosoc_gen/soc_model/__main__.py:111` — `--emit-vivado-bd`
- `nanosoc_gen/soc_model/__main__.py:116-123` — `--fpga-wrapper`
- `nanosoc_gen/soc_model/__main__.py:37` — `backends.fpga_wrapper.SoCFpgaWrapperBackend`
- driven by `nanosoc_gen/lib/fpga_profile/*.yaml`

**It is inert here.** The only profile that exists is
`lib/fpga_profile/nanosoc_multicore.yaml` — the multicore SoC, not this one.
The `soc_model` recipe (`arch_tech/makefile:299-303`) passes neither flag, and
`nanosoc_m0_soc/build_soc/fpga/` does not exist. Design intent is in
`arch_tech/docs/roadmap/08-vivado-block-diagram-generation.md`. Treat it as a
future replacement for hand-written wrappers, not as an option today.

### 1.4 What exactly is broken in flow A

Two independent problems. The SPI/QSPI removal is the smaller one.

#### (a) SPI/QSPI references — 10 files

`nanosoc_m0_soc/build_soc/rtl/nanosoc.sv` has **no SPI ports and no QSPI ports**
today; the only surviving token is `.QSPI_PRESENT (0)` at line 903, a parameter
passed to the discovery block. `src/rtl/wrappers/qspi_flash_ahb.v` was deleted
in `1072b20`.

Measured drift between flow A's wrapper and today's generated `nanosoc`:

```
nanosoc.sv                                   68 ports, 43 parameters
wrapper                                      73 connections
names in the wrapper that no longer exist:    4   (spi_sclk, spi_ss, spi_mosi, spi_miso)
nanosoc.sv ports the wrapper fails to connect: 0
```

**Exactly four names are wrong. Everything else still lines up.** Repair
surface:

| File | Lines | What |
|---|---|---|
| `pynq/vivado_ip/nanosoc_vivado_wrapper.v` | 64-67, 88-92, 103, 166-169, 269-273 | 5 module ports, 1 `assign`, 4 instance connections |
| `pynq/targets/pynq-z2/nanosoc_design.tcl` | 70-74, 88, 206-210, 221 | 5 BD ports, 5 BD connections |
| `pynq/targets/pynq-z2/nanosoc_design_wrapper.v` | 53-58, 69, 80, 147-151, 167, 172-183 | ports, wire, connections, LD1 repurpose |
| `pynq/targets/pynq-z2/nanosoc.xdc` | 43-46, 50-51, 141 | 5 pin constraints, 2 pullups |
| `pynq/targets/pynq-z2/nanosoc_timing.xdc` | 24-41, 47 | false paths — this XDC **is** live (`build_nanosoc_design.tcl:111`) |
| `pynq/filelist.tcl` | 177-204 | PL022 block, 20 files — delete |
| `pynq/filelist.tcl` | 253-303 | QSPI + CG092 block, 17 files — delete |
| `pynq/vivado_ip/package_nanosoc_ip.tcl` | 64-65 | IP display name / description |
| `pynq/fpgahub.toml`, `pynq/README.md` | various | prose |

`filelist.tcl:268-272` is a **hard `error`** when `SOCLABS_AHB_QSPI_DIR` is
unset, and `filelist.tcl:298` reads the deleted
`src/rtl/wrappers/qspi_flash_ahb.v`. The flow cannot get past IP packaging.

The firmware side is already safe:
`nanosoc_m0_soc/firmware/bootloader/stage0/stage0_bootloader.c:65` guards every
QSPI path on `#if defined(NANOSOC_QSPI_CTRL_BASE)`, which the generated memmap
no longer emits. `build/firmware/bootloader/stage0/out/bootrom.sv` exists and
builds.

#### (b) The AAA dependency — the bigger problem

`pynq/filelist.tcl` reads Arm IP **straight out of the Academic Access tree**,
bypassing this project's flist chain entirely:

- `pynq/Makefile:41` — `export ARM_IP_LIBRARY_PATH ?= /research/AAA/ip_library`
- `pynq/filelist.tcl:47-52` — 6 include dirs under `latest/Cortex-M0/`, `latest/Corstone-101/`, `PL022/`
- `pynq/filelist.tcl:58-78` — 20 CMSDK files under `latest/Corstone-101/logical/`
- `pynq/filelist.tcl:83-89` — 5 globs under `latest/Cortex-M0/logical/`
- `pynq/filelist.tcl:182-204` — PL022 SSP, 20 files
- `pynq/filelist.tcl:274-288` — Arm CG092 flash cache, 10 files

34 `${ARM_IP_LIBRARY_PATH}` references in one file. The Quickstart tree is laid
out differently — `latest/Cortex-M0-QS/Cortex-M0-logical/` and
`.../Corstone-101-logical/` — so these are not merely the wrong root, they are
the wrong shape.

I tested the rewrite mechanically. Substituting
`latest/Cortex-M0/logical` → `latest/Cortex-M0-QS/Cortex-M0-logical` and
`latest/Corstone-101/logical` → `latest/Cortex-M0-QS/Corstone-101-logical`:

```
mappable and present on disk:  29
missing or unmappable:          0
PL022 / CG092 (no QS equivalent, to be deleted): 3 path roots
```

**PL022 and CG092 do not exist under Quickstart at all** — `find
/research/AAA/ip_library/latest/Cortex-M0-QS -iname '*ssp*' -o -iname '*pl022*'`
and the CG092 equivalent both return nothing. That is fine: both blocks are
being deleted anyway.

#### (c) The AAA-freedom proof does not cover the FPGA flow

Gate A (`docs/PLAN.md:71-83`) proved *97 Arm IP references, all under
`Cortex-M0-QS`, 0 AAA* on a clean clone with `ARM_IP_LIBRARY_PATH` unset, with a
negative control shown able to fail. **But it measures `DESIGN_VC`, never
`DESIGN_VC_FPGA`**: `flows/makefile.simulate:97,194` and `flows/makefile.lint:41`
all read `$(DESIGN_VC)` (= `top.flist`, `arch_tech/makefile:241`).
`pynq/filelist.tcl` is Tcl and outside the flist chain entirely, so no checker
has ever looked at it.

### 1.5 What is broken in flow B

**Structurally: much less than expected, and no SPI at all.**

Flow B's PYNQ-Z2 target contains zero SPI or QSPI references. The 193 hits in
the wider `fpga/` tree are the MPS3 wrapper's board QSPI flash pins
(`targets/arm_mps3/nanosoc_design_wrapper.v:174-178`), an `fpga.mk` comment and
a device-tree `GIC SPI` interrupt — none of them this SoC's SPI.

I compiled flow B's chain and audited it:

```
$ filelist_compile.py -v -a -f flist/project/top_FPGA.flist
entries:                           218
Arm IP refs under Cortex-M0-QS:     91
AAA refs:                            0
referenced files missing on disk:    0
```

Negative control, to prove the audit can fail: the same command on
`arch_tech/rtl/sldma230_tech/flist/arm_pl230_ip.flist` reports **4** AAA
references. The zero above is a measurement, not an absence of measurement.

Block design cross-checked against today's generated chip:

```
generated nanosoc_chip ports:            33
pins the pynq_z2 BD references:          24
BD pins missing from the generated chip:  0
```

(`build_soc/rtl/nanosoc_chip.v` vs
`fpga/fpga/targets/pynq_z2/vivado_script/2021_1/nanosoc_design.tcl:849-866`.)

**Real defects in flow B, none of them SPI-related:**

1. **`fpga_timing.xdc` is dead.** `soctools_flow/resources/fpga/build_design.tcl:58`
   adds **only** `$pinmap_file`, and `flows/makefile.fpga:50` sets that to
   `fpga_pinmap.xdc`. `fpga_timing.xdc` exists in all five target directories and
   is read by nothing. It also constrains ports that do not exist — `XTAL1`,
   `SWCLKTCK`, `P0[]` (`targets/pynq_z2/fpga_timing.xdc:7-10,28+`) — against a
   wrapper whose entire port list is `PMOD0_0..7`
   (`targets/pynq_z2/nanosoc_design_wrapper.v:33-40`). Flow B builds with no user
   timing constraints at all. Independently corroborated by the FPGA toolkit's
   own `README.md:83-87`.
2. **The BD Tcl is mislabelled.** It lives under `vivado_script/2021_1/` but is a
   2024.1 script: `nanosoc_design.tcl:23` reads `##set scripts_vivado_version
   2024.1` with the whole version guard commented out, and it requires
   `xilinx.com:ip:processing_system7:5.5` (`:134`). `build_design.tcl:12` still
   says "Developed & Tested using vivado_version 2021.1". `VIVIADO_VERSION`
   defaults to `2021_1` (`flows/makefile.fpga:16`), which selects the right
   directory by accident.
3. **Untested prerequisites.** `package_nanosoc` depends on `code`
   (`flows/makefile.fpga:87`), which is `firmware_config bootrom testcode
   debugtester` (`flows/makefile.software:37`). Only `bootrom` is proven here
   (Gate A). `package_socket` (`flows/makefile.fpga:75-76`) has never run in this
   project; the five socket IP packages it needs do exist at
   `arch_tech/rtl/socdebug_tech/socket/vivado_packages/`.

### 1.6 Cost to repair in place

Vivado 2024.1 is on `PATH` (`/apps/Xilinx/Vivado/2024.1/bin/vivado`); 2025.2 and
2026.1 are available as modules. Four PYNQ-Z2 boards are live on `fpgahub`
(`pynq_z2_01..04`). Neither flow sets `board_part`, so no Vivado board file is
needed.

| | Edit work | First-build debugging | Total |
|---|---|---|---|
| **Flow A** | 0.5–1 day — the surface is fully enumerated in §1.4 and every path rewrite is verified to resolve | 1–1.5 days | **1.5–2.5 days** |
| **Flow B** | ~0 days of SPI work; the chain already compiles clean | 2–3 days — never run here, three unproven prerequisites, no timing constraints, a 2025-era BD | **2–3 days** |

Flow A's estimate is the more trustworthy: its unknowns are bounded — a
13-minute build loop, a known-good prior result on the same SoC lineage, and a
statically verified port match. Flow B's are not.

---

## Q2 — Can the nanoSoC FPGA Toolkit be adopted here?

Sources: `/home/dam1n19/SoCLabs/nanoSoC-FPGA-Toolkit` (HEAD `c8a8ef4`,
2026-09-17) and **two** real consumers — `nanosoc-ethernet-chiplet/fpga/` and
`NanoSoC-Compute-Chiplet/fpga/`.

### 2.1 The contract and the stage graph

`CONTRACT.md` is 958 lines and normative: *"This file is the interface… If your
code and this file disagree, one of them is a bug — say which, do not silently
pick"* (`CONTRACT.md:3-5`). Two house rules govern everything: assert on
artefacts never on exit status (`:16-19`), and a gate never invents a verdict
from missing data — absent evidence is `UNVERIFIED`, which counts as a failure
(`:21-24`).

```
dirs → flist → package-ip → bd → synth → impl → bitstream      (CONTRACT.md:387)
```

`all` is recipe lines calling `$(MAKE)`, not prerequisites, because
prerequisites carry no ordering under `-j` (`:401-404`). `check-quiet` is a
prerequisite of every stage (`:406`).

**Mandatory, hard `$(error)` at parse time** (`CONTRACT.md:110-116`, enforced
`mk/flow.mk:66,72,77`): `FPGA_FLOW_DIR`, `BLOCK`, `BOARD`.

**Mandatory, reported by `make check`** (`CONTRACT.md:118-126`): `TOP` (*"the
board-level top module. Not the SoC top — getting this wrong is quiet"*),
`RTL_FLIST`, `XDC_PINS`, `PART`.

**A configured-but-missing optional input is an error, not a shrug**
(`CONTRACT.md:131`).

`package-ip` and `bd` are the two skippable stages (loud SKIP at
`mk/flow.mk:1180-1184` and `:1224-1228`). `FLOW_MODE` has exactly one legal
value, `direct`; `project`, `protocompiler` and `dfx` are refused by name
because *"three of those four names selected nothing"* (`CONTRACT.md:158-186`).

**Seams** are the eleven hook points in `flow/common/seams.txt` — `pre_`/`post_`
for flist, package_ip, bd, synth, impl, plus `post_bitstream`. There is
deliberately no `pre_bitstream`. That file is the only copy; a hook whose name
is not on it never runs, and `make check` warns and names it.

### 2.2 The part / board split

Confirmed as described (`CONTRACT.md:49-55`, `646-705`): a **part pack** is a
silicon fact and ships in the toolkit at `part/<part>/part.tcl`; a **board
pack** is a PCB fact and ships in the project at `fpga/board/<board>/board.tcl`.
`part/README.md:47-58` — *"A pin, an IO standard or a board name under `part/`
is a bug."*

**A PYNQ-Z2 part pack already exists.** `part/xc7z020clg400-1/part.tcl`, 317
lines, 51 `part_set` keys, added 2026-09-08 in `fcb1cd6`. Every value was read
from a real Vivado 2024.1 install (`:58-64` `facts_source`): die census (53 200
LUTs, 106 400 FFs, 140 BRAM36, 220 DSP, 0 URAM, 6 clock regions, 125 user
IOBs), IO banks `{0 13 34 35 500 501 502}` with the three PL banks typed
`BT_HIGH_RANGE`, clocking (`BUFGCTRL`×32, `MMCME2_ADV`×4, `PLLE2_ADV`×4),
`IDELAYE2` with three disjoint legal reference bands, `idcode 0x03727093`,
`min_vivado_version 2024.1`, `has_ps true` / `ps_type PS7`, and a
retarget/reject table (note `BUFGCE → BUFGCTRL`, which **loses the clock
enable** on this part). Exercised by `test/shell/t_packs.sh:187,698,719,785`.

Two deferred keys — `ps_clk_config` and `idelay_ref_freq_hz` — do **not** block
a build: `part/pack_api.tcl:392,827` exclude deferred keys from the validator,
and no stage script reads any PS key (grep of `flow/ mk/ scripts/ ci/` for
`ps_clk_config|has_ps|ps_type` returns zero). The only pack value any stage
reads is `board bin_style` at `flow/vivado/6_bitstream.tcl:230-240`.

**Has the xc7z020 pack ever driven a build? Pack yes, flow not reproducibly.**
Real stage behaviour *was* measured on this part at least twice —
`flow/steps/synth_setup.tcl:197-203` (a two-way gated-clock-conversion
experiment), `flow/common/provenance.tcl:1361`, `CONTRACT.md:266`,
`test/shell/t_measure.sh:8,146` (*"COPIED FROM A REAL RUN — Vivado 2024.1,
xc7z020"*) — and commit `7999abc` (2026-09-08) is "The full stage graph runs:
RTL to bitstream under real Vivado" on a small fixture. But **no xc7z020 run
artefact survives anywhere on this machine**, the fixture project was deleted
(`9e9cc2f`), and `test/KNOWN_DEFECTS` states flatly that only
`xck26-sfvc784-2LV-c` "has ever built anything". Treat it as **pack proven,
flow unproven on it**.

**No PYNQ-Z2 board pack exists anywhere.** A tree-wide search finds exactly two
`board.tcl` files, both KR260 —
`nanosoc-ethernet-chiplet/fpga/board/kr260-eth-chiplet/board.tcl` and
`NanoSoC-Compute-Chiplet/fpga/board/kr260-compute-chiplet/board.tcl`. A PYNQ-Z2
board pack is roughly 90 filled-in lines from `templates/board.tcl.in`, and this
project would be writing it.

Also worth knowing: the toolkit's `README.md:39` says "three packs" — **four
ship**; commit `4f07758` is titled *"t_packs named its three packs, so the
fourth shipped unasserted"*.

### 2.3 What an adoption must supply, file by file

`scripts/fpga-flow-init --block <top> --board <board> [--part <part>]` installs
11 templates and creates `fpga/overrides/` empty. It leaves **21 `<<FILL IN>>`
markers** across six files, and a fresh scaffold is *designed* to fail `make
check` until they are filled (`scripts/fpga-flow-init:411-413`). Both shipped
hooks (`pre_synth.tcl` 707 L, `post_impl.tcl` 575 L) **refuse with exit 2** until
their declaration table is configured; deleting the file is an explicitly
legitimate answer (`CONTRACT.md:526-538`).

**Not scaffolded and authored by hand:** the BD Tcl, the board pack's real
values, and the flist.

The worked example — the ethernet chiplet, 5 024 lines of project-side material
excluding build output:

| File | Lines | Origin |
|---|---|---|
| `fpga/Makefile` | 47 | scaffolded; 3 functional lines |
| `fpga/design.mk` | **1221** | **authored** — the manifest |
| `fpga/generate.mk` | 224 | authored — project-specific derivations |
| `fpga/board/<board>/board.tcl` | 246 | **authored** — the board pack |
| `fpga/targets/<t>/bd_create.tcl` | 122 | **authored** — the `BD_TCL` driver |
| `fpga/targets/<t>/board_glue.flist` | 43 | authored — the `RTL_FLIST` |
| `fpga/hooks/pre_synth.tcl` | 718 | scaffolded 707, configured |
| `fpga/hooks/post_bd.tcl`, `pre_impl.tcl` | 52, 91 | authored |
| `fpga/overrides/` | empty | correctly so |

The compute chiplet is the same shape (`design.mk` 1028 L, `board.tcl` 245 L,
`pre_synth.tcl` 737 L). **Budget roughly 1000–1250 lines of project-side
declaration**, most of it `design.mk`.

**Crucially, both consumers point at existing target collateral rather than
copying it.** The eth chiplet's `TARGET_DIR`, `XDC_PINS`, `XDC_TIMING`,
`XDC_DRC`, `BD_TCL`, `TOP_HDL`, `EXTRA_SRCS` and `FPGAHUB_TOML` all resolve into
the legacy `tidelink/fpga/targets/kr260-eth-chiplet/` tree
(`fpga/design.mk:99,163,220,598,610`; rationale at `fpga/README.md:63-80` —
*"a copy is a snapshot that drifts silently; a pointer cannot"*), and the three
scaffolded XDCs plus `post_impl.tcl` were deleted. **This is why repairing flow
A is not wasted work** — its collateral becomes the toolkit's `TARGET_DIR`.

### 2.4 Does it support a design with no SPI and no QSPI?

**Yes, without modification.** An exhaustive grep of the toolkit outside its
tests for `qspi|spi|flash|mcs|bpi|write_cfgmem|bootgen|boot.bin` returns **7
hits, all benign**:

- `part/pack_schema.tcl:376,484` and `templates/board.tcl.in:153` —
  `deploy_style` is an optional enum `{jtag qspi sd tftp}`, a declaration of how
  a board is *loaded*
- `flow/steps/bitstream_opts.tcl:183-192` — `BITSTREAM_CONFIGRATE` and
  `BITSTREAM_SPI_BUSWIDTH`, **both defaulting to empty**
- `ci/check-vendor-collateral.sh:479` — `.mcs` in a *forbidden artefact* glob

There is no `write_cfgmem`, no `bootgen`, no `BOOT.BIN` and no flash-programming
step anywhere, and the flow never names an SoC port. The only port-shaped
requirement is that `TOP` is the board-level top and `XDC_PINS` constrains it —
both project-supplied.

The one family-dependent piece is `.bin` conversion, a pure byte transform
selected by `BIN_STYLE` (`6_bitstream.tcl:297-375`): `zynq7` = 32-bit word
byte-swap, `zynqmp` = header strip. **The `zynq7` path has been exercised** —
commit `7999abc`: *"Payload 3002 0001 became 0100 0230, first difference at byte
33, sizes identical."* A PYNQ-Z2 project sets `bin_style zynq7` and is done.

### 2.5 The block-design question — the one that decides this

**`flow/vivado/3_bd.tcl` is entirely vendor-IP-agnostic. It is a driver, not a
BD author.** Grepping `flow/` for `ps7|processing_system7|clk_wiz|proc_sys_reset`
yields exactly one hit, and it is a comment (`3_bd.tcl:596`).

The consumer supplies its own BD Tcl: `3_bd.tcl:151` fires `pre_bd`, `:153-157`
asserts `BD_TCL` exists, then `source`s it inside the stage's project.
`BD_OVERLAY_TCL` is an ordered list applied over it (`:160-170`). Around it the
stage does exactly the things the PYNQ-Z2 pattern needs: `create_project
-in_memory -part` **before** the IP catalogue (commit `26685d9`; asserted by
`test/shell/t_bd.sh:181-205`), `board_part_repo_paths` + `board_part` with a
refusal naming the paths tried (`:240-258`), reads `work/sources.tcl` so module
references resolve (`:172-181`), and calls `generate_target` asserting on the
generated `synth/<bd>.v` on the filesystem rather than on the call (`:613-650`).

**Flow A's block design is already in the shape the toolkit wants.**
`pynq/targets/pynq-z2/nanosoc_design.tcl` is a library defining
`create_root_design`, and `pynq/build_nanosoc_design.tcl:66-70` does
`source` → `create_bd_design` → `create_root_design ""`. The eth chiplet's
`targets/kr260-eth-chiplet/bd_create.tcl:66-118` is the same two calls wrapped
in assertions, with the note that the stage already created the project, set the
part, set the board part and added the IP repos. **The adaptation is a ~120-line
`bd_create.tcl`, not a rewrite.**

**But nothing PS7-shaped has ever been run through this toolkit.** The only BD
it has built is the `zynq_ultra`-based KR260 design, and `test/shell/t_bd.sh:38-42`
admits its own limit: *"It runs with no EDA tool, so it cannot build a block
design; every proof about a Vivado stage script here is STRUCTURAL"* — 3 mutation
proofs.

### 2.6 Its actual proven state

**The toolkit's own README understates it.** `README.md` was last touched at
`a7b04ee` (2026-09-11) and still says *"A bitstream for the KR260 eth chiplet —
**NO — parity fails at stage 3**"* and *"a block-design-based project cannot be
built here"*. That was superseded on **2026-09-08 at 21:21** by commit `26685d9`,
*"The BD path: netlist parity with the shipping KR260 design"*. The consumer's
`PARITY_REPORT.md` (842 lines, 2026-09-08) is likewise a snapshot of the
now-fixed failure. **Do not quote either as current.**

What is actually on disk:

**Proof 1 — eth chiplet, run tag `landed`, 2026-09-14.** The whole nanoSoC
multicore SoC + ethernet MAC + TideLink + TideChart, on a KR260:

```
fpga/build/landed/outputs/
  nanosoc_eth_chiplet.bit          6 692 289 B
  nanosoc_eth_chiplet.bin          6 692 148 B
  nanosoc_eth_chiplet.xsa          3 650 529 B
  nanosoc_eth_chiplet_routed.dcp  48 919 696 B
  tidelink_design.hwh, tidelink_design_axi_smc_0.hwh
reports/bitstream_manifest.txt:  tool_version 2024.1, part xck26-sfvc784-2LV-c,
                                 toolkit_git_sha dea38e3, project_git_sha 8043d53 (DIRTY)
reports/route_status.rpt:        106 112 routable nets, 106 112 fully routed, 0 with errors
reports/timing_summary.rpt:      WNS +0.276, WHS +0.010, 0 failing endpoints of 116 648
reports/impl_gate.txt:12:        HARD FAILURES: none
```

The gate is honest about what it did *not* measure: 37 866 unconstrained
internal endpoints, 30 warning-level post-route DRCs, no power, no SI, no
functional check, and `make xdc-lint` not yet implemented.

**Proof 2 — compute chiplet, run tag `cwallow`, 2026-09-17** (one day old). A
Cortex-M0+ manager plus a Cortex-M4F with two TideLink links:
`build/cwallow/outputs/nanosoc_compute_chiplet.{bit 6 639 617 B, bin, xsa,
routed.dcp}`, manifest `tool_version 2024.1`, `part xck26-sfvc784-2LV-c`,
`toolkit_git_sha ddd1522`.

**Proof 3 — bitstream-level agreement with the legacy flow.** In
`fpga/build/_bitdiff/`, comparing the artefacts the parity investigation left
behind:

```
NEW_DEFAULT.bit vs tidelink/imp/fpga/output/kr260-eth-chiplet/tidelink.bit
    differing bytes: 8    last differing offset: 121
OLD.bit         vs NEW.bit
    differing bytes: 4    last differing offset: 136
```

Every differing byte is inside the `.bit` header's build date and time
(`2026/09/09 15:51:22` against `2026/08/21 09:54:38`); the configuration payload
is identical. Both runs record `cells 131005`, `nets 352170`, `vivado 2024.1`
(`_bitdiff/{OLD,NEW}_asfound_env.txt`). *Inference:* `NEW` is the toolkit's
routed design and `OLD` the legacy flow's — consistent with `26685d9`'s cell and
net counts, but the filenames are the only direct evidence of which produced
which.

**Both proofs are real nanoSoCs, not fixtures.** The only synthetic thing the
toolkit has built is a small six-port fixture design that is not in the
repository and left no surviving artefact.

**What is still unproven, and it matters here:**

1. **Everything proven is one part (`xck26`), one board family (KR260), one tool
   version (2024.1), one flow mode (`direct`), and BD-based.** No Zynq-7000 block
   design has ever been built. `bin_style` accepts `zynq7`, and the `.bin`
   transform is proven, but `CONTRACT.md:698-701` warns the two styles are *not*
   interchangeable and the wrong one corrupts the load.
2. **`test/run.sh` launches no EDA tool.** It is shell plus bare-`tclsh`
   recording stubs; `t_doctor.sh:265-309` builds *stub* `vivado` binaries on
   `PATH`. Green there is a claim about the contract layer only.
3. **Five of six stage scripts have no unit test.** Stage 1 was closed on
   2026-09-17 with 28 planted faults; `2_package_ip`, `3_bd`, `4_synth`,
   `5_impl`, `6_bitstream` remain. `test/KNOWN_DEFECTS` states the boundary
   plainly: recording stubs prove a call was issued, never that Vivado would
   accept it — *"That half still rests on one integration result."*
4. **`mk/flow.mk` is 1771 lines and only its parse-time guards are tested** (13
   planted faults). Nothing covers the stage graph, the ~70-variable surface or
   any recipe.
5. **The deploy tier has never touched a board** — settled, not merely claimed:
   `fpga/build/deploy-proof-held/reports/deploy_gate.txt:15-16` — *"no program
   request was sent — preflight refused — no lease was taken and no board was
   touched."*
6. **"The part/board split is a one-implementation contract"**
   (`test/KNOWN_DEFECTS`). Both consumers are on the same part, so it is still
   one implementation in the sense that matters. What would settle it, in its own
   words: *"a second board on a different part, built end to end by somebody who
   did not write the pack API."* **A PYNQ-Z2 adoption is exactly that test.**
7. **Live defects in the ledger**, e.g. the `FPGA_POST_TARGET_VARS` census is
   read by nothing, so a misspelt `BITSTREM_POST_TARGETS` gets "Contract
   complete." and the deploy hook silently never runs; and a `post_bitstream`
   hook can replace the `.bit` unrecorded.

### 2.7 The vendor guard will not protect this project as shipped

This is the finding that matters most for a QuickStart-only SoC.
`VENDOR_COLLATERAL.md` and `ci/check-vendor-collateral.sh` (1364 lines) are a
genuinely good guard — built around the failure that *"somebody wrote a check
that could not fail"*, and every rule is armed with an invented specimen it must
match and a near-miss it must not (`:47-60`).

**But its path rules are Xilinx-specific** — `/(apps|opt|tools|eda|usr/local)/xilinx`
(`:412-416`) and `/(apps|opt|tools|eda)/(vivado|vitis|petalinux)` (`:418-421`).
**`/research`, `AAA` and `ip_library` are matched by nothing.** Adopting the
toolkit does **not** by itself give this project AAA protection. What would: one
row added to the rule table (`vc_text_rule path fold '<regex>' …`), which the
arming block then forces you to supply a specimen and counter-specimen for.

Four live defects in that guard, all carried as `t_known_defect`
(`test/KNOWN_DEFECTS:176-202`, commit `888a60e` *"the vendor guard lets a skipped
scan exit 0"*):

1. `:659` discards both stderr and the exit status of the `awk` scan; gawk is
   fatal on an unreadable operand, so one mode-000 file aborts a 400-file batch
   while the census still reports them "read for content".
2. `:1133` feeds `wc -c` into a **positional** loop; a file `wc` cannot open
   shifts every size by one, so `file.size` names the wrong file.
3. **The pre-commit hook silently drops every content finding**: `vc_addedlines`
   (`:934-936`) omits `--cached`, so the added-line map describes HEAD-vs-worktree
   while the scan reads the index. `--staged --fast` finds the violation and exits
   1; add `--new-lines-only` — which the hook does — and the same repo exits 0 in
   silence.
4. `:547` treats any name containing a dot as having an extension, so **a tracked
   dotfile is never opened** — *"exactly where a licence-server export lands."*

And structurally, `core.hooksPath` is local config: **the hooks do not run at all
in a fresh clone** until someone runs `make hooks-install`.

### 2.8 Other friction a new adopter will hit

From the first consumer's own list (`nanosoc-ethernet-chiplet/fpga/README.md:200-292`,
eleven defects raised against the toolkit) and the toolkit's makefiles:

1. **`make check` fails when `PART` is empty**, although both `design.mk.in` and
   `mk/flow.mk` say the board pack should be the single source of the device. So
   `PART` ends up stated twice, with nothing comparing the two.
2. **`make check` cannot see an unreadable `-f` include** and reports a green
   count anyway — the toolkit's own rule-2 failure mode.
3. **`cfgbvs` / `config_voltage`** are documented as board keys
   (`CONTRACT.md:684-690`) but still declared at part scope
   (`part/pack_api.tcl:388,392`), so *nothing* can legally state them.
4. **`FPGAHUB_TOML`'s scaffolded default asserts where the contract says it must
   discover**, so a fresh scaffold cannot pass `make check` until it creates an
   empty file it never asked for.
5. **Git hooks are not flow hooks and nothing installs them** (`mk/hooks.mk:30-35`
   — *"WHAT IT DOES NOT DO: INSTALL ITSELF"*). Per clone, per machine.
6. **`XDC_OPTIONAL` conditions must be `export`ed**, and are compared against the
   literal `1`; `true`/`yes` mean *not read* (`CONTRACT.md:239-249`). This cost a
   synthesis run.
7. **Project makefile fragments must be included *after* `mk/flow.mk`** — a
   rule's target is expanded at parse time; a rule declared in `design.mk`
   expanded to the filesystem root and failed silently
   (`nanosoc-ethernet-chiplet/fpga/generate.mk:4-13`).
8. **`RTL_DEFINES` do not survive IP packaging** — `ipx::package_project` drops
   fileset defines by three separate routes, and it has already silently disabled
   a feature (`CONTRACT.md:741-744`). Use `RTL_PARAMS` or `RTL_DEFINES_INBODY`.
9. **`.gitmodules` pins only a SHA.** The eth chiplet sets no `branch =` for
   `fpga/fpga-toolkit`, its pin `6d87c88` is one commit behind toolkit `main`,
   and the shipping `landed` bitstream records `toolkit_git_sha dea38e3` — an
   *older* revision than the one now pinned, never re-run.
10. **The toolkit defaults to a sibling checkout**
    (`FPGA_FLOW_DIR ?= $(FPGA_DIR)/../../nanoSoC-FPGA-Toolkit`). Both real
    consumers vendored it as a submodule instead.
11. **Preflight is good and free**: `make check` (`scripts/fpga-flow-check`, 1760
    lines of stdlib Python, under a second, no tool) and `make doctor`
    (`fpga-flow-doctor`, 900 lines, reports what is *on the filesystem*, never
    what a modulefile claims).

---

## Q3 — Recommendation

**Both, in sequence. Repair flow A now; adopt the toolkit next, pointing it at
the collateral the repair produces. Do not invest in flow B beyond leaving it
alone.**

### Rank 1 — Repair flow A to a bitstream. 1.5–2.5 days.

Do this first because it is the only path whose unknowns are bounded: the same
SoC lineage has produced a working PYNQ-Z2 bitstream through this exact flow
(§1.2), the port drift is exactly four names (§1.4a), all 29 IP-path rewrites
are verified to resolve under Quickstart (§1.4b), and the build loop is 13
minutes.

**It is not throwaway.** The repaired `nanosoc_design.tcl`,
`nanosoc_design_wrapper.v`, `nanosoc.xdc` and `nanosoc_timing.xdc` become the
toolkit's `TARGET_DIR`, exactly as both existing consumers point at legacy
target directories (§2.3) — and flow A's BD script is already in the
`create_bd_design` + `create_root_design` shape the toolkit's `BD_TCL` expects
(§2.5).

**Top three risks**

1. **The AAA rewrite is covered by no gate.** `pynq/filelist.tcl` is Tcl, outside
   the flist chain Gate A measures (§1.4c). One missed `${ARM_IP_LIBRARY_PATH}`
   would build green and silently reintroduce the dependency this project exists
   to remove. *Mitigation: extend the Gate A audit over the generated Vivado
   source list, and prove that check can fail before trusting it.*
2. **Statically verified ports are not an elaboration.** I compared port names,
   not widths, directions or parameter semantics, and ran no tool.
3. **Duplication debt.** Repairing flow A entrenches a fourth copy of a pattern
   copy-pasted ~20 times in this tree (toolkit `README.md:62-72`:
   `build_design.tcl` has 179 copies with 8 distinct contents). Time-box it; do
   not extend it.

### Rank 2 — Adopt the toolkit. 4–8 days on top of Rank 1.

It is proven where it matters most — two real nanoSoCs to timing-clean routed
bitstreams under Vivado 2024.1, gates green, one of them payload-identical to
the shipping design (§2.6) — and it is the only option with a contract, a
verdict layer and provenance. The PYNQ-Z2 part pack already exists, the BD stage
is generic, and there is no SPI/QSPI coupling anywhere.

Work: a board pack (~90 filled-in lines), `design.mk` (~1000–1250 lines), a
~120-line `bd_create.tcl` wrapping flow A's BD, `pre_synth.tcl` from the
707-line template, and `bin_style zynq7`.

**Top three risks**

1. **First non-`xck26` part and first PS7 block design.** Everything proven is
   one part, one board family, one tool version. You would be the second
   implementation `test/KNOWN_DEFECTS` is explicitly asking for. Budget 1–2 days
   for this alone; the `.bin` byte-swap half is already proven, the BD half is
   not.
2. **The vendor guard does not know `/research/AAA/ip_library` by name** (§2.7),
   and three of its four live defects let a scan exit 0. Adopting the toolkit
   buys the *mechanism*, not the protection. *Mitigation: add the path rule with
   its specimen and counter-specimen as part of the adoption, and run
   `make hooks-install` in the clone.*
3. **Scope creep into an unfinished half.** Five of six stage scripts are
   untested, `mk/flow.mk` is 1771 largely untested lines, and no board has ever
   been deployed to. *Mitigation: adopt for `flist`→`bitstream` only; leave every
   `EXPECT_*` at `-1` (measure, do not gate) until a first green run, exactly as
   both existing consumers did.*

### Rank 3 — Repair flow B. Not recommended as the first move.

It is the flow this project's `Makefile` already reaches and its flist chain is
provably Quickstart-clean and complete — 218 entries, 91 QS refs, 0 AAA, 0
missing files (§1.5) — which is genuinely attractive, and it needs no SPI work at
all. But it has never been run here, three of its prerequisites are unproven, its
builds carry no user timing constraints, and its target collateral is a 2025-era
BD. Its cost (2–3 days) is no lower than flow A's and its unknowns are unbounded.
Leave it in place as the fallback if flow A's repair surprises.

**Do not** port `fpga_timing.xdc` into anything. It is read by nothing and
constrains ports that do not exist (§1.5).

### What I could not determine

- **Whether either flow actually runs.** No EDA tool was launched. Every verdict
  above is static: port-name comparison, flist compilation, file existence, and
  artefacts left on disk by earlier runs.
- **Whether the toolkit's `bd` stage handles a PS7 design in practice.** I
  established that `3_bd.tcl` contains no architecture-specific code and that the
  consumer supplies the BD; I could not establish that a Zynq-7000 BD survives it,
  because none has ever been run.
- **Which flow produced `_bitdiff/NEW*.bit`.** The filenames and the matching
  cell/net counts make "toolkit" the obvious reading, but that is an inference.
  Proof 1 (`landed`) does not depend on it.
- **Whether the compute-chiplet bitstream came from an unmodified toolkit.** Its
  manifest records `toolkit_git_sha ddd1522`; I did not verify the working tree
  was clean at build time.
- **Whether flow B brings up a usable console.** Its board wrapper exposes only
  `PMOD0_0..7` and host access is via the debug socket over the PS AXI master,
  not a UART. `docs/PLAN.md:196-204` records that UART and HOSTIO4 are mutually
  exclusive in this SoC and there is no second UART.
- **Whether the flow-A repair leaves anything else broken.** Only port *names*
  were diffed; parameter semantics after the QSPI removal were not re-derived.

---

*Copyright (C) 2026, SoC Labs (www.soclabs.org)*
