# SPDX-FileCopyrightText: © 2026 AKLN0401
# SPDX-License-Identifier: Apache-2.0
"""cocotb tests for tt_um_akln0401_npu, through the pins only, so they run unchanged at
gate level (GATES=yes). The array size is read from the ID bytes. Written for cocotb 2.x
(TT CI); RTL also runs on 1.9 (positional time units, no signal bit indexing)."""

import os
import random
import re

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from scan_map import chain, from_bits, to_bits

# Keep in sync with CLOCK_PERIOD in src/config.json and clock_hz in info.yaml
CLK_HZ = 50_000_000
CLK_PS = round(1e12 / CLK_HZ)  # whole ps: cocotb 2 Timer/Clock reject unrepresentable times

GL = os.environ.get("GATES") == "yes"

A0, A1, B0, B1, CTRL, ROWEN, RSEL = range(7)
CTRL_CLEAR, CTRL_STEP, CTRL_AUTO = 1, 2, 4

STROBE, TEST_MODE, SCAN_EN, SCAN_IN = 1 << 3, 1 << 4, 1 << 5, 1 << 6


def s4(x):
    return (x & 0xF) - 16 if x & 0x8 else x & 0xF


def pack(vals, nbytes):
    """Signed int4 list -> list of register bytes, two nibbles per byte (low nibble first)."""
    v = 0
    for k, x in enumerate(vals):
        v |= (x & 0xF) << (4 * k)
    return [(v >> (8 * k)) & 0xFF for k in range(nbytes)]


