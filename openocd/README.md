# OpenOCD for the nanoSoC-M0 QuickStart SoC

> **Which OpenOCD these configs are for — and the gap in that claim.**
> They are **written for v0.12.0 (`9ea7f3d`)**, the revision the HAPS bench pins
> (haps-dev runs `0.12.0` from `/usr/local/bin/openocd`).
> They have **never been parsed by a v0.12.0 binary.** Every config here was
> parsed against `0.12.0+dev-g43441cd`, because that is the only OpenOCD built on
> this workstation. Line numbers quoted in comments are from that dev tree unless
> a v0.12.0 line is given beside them.
>
> So these configs are validated against something *adjacent* to what ships. If a
> stanza fails to parse on the pinned build, that is this gap, not your setup —
> please report it. Re-parsing against the shared v0.12.0 build, once one exists
> at a path reachable from wherever OpenOCD actually runs, is a tracked step of
> the driver-integration recipe.

Start here:

```bash
# PYNQ-Z2 — look, change nothing
openocd -f openocd/cfg/pynq-z2.cfg
# then, in another shell:  telnet localhost 4444   ->   qs_ident

# KR260 — same, but read "KR260" below first: this repo has no SWD pinout for it
openocd -f openocd/cfg/kr260.cfg

# HAPS-SX — the bench tool owns the probe; you supply the target half
haps-openocd save nanosoc-m0-qs-mem --from openocd/cfg/haps-sx-mem.cfg
haps-openocd up   nanosoc-m0-qs-mem
```

Everything below is either measured or cited to a file and line. Nothing is
assumed from a datasheet.

---

## What is on the wire

This SoC has a single Cortex-M0 using **its own integrated `CORTEXM0DAP`**.
There is no CoreSight SoC-400 SWJ-DP and there is no second access port.

