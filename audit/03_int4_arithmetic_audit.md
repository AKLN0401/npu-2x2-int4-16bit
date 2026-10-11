# 03 — INT4 arithmetic audit

## 1. Intended semantics (from `docs/info.md` and the `src/project.v` header)

    one step:  acc[i][j] += a[i] * b[j]   for every enabled row i, every column j
    a, b:      signed int4, two's complement, -8..7
    acc:       signed 16-bit, wraps modulo 2^16 (no saturation)
    read:      acc sign-extended to 32 bit, byte RSEL[5:4] of lane RSEL[3:0], lane = 2*i + j
    clear:     all four accumulators -> 0 (also during reset); clear + step in one write = clear only

## 2. RTL implementation, line by line (`src/npu_pe.v`, `src/npu_array.v`, `src/project.v`)

| Item | RTL | Width/sign analysis | Verdict |
|---|---|---|---|
| Operand ports | `input wire signed [DW-1:0] a, b` (DW = 4) | slices `a[DW*i +: DW]` of unsigned regs connected to signed ports: the bits are reinterpreted as signed. Correct | OK |
| Product | `wire signed [2*DW-1:0] prod = a * b;` | both operands signed → signed multiply; context width 8 (LHS), operands sign-extended to 8 first. Range [-56, 64]; 64 = 0x40 fits a signed 8-bit result (max +127). No truncation | OK |
| Extension | `{{(ACC_W-2*DW){prod[2*DW-1]}}, prod}` | sign-extend 8 → 16 by replicating bit 7. Concatenation is unsigned, `acc` is signed: the addition is evaluated as unsigned 16-bit, which is bit-identical for two's-complement modular addition | OK |
| Accumulate | `acc <= acc + ext` | 16 + 16 → 16 (LHS width), carry discarded = wrap mod 2^16 | OK, matches spec |
| Priority | `scan_en > clear > step > hold` | clear beats step: documented | OK |
| Step gating | PE `step = step && row_en[i]`; array `step = step_q && !scan_en` | disabled rows hold even with clocks forced on (test mode) | OK |
| Clock gating | ICG `en = (step && row_en[i]) || clear`, `test_en = test_mode` | gclk pulses exactly when a PE may change (or always in test mode). Proven: the PE only changes when step/clear/scan_en (formal, §5), and scan_en ⇒ test_mode | OK |
| Lane mapping | PE(i,j) gets `a[i]`, `b[j]`, output at `acc[ACC_W*(COLS*i+j)]` | lane = 2i + j, as documented | OK |
| Read-back | `acc_sel = idx < 4 ? acc[16*idx +: 16] : 0`; `acc_ext = {16{acc_sel[15]}, acc_sel}`; `uo = acc_ext[8*rsel[5:4] +: 8]` | out-of-range part-select guarded; sign extension correct | OK |
| Reset/clear | `clear = clear_q || !rstn`; `clear_q` resets to 1 | accumulators clear during reset and once more after release, provided clk runs during reset | OK (AS-3) |
| Overflow bound | max |product| = 64, 511 × 64 = 32,704 ≤ 32,767 | "511 steps can never overflow" in docs: correct (512 × 64 = 32,768 overflows) | OK |

No signedness, width or truncation errors were found.

## 3. Independent reference model (`tests/audit_arith.py`, class `Ref`)

- Operands decoded from 4-bit codes with `code - 16 if code >= 8`. It doesn't reuse the testbench's `s4()`.
- The model keeps the **exact, unbounded mathematical sum** since the last clear. The 16-bit register value is derived
  only at compare time: `r = total mod 2^16; r -= 2^16 if r >= 2^15`. The expected 32-bit read is `r & 0xFFFFFFFF`.
  Because the wrap is applied only once, at compare time, the model can't share an incremental-wrap bug with the RTL.
- Host driver written from the datasheet (own `wr()`, random strobe phase, minimum hold 4 / gap 2), pins only.
  The same file runs on RTL and on the post-PnR netlist.

## 4. Tests and results

Run on RTL (Icarus 12, `-DSIM`) at seeds 1, 2, 3 and on the post-PnR netlist (`runs/wokwi/final/pnl`, sky130
functional models, unit delay) at seeds 1, 2. **All 9 tests pass in all 5 runs.** Logs:
`npu1x1/runs/audit/sim/audit_{rtl,gl}_seed*.log/.xml`, rerun by `run_pre_tapeout_audit.sh`.

