# 01 — Repository and architecture

Audit date 2026-10-11. Audited revision: `npu1x1` `main` @ `ce832bbafac3472bc7360173b35ae52156fc60fa`
(= `origin/main`, https://github.com/AKLN0401/npu-2x2-int4-16bit), clean working tree.
"Verified" means checked against source, netlist or tool output in this audit; "inferred" means reasoned, not measured.

## 1. Which design is the submission

The workspace holds two designs:

| Path | Design | Role |
|---|---|---|
| `~/tinytapeout/` (repo root) | 6×2-tile TinyQV RISC-V + 4×4 NPU row macros, 38 MHz | project/portfolio design, **not submitted** (`MEMORY.md` "Current Focus") |
| `~/tinytapeout/npu1x1/` (own git repo) | 1×1-tile 2×2 int4 NPU, 16-bit accumulators, 50 MHz | **the TTSKY26d submission** (`npu1x1_MEMORY.md`) |

This audit covers `npu1x1` only.

**Spec discrepancy (verified, needs owner confirmation):** the audit brief says "2×2 NPU with 16 INT4
accumulators". The RTL has **4 accumulators** (one per PE, `NPE = ROWS*COLS = 4`), each **16 bits wide** and
signed (`ACC_W = 16`). Only the operands are int4. "16" is the accumulator width, not the count. The parent 4×4 design is
the one with 16 accumulators. Everything in this audit checks the RTL as written and as documented in
`docs/info.md`. See R-01 in `07_bug_and_risk_register.md`.

## 2. Inventory

| File | Lines | Content |
|---|---|---|
| `src/project.v` | 191 | top `tt_um_akln0401_npu #(ROWS=2, COLS=2, ACC_W=16)`: pin register bus, strobe synchronizer, operand/control registers, reset synchronizer, read mux, scan for the interface state |
| `src/npu_array.v` | 64 | `npu_array`: ROWS×COLS `npu_pe`, one `clk_gate` per row, scan chain through the PEs |
| `src/npu_pe.v` | 40 | `npu_pe`: `acc += a*b` (signed), clear, scan shift |
| `src/dft/clk_gate.v` | 33 | `clk_gate`: `sky130_fd_sc_hd__dlclkp_1` (synthesis) / latch+AND model (`SIM`) |
| `src/config.json`, `src/base.sdc` | | LibreLane config (TT template + documented additions), SDC |
| `info.yaml` | | TT metadata (1x1, 50 MHz, 4 sources, pinout, yaml_version 6) |
| `test/` | | cocotb 2.1 suite `test.py` (8 tests), `scan_map.py`, `tb.v`, `Makefile` |
| `test/extra/` | | archived co-sim and SDF harnesses + results README |
| `docs/info.md`, `docs/overview.html` | | datasheet; self-contained project page (~2 MB) |
| `.github/workflows/` | | `gds`, `test`, `docs`, `fpga` — byte-identical to `ttsky-verilog-template` |

No generated RTL, no `include` files, no macros, no memories, no parameter overrides at the top (the TT flow uses
the defaults 2/2/16). One technology cell is instantiated in RTL: `sky130_fd_sc_hd__dlclkp_1` (ICG).

## 3. Hierarchy

```
tt_um_akln0401_npu                      (src/project.v)
├── rst_sync[1:0]                        2 x dfrtp, async assert / sync release, off the scan chain
├── st[31:0]                             interface state, one mux-D scan vector
└── i_array : npu_array #(2,2,4,16)      (src/npu_array.v)
    ├── g_row[0].i_cg : clk_gate         -> sky130_fd_sc_hd__dlclkp_1
    │   ├── g_col[0].i_pe : npu_pe       acc[0][0]  16 bit
    │   └── g_col[1].i_pe : npu_pe       acc[0][1]  16 bit
    └── g_row[1].i_cg : clk_gate
        ├── g_col[0].i_pe : npu_pe       acc[1][0]
        └── g_col[1].i_pe : npu_pe       acc[1][1]
```

## 4. Block diagram (verified against RTL)

```
 uio[3] strobe ─► wr_sync[0]─►wr_sync[1]─►wr_sync[2]      wr = wr_sync[1] & ~wr_sync[2]  (1-cycle pulse)
 uio[2:0] addr ─────────────────────────┐ (sampled directly when wr=1; host holds it >= 4 clk)
 ui[7:0]  data ─────────────────────────┤
                                        ▼
               ┌──────── register decode (addr 0..6) ────────┐
               │ A0 a_reg[7:0]   B0 b_reg[7:0]   CTRL: clear_q, step_q (1-cycle, registered), auto
               │ ROWEN row_en[1:0] (reset 11)   RSEL rsel[7:0]  (A1/B1 data unused at 2x2; B1 steps if auto)
               └──────────────┬───────────────────────────────┘
       a[i] = a_reg[4i+3:4i]  │ b[j] = b_reg[4j+3:4j]      step = step_q & !scan_en   clear = clear_q | !rstn
                              ▼
   row i:  ICG(en = (step & row_en[i]) | clear,  test_en = test_mode) ─► gclk_i
           PE(i,j) on gclk_i:  scan_en ? shift : clear ? 0 : (step & row_en[i]) ? acc + sext16(a[i]*b[j]) : acc
                              ▼
   read mux: rsel[7] ? ID byte[rsel[1:0]] : byte rsel[5:4] of sext32(acc[rsel[3:0]])  (lanes >= 4 read 0) ─► uo[7:0]
   uio[7] = test_mode & scan_out      uio_oe = 8'b1000_0000      uio_out[6:0] = 0
   scan: uio[6] ─► st[0..31] ─► acc[0][0] .. acc[1][1] (LSB first) ─► uio[7]   (shift while test_mode & uio[5])
```

## 5. Interface table (TT wrapper ports)

| Port | Dir | Function | Verified behaviour |
|---|---|---|---|
| `clk` | in | 50 MHz system clock | only clock; ICGs derive the 2 row clocks |
| `rst_n` | in | active-low reset, asynchronous assert | 2-flop sync (`dfrtp`), release synchronous; clears st (ROWEN←11, clear_q←1) and, via `clear`, all accumulators; **needs clk running during reset** (sync clear of st/accs) |
| `ena` | in | TT "design selected" | unused (`_unused`), allowed by TT |
| `ui_in[7:0]` | in | write data | sampled when `wr`=1 |
| `uo_out[7:0]` | out | read data | combinational from rsel + acc/ID |
| `uio_in[2:0]` | in | register address | sampled when `wr`=1 |
| `uio_in[3]` | in | write strobe | 2-flop synchronizer + rising-edge detect |
| `uio_in[4]` | in | test_mode | forces ICGs on; enables scan_out and scan_en |
| `uio_in[5]` | in | scan_en | ANDed with test_mode |
| `uio_in[6]` | in | scan_in | first chain bit |
| `uio_in[7]` | in | — | unused (pad is an output) |
| `uio_out[7]` | out | scan_out | `test_mode & chain end`, 0 otherwise |
| `uio_out[6:0]` | out | — | tied 0 (14 conb LO cells in netlist) |
| `uio_oe` | out | | constant `0x80` (only uio[7] drives) |

## 6. State elements (verified: netlist has 96 `dfxtp_2` + 2 `dfrtp_2` + 2 `dlclkp_1`, no latches)

| Group | Flops | Reset value | Scan positions |
|---|---|---|---|
| `wr_sync[2:0]` | 3 | 0 | 0–2 |
| `a_reg[7:0]` (a0, a1) | 8 | 0 | 3–10 |
| `b_reg[7:0]` (b0, b1) | 8 | 0 | 11–18 |
| `auto` | 1 | 0 | 19 |
| `row_en[1:0]` | 2 | 11 | 20–21 |
| `rsel[7:0]` | 8 | 0 | 22–29 |
| `step_q`, `clear_q` | 2 | 0, 1 | 30, 31 |
| `acc[0][0] … acc[1][1]` | 4 × 16 | 0 (via clear) | 32–95 |
| `rst_sync[1:0]` | 2 | 0 (async) | off chain |
| **Total** | **98** | | chain 96 |

No FSMs, no counters, no memories, no valid/ready handshake. The only "protocol" is the strobe edge.
The array has no pipeline: a step is applied one cycle after the write pulse (step_q registered) and is
complete at the next gated edge.

## 7. Arithmetic resources (inferred from RTL, consistent with netlist cell count)

4 × (4×4 signed multiplier → 8-bit product, sign-extend to 16, 16-bit adder, 3:1 next-state mux) — one per PE,
no sharing. Physical replication, not time multiplexing. Read path: 4:1 × 16-bit lane mux, sign extension to
32 bit, 4:1 byte mux, 2:1 ID/data mux.

## 8. Latency, throughput, workload

- Write: register updated 2–3 clk after strobe rise (synchronizer), step/clear one clk later.
- Host protocol minimum: strobe high ≥ 4 clk, low ≥ 2 clk → ≥ 6 clk per write. One 2×2 outer-product step
  (4 MACs) = A0 + B0 + CTRL writes (or A0 + B1 with auto), so ≥ 12–18 clk per step from the bus; in practice the
  MicroPython host is µs per write, so throughput is host-bound.
- Workload: `C = A·B` with inner dimension K = K steps; no overflow for K ≤ 511 at worst-case operands.
- Encoding: operands 4-bit two's complement, two per byte (low nibble = index 0); result 16-bit two's complement,
  read sign-extended to 32 bit, 4 byte reads per lane.

## 9. Fit in the tile (verified)

Die 161.00 × 111.52 µm = 1×1 entry of `tt/tech/sky130A/tile_sizes.yaml`; DEF `DIEAREA (0 0) (161000 111520)`.
Std-cell utilization 84.4% (13,922 µm² of 16,493 µm² core), routing DRC 0 after 4 detailed-route iterations,
no congestion overflow reported. Fits, but tight: the 2×3 variant failed detailed placement (`npu1x1_MEMORY.md`).

## 10. Assumptions

| # | Assumption | Status |
|---|---|---|
| AS-1 | Intended arithmetic = signed int4 × int4, 16-bit wrap, as in `docs/info.md` | from repo docs; **owner to confirm vs. the "16 INT4 accumulators" wording** |
| AS-2 | Host keeps addr/data stable ≥ 4 clk and strobe low ≥ 2 clk | documented protocol; untimed at the pins (async interface) |
| AS-3 | Clock runs while `rst_n` is low | TT demo board clocks the project during reset (RP2 SDK); required for the synchronous clears |
| AS-4 | DFT pins static in mission mode, scan done with slow/stopped clock | documented; false-pathed in SDC |
| AS-5 | TT mux/pad behaviour (insertion delay ≤ 10 ns, IO 33/66 MHz) per tinytapeout.com/specs | official docs; not testable pre-silicon |
