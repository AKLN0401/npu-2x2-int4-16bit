![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# int4 NPU — Tiny Tapeout TTSKY26d (SKY130, 1×1 tile)

A 2×2 int4 multiply-accumulate array with 16-bit accumulators, one clock gate per row and a full scan chain
(96 flops), driven by a host microcontroller over a byte-wide register bus on the pins. Top module
`tt_um_akln0401_npu`, 50 MHz.

- Datasheet (how it works, register map, protocol, how to test, scan chain map): [docs/info.md](docs/info.md)
- Project page with layout images and signoff numbers: `docs/overview.html` (self-contained, open locally)

## Layout

| Path | Contents |
|---|---|
| `info.yaml` | TT metadata: top module, tile size, clock, sources, pinout |
| `src/` | `project.v` (top, pin register bus, scan, reset sync), `npu_array.v`, `npu_pe.v`, `dft/clk_gate.v` (ICG wrapper); `config.json` + `base.sdc` (flow config) |
| `test/` | cocotb tests through the pins (RTL and gate level); `scan_map.py` prints the scan chain map |
| `test/extra/` | archived harnesses: RTL-vs-netlist co-simulation and SDF gate-level sims |
| `tools/` | local helpers: container image, sims, hardening, precheck, layout renders |

## Running the tests

```bash
cd test
make                 # RTL (cocotb 2.1 + Icarus, see requirements.txt)
make GATES=yes       # gate level, needs gate_level_netlist.v and PDK_ROOT
```

## Pre-submission signoff (local, LibreLane 3.0.14, same flow as the `gds` action)

DRC 0, LVS 0, antenna 0, utilization 84.4%, setup +5.70 ns / hold +0.162 ns across 12 corners (−40…100 °C),
TT precheck 15/15, RTL and GL tests 8/8, SDF GL tests 8/8 at 4 corners, RTL-vs-netlist co-simulation 26M cycles
with 0 mismatches.
