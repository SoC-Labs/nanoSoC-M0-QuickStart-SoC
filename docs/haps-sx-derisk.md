# HAPS-SX board-top de-risk: three RTL questions answered

Scope: `nanoSoC-M0-QuickStart-SoC` @ branch `feat/padring-boundary-scan`, read-only RTL analysis.
Target: an XCVU19P HAPS-SX board top with **no PS** — HOSTIO4 on one PMOD, SWD on another.

Everything below is cited to `file:line`. `nanosoc_m0_soc/build_soc/` is generated and gitignored but
is the only place the design is actually wired, so it is treated as authoritative for connectivity.
Where a checked-in source and a generated source disagree, both are named and one is picked.

---

## 0. Which module does a board top instantiate? (prerequisite for all three answers)

Three candidate integration levels exist, and they are **not** interchangeable:

| Level | File | Straps `alt_mode`/`swd_mode`? | Used by |
|---|---|---|---|
| `nanosoc` (core top) | `nanosoc_m0_soc/build_soc/rtl/nanosoc.sv:37` | n/a — no such ports | **the shipping PYNQ-Z2 build** |
| `nanosoc_chip` (generated) | `nanosoc_m0_soc/build_soc/rtl/nanosoc_chip.v:12` | ports exist, **unconnected** | `nanosoc_chip_vivado_wrapper.v` (unused) |
| `nanosoc_chip` (checked-in) | `nanosoc_m0_soc/chip/chip/verilog/nanosoc_chip.v:13` | ports exist, **unconnected** | `nanosoc_ip.flist:21` (sim/ASIC) |

The shipping FPGA reference — `nanosoc_m0_soc/pynq/vivado_ip/nanosoc_vivado_wrapper.v:180` — instantiates
`nanosoc` **directly**, deliberately bypassing `nanosoc_chip` and `nanosoc_system`; the reasons are
stated in its own header at `nanosoc_vivado_wrapper.v:16-23`.

**Recommendation: the HAPS-SX top should instantiate `nanosoc` and copy
`pynq/vivado_ip/nanosoc_vivado_wrapper.v` as its starting point.** It is the only integration level
that is exercised on real silicon-equivalent hardware today, and it makes Question 3 moot (see §3).

Two flist divergences to be aware of before choosing:

- `nanosoc_m0_soc/build_soc/flist/nanosoc_chip_chip.flist:2-3` points at the **generated** chip/pads,
  but nothing references that flist — `grep` across the repo finds only a prose mention in
  `nanosoc_m0_soc/doc/reports/submodule_triage.md:133`. The live flist
  `nanosoc_m0_soc/nanosoc_arch_tech/rtl/flist/nanosoc_ip.flist:21` pulls the **checked-in**
  `chip/chip/verilog/nanosoc_chip.v` instead. The two files have different port lists (the
  checked-in one adds `spi_sclk_o`/`spi_ss_o`/`spi_mosi_o`/`spi_miso_i` at
  `chip/chip/verilog/nanosoc_chip.v:56-59`; the generated one has no SPI ports at all).
- `nanosoc_ip.flist:28` likewise uses the checked-in `rtl/src/system/nanosoc_system.v`, not the
  generated `build_soc/rtl/nanosoc_system.sv`.

---

## 1. The `FT1248MODE` strap

### (a) Polarity — **1 = FT1248/UART2, 0 = EXTIO 8x4**

Confirmed from the RTL, not from the comment:

- `nanosoc_m0_soc/nanosoc_arch_tech/rtl/src/subsystems/hostio4/nanosoc_ss_hostio4.v:20` — port comment
  "high = FT1248/UART2, low = EXTIO (driven by P1_IN[7])".
- Every functional mux agrees with that comment. The ADP byte stream:
  `nanosoc_ss_hostio4.v:111-113` select `FT_ADP_*` when `FT1248MODE` is 1 and `EXT_ADP_*` when 0;
  `:121-123` gate the EXTIO path off when `FT1248MODE` is 1.
- The `hostio4_controller` (the EXTIO 8x4 engine) is wired **only** to the `EXT_*` nets —
  `nanosoc_ss_hostio4.v:147-173`. So `FT1248MODE = 1` disconnects the HOSTIO4 controller from ADP.
- Pad muxing agrees: `nanosoc_ss_hostio4.v:188-227`. With `FT1248MODE = 0`, P1[0]=`ioreq1_o`,
  P1[1]=`ioreq2_o`, P1[2]=`ioack_i` (input), P1[3..6]=`iodata4[3:0]` — the 7-pin HOSTIO4 interface
  described in `nanosoc_arch_tech/rtl/hostio4/README.md`.

Cross-check from an independent source — the stage-0 bootrom prints the mode it detected:
`nanosoc_m0_soc/firmware/bootloader/stage0/stage0_bootloader.c:513-516`:
`if (CMSDK_GPIO1->DATA & 0x80) UartPuts("FT1+U38400"); else UartPuts("EXTIO-DMA");`
Bit 7 high → FT1248. **Same polarity. No source disagrees.**

> **For HOSTIO4 on the HAPS-SX PMOD you need `FT1248MODE = 0`.** This is the opposite of what the
> PYNQ reference straps (see (b)). Do not copy that line.

### (b) Is it strapped inside `nanosoc_chip`, or exposed to a pad?

