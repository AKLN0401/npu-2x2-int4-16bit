# 00 — Executive summary: pre-tapeout audit of `tt_um_akln0401_npu` (TTSKY26d)

Audit date 2026-10-11 · revision `npu1x1` `main` @ `ce832bb` · signed-off build: GitHub gds run 38113024258.

## Recommendation: **CONDITIONAL**, ready for final human review once two owner decisions are closed

The design passed every functional, arithmetic, integration, timing and physical check that could be run here,
and it has evidence for every mandatory shuttle requirement except the submission itself. There are no technical
blockers. The open items are decisions or actions that belong to you.

| # | Must close before submitting | Why |
|---|---|---|
| 1 | **Confirm the spec**: the chip has **4 accumulators of 16 bits** (2×2 PEs, int4 operands), not "16 INT4 accumulators" | If 16 accumulators were intended, the design doesn't meet the spec. A 4×4 array doesn't fit 1×1. (R-01) |
| 2 | **Decide on the doc fix**: merge branch `audit/host-protocol-docs` (datasheet host rules + CI arithmetic tests), push, get a green gds run, rerun `run_pre_tapeout_audit.sh` | The datasheet currently allows a strobe/data ordering that a MicroPython host gets wrong (stale writes), and it doesn't say test pins must be driven low. That's a bench risk, not a silicon one. (R-02–R-04) |
| 3 | Check the live page app.tinytapeout.com/shuttles/ttsky26d (cutoff time, fields), then **submit** | The page couldn't be read here; the project isn't in the shuttle yet. (R-11/12) |

## What was proven (evidence in 02–05, scripted in `run_pre_tapeout_audit.sh` → 35 PASS / 1 WARN / 0 FAIL)

- **Arithmetic:** signed int4 × int4 → 8-bit product, sign-extended, 16-bit wrapping accumulate, 32-bit
  sign-extended read-back. Checked as follows:
  - all 256 operand pairs on each of the 4 PEs at RTL and gate level;
  - exact ±32767/−32768 boundaries both ways, multiple wraps, K = 511 matmul and a tiled 4×4 matmul, all against
    an independent model;
  - an **unbounded formal proof** of the PE (all 2¹⁶ states × 256 pairs).
  - The suite kills 6/6 deliberate arithmetic mutants.
- **RTL ≡ silicon netlist:** formal induction over all 98 flops, all outputs and both clock-gate enables (non-vacuous).
  Plus 4M new random lock-step cycles, SDF-annotated sims at the slow-cold and fast corners, and GL runs of both
  test suites.
- **Timing:** 12 corners including the cold-slow ss_n40C (sky130 is slower cold at 1.6 V). Setup +5.70 ns,
  hold +0.162 ns, 0 violations. Clock-gating checks ≥ +0.70 ns hold / +13.6 ns setup. No unconstrained
  endpoints. Only 2 false paths, both on static DFT pins and justified.
- **Physical:** Magic DRC 0, KLayout DRC clean (precheck), LVS "circuits match uniquely", antenna 0, route DRC 0,
  TT precheck 15/15. 84.4% utilization in the 161 × 111.52 µm tile.
- **Shuttle fit:** sky130A with open_pdks 8afc8346 matches the TTSKY26d `librelane.txt`. LibreLane 3.0.14 runs through
  `tt-gds-action@ttsky26d`, with the template workflows byte-identical. Deadline 2026-11-30 per `config.yaml`
  and the website. Production and staging shuttle repos are identical on everything relevant.
- **Artifact integrity:** the CI `tt_submission` artifact is built from HEAD. Its netlist is bit-identical to the
  signoff netlist, all 371 metrics are equal, and the GDS XOR shows 0 differences.

## Most important residual risks (all LOW unless stated)

1. Bench host behaviour (MEDIUM until the doc branch is merged): stale-data writes if the strobe precedes the
   data, floating test pins, strobe high during reset.
2. 10 max-slew pins at ss_n40C (0.84 vs 0.75 ns), off the critical paths, already included in timing.
3. What can't be checked before silicon: TT mux/pad behaviour, real clock quality, manufacturing defects.
   The 96-flop scan chain is the bench tool for the last one.
4. Power (vector-based estimate, `11`): 191–308 µW at tt depending on workload. **Clock gating saves 45–59%** (≈ 0.25–0.27 mW at tt), confirmed on the bench only once silicon arrives.

## What this audit did NOT do

No push, no submission, no RTL or constraint change, no re-harden (none was needed: the branch doesn't touch
`src/`, `info.yaml` or the config). No SMT solver was available (formal used ABC PDR and yosys SAT). Icarus
doesn't evaluate timing checks, so STA is the timing signoff.

## Documents

`01` architecture · `02` verification plan · `03` int4 arithmetic · `04` synthesis & timing · `05` physical
signoff · `06` TT compliance · `07` bug & risk register · `08` release manifest · `09` TTSKY26d compliance ·
`10` signoff checklist · `11` power & clock-gating saving · `run_pre_tapeout_audit.sh` · `results/results.json` · `logs/`.
