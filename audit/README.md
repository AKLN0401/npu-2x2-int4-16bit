# Pre-tapeout audit (2026-10-11)

Independent signoff review of this design for TTSKY26d. Start with `00_executive_summary.md`; `10_signoff_checklist.md`
lists every item with its status and evidence, `11_power_clock_gating.md` has the vector-based power results.

- `run_pre_tapeout_audit.sh`: reruns every automated check (lint, both cocotb suites RTL + GL, mutation check, formal
  PE proof, formal RTL ≡ post-PnR netlist, STA spot checks, signoff metrics, precheck, CI artifact vs local build,
  GDS XOR, docs check) and writes `results/results.json`. Needs a local hardening run in `runs/wokwi`
  (`tools/harden.sh`), the tools image, the LibreLane 3.0.14 image and the sky130 PDK (see the script header).
- `tests/`, `formal/`, `equiv/`, `sta/`, `power/`: the harnesses used by the script and the documents.
- `logs/`: raw evidence of the audit runs (local paths shortened to `~` / `<npu1x1>`).

The audit was written for the working copy at `~/tinytapeout/npu1x1`; paths like `npu1x1/runs/audit/...` in the
documents refer to generated, gitignored run directories.