**It is genuinely exposed. Nothing inside the SoC straps it.**

- `nanosoc.sv:1057` — `.FT1248MODE (p1_in[7])`, straight off the core-top port.
- `nanosoc.sv:81` — `p1_in` is a plain `input wire [15:0]` on the core top.
- `build_soc/rtl/nanosoc_chip.v:132` — `assign P1_IN = p1_i;`, a pure passthrough. No strap, no
  override, no `ifdef`.
- `chip/chip/verilog/nanosoc_chip.v:156` — same, `assign P1_IN = p1_i;`.
- `build_soc/rtl/nanosoc_chip_pads.v:436-441` — `PAD_INOUT8MA_NOE uPAD_P1_07` is a plain bidirectional
  pad on `P1[07]`.

**But the FPGA reference design *does* strap it, one level up, in the board wrapper:**
`nanosoc_m0_soc/pynq/vivado_ip/nanosoc_vivado_wrapper.v:156` — `assign p1_in[7] = 1'b1; // FT1248MODE
strap: FT1248/UART2`. The rest of that block (`:149-157`) also fakes a self-draining FT1248 target so
the bootrom banner cannot wedge — the reasoning is in the file header at `:51-58`.

So the premise in the brief is right: **the reference straps it, this SoC does not.** A HAPS-SX top
that instantiates `nanosoc` directly inherits *no* strap and must drive `p1_in[7]` itself.

### (c) What the other `p1_i` bits do

**`p1_i[6:0]` — owned by the hostio4 subsystem, meaning depends on the strap**
(`nanosoc.sv:1086` routes `p1_in[6:0]` into `u_ss_hostio4.P1_IN`):

| Pin | `FT1248MODE=0` (EXTIO — what you want) | `FT1248MODE=1` (FT1248/UART2) | Cite |
|---|---|---|---|
| P1[0] | `ioreq1_o` **output**, OUTEN forced 1 | `FT_MISO` input, OUTEN forced 0 | `:188-191` |
| P1[1] | `ioreq2_o` **output**, OUTEN always 1 | `FT_CLK` output | `:194-196` |
| P1[2] | `ioack_i` **input**, OUTEN forced 0 | `FT_MIOSIO` bidir | `:199-203` |
| P1[3] | `iodata4[0]` bidir (`iodata4_e[0]`) | `FT_SSN` output, OUTEN 1 | `:206-209` |
| P1[4] | `iodata4[1]` bidir | UART2 **RXD** input | `:212-215` |
| P1[5] | `iodata4[2]` bidir | UART2 **TXD** output (altfunc) | `:218-221` |
| P1[6] | `iodata4[3]` bidir | reserved / GPIO1 altfunc | `:224-227` |

**`p1_i[15:7]` — plain GPIO1 inputs, input-only.**

- `nanosoc.sv:724-730` routes `p1_in[15:7]` into `sys_p1_in[15:7]`.
- `nanosoc.sv:1029` feeds `sys_p1_in` into `u_ss_systemctrl.P1_IN`, which reaches the CMSDK GPIO1
  DATA register (base `0x4001_1000`, per
  `nanosoc_arch_tech/rtl/src/regions/soc_peripheral/nanosoc_soc_peripheral_decode.v:47`).
- `nanosoc.sv:700-714` ties `p1_out[15:7]` and `p1_outen[15:7]` to **zero** via `soc_glue_constant`.
  So the SoC can never drive P1[15:7] — they are pure inputs at the core boundary.
- Two of them have a second function:
  `nanosoc_arch_tech/rtl/src/control/verilog/nanosoc_pin_mux.v:111-112` —
  `timer0_extin = p1_in[8]`, `timer1_extin = p1_in[9]`.

**What a HAPS-SX top must drive on `p1_i[15:8]`:** nothing functional is required. Drive them to a
defined constant (the PYNQ reference uses `8'h00` — `nanosoc_vivado_wrapper.v:157`) unless you want
timer capture on bits 8/9. Leaving them floating only risks noise on GPIO1 DATA reads and spurious
GPIO1 interrupts (`nanosoc.sv:154` `sys_gpio1_any_irq` feeds `cpu_0_irq[7]`).

### (d) Is there a pull or default that makes an undriven pad safe?

**No. Not found anywhere.**

- `generic_lib_tech/pads/verilog/PAD_INOUT8MA_NOE.v:29-40` — behavioural model is
  `bufif1`/`buf` only. No pull, no keeper.
- `fpga_lib_tech/pads/verilog/PAD_INOUT8MA_NOE.v:27-35` — a bare Xilinx `IOBUF` with only
  `IOSTANDARD` and `DRIVE` set. No `PULLTYPE`.
- No XDC in the repo sets a pull on any P1 pin. `grep -rn PULL --include=*.xdc` returns only:
  the PMOD0 pulls on the *multicore* KR260/KV260/ZCU104 pinmaps
  (`nanosoc_arch_tech/fpga/fpga/targets/pynq_kr260/fpga_pinmap.xdc:10-39` etc.) and the pynq-z2 SPI/SWD
  pulls (`nanosoc_m0_soc/pynq/targets/pynq-z2/nanosoc.xdc:50-51,109,114`). The pynq-z2 XDC does not
  constrain any P1 pin at all — P1 is not bonded out on that board.
- Nothing in `nanosoc.sv` or either `nanosoc_chip.v` defaults `p1_in[7]`.