```
SWD --> CORTEXM0DAP (the core's own DAP)
         `-- AP 0: AHB-AP -> the core's SLV debug port
                             (system memory AND the core's PPB)
```

| value | is | read from |
|---|---|---|
| SW-DP DPIDR | `0x0BB11477` | `$ARM_QS_IP_DIR/Cortex-M0-logical/cortexm0_dap/verilog/cm0_dap_dp_sw_defs.v:24` |
| JTAG-DP DPIDR | `0x0BB11477` | `.../cm0_dap_dp_jtag_defs.v:24` |
| JTAG IDCODE | `0x0BA01477` | `.../cm0_dap_dp_jtag_defs.v:23` |
| AP 0 IDR | `0x04770021` | `.../cm0_dap_ap_mast_defs.v:28` |
| AP 0 CFG | `0x00000000` | `.../cm0_dap_ap_mast_defs.v:24` |
| AP 0 CSW readback | `0x03000042` | `.../cm0_dap_ap_mast.v:303-312` |
| CPUID | `0x410CC200` | `.../cortexm0/verilog/cm0_matrix_sel.v:342` |
| core ROM table SCS entry | `0xFFF0F003` | `.../cortexm0/verilog/cm0_dbg_sel.v:500` |
| core ROM table CID1 | `0x00000010` | `.../cm0_dbg_sel.v:512` |

The DP is a SW-DP **or** a JTAG-DP, fixed at build time by `CORTEXM0DAP`'s
`JTAGnSW`, driven from `slcorem0`'s `INCLUDE_JTAG` (`slcorem0.v:266`). It is not
an SWJ-DP — there is no runtime JTAG-to-SWD switch. `INCLUDE_JTAG` defaults to
`0` everywhere in this repo, so these configs are SWD-only. A build with
`INCLUDE_JTAG=1` needs a `jtag newtap` config and none of these will reach it.

### AP 0 BASE is not what you may have been told

`BASEADDR` is an input to `CORTEXM0DAP`, tied externally, fed from `slcorem0`'s
`ROMTABLE_BASE` as `{ROMTABLE_BASE[31:2], 2'd3}` (`slcorem0.v:184,294`).

- `nanosoc_ss_cpu`'s **module default** is `0xE00FF003`, the core's own ROM
  table (`nanosoc_m0_soc/build_soc/rtl/nanosoc_ss_cpu.sv:33`).
- **The SoC top overrides it.** `nanosoc.sv:759` passes `SYSTABLE_BASE`, which is
  `0xF0000000` (`nanosoc.sv:54`). So the SoC as generated in this repo reads
  **`AP 0 BASE = 0xF0000003`** — the system ROM table, which really exists:
  `build_soc/reports/nanosoc_memory_map.txt` lists `systable u_region_systable
  0xF0000000`. That also matches the CMSDK header's `MCU_AP_BASE_VALUE
  0xF0000003` (`nanosoc_arch_tech/firmware/testcodes/generic/config_id.h:36`).

Both values are correct for *some* build, so `qs_ident` prints what it read and
names which build that implies. It does not pass or fail on it. A **third**
value is a fail.

### What AP 0 can and cannot do

`cm0_dap_ap_mast.v`, lines given:

- CSW is almost entirely read-only. Only `Size[1:0]` (CSW[1:0]) and `AddrInc`
  (CSW[4]) are writable (`:285,291`). Prot is hardwired `2'b11`, CSW[5] is tied
  0 so **packed transfers do not exist**, CSW[2] is tied 0 so the only sizes are
  byte / halfword / word (`:303-312`).
- A CSW readback is therefore `0x03000042` (word, no increment, DeviceEn high)
  or `0x03000002` (the same with **DeviceEn low** — debug is not powered and
  every memory access will fail). The leading `0x03` is itself the
  discriminator: a SoC-400 AHB-AP has a writable HPROT and reads `0x23......`.
- **TAR auto-increment wraps at 1 KB** — only `tar[9:0]` increments
  (`:323-324`). A burst that crosses a 1 KB boundary silently re-reads the same
  kilobyte.
- AP register byte offsets: CSW `0x00`, TAR `0x04`, DRW `0x0C`, CFG `0xF4`,
  BASE `0xF8`, IDR `0xFC` (`cm0_dap_ap_mast_defs.v:41-49`).

---

## Files

| file | what it is |
|---|---|
| `cfg/nanosoc_m0_qs.cfg` | **the canonical target half.** DAP, targets, helper procs. No adapter, no transport, no ports. |
| `cfg/pynq-z2.cfg` | PYNQ-Z2 probe half; sources the above out of its own directory |
| `cfg/kr260.cfg` | KR260 probe half; same |
| `cfg/haps-sx-mem.cfg` | HAPS-SX `haps-openocd` target half — `mem_ap` |
| `cfg/haps-sx-core.cfg` | HAPS-SX `haps-openocd` target half — `cortex_m` |

The two `haps-sx-*.cfg` files are **deliberate self-contained copies** of the
relevant half of `nanosoc_m0_qs.cfg`. `haps-openocd save` ships a single file to
`haps-dev`, so they cannot `source` a sibling. `nanosoc_m0_qs.cfg` is canonical;
change both when either changes. Both carry that warning in their own header.

---

## Picking a target type

`QS_TARGET` selects it. Set it before the config is sourced:

```bash
openocd -c "set QS_TARGET core" -f openocd/cfg/pynq-z2.cfg
```

On HAPS-SX the choice is the filename instead (`haps-sx-mem.cfg` /
`haps-sx-core.cfg`), because `haps-openocd` sources one file and takes no
variables.

### `mem` (default) — `nanosoc.mem`, a `mem_ap`. Non-disturbing.

Nothing is written to the core. No `cortex_m` examine runs. Because AP 0 is the
core's own SLV debug port, it reaches **both** system memory and the PPB, so
`mdw 0xE000ED00` (CPUID) and `mdw 0xE000EDF0` (DHCSR) both answer **against a
freely running core**, with no write anywhere.

Use it for: is the design alive, is it the design I think it is, what is in
memory. No registers, no breakpoints, no stepping — a `mem_ap` has no register
model of the real core.

### `core` — `nanosoc.cpu0`, a `cortex_m`. Intrusive.

OpenOCD's `cortex_m` examine **writes** `DHCSR.C_DEBUGEN` and `DEMCR.TRCENA` at
`init` (`cortex_m.c` ~3003-3015 as of `0.12.0+dev-g43441cd`; line numbers move
between builds, the behaviour does not). The core keeps running, but a `BKPT` in
its code now halts it instead of faulting, and a gdb attach halts it — OpenOCD's
default `gdb-attach` event is `halt 1000`. Uncomment the
`configure -event gdb-attach {}` line to attach without halting.

Use it for: registers, breakpoints, stepping, gdb, flashing.

Note this config does **not** use `-defer-examine`, unlike the multicore bench's
`cfg/nanosoc.cfg`. That file defers because its cores sit behind a system DAP
with `AHBSLV=0`, where a debug read of a running core's PPB returns the
instruction-fetch stream. This SoC has no such stage, so auto-examine works.

### `both` — both targets, `cortex_m` deferred.

`init` writes nothing. Current target is left on `nanosoc.mem`. Promote the core
when you want it: `nanosoc.cpu0 arp_examine`. Until then a gdb attach to it is
refused with "Target not examined yet". The `cortex_m` is created first so it
takes the base gdb port.

---

## gdb and a `mem_ap` target — read this, do not assume it

**The widely repeated claim is that OpenOCD serves no gdb port for a `mem_ap`,
so you get telnet and tcl only. It is FALSE — checked on BOTH revisions in play
on this bench, so it is not a version difference.**

What the code actually says:

- `target_supports_gdb_connection()` is `!!type->get_gdb_reg_list &&
  !!target->gdb_max_connections` (`src/target/target.c:1426-1433`).
- `struct target_type mem_ap_target` **does** set
  `.get_gdb_reg_list = mem_ap_get_gdb_reg_list` (`src/target/mem_ap.c:284`).
- `gdb_max_connections` defaults to `1` (`src/target/target.c:5903`).
- So a `mem_ap` **does** get a gdb server. The comment immediately above the
  check — `/* skip targets that cannot handle a gdb connections (e.g. mem_ap) */`
  (`src/server/gdb_server.c:3980`) — is stale and no longer describes the code
  below it. That stale comment is the likeliest origin of the claim.
- OpenOCD's own manual agrees: "It's possible to connect a GDB client to this
  target … and a fake ARM core will be emulated to comply to GDB remote
  protocol" (`doc/openocd.texi:5195-5201`).

Read on both revisions, in the same source tree at `/tmpdir/openocd-build/openocd`:

| revision | `.get_gdb_reg_list` set? | |
|---|---|---|
| `0.12.0+dev-g43441cd` (2026-07-28) | yes, `mem_ap.c:284` | the only build available on this workstation |
| **`v0.12.0` (`9ea7f3d`)** | **yes, `mem_ap.c:285`** | **the revision the bench pins** |

`target_supports_gdb_connection()` has the same two-term form on both
(`target.c:1426` on dev, `target.c:1470` on v0.12.0). `mem_ap.c` differs between
them by 25 insertions and 26 deletions, none of which touch this.

**So: a gdb port DOES appear, on the pinned revision as well as on master.**
Check 6 below is still the command that settles it on any other build. When it appears,
treat it with suspicion: the registers gdb shows you are a *fake emulated ARM
core*, not this SoC's Cortex-M0. For real registers use `QS_TARGET=core`.

On HAPS-SX this also changes what you should expect from `haps-openocd`: the
bench README states that the gdb forwards carry nothing for `dap-only.cfg`. If
your bench OpenOCD is a build where `mem_ap` gets a server, that forward does
carry something — a fake core. Check 6 is how you find out which you have.

---

## Per board

### PYNQ-Z2

Wiring, from `nanosoc_m0_soc/pynq/targets/pynq-z2/nanosoc.xdc:19-20,99-114` —
the 2x3 SPI header:

| header pin | FPGA pin | signal | pull |
|---|---|---|---|
| 1 (MISO) | W15 | `swd_dio` -> SWDIO | PULLUP |
| 2 | — | 3V3 -> VTref | |
| 3 (SCK) | H15 | `swd_clk` -> SWCLK | PULLDOWN |
| 6 | — | GND | |

No reset wire exists on that header, so `nSRST` does not exist and the only
target reset is `SYSRESETREQ` through the DAP.

**The repo disagrees with itself about the probe.** `nanosoc.xdc:19` documents a
SEGGER J-Link; the older `nanosoc_m0_soc/pynq/scripts/openocd/nanosoc.cfg:25`
defaults to `interface/stlink.cfg`. `cfg/pynq-z2.cfg` keeps the older default so
nothing changes silently. Override per run:

```bash
openocd -c "set QS_ADAPTER interface/jlink.cfg" -f openocd/cfg/pynq-z2.cfg
```

An ST-Link **must** end up on the dapdirect path, not the deprecated HLA one: a
`mem_ap` and every `dap` command need a real DAP and HLA provides none. Confirm
with `adapter name` — it must print `st-link`, `jlink` or `cmsis-dap`, never
`hla`.

### KR260

**This repo does not contain a KR260 SWD pinout, and this config cannot invent
one.** `nanosoc_arch_tech/fpga/fpga/targets/pynq_kr260/fpga_timing.xdc:10`
creates a clock on `[get_ports SWCLKTCK]`, but no `set_property PACKAGE_PIN …
[get_ports SWCLKTCK]` exists anywhere in the repo, and
`pynq_kr260/fpga_pinmap.xdc` assigns only generic `PMOD0_n` / `PMOD1_n`. The
constraint has nothing behind it.

Before this config can reach anything, somebody must pick two PMOD pins, add the
`PACKAGE_PIN` / `IOSTANDARD` / `PULLTYPE` lines the way pynq-z2 does
(`nanosoc.xdc:107-114` is the pattern), and record the choice in
`cfg/kr260.cfg`'s header. The KR260 PMODs are LVCMOS33, so a 3V3 probe is
correct and a 1V8-only probe is not.

The config defaults to `interface/cmsis-dap.cfg`; same ST-Link caveat as above.

### HAPS-SX

`haps-openocd` owns the probe. It writes the probe half on `haps-dev` — adapter
driver, serial, `transport select swd`, speed, `reset_config none`, `bindto`,
and the three `*_port`s — and sources your target half after it. Your file
declares only `swd newdap` / `dap create` / `target create` and procs. A config
that pins a port is refused twice: by `haps-openocd check` before anything is
opened, and by the far side at `up`.

```bash
haps-openocd check openocd/cfg/haps-sx-mem.cfg          # lints it here, no probe, no ssh
haps-openocd save  nanosoc-m0-qs-mem  --from openocd/cfg/haps-sx-mem.cfg
haps-openocd up    nanosoc-m0-qs-mem
haps-openocd port                                        # the forwarded numbers
```

PMOD2 carries SWCLK / SWDIO / GND / VTref and nothing else, so again there is no
reset wire and `SYSRESETREQ` is the only target reset.

---

## Verification

Every check below names the exact command, the exact line that proves it worked,
and **how it can fail**. A check that cannot fail is worthless; the two that are
weaker than they look are called out at the end.

Throughout, `<board>` is `pynq-z2` or `kr260`. On HAPS-SX, `haps-openocd up …`
replaces the `openocd -f …` invocation and the log is
`haps-openocd status` / the session log on `haps-dev`.

### Check 1 — the config is well formed (no hardware needed)

```bash
openocd -c "set QS_ADAPTER interface/cmsis-dap.cfg" -f openocd/cfg/<board>.cfg \
        -c "targets" -c shutdown
```

Proves it worked — this table, with exactly one row for `QS_TARGET=mem`:

```
    TargetName         Type       Endian TapName            State
--  ------------------ ---------- ------ ------------------ ------------
 0* nanosoc.mem        mem_ap     little nanosoc.cpu        unknown
```

**How it fails:** a Tcl error names the file and line and OpenOCD exits non-zero.
Proven to fail on demand:

```bash
openocd -c "set QS_TARGET nope" -f openocd/cfg/pynq-z2.cfg -c shutdown ; echo $?
# openocd/cfg/nanosoc_m0_qs.cfg:164: Error: nanosoc_m0_qs.cfg: QS_TARGET must be mem, core or both (got 'nope')
# 1
```

That exact output was observed while writing this file. So was the `QS_TARGET=both`
table showing `nanosoc.cpu0 … examine deferred` above `nanosoc.mem`.

For the two HAPS files the equivalent gate is the bench tool's own linter:

```bash
haps-openocd check openocd/cfg/haps-sx-mem.cfg
# ok: openocd/cfg/haps-sx-mem.cfg
```

Both files were run through it and both print `ok:`. **How it fails:** it exits 2
with `<path>:<line>: <reason>` for a missing header line, a pinned port, a
missing `swd newdap` or `dap create`, a `jtag` stanza, or a Tcl syntax error.

### Check 2 — am I talking to the right debug port

```bash
openocd -f openocd/cfg/<board>.cfg -c init -c shutdown 2>&1 | grep 'SWD DPIDR'
```

Proves it worked — this line, compared **by you**, character by character:

```
Info : SWD DPIDR 0x0bb11477
```

That is `SW_DPIDR_REG_VAL` from `cm0_dap_dp_sw_defs.v:24`.

**This comparison is deliberately manual. Do not add `-expected-id`.** Measured
from OpenOCD 0.12's source: `expected_ids` is stored by `jtag/tcl.c` and compared
only in `jtag/core.c` (reached solely from `jtag_examine_chain()`, the JTAG chain
scan), `jtag/hla/hla_interface.c` (HLA: ST-Link, TI-ICDI) and
`jtag/aice/aice_interface.c`. Neither the cmsis-dap + SWD path nor the ST-Link
**dapdirect** path is any of those — `adi_v5_swd.c` reads `DP_DPIDR`, logs it and
compares nothing. A wrong id would connect silently while looking guarded. A
successful connect is therefore **not** evidence about the DP.

**How it fails:**
- `Info : SWD DPIDR 0x6ba02477` — a CoreSight SoC-400 SWJ-DP. That is the
  multicore nanoSoC, not this one. Wrong bitstream on the FPGA.
- `Error: Error connecting DP: cannot read IDR` — nothing is answering. Wiring,
  VTref, or no bitstream.
- A DPIDR that **changes** when you slow the clock is the floating-VTref/wiring
  fault, not a design fact. Re-run with `-c "adapter speed 100"` and require the
  same value. This leg is borrowed from the HAPS bench's `check-swd.sh`.

Live second opinion, once connected: `qs_dpidr` in the telnet shell reads DP
register `0x0` and returns the same `0x0bb11477`. The logged line stays primary
because it is the value the connect itself acted on.

### Check 3 — is it the right SoC

Connect, then in `telnet localhost 4444`:

```
> qs_ident
```

Proves it worked — these lines, values on the left of each `expect`:

```
-- nanoSoC-M0 QuickStart identity, AP 0 --
DPIDR (live)  0x0bb11477   expect 0x0bb11477
AP IDR        0x04770021   expect 0x04770021
AP CFG        0x00000000   expect 0x00000000
AP BASE       0xf0000003   0xf0000003 = SoC systable build; 0xe00ff003 = core-ROM-table build
AP CSW        0x03000042   expect 0x03000042 (0x03000002 = DeviceEn LOW, debug not powered)
CPUID         0x410cc200   expect 0x410cc200  (Cortex-M0 r0p0, ECOREVNUM 0)
ROM SCS ent   0xfff0f003   expect 0xfff0f003
ROM CID1      0x00000010   expect 0x00000010  (CoreSight ROM table class)
DHCSR         0x01000000   bit17 S_HALT: 0 = core running, 1 = halted
```

**How each line fails:**

| line | a wrong value that really happens | what it means |
|---|---|---|
| `AP IDR` | anything but `0x04770021` | not this AP. A CoreSight SoC-400 AHB-AP is the likely impostor; its IDR is not asserted here because no file in this repo states it, so treat a non-match as "wrong AP" and identify it from its own RTL. |
| `AP IDR` | `0x00000000` | AP not answering: debug power down, or no AP at this APSEL. |
| `AP CFG` | non-zero | large address or large data — not this AP. |
| `AP BASE` | anything but `0xf0000003` / `0xe00ff003` | `ROMTABLE_BASE` was overridden to something this repo does not build. |
| `AP CSW` | `0x23000042` | Prot is writable — that is a SoC-400 AHB-AP, not `CORTEXM0DAP`. |
| `AP CSW` | `0x03000002` | **DeviceEn is low.** Debug is not powered/enabled; every memory read below is meaningless. |
| `CPUID` | `0x410cc601` | Cortex-M0**+**. That is the multicore nanoSoC, not this SoC. |
| `CPUID` | `0x00000000` or junk | the read is not landing; see `AP CSW`. |
| `ROM SCS ent` | not `0xfff0f003` | the PPB is not where it should be, or the read is stale. |

`DHCSR` has **no fixed expected value** and is stated that way on purpose: bit 24
`S_RETIRE_ST` is sticky and clears on read, so a running core gives you
`0x01000000` or `0x00000000` depending on what happened since the last read. The
only assertion worth making is `S_HALT` (bit 17) **== 0** while the core is
running, and `== 1` after `qs_halt`.

### Check 4 — exactly one AP

```
> nanosoc.dap apid 0
0x04770021
> nanosoc.dap apid 1
0x00000000
```

`0x00000000` on AP 1 is the *correct* answer here and it is an RTL fact, not an
absence: `cm0_dap_dp_sw.v:763` encodes APSEL as `~(|sw_data[31:24])`, so the AP
is selected only for APSEL `0x00`; `:950` then never starts a transaction and
`:864-866` masks the returned data to zero. The DP still ACKs OK.

**How it fails:** `dap apid 1` returning `0x04770021` means there is a real
second AP — you are connected to the multicore nanoSoC, not this SoC.

### Check 5 — prove the reader is not a latch

This is the check that makes Check 3 mean anything.

```
> qs_rd 0xE000ED00
0x410cc200
> qs_rd 0x60000000
<anything that is not 0x410cc200>
```

`0x60000000` is unmapped: `build_soc/reports/nanosoc_memory_map.txt` runs
`dmac_ctrl` to `0x5FFFFFFF` and picks up again at `qspi_mem 0x70000000`.

**How it fails — and this is the point:** if the second read also returns
`0x410cc200`, the DRW is handing you the previous result and **every number in
Check 3 is worthless**. Run this before believing a clean `qs_ident`.

### Check 6 — does YOUR OpenOCD serve a gdb port for `mem_ap`

```bash
openocd -f openocd/cfg/<board>.cfg -c init 2>&1 | grep -i 'gdb server'
```

Two possible proofs, both valid answers:

```
Info : [nanosoc.mem] starting gdb server on 3333      # your build DOES serve one
```

or nothing at all on that grep, in which case confirm the reason rather than
assuming it:

```bash
openocd -d3 -f openocd/cfg/<board>.cfg -c init 2>&1 | grep -i 'skip gdb server'
# Debug: ... [nanosoc.mem] skip gdb server
```

**How it fails:** if neither line appears, you have measured nothing — `init`
probably did not complete, and the absence of a gdb line is about your session,
not about `mem_ap`. Check the exit status and the DPIDR line first.

Run this once per OpenOCD build you use, and write the answer down. The exact
log strings are `src/server/gdb_server.c:3949` (`LOG_TARGET_INFO`, which prefixes
`[<target name>] `) and `:3982`.

### Check 7 — the intrusive one, only when you mean it

```
> qs_halt
DHCSR         0x00030003   bit17 S_HALT should now be 1
> qs_resume
```

`qs_halt` writes `DHCSR = 0xA05F0003` (DBGKEY | C_HALT | C_DEBUGEN) through the
AP, so nothing is read from the core in order to decide to write it.

**How it fails:** `S_HALT` still 0 afterwards means the write did not land —
DBGKEY wrong, `DeviceEn` low (see Check 3), or the AP is not reaching the PPB.

---

## Checks that are weaker than they look

Stated so they are not mistaken for proof.

1. **Check 4's `0x00000000` on AP 1 only discriminates once AP 0 has answered.**
   A dead link gives `0x00000000` on every AP. Read it as "given Check 3 passed,
   there is no second AP", never on its own.

2. **Check 5 cannot tell an AHB error response from a zero-returning default
   slave.** It proves the reader is not a latch — the thing that actually goes
   wrong — but it does not prove the interconnect signals errors correctly for
   unmapped addresses. Doing that needs the `HRESP` path checked in RTL or
   simulation, not over SWD.

3. **Check 2 proves the DP *part*, not the *SoC*.** Any Cortex-M0 with a
   `CORTEXM0DAP` answers `0x0BB11477`. It is Check 3 — CPUID plus AP BASE plus
   the CSW shape — that says *this* SoC. Never report a DPIDR match as "the right
   design is loaded".

4. **Nothing here has been run against hardware.** Checks 1 (both halves) were
   executed while writing this file. Checks 2 to 7 are derived from RTL and from
   OpenOCD source read at `/tmpdir/openocd-build/openocd`
   (`0.12.0+dev-g43441cd`); the expected values are grounded, the *observation*
   is not yet made. The first person to run them on a board should replace this
   paragraph with what they saw.