class Npu:
    """Pin-level host driver plus a Python reference model of the accumulators."""

    def __init__(self, dut):
        self.dut = dut
        self.uio = 0
        self.rows = self.cols = self.acc_w = None

    def _drive(self):
        self.dut.uio_in.value = self.uio

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, CLK_PS, "ps").start())
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.uio = 0
        self._drive()
        await self.reset()
        assert await self.rd(RSEL, 0x80) == 0x4E, "ID byte 0"
        rc = await self.rd(RSEL, 0x81)
        self.rows, self.cols = rc >> 4, rc & 0xF
        self.acc_w = await self.rd(RSEL, 0x82)
        assert await self.rd(RSEL, 0x83) == 0x01, "ID byte 3 (version)"
        assert 1 <= self.rows <= 4 and 1 <= self.cols <= 4 and self.rows * self.cols <= 16
        self.acc = [[0] * self.cols for _ in range(self.rows)]
        self.dut._log.info(f"NPU {self.rows}x{self.cols}, ACC_W {self.acc_w}")

    async def reset(self, cycles=10):
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, cycles)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 5)
        if self.acc_w:
            self.acc = [[0] * self.cols for _ in range(self.rows)]

    # ---- register bus -------------------------------------------------------------
    async def wr(self, addr, data, hold=4, gap=2, phase_ps=None):
        """One write: address and data change with the strobe rise, held `hold` clocks."""
        await FallingEdge(self.dut.clk)
        if phase_ps is not None:
            await Timer(phase_ps, "ps")  # host is asynchronous: any phase
        self.uio = (self.uio & ~0x0F) | (addr & 7) | STROBE
        self.dut.ui_in.value = data & 0xFF
        self._drive()
        await ClockCycles(self.dut.clk, hold, False)
        self.uio &= ~STROBE
        self._drive()
        await ClockCycles(self.dut.clk, gap, False)

    async def rd(self, sel_addr, sel):
        """Write a select register, then return uo_out."""
        await self.wr(sel_addr, sel)
        return int(self.dut.uo_out.value)

    async def read_acc(self, i, j):
        v = 0
        for byte in range(4):
            v |= await self.rd(RSEL, (byte << 4) | (self.cols * i + j)) << (8 * byte)
        return v - (1 << 32) if v & 0x80000000 else v

    # ---- operations + reference model ---------------------------------------------------
    def wrap(self, v):
        v &= (1 << self.acc_w) - 1
        return v - (1 << self.acc_w) if v >> (self.acc_w - 1) else v

    async def set_a(self, a):
        for k, byte in enumerate(pack(a, (self.rows + 1) // 2)):
            await self.wr(A0 + k, byte)
        self.a = list(a)

    async def set_b(self, b, last_steps=False):
        """Write B0 (and B1). With last_steps the B1 write is the auto-step trigger."""
        bytes_ = pack(b, 2 if last_steps else (self.cols + 1) // 2)
        for k, byte in enumerate(bytes_):
            await self.wr(B0 + k, byte)
        self.b = list(b)

    def ref_step(self, row_en=None):
        row_en = (1 << self.rows) - 1 if row_en is None else row_en
        for i in range(self.rows):
            if row_en >> i & 1:
                for j in range(self.cols):
                    self.acc[i][j] = self.wrap(self.acc[i][j] + s4(self.a[i]) * s4(self.b[j]))

    async def step(self, row_en=None):
        await self.wr(CTRL, CTRL_STEP)
        self.ref_step(row_en)

    async def clear(self):
        await self.wr(CTRL, CTRL_CLEAR)
        self.acc = [[0] * self.cols for _ in range(self.rows)]

    async def check(self, what):
        for i in range(self.rows):
            for j in range(self.cols):
                got = await self.read_acc(i, j)
                assert got == self.acc[i][j], f"{what}: acc[{i}][{j}] = {got}, expected {self.acc[i][j]}"

    def rand4(self, n):
        return [random.randint(-8, 7) for _ in range(n)]

    # ---- scan ---------------------------------------------------------------------------
    async def scan(self, image=None):
        """Enter test mode, shift the whole chain once, leave test mode. Returns the
        captured chain image (by position, scan_in side first) and loads `image`."""
        n = len(chain(self.rows, self.cols, self.acc_w))
        image = image or [0] * n
        return (await self.shift(image[::-1]))[::-1]   # last position goes in first

    async def shift(self, bits_in):
        """Shift len(bits_in) bits in test mode; returns scan_out sampled before each shift."""
        out = []
        await FallingEdge(self.dut.clk)
        self.uio = (self.uio & ~0x7F) | TEST_MODE | SCAN_EN
        for b in bits_in:
            self.uio = (self.uio & ~SCAN_IN) | (b << 6)
            self._drive()
            await Timer(CLK_PS // 4, "ps")
            out.append(int(self.dut.uio_out.value) >> 7 & 1)
            await FallingEdge(self.dut.clk)
        self.uio &= ~(TEST_MODE | SCAN_EN | SCAN_IN)
        self._drive()
        await ClockCycles(self.dut.clk, 2, False)
        return out


def row_gclk(dut, i):
    """Row i's gated clock: the RTL net, or the GCLK pin of the ICG cell in the netlist."""
    if not GL:
        return dut.user_project.i_array.g_row[i].gclk
    # The ICG keeps its (escaped) instance name through synthesis; take the net on its GCLK
    # pin from the netlist text, then find that net by iterating (cell pins are not visible
    # through the sky130 models, and cocotb parses "[i]" in a handle name as an index)
    icg = f"i_array.g_row[{i}].i_cg.icg"
    with open(os.path.join(os.path.dirname(__file__), "gate_level_netlist.v")) as f:
        m = re.search(r"dlclkp_\d+\s+\\" + re.escape(icg) + r"\s*\((.*?)\);", f.read(), re.S)
    assert m, f"ICG {icg} not found in the netlist"
    net = re.search(r"\.GCLK\(\s*\\?([^\s)]+)", m.group(1)).group(1)
    for h in dut.user_project:
        if h._name == net:
            return h
    raise AssertionError(f"gated clock net {net} of {icg} not found (needs cocotb 2.x at gate level)")


async def start(dut):
    npu = Npu(dut)
    await npu.start()
    return npu


@cocotb.test()
async def test_reset_and_id(dut):
    """ID bytes, reset values, pin directions; reset in the middle of a computation."""
    npu = await start(dut)
    assert int(dut.uio_oe.value) == 0x80
    assert int(dut.uio_out.value) == 0, "uio[7] (scan_out) must be 0 outside test mode"
    await npu.check("after reset")

    # Change every register, then reset: accumulators, A/B, ROWEN, auto and RSEL go back
    await npu.set_a(npu.rand4(npu.rows))
    await npu.set_b(npu.rand4(npu.cols))
    await npu.step()
    await npu.wr(ROWEN, 0)
    await npu.wr(CTRL, CTRL_AUTO)
    await npu.wr(RSEL, 0x81)
    await npu.reset()
    assert int(dut.uo_out.value) == 0, "RSEL resets to 0 (acc[0][0] byte 0)"
    await npu.check("after mid-run reset")
    npu.a, npu.b = [0] * npu.rows, [0] * npu.cols
    await npu.step()                    # A = B = 0 after reset: adds nothing
    await npu.check("A/B reset to 0")
    await npu.set_a([1] * npu.rows)
    await npu.set_b([1] * npu.cols)
    await npu.wr(B1, pack([1] * npu.cols, 2)[1])   # auto is off after reset: no step
    await npu.check("auto reset to 0")
    await npu.step()                    # ROWEN back to all rows
    await npu.check("ROWEN reset to all rows")


@cocotb.test()
async def test_matmul_random(dut):
    """Random int4 matrix products C = A*B (inner dimension K) against Python."""
    npu = await start(dut)
    for trial in range(8):
        k = random.randint(1, 31)
        await npu.clear()
        for _ in range(k):
            await npu.set_a(npu.rand4(npu.rows))
            await npu.set_b(npu.rand4(npu.cols))
            await npu.step()
        await npu.check(f"trial {trial}, K={k}")


@cocotb.test()
async def test_worst_case_and_wrap(dut):
    """-8*-8 every step: no overflow up to (2^(ACC_W-1)-1)//64 steps, then two's-complement wrap."""
    npu = await start(dut)
    await npu.set_a([-8] * npu.rows)
    await npu.set_b([-8] * npu.cols)
    safe = ((1 << (npu.acc_w - 1)) - 1) // 64
    for _ in range(safe):
        await npu.step()
    assert npu.acc[0][0] == 64 * safe
    await npu.check(f"{safe} worst-case steps")
    for _ in range(2):
        await npu.step()
    assert npu.acc[0][0] < 0, "reference model should have wrapped"
    await npu.check("wrapped")
    await npu.set_a([-8] * npu.rows)
    await npu.set_b([7] * npu.cols)     # most negative product
    await npu.clear()
    for _ in range(safe + 2):
        await npu.step()
    await npu.check("negative wrap")


@cocotb.test()
async def test_auto_step(dut):
    """CTRL.auto: a B1 write also steps, with the B bytes written in that same write."""
    npu = await start(dut)
    await npu.wr(CTRL, CTRL_AUTO)
    for _ in range(6):
        await npu.set_a(npu.rand4(npu.rows))
        await npu.set_b(npu.rand4(npu.cols), last_steps=True)
        npu.ref_step()
    await npu.check("auto-step")
    await npu.wr(CTRL, 0)
    await npu.wr(B1, 0x77)
    if npu.cols > 2:
        npu.b[2:4] = [7, 7][: npu.cols - 2]
    await npu.check("auto off: B1 does not step")
    await npu.step()
    await npu.check("explicit step after auto off")


@cocotb.test()
async def test_clear(dut):
    """Clear; clear and step in the same CTRL write only clears."""
    npu = await start(dut)
    await npu.set_a(npu.rand4(npu.rows))
    await npu.set_b(npu.rand4(npu.cols))
    for _ in range(3):
        await npu.step()
    await npu.wr(CTRL, CTRL_CLEAR | CTRL_STEP)
    npu.acc = [[0] * npu.cols for _ in range(npu.rows)]
    await npu.check("clear + step")
    await npu.step()
    await npu.check("one step after clear")


@cocotb.test()
async def test_row_enable_and_clock_gating(dut):
    """ROWEN: disabled rows hold, also in test mode (clocks forced on). Count the edges of
    each row's gated clock (RTL net / ICG cell output at gate level): one per step on
    enabled rows, none on disabled rows."""
    npu = await start(dut)
    edges = [0] * npu.rows

    async def count(i, gclk):
        while True:
            await RisingEdge(gclk)
            edges[i] += 1

    for i in range(npu.rows):
        cocotb.start_soon(count(i, row_gclk(dut, i)))

    for mask in list(range(1, 1 << npu.rows)) + [0]:
        await npu.wr(ROWEN, mask)
        before = list(edges)
        steps = 3
        for _ in range(steps):
            await npu.set_a(npu.rand4(npu.rows))
            await npu.set_b(npu.rand4(npu.cols))
            await npu.step(mask)
        await npu.check(f"ROWEN {mask:#x}")
        for i in range(npu.rows):
            want = steps if mask >> i & 1 else 0
            assert edges[i] - before[i] == want, \
                f"ROWEN {mask:#x}: row {i} clock had {edges[i] - before[i]} edges, expected {want}"

    # Test mode without scan_en: row clocks forced on, a disabled row must still hold
    await npu.wr(ROWEN, 1)
    npu.uio |= TEST_MODE
    await npu.set_a(npu.rand4(npu.rows))
    await npu.set_b(npu.rand4(npu.cols))
    before = list(edges)
    await npu.step(1)
    await ClockCycles(dut.clk, 10)
    assert all(edges[i] - before[i] > 10 for i in range(npu.rows)), "test mode forces row clocks on"
    npu.uio &= ~TEST_MODE
    npu._drive()
    await npu.check("ROWEN in test mode")


@cocotb.test()
async def test_write_protocol(dut):
    """Asynchronous strobe at any phase, minimum hold/gap, garbage on the bus between
    writes, and a long strobe giving exactly one write."""
    npu = await start(dut)
    for n in range(20):
        a, b = npu.rand4(npu.rows), npu.rand4(npu.cols)
        for k, byte in enumerate(pack(a, (npu.rows + 1) // 2)):
            await npu.wr(A0 + k, byte, phase_ps=random.randrange(CLK_PS))
            dut.ui_in.value = random.randint(0, 255)          # bus changes once the strobe is low
            npu.uio = (npu.uio & ~7) | random.randint(0, 7)
            npu._drive()
        for k, byte in enumerate(pack(b, (npu.cols + 1) // 2)):
            await npu.wr(B0 + k, byte, phase_ps=random.randrange(CLK_PS))
        npu.a, npu.b = a, b
        await npu.wr(CTRL, CTRL_STEP, phase_ps=random.randrange(CLK_PS))
        npu.ref_step()
    await npu.check("random-phase writes")

    # Strobe held for 100 clocks with auto on: exactly one step
    await npu.wr(CTRL, CTRL_AUTO)
    await npu.wr(B1, pack(npu.b, 2)[1], hold=100)
    npu.ref_step()
    await npu.wr(CTRL, 0)
    await npu.check("long strobe = one write")


@cocotb.test()
async def test_scan_chain(dut):
    """Shift through the whole chain: length, capture of every field at its mapped position,
    and a loaded state that the design then computes with."""
    npu = await start(dut)
    rows, cols, acc_w = npu.rows, npu.cols, npu.acc_w
    n = len(chain(rows, cols, acc_w))
    dut._log.info(f"scan chain: {n} flops")

    # 1. Length: a random pattern comes back out after exactly n shifts (staying in shift
    #    mode: a functional clock in between would rewrite wr_sync / step_q / clear_q)
    pat = [random.randint(0, 1) for _ in range(n)]
    out = await npu.shift(pat + [0] * n)
    assert out[n:] == pat, f"pattern did not come back after {n} shifts"
    assert out[n - 1:-1] != pat or pat == pat[1:] + pat[:1], "chain is shorter than the map"

    # 2. Capture: set a known functional state, shift it out, decode with the map
    await npu.reset()
    a, b = npu.rand4(rows), npu.rand4(cols)
    await npu.set_a(a)
    await npu.set_b(b)
    await npu.step()
    await npu.wr(CTRL, CTRL_AUTO)
    row_en = random.randint(1, (1 << rows) - 1)
    await npu.wr(ROWEN, row_en)
    rsel = random.choice([0x00, 0x15, 0x2A, 0x83]) & 0xBF
    await npu.wr(RSEL, rsel)
    # strobe held high on the reserved address -> wr_sync = 111 when captured
    await FallingEdge(dut.clk)
    npu.uio = (npu.uio & ~7) | 7 | STROBE
    npu._drive()
    await ClockCycles(dut.clk, 5, False)
    got = from_bits(rows, cols, acc_w, await npu.scan())
    npu.uio &= ~(STROBE | 7)
    npu._drive()
    want = {"wr_sync": 7, "a_reg": int.from_bytes(bytes(pack(a, 2)), "little") & ((1 << 4 * rows) - 1),
            "b_reg": int.from_bytes(bytes(pack(b, 2)), "little") & ((1 << 4 * cols) - 1),
            "auto": 1, "row_en": row_en, "rsel": rsel, "step_q": 0, "clear_q": 0}
    for i in range(rows):
        for j in range(cols):
            want[f"acc[{i}][{j}]"] = npu.acc[i][j] & ((1 << acc_w) - 1)
    assert got == want, f"captured {got}\nexpected {want}"

    # 3. Load: random accumulators, operands, ROWEN, auto, RSEL; then compute with them
    acc = [[random.randint(-(1 << acc_w - 2), (1 << acc_w - 2) - 1) for _ in range(cols)] for _ in range(rows)]
    a, b = npu.rand4(rows), npu.rand4(cols)
    row_en = random.randint(1, (1 << rows) - 1)
    idx = random.randrange(rows * cols)
    fields = {"a_reg": int.from_bytes(bytes(pack(a, 2)), "little") & ((1 << 4 * rows) - 1),
              "b_reg": int.from_bytes(bytes(pack(b, 2)), "little") & ((1 << 4 * cols) - 1),
              "auto": 1, "row_en": row_en, "rsel": idx}
    for i in range(rows):
        for j in range(cols):
            fields[f"acc[{i}][{j}]"] = acc[i][j] & ((1 << acc_w) - 1)
    await npu.scan(to_bits(rows, cols, acc_w, fields))
    assert int(dut.uo_out.value) == acc[idx // cols][idx % cols] & 0xFF, "loaded RSEL / accumulator"
    npu.acc, npu.a, npu.b = acc, a, b
    await npu.wr(B1, pack(b, 2)[1])     # loaded auto = 1: this write steps (B unchanged)
    npu.ref_step(row_en)
    await npu.wr(ROWEN, (1 << rows) - 1)
    await npu.check("computed from a scan-loaded state")