So an undriven `p1_i[7]` is indeterminate. On the FPGA, if you leave the wrapper port unconnected,
Vivado will constant-tie it and warn (Synth 8-3295) — which happens to land on EXTIO, but that is
tool behaviour, not design intent, and it is not something to rely on.

Note the interesting asymmetry for a PMOD design: those multicore pinmaps pull PMOD0_0/PMOD0_1
**down** (ioreq1/ioreq2) and PMOD0_2..7 **up** (ioack + iodata4) — a sensible idle posture for a
HOSTIO4 PMOD that the HAPS-SX XDC should copy.

### Falsifiable statement — Question 1

> **The board top must drive `p1_i[7]` to `0` (and must drive it — not leave it floating).
> If it is wrong (1), the symptom is: HOSTIO4 is dead — `hostio4_controller` is disconnected from the
> ADP stream (`nanosoc_ss_hostio4.v:121-123` force `EXT_ADP_RXD_TVALID = 0` and
> `EXT_ADP_TXD_TREADY = 0`), P1[0] stops driving `ioreq1` (`:189` forces `P1_OUTEN[0] = 0`), and
> `ioack_i` is forced to a constant 1 (`:203`) so the controller sees a permanently-acknowledging
> target that never transfers a byte. The PMOD looks electrically alive and moves no data.**

**How to detect it on the bench rather than guess** — three independent checks, cheapest first:

1. **Scope P1[1] at reset.** In EXTIO mode `P1_OUTEN[1]` is unconditionally 1 (`:195`) and P1[1] carries
   `ioreq2_o`. In FT1248 mode P1[1] carries `FT_CLK` — a free-running divided clock
   (`FT1248_CLKON = 1`, `FT1248_CLKDIV = 15` at `nanosoc.sv:52-53`). **A continuous clock on P1[1]
   means you are in FT1248 mode.** This needs no firmware and no host.
2. **Scope P1[0] direction.** EXTIO drives it (`P1_OUTEN[0] = 1`, `:189`); FT1248 releases it
   (`P1_OUTEN[0] = 0`, `:189`). A pin that stays Hi-Z is FT1248.
3. **Read the boot banner.** Stage-0 emits its own verdict —
   `stage0_bootloader.c:512-517` prints `SoCLabs NanoSoC'25 ARM-CM0+ADP+` then either `FT1+U38400`
   or `EXTIO-DMA`. In EXTIO mode that text comes out of the HOSTIO4 PMOD itself, so seeing
   `EXTIO-DMA` on the Pico/host is simultaneously the strap check and the link-up check.
   Firmware can also read the strap back directly: `CMSDK_GPIO1->DATA & 0x80`
   (`stage0_bootloader.c:139`, GPIO1 @ `0x4001_1000`), because `sys_p1_in[7]` is wired straight from
   the pad (`nanosoc.sv:724-730`).

---

## 2. The IMEM load path on a board with no PS

### (a) What `IMEM_0_RAM_PRELOAD` actually changes: **nothing. It is inert.**

This corrects one of the premises given. The premise's *quotation* is accurate —
`build_soc/rtl/nanosoc_soc_config.vh:22` really does say `` `define IMEM_0_RAM_PRELOAD 0 `` and
`nanosoc.sv:64` really does document it as "0=SRAM (ADP load), 1=ROM (preloaded image)". But nothing
consumes it:

- `nanosoc_arch_tech/rtl/src/regions/imem/nanosoc_region_imem.v:39` branches on
  `` `ifdef RAM_PRELOAD `` — a **different symbol**, a preprocessor define, not the parameter.
- `IMEM_0_RAM_PRELOAD` appears exactly **once** in `nanosoc.sv` (line 64, the declaration —
  `grep -c` returns 1). It is never passed down: `nanosoc.sv:760-765` passes `IMEM_RAM_ADDR_W`,
  `IMEM_RAM_DATA_W` and `IMEM_MEM_FPGA_IMG` to `u_ss_cpu` and nothing else. `nanosoc_ss_cpu.sv:242-247`
  passes only `RAM_ADDR_W`/`RAM_DATA_W`/`MEM_FPGA_IMG` to `nanosoc_region_imem`.
- `nanosoc_soc_config_pkg.sv:43` declares `localparam int IMEM_0_RAM_PRELOAD = 0` — also unreferenced.
- `nanosoc_soc_config.vh` is **included by no RTL file at all**
  (`grep -rn 'include.*soc_config' --include=*.v --include=*.sv --include=*.vh` returns nothing), so
  its `` `define `` never even reaches a compiler.

**What actually selects the IMEM implementation is `RAM_PRELOAD`,** and in this repo it is defined
**unconditionally**:

- `system/src/defines/gen_defines.v:11` — `` `define RAM_PRELOAD ``. This file is `include`d by
  `chip/chip/verilog/nanosoc_chip.v:11`, `nanosoc_arch_tech/verification/tb/verilog/nanosoc_tb.v:40`,
  `nanosoc_chip_vivado_wrapper.v:21` and the ASIC pad wrappers.
- For the Vivado flow it is forced as a synthesis define regardless:
  `nanosoc_m0_soc/pynq/filelist.tcl:42` and `nanosoc_m0_soc/pynq/build_nanosoc_design.tcl:121` both
  `set_property verilog_define {RAM_PRELOAD}`, and `pynq/vivado_ip/package_nanosoc_ip.tcl:174-185`
  propagates it into the packaged IP's filesets.