| Test | Covers (brief item) | Result |
|---|---|---|
| t01 exhaustive_operand_pairs | (1) all 16×16 pairs on **each of the 4 PE instances**: a1 = 5x+3, b1 = 11y+6 (mod 16) are bijections, so every PE sees all 256 pairs and the 4 lanes always differ; each check reads all 4 bytes (32-bit sign extension) of all 4 lanes; per-lane pair coverage asserted = 256 | PASS |
| t02 exact_overflow_boundaries | (3)(4) 511 × 64 = 32,704; +49 +14 → exactly +32,767; +1 → −32,768; −1 → +32,767; 585 × (−56) = −32,760; −8 → exactly −32,768; −56 wraps; 2,099 × 64 with checks at 512, 1023, 1024, 1025, 2048 (multiple wraps) | PASS |
| t03 alternating_and_random_long | (2)(5)(13) 64 strictly alternating-sign steps; 1,500 steps, operands 50% from {−8,−7,−1,0,1,7}; random ROWEN; random-phase min-timing writes; interleaved reads repeated (reads don't disturb) | PASS |
| t04 zero_clear_restart | (6)(7)(11) all-zero, one-zero operand cases, operand writes alone, clear, clear+step, 5 consecutive operations without reset, back-to-back steps | PASS |
| t05 reset_cases | (12) reset idle; 12 × reset asserted at a random ps offset inside a step write; ID, A=B=0 and first operation after reset | PASS |
| t06 lane_isolation_and_read_port | (8)(9) distinct per-lane values under masks 01/10/00/11; lanes 4..15 read 0; RSEL[6] ignored; ID uses RSEL[1:0] only | PASS |
| t07 matmul_reference | (10) C = A·B for K = 1, 2, 3, 8, 64, 511 vs a Python triple loop; 4×4 = (4×8)(8×4) by host tiling into four 2×2 tiles | PASS |
| t08 auto_step_and_write_counting | auto mode steps on B1 with the new B; CTRL write clears auto; 200-clock strobe = one step | PASS |
| t09 strobe_high_across_reset | characterisation: a strobe high at reset release performs one write (see R-03) | PASS (behaviour pinned) |

Brief item 13 (valid/ready, backpressure, pipeline): **NOT APPLICABLE**. There is no handshake or pipeline.
The equivalent checks are the strobe protocol (random phase, minimum timing, long strobe, garbage on the bus between writes)
in t03/t08 and in `test/test.py::test_write_protocol`.

### Mutation check (the suite can fail)

6 RTL mutants, each run against the full suite (`tests/mutants.sh`, `npu1x1/runs/audit/sim/mutants.summary`):

| Mutant | Effect | Tests failing |
|---|---|---|
| m1 unsigned multiply | `$unsigned(a) * $unsigned(b)` | 8 / 9 |
| m2 zero-extend product | product not sign-extended | 8 / 9 |
| m3 saturate | saturating instead of wrapping add | 1 / 9 (t02) |
| m4 lane swap row 1 | row 1 gets b[1-j] | 7 / 9 |
| m5 read zero-extend | read port zero-extends | 8 / 9 |
| m6 sext from bit 6 | wrong sign bit for the extension | 6 / 9 |

All 6 killed. Saturation is only caught by the boundary test, which shows why t02 is needed: the existing
`test.py` checks wrap only at its "safe+2" point.

## 5. Formal proof (unbounded)

`formal/pe.sby` + `formal/pe_props.sv`, SymbiYosys in the LibreLane 3.0.14 image, engine `abc pdr`. No SMT
solver is installed, so `smtbmc` and cover tasks are unavailable.

Property, checked on every clock with `acc` starting **unconstrained** (so it covers all 2^16 accumulator states ×
all 256 operand pairs × every control combination):

    scan_en  ⇒ acc' = {acc[14:0], scan_in}
    else clear ⇒ acc' = 0
    else step  ⇒ acc' = acc + ref_prod      ref_prod = (sext16(a) * sext16(b))[15:0]   (independent formulation)
    else       ⇒ acc' = acc
    always     scan_out = acc[15]

Result: **PASS** (property proved, 2.9 s). The control task with the zero-extension mutant: **FAIL**, as
required. So the proof is not vacuous. sby reports the mutant task as `ERROR rc=16` only because it can't
write a counterexample trace without an SMT solver.

## 6. RTL ↔ silicon netlist

The arithmetic proven in RTL is carried to the post-PnR netlist by the formal equivalence in `05_physical_signoff.md`
§6 (98 state bits, all outputs, ICG enables), by the GL runs above and by the earlier random co-simulation.

## 7. Conclusions

- Operand encoding: signed two's complement, verified.
- Product width 8 bits signed, correct for the full range including (−8)(−8) = +64.
- Accumulator: 16-bit signed, wraps modulo 2^16, verified at both exact boundaries and across multiple wraps.
- Output conversion: sign extension to 32 bits, verified on every byte of every lane for all 256 pairs.
- No arithmetic defect found. Residual risk: none identified in function. Silicon defects (manufacturing) are
  covered by the scan chain on the bench, not by this audit.