With `RAM_PRELOAD` defined, `nanosoc_region_imem.v:41-62` instantiates `sl_ahb_rom`, which at
`nanosoc_m0_soc/src/rtl/fpga_lib/rom/sl_ahb_rom.v:85-96` instantiates `sl_fpga_rom_word`.

**Despite the name, that is not a ROM.** `nanosoc_m0_soc/src/rtl/fpga_lib/rom/sl_fpga_rom_word.v:6-22`
says so explicitly, and `:88-91` implement four byte-enabled write lanes. It is a writable BRAM with
`$readmemh` initial content (`:78`). Its own header records that the previous read-only version
made "SWD-driven firmware hot-flash impossible" and that the fix was deliberate.

**Net effect for the HAPS-SX: IMEM is a writable 16 KB BRAM, preloaded from a hex at bitstream build,
and writable afterwards over any AHB master.** Setting `IMEM_0_RAM_PRELOAD = 1` would change nothing;
*undefining* `RAM_PRELOAD` would swap in `sl_ahb_sram` (`nanosoc_region_imem.v:65-85`) — still
writable, but with no bitstream-baked image.

### (b) Does preload need a generated `image.hex`? Format, width, make target

Yes, and it must be the **word** format, not objcopy's byte format.

- `sl_fpga_rom_word.v:43-45` — parameter `filename`, default `"image_word.hex"`;
  `:78` — a single `$readmemh(filename, mem)` into `reg [31:0] mem [0:DEPTH-1]`.
- **Format: one 32-bit word per line, uppercase hex, little-endian byte order within the word, with
  `@` headers carrying a WORD address (byte address >> 2).** Cited at
  `nanosoc_m0_soc/pynq/scripts/hex_byte_to_word.py:13-21` (worked example) and `:48-70` (the emitter;
  `:61` writes `@{min_addr >> 2:08X}`, `:69` packs `b0 | b1<<8 | b2<<16 | b3<<24`).
- **Why it must be converted:** `sl_ahb_rom.v:80-84` explains that ARM's `cmsdk_fpga_rom` byte-shuffle
  loop is silently dropped by Vivado (`WARNING [Synth 8-311]`) leaving BRAM contents zero. Same
  warning is restated at `hex_byte_to_word.py:5-11`. Feeding a raw objcopy hex to `sl_fpga_rom_word`
  gives a **silently empty IMEM**.
- **Make target:** there is no top-level one. The chain lives in `nanosoc_m0_soc/pynq/Makefile`:
  - `firmware:` (`:136-148`) builds the CMake superproject → `$(FIRMWARE_HEX)` =
    `imp/fpga/firmware/fw/testcodes/$(APP)/$(APP).hex` (`:78`), objcopy byte format.
  - `$(FIRMWARE_HEX_WORD):` (`:164-166`) runs `python3 scripts/hex_byte_to_word.py` →
    `imp/fpga/$(APP)_word.hex` (`:80`).
  - `build_design:` (`:168-178`) depends on both and exports `FIRMWARE_HEX=$(FIRMWARE_HEX_WORD)`.
  - So: **`make -C nanosoc_m0_soc/pynq firmware && make -C nanosoc_m0_soc/pynq imp/fpga/hello_word.hex`**
    (or just `build_design`, which also runs Vivado). `APP` defaults to `hello` (`:75`).
  - `nanosoc_m0_soc/nanosoc_arch_tech/makefile` has **no** hex/firmware target — its only targets are
    `gen_defs`, `docs`, `soc_model`, `TEST_AMS` (lines 283, 287, 296, 303). A HAPS-SX flow needs its
    own copy of the pynq Makefile's firmware + hex-convert rules.

**Size trap found while checking this.** The generated linker script and memmap both claim 64 KB of
IMEM, but the RTL builds 16 KB:

- `build_soc/firmware/nanosoc_cmsdk_cm0_memory.ld:11` — `IMEM_0 (rwx) : ORIGIN = 0x00000000,
  LENGTH = 0x10000 /* 64K */`; `build_soc/firmware/nanosoc_memmap.h:19` — `NANOSOC_IMEM_0_SIZE
  (0x00010000UL)`. Both derive from `sys_desc/subsystems/cpu/nanosoc_ss_cpu.yaml:200`
  (`phys_size: "4 * (2 ** $IMEM_RAM_ADDR_W)"` = 4 × 2¹⁴ = 65536).
- The RTL disagrees. `IMEM_RAM_ADDR_W = 14` (`nanosoc_soc_config.vh:14`) is a **byte** address width:
  `cmsdk_ahb_to_sram` declares `input wire [AW-1:0] HADDR` and `output wire [AW-3:0] SRAMADDR`
  (BP210 r1p1 `cmsdk_ahb_to_sram.v:42,49`), and `sl_fpga_rom_word.v:55` computes
  `DEPTH = 1 << (AW - 2)` = 4096 words = **16 KB**.
- `nanosoc_arch_tech/rtl/src/system/nanosoc_system.v:33` agrees with the RTL ("Default 16KB");
  `build_soc/rtl/nanosoc.sv:29` agrees with the (wrong) YAML ("default 64 KB").
- **I trust the RTL: IMEM is 16 KB.** The 4× overstatement means an image between 16 KB and 64 KB
  links clean, loads clean, and aliases on top of itself. Worth confirming with an `I=` readback
  (see the detection note below) before anyone blames the load path.

### (c) Is IMEM writable over the HOSTIO4/ADP AHB master at run time? **Yes.**

The path exists end to end:

1. HOSTIO4 pins → `hostio4_controller` → `EXT_ADP_*` stream (`nanosoc_ss_hostio4.v:147-164`).
2. `EXT_ADP_*` → `ADP_*` when `FT1248MODE = 0` (`:111-113`, `:121-123`).
3. `ADP_*` → `u_ss_debug` (`nanosoc.sv:1058-1063` bind `adp_rxd_*`/`adp_txd_*`).
4. `nanosoc_ss_debug` exposes a full AHB **master**:
   `nanosoc_arch_tech/rtl/src/subsystems/debug/nanosoc_ss_debug.v:27-37` (`DEBUG_HADDR`,
   `DEBUG_HWRITE`, `DEBUG_HWDATA`, …).
5. That master is an interconnect initiator named `debug`, and its target list **includes `cpu_ss`**:
   `sys_desc/nanosoc_m0_soc.yaml:1183-1186`. (`cpu_0` deliberately does not have `cpu_ss` in its list —
   `:1168-1181`.)
6. `cpu_ss` is the whole `0x00000000-0x1FFFFFFF` window (`sys_desc/nanosoc_m0_soc.yaml:1150`), and
   inside it the `cpu_ss` passthrough initiator can reach `imem_0`:
   `sys_desc/subsystems/cpu/nanosoc_ss_cpu.yaml:222-236`, target `imem_0` at base **`0x10000000`**
   (`:200`, `sw_access: rwx`), plus the remap alias at `0x00000000`.
7. Confirmed in the generated firmware header: `build_soc/firmware/nanosoc_memmap.h:18` —
   `NANOSOC_IMEM_0_BASE (0x10000000UL)`.
8. The memory itself accepts writes: `sl_fpga_rom_word.v:88-91`.

**So yes — firmware can be pushed into IMEM over HOSTIO4/ADP at `0x10000000` instead of preloaded.**
This is what `adp: upload_target: imem_0` at `sys_desc/nanosoc_m0_soc.yaml:1269-1271` declares, and
`build_soc/firmware/nanosoc_adp.py` / `nanosoc_adp.vh` are the generated host-side descriptors.

### (d) Is IMEM writable over SWD via the Cortex-M0 DAP's AP? **Yes.**

- `nanosoc_chip.v` (both copies) wires the SWD pads to the core: generated
  `build_soc/rtl/nanosoc_chip.v:117-121`; checked-in `chip/chip/verilog/nanosoc_chip.v:140-144`.
  At the core top these are `cpu_0_swdi/swclk/swdo/swdoen` (`nanosoc.sv:74-77`), forwarded through
  `nanosoc_ss_cpu.sv:215-218` into `u_cpu_0`.
- `slcorem0.v:26-30` — `EXTERNAL_DAP` defaults to **0**, i.e. the per-core `CORTEXM0DAP` is
  instantiated and `CORE_SWDI/SWCLK/SWDO/SWDOEN` are live (`:201`, `:227`). The PYNQ wrapper confirms
  the intent: `nanosoc_vivado_wrapper.v:81-82` "Drives the Cortex-M0 DAP directly (single core,
  EXTERNAL_DAP=0)".
- The DAP drives the core's debug slave port (`slcorem0_integration.v:122-130`, `SLVADDR`/`SLVWDATA`/…),
  which the Cortex-M0 arbitrates onto its own AHB master port. **The DAP therefore sees exactly the
  `cpu_0` address map**: `imem_0` at `0x10000000` (and at `0x00000000` after remap) —
  `sys_desc/subsystems/cpu/nanosoc_ss_cpu.yaml:205-220`.
- Tooling already exists and is parameterised for exactly this:
  `nanosoc_arch_tech/python/nanosoc_dap_hal/loader.py:17-21` — the worked example is
  `launch_imem(sess, ap=1, load_addr=0x10000000, vtor_base=0x10000000, …)`. The single-core OpenOCD
  config uses AP 0: `nanosoc_m0_soc/pynq/scripts/openocd/nanosoc.cfg:39` —
  `target create $_CHIPNAME.cpu0 cortex_m -dap $_CHIPNAME.dap -ap-num 0`.
- And the memory survives it: `sl_fpga_rom_word.v:18-22` — "BRAM cells on 7-series are NOT
  reset-clearable, so an SWD-loaded image survives a SYSRESETREQ and is picked up on the next
  Reset_Handler."

### Ranked IMEM load paths for the HAPS-SX

| # | Path | New work | Why |
|---|---|---|---|
| **1** | **SWD → DAP AP → `0x10000000`** | **Least.** Wire 2 PMOD pins; reuse `nanosoc_dap_hal` + `pynq/scripts/openocd/nanosoc.cfg`. | The loader is written, parameterised and hardware-proven; the address it defaults to is this SoC's IMEM base; no new RTL, no new host protocol, no bitstream rebuild per firmware change. |
| **2** | **Bitstream preload (`image_word.hex`)** | **Medium.** Port the two `pynq/Makefile` rules (`firmware`, `$(FIRMWARE_HEX_WORD)`) into a HAPS-SX flow and set `IMEM_MEM_FPGA_IMG`. | Mechanically simple and already scripted, but every firmware change costs a full place-and-route on an XCVU19P. Fine for a golden image, painful for iteration. |
| **3** | **HOSTIO4/ADP → `0x10000000`** | **Most.** Needs `p1_i[7]=0`, a 7-pin PMOD with the right idle pulls, an RP2040/RP2350 PIO host (`nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio/`), and an ADP command layer on top. | The RTL path is complete and the Pico driver exists, but nothing in this repo drives ADP over HOSTIO4 today — the PYNQ flow uses `pynq.MMIO` from the PS, which has no analogue here. This is the path that gets you a console *and* a loader, so it is worth building — just not first. |

Note these are not exclusive. The pragmatic bring-up order is: bitstream-preload a known-good `hello`
so the board boots at all, bring up SWD for iteration, then bring up HOSTIO4 for the console.

### Falsifiable statement — Question 2

> **The board top must drive `IMEM_MEM_FPGA_IMG` at the `nanosoc` instance to a word-format hex that
> actually exists on the synthesis include path, AND the synthesis fileset must define `RAM_PRELOAD`.
> If `RAM_PRELOAD` is missing the symptom is: `nanosoc_region_imem.v:65` instantiates `sl_ahb_sram`
> instead, IMEM comes out of configuration all-zero, and the CPU takes a HardFault immediately after
> stage-0's REMAP because the reset vector at `0x00000000` is `0x00000000`. If `RAM_PRELOAD` is
> defined but the hex is missing or in byte format, the symptom is identical — a silent all-zero
> IMEM — because `$readmemh` on a missing file only warns.**

**How to detect it on the bench rather than guess:** stage-0 already prints the answer. Before it
jumps, `FlashLoader()` emits `I=<w0>,<w1>` — the first two words read back from
`NANOSOC_IMEM_0_BASE` — then `V=`, `M=`, `W=` and `R`
(`stage0_bootloader.c:258-302`, format documented at `:263-269`).
- `I=00000000,00000000` → the image never got into IMEM (build/format problem).
- `I=` non-zero but `W=` still showing the bootrom vectors → the REMAP did not take.
- `R` never printed → the boot wedged before the jump.

Caveat: those markers go out on **UART2 (P1[5], 38400 baud)**, which only exists when
`FT1248MODE = 1` (`nanosoc_ss_hostio4.v:218-219`, `stage0_bootloader.c:139-144`). In EXTIO mode the
banner text still comes out, but over HOSTIO4. **Practical consequence: bring the board up once with
`p1_i[7]=1` and a 2-wire UART on P1[4]/P1[5] to get the `I=`/`W=`/`R` diagnostics, then flip the
strap to 0 for HOSTIO4.** Budget one extra PMOD pin pair for this; it is the difference between a
one-evening bring-up and a week of guessing.

---

## 3. The `alt_mode` and `swd_mode` straps

### What each one actually gates: **neither gates anything. Both are dangling inputs.**

This is the finding that resolves the contradiction in the brief.

In the **generated** chip, `build_soc/rtl/nanosoc_chip.v`:
- `alt_mode` — declared at `:31`, and that is its **only** occurrence in the file (`grep -c` = 1).
- `swd_mode` — declared at `:34`, only occurrence (`grep -c` = 1).
- Same for `uart_rxd_i` (`:32`), `diag_mode` (`:21`), `diag_ctrl` (`:22`), `bist_mode` (`:27`),
  `bist_enable` (`:28`), `test_i` (`:36`), `scan_in` (`:25`).
- `uart_txd_o` (`:33`) and `scan_out` (`:26`) are declared **outputs that nothing drives** — they
  read `z`.
- The only ports in that group that do anything are `scan_mode`/`scan_enable` (`:102-103`) and
  `bist_in`→`bist_out` (`:105`, a passthrough).

In the **checked-in** chip, `chip/chip/verilog/nanosoc_chip.v`, it is the same picture and the history
is visible: the assignments that would have made them live are **commented out** —
`:121` `/// assign scan_out = scan_in;` and `:123` `/// assign uart_txd_o = uart_rxd_i;`.

So all three postures in the brief are equally inert:
- PYNQ block designs tie both to 0 — e.g.
  `nanosoc_arch_tech/fpga/fpga/targets/pynq_z2/vivado_script/2021_1/nanosoc_design.tcl:864`
  (one `xlconstant_zero` fans out to `diag_mode`, `diag_ctrl`, `scan_mode`, `scan_enable`,
  `bist_mode`, `bist_enable`, `alt_mode`, `uart_rxd_i`, `swd_mode`, `test_i`). Same line in the
  kr260/kv260/zcu104/mps3 variants.
- `nanosoc_chip_vivado_wrapper.v:94,97` ties both to 1.
- A third posture exists that the brief did not mention: `chip/chip/verilog/nanosoc_chip_cfg.v:408,411`
  ties `alt_mode = 1'b0` and `swd_mode = 1'b1`.

**They disagree because none of them matters.** No source is "right"; the ports are decoration.

**Where they were *meant* to matter** is one level up, in the pad-config block
`chip/chip/verilog/nanosoc_chip_cfg.v`, which decodes a config strap into a pad-sharing scheme:
`:221` `assign soc_swd_mode = cfg_sys;`, `:223` `assign soc_alt_mode = cfg_alt;`,
`:225-232` share one bidirectional `pad_altio` pin between SWDIO and UART-TXD, and one `pad_altin`
pin between SWCLK, UART-RXD and scan-enable. That is a **pin-count-saving multiplexer for the ASIC
pad ring**, not an enable for SWD or UART inside the SoC. It is also not on any live path here: the
`ASIC_TEST_PORTS` branch that instantiates `nanosoc_chip` from `nanosoc_chip_cfg` contains a Verilog
syntax error — `:402` `{GPIO_TIO{1'b0})` and `:406` `{GPIO_TIO{1'b1})`, each missing a closing brace —
so it has never been compiled.

### What posture does a HAPS-SX board top need?

**Neither strap. Do not instantiate `nanosoc_chip` at all.**

Working SWD and working UART come from somewhere else entirely:

- **SWD** comes from the four core-top ports `cpu_0_swdi`/`cpu_0_swclk`/`cpu_0_swdo`/`cpu_0_swdoen`
  (`nanosoc.sv:74-77`), driven straight from PMOD pins. See `nanosoc_vivado_wrapper.v:162-163,195-198`
  for the tristate adapter (`swd_dio_t = ~cpu_0_swdoen`). `swd_mode` is not in that path.
- **UART** comes from `FT1248MODE = 1` plus firmware setting GPIO1 ALTFUNC bit 5. Chain:
  `nanosoc_pin_mux.v:110` `uart2_rxd = p1_in[4]`; `:123` `p1_out_mux[5] = p1_altfunc[5] ? uart2_txd :
  p1_out[5]`; `:145` the matching output enable; `nanosoc_ss_hostio4.v:212-221` routes those to the
  P1[4]/P1[5] pads **only when `FT1248MODE` is 1**; `stage0_bootloader.c:143`
  `CMSDK_GPIO1->ALTFUNCSET = (1<<5)`. `alt_mode` is not in that path either.

**The direct conflict a board top must resolve is between UART and HOSTIO4, not between `alt_mode`
and `swd_mode`.** `nanosoc_ss_hostio4.v:214` is the crux:
`assign SYS_P1_IN[4] = (FT1248MODE) ? P1_IN[4] : SYS_P1_OUT_MUX[5];`
— in EXTIO mode, UART2's RX line is an internal loopback of UART2's own TX, not the pad. The SoC's
own YAML says so: `nanosoc_arch_tech/rtl/src/subsystems/systemctrl/nanosoc_ss_systemctrl.v:200-202` —
"P1_IN here is the post-hostio4-mux bus … in FT1248/UART2 mode nanosoc_ss_hostio4.v:214 passes the
real pad through to bit 4, which is what UART2's RXD needs."

**Recommended HAPS-SX posture:**

| Signal | Drive | Why |
|---|---|---|
| `cpu_0_swdi` / `cpu_0_swclk` | PMOD pins, `PULLUP` on DIO, `PULLDOWN` on CLK | copy `pynq/targets/pynq-z2/nanosoc.xdc:107-114` |
| `p1_i[7]` | `1'b0` for HOSTIO4, `1'b1` for UART console — **make it a top-level port or a parameter, not a hard tie** | the two are mutually exclusive (`nanosoc_ss_hostio4.v:212-221`) |
| `p1_i[6:0]` | to the HOSTIO4 PMOD via real tristates, using `p1_outen[6:0]` | `nanosoc_ss_hostio4.v:188-227` |
| `p1_i[15:8]` | `8'h00` | `nanosoc_vivado_wrapper.v:157` |
| `alt_mode`, `swd_mode` | **do not instantiate** | inert (above) |

Two more board-top items that bit the PYNQ wrapper and will bite here:

1. `nanosoc.sv:139-143` declares `qspi_sclk`/`qspi_csn`/`qspi_io_o`/`qspi_io_i`/`qspi_io_e`.
   `nanosoc_vivado_wrapper.v` connects **none** of them, so `qspi_io_i` floats. `BOOT_MODE = 0`
   (`nanosoc.sv:59`) keeps QSPI off the boot path, but `QSPI_FLASH_PRESENT = 1` (`:58`) means stage-0
   still *attempts* a flash boot (`stage0_bootloader.c:521-530`) before falling back. Tie
   `qspi_io_i = 4'b0000` explicitly, or set `QSPI_FLASH_PRESENT = 0`, to skip the attempt.
2. The expansion port group has inverted port directions and must be tied off the way
   `nanosoc_vivado_wrapper.v:212-267` ties it — the reasoning (Vivado Synth 8-6104/8-3848) is in that
   file's header at `:25-39`.

### Falsifiable statement — Question 3

> **The board top must drive neither `alt_mode` nor `swd_mode` — it must not instantiate
> `nanosoc_chip` at all, and must instead instantiate `nanosoc` and wire `cpu_0_swdi`/`cpu_0_swclk`/
> `cpu_0_swdo`/`cpu_0_swdoen` to pads directly. If someone instead instantiates `nanosoc_chip` and
> expects `swd_mode = 1` to enable debug, the symptom is: SWD works anyway (the strap is ignored), so
> the mistake is invisible — until a regeneration of `build_soc` silently disables it (see the
> regeneration hazard below). If someone expects `alt_mode = 1` to enable the UART, the symptom is:
> `uart_txd_o` is permanently `z` (`build_soc/rtl/nanosoc_chip.v:33`, never assigned) and the console
> is dead, while the real console on P1[5] works fine and is being ignored.**

**How to detect it on the bench rather than guess:** drive `swd_mode` and `alt_mode` from a board
switch or two spare PMOD pins for the first bring-up and toggle them while OpenOCD is connected.
`swd newdap` + `dap create` + `target examine` (`pynq/scripts/openocd/nanosoc.cfg:35-39`) will succeed
or fail identically in all four combinations — **that invariance is the proof that the straps are
inert**, and it takes about two minutes. If instead you see a dependence, the board top is not
instantiating the module you think it is.

---

## Regeneration hazard — flagged because it silently kills SWD

`nanosoc_m0_soc/build_soc/rtl/nanosoc_chip.v` was generated **2026-04-01** (`:10`) from
`nanosoc_arch_tech/nanosoc_gen/soc_model/backends/templates/soc_chip.v.j2`. **The template has since
changed and no longer produces what is checked in.**

- Checked-in generated file, `build_soc/rtl/nanosoc_chip.v:117-121`:
  `assign CPU_0_SWCLK = swdclk_i; assign CPU_0_SWDI = swdio_i; assign swdio_o = CPU_0_SWDO; …`
  — live SWD.
- Current template, `soc_chip.v.j2:106-115`: "Legacy SWDIO/SWDCK pads (retained, inert) … Debug now
  leaves the die through the `dap_*` group … hold the SWDIO pad output disabled (Hi-Z);
  `swd_mode`/`swdio_i`/`swdclk_i` idle", followed by
  `assign swdio_o = 1'b0; assign swdio_e = 1'b0; assign swdio_z = 1'b1;` — **unconditionally**, with
  no `CPU_0_SWD*` wires at all.
- The replacement debug path is `{% for port in dap_ports %}` (`soc_chip.v.j2:43-45`). But
  `grep -n "dap" nanosoc_m0_soc/sys_desc/nanosoc_m0_soc.yaml` returns **nothing** — this SoC declares
  no DAP port group.

**So regenerating `build_soc` today would produce a `nanosoc_chip` with SWDIO tied Hi-Z and no `dap_*`
replacement — no external debug path at all.** This does not affect a board top that instantiates
`nanosoc` directly (the core top's `cpu_0_swd*` ports are unaffected), which is one more reason to
prefer that route. Anyone who runs `make soc_model` before a HAPS-SX build should diff
`build_soc/rtl/nanosoc_chip.v:117-121` afterwards.

---

## What could not be resolved from RTL alone

1. **Which HOSTIO4 *host* the HAPS-SX will use.** The RTL makes the SoC the HOSTIO4 **initiator**
   (`nanosoc_arch_tech/rtl/hostio4/README.md`, "Initiator (SoC) port interface"), so the board needs a
   target. Two exist in-tree — an RP2040/RP2350 PIO driver
   (`nanosoc_arch_tech/rtl/hostio4/rpi-pico-pio/hostio4.pioasm`, plus C and MicroPython hosts) and a
   fabric target IP (`nanosoc_arch_tech/rtl/socdebug_tech/socket/vivado_packages/extio8x4_axis_target_1.0/`,
   also `rtl/hostio4/target_rtl/hostio4_target.sv`). Which one the HAPS-SX uses is a bench decision.
   The Pico route needs no fabric IP and no PS; the fabric-target route needs something to drain the
   AXI-Stream, which on a PS-less board means writing that something.
2. **The ADP command protocol for pushing an image over HOSTIO4.** The AHB master and the address
   window are proven (§2c), and `build_soc/firmware/nanosoc_adp.py` + `nanosoc_adp.vh` exist, but I
   did not verify a working host-side ADP write sequence — the PYNQ flow reaches ADP through
   `pynq.MMIO` from the PS, which does not transfer. This is the main reason path 3 is ranked last.
3. **Whether the 16 KB vs 64 KB IMEM mismatch has already bitten.** The RTL arithmetic is unambiguous
   (§2b) but I found no bench evidence either way. The `hello` testcode is far below 16 KB, so it
   would not show.
4. **Whether `sw_access: rwx` in the YAML produces any write-gating RTL.** I traced the address map
   and the memory model, but did not read the generated interconnect to confirm that `sw_access` is
   metadata only. Both write paths (§2c, §2d) are asserted on the address map plus a writable memory
   model; if the interconnect turns out to gate on `sw_access`, `imem_0` is `rwx` anyway
   (`sys_desc/subsystems/cpu/nanosoc_ss_cpu.yaml:200`), so the conclusion does not change.
5. **A stale comment worth not trusting.** `nanosoc_vivado_wrapper.v:46-49` claims "the UART2 RXD input
   path stops at the pin mux (uart2_rxd is derived from an internal feedback, not from the pads), so
   the SoC-side UART is transmit-only." That was fixed: `nanosoc_pin_mux.v:68-81` and `:149-167`
   document the removal of the feedback network, `:110` now reads `uart2_rxd = p1_in[4]`, and
   `nanosoc_ss_hostio4.v:214` passes the real pad through in FT1248 mode. **I trust the RTL — UART2 RX
   works in FT1248 mode.** Do not copy that comment into the HAPS-SX wrapper.
