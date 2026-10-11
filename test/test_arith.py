# SPDX-License-Identifier: Apache-2.0
"""Independent INT4 arithmetic and control tests for tt_um_akln0401_npu (pre-tapeout audit).

Pin-level only (runs unchanged on RTL and on the post-PnR netlist). Deliberately does NOT reuse
test/test.py: own host driver, own reference model.

Reference model (spec from docs/info.md + src/project.v header):
  * a[i], b[j]: 4-bit two's complement (-8..7)
  * one step: acc[i][j] += a[i]*b[j] for enabled rows i, all columns j
  * acc: 16-bit two's complement, wraps modulo 2^16 (no saturation)
  * read port: acc sign-extended to 32 bit, byte RSEL[5:4] of lane RSEL[3:0] (lane = 2*i + j),
    lanes 4..15 read 0; RSEL[7]=1 selects ID byte RSEL[1:0]
The model keeps the exact (unbounded) mathematical sum since the last clear and applies the
mod-2^16 rule only when comparing, so it cannot share an incremental-wrap bug with the RTL.
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer

CLK_PS = 20_000                     # 50 MHz, info.yaml clock_hz
ROWS = COLS = 2
ACC_W = 16
A0, A1, B0, B1, CTRL, ROWEN, RSEL = range(7)
CLEAR, STEP, AUTO = 1, 2, 4
STROBE = 1 << 3
GL = os.environ.get("GATES") == "yes"


def sx4(code):
    """4-bit code -> signed integer."""
    assert 0 <= code <= 15
    return code - 16 if code >= 8 else code


def code4(v):
    """signed integer -8..7 -> 4-bit code."""
    assert -8 <= v <= 7
    return v + 16 if v < 0 else v


class Ref:
    def __init__(self):
        self.reset()

    def reset(self):
        self.total = [[0] * COLS for _ in range(ROWS)]   # exact sums since last clear
        self.a = [0] * ROWS                               # signed values
        self.b = [0] * COLS
        self.rowen = (1 << ROWS) - 1
        self.auto = False

    def clear(self):
        self.total = [[0] * COLS for _ in range(ROWS)]

    def step(self):
        for i in range(ROWS):
            if (self.rowen >> i) & 1:
                for j in range(COLS):
                    self.total[i][j] += self.a[i] * self.b[j]

    def reg(self, i, j):
        """Signed 16-bit register value: exact sum reduced modulo 2^16."""
        r = self.total[i][j] % (1 << ACC_W)
        return r - (1 << ACC_W) if r >= (1 << (ACC_W - 1)) else r

    def read32(self, i, j):
        return self.reg(i, j) & 0xFFFFFFFF


class Host:
    def __init__(self, dut, rnd):
        self.dut, self.rnd = dut, rnd
        self.uio = 0
        self.ref = Ref()
        self.writes = 0

    def drive(self):
        self.dut.uio_in.value = self.uio

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, CLK_PS, "ps").start())
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.uio = 0
        self.drive()
        await self.reset()
        assert [await self.rd_sel(0x80 | k) for k in range(4)] == [0x4E, 0x22, 0x10, 0x01], "ID"

    async def reset(self, cycles=10):
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, cycles)
        self.dut.rst_n.value = 1
        await ClockCycles(self.dut.clk, 5)
        self.ref.reset()

    async def wr(self, addr, data, hold=4, gap=2, random_phase=True):
        """Spec protocol: addr/data/strobe together, held >= 4 clk, strobe low >= 2 clk."""
        await FallingEdge(self.dut.clk)
        if random_phase:
            await Timer(self.rnd.randrange(1, CLK_PS), "ps")
        self.uio = (self.uio & ~0x0F) | (addr & 7) | STROBE
        self.dut.ui_in.value = data & 0xFF
        self.drive()
        await ClockCycles(self.dut.clk, hold, False)
        self.uio &= ~STROBE
        self.drive()
        await ClockCycles(self.dut.clk, gap, False)
        self.writes += 1

    async def rd_sel(self, sel):
        await self.wr(RSEL, sel)
        return int(self.dut.uo_out.value)

    async def read32(self, lane):
        v = 0
        for byte in range(4):
            v |= await self.rd_sel((byte << 4) | lane) << (8 * byte)
        return v

    # operations, mirrored into the reference model
    async def set_codes(self, a_codes, b_codes):
        await self.wr(A0, a_codes[0] | a_codes[1] << 4)
        await self.wr(B0, b_codes[0] | b_codes[1] << 4)
        self.ref.a = [sx4(c) for c in a_codes]
        self.ref.b = [sx4(c) for c in b_codes]

    async def set_vals(self, a, b):
        await self.set_codes([code4(x) for x in a], [code4(x) for x in b])

    async def step(self):
        await self.wr(CTRL, STEP | (AUTO if self.ref.auto else 0))
        self.ref.step()

    async def clear(self):
        await self.wr(CTRL, CLEAR | (AUTO if self.ref.auto else 0))
        self.ref.clear()

    async def set_rowen(self, m):
        await self.wr(ROWEN, m)
        self.ref.rowen = m & ((1 << ROWS) - 1)

    async def check(self, what, lanes=None):
        for lane in lanes if lanes is not None else range(ROWS * COLS):
            i, j = divmod(lane, COLS)
            got = await self.read32(lane)
            want = self.ref.read32(i, j)
            assert got == want, (f"{what}: lane {lane} (acc[{i}][{j}]) read {got:#010x}, "
                                 f"expected {want:#010x} (exact sum {self.ref.total[i][j]})")


async def setup(dut, salt):
    seed = int(os.environ.get("AUDIT_SEED", "1")) * 1000 + salt
    dut._log.info(f"audit seed {seed} (GL={GL})")
    h = Host(dut, random.Random(seed))
    await h.start()
    return h


@cocotb.test()
async def t01_exhaustive_operand_pairs(dut):
    """All 16x16 signed int4 pairs on every one of the 4 multiplier/accumulator instances.
    Lane operands are bijections of (x, y) so each PE sees all 256 pairs and the 4 lanes
    always carry different values (catches swapped / duplicated / cross-coupled lanes)."""
    h = await setup(dut, 1)
    seen = [set() for _ in range(4)]
    for x in range(16):
        for y in range(16):
            a = [x, (5 * x + 3) & 15]
            b = [y, (11 * y + 6) & 15]
            await h.clear()
            await h.set_codes(a, b)
            await h.step()
            await h.check(f"pair x={x} y={y}")
            for i in range(2):
                for j in range(2):
                    seen[2 * i + j].add((a[i], b[j]))
    assert all(len(s) == 256 for s in seen), [len(s) for s in seen]
    dut._log.info("each of the 4 PEs checked on all 256 operand pairs (incl. 32-bit sign extension)")


@cocotb.test()
async def t02_exact_overflow_boundaries(dut):
    """Exact 16-bit boundaries in both directions, all lanes."""
    h = await setup(dut, 2)
    # positive side: 511 * 64 = 32704 (largest worst-case run that cannot overflow)
    await h.set_vals([-8, -8], [-8, -8])
    for _ in range(511):
        await h.step()
    await h.check("511 x (-8*-8) = 32704")
    assert h.ref.reg(0, 0) == 32704
    await h.set_vals([7, 7], [7, 7])      # +49 -> 32753
    await h.step()
    await h.set_vals([7, 7], [2, 2])      # +14 -> 32767
    await h.step()
    assert h.ref.reg(1, 1) == 32767
    await h.check("exactly +32767")
    await h.set_vals([1, 1], [1, 1])      # +1 -> wraps to -32768
    await h.step()
    assert h.ref.reg(0, 1) == -32768
    await h.check("+32767 + 1 -> -32768 (positive overflow wraps)")
    await h.set_vals([-1, -1], [1, 1])    # -1 -> wraps to +32767
    await h.step()
    assert h.ref.reg(1, 0) == 32767
    await h.check("-32768 - 1 -> +32767 (negative overflow wraps)")
    # negative side from zero: 585 * (-56) = -32760, then -8 -> -32768
    await h.clear()
    await h.set_vals([-8, -8], [7, 7])
    for _ in range(585):
        await h.step()
    await h.check("585 x (-8*7) = -32760")
    await h.set_vals([-8, -8], [1, 1])
    await h.step()
    assert h.ref.reg(0, 0) == -32768
    await h.check("exactly -32768")
    await h.set_vals([-8, -8], [7, 7])    # -56 -> wraps to +32720
    await h.step()
    await h.check("-32768 - 56 wraps")
    # repeated max positive past several wraps
    await h.clear()
    await h.set_vals([-8, -8], [-8, -8])
    for k in range(1, 2100):
        await h.step()
        if k in (512, 1023, 1024, 1025, 2048, 2099):
            await h.check(f"{k} x 64 (wrap count {64 * k // 65536})")


@cocotb.test()
async def t03_alternating_and_random_long(dut):
    """Long accumulation without clear: alternating +/- products, extremes-weighted random
    operands, random ROWEN, min-timing writes at random phase, reads interleaved (and
    repeated, reads must not disturb state)."""
    h = await setup(dut, 3)
    r = h.rnd
    extremes = [-8, -7, -1, 0, 1, 7]

    def val():
        return r.choice(extremes) if r.random() < 0.5 else r.randint(-8, 7)

    # strictly alternating sign
    for k in range(64):
        s = 1 if k % 2 == 0 else -1
        await h.set_vals([-8, 7], [-8 * s, 7 * s] if s > 0 else [7, -8])
        await h.step()
    await h.check("alternating signs")
    for n in range(1500):
        await h.set_vals([val(), val()], [val(), val()])
        if r.random() < 0.05:
            await h.set_rowen(r.randrange(4))
        await h.step()
        if r.random() < 0.03:
            lane = r.randrange(4)
            await h.check(f"step {n}", [lane])
            await h.check(f"step {n} re-read", [lane])
    await h.set_rowen(3)
    await h.check("end of long run")
    dut._log.info(f"exact sums at end: {h.ref.total}, {h.writes} bus writes")


@cocotb.test()
async def t04_zero_clear_restart(dut):
    """All-zero / one-zero operands, clear mid-run, restart, clear+step = clear only,
    consecutive operations without reset, operand writes alone never change accumulators."""
    h = await setup(dut, 4)
    await h.set_vals([3, -5], [-7, 6])
    for _ in range(5):
        await h.step()
    await h.check("before zero steps")
    for a, b in (([0, 0], [0, 0]), ([0, -8], [7, 0]), ([-8, 0], [0, -8]), ([5, 5], [0, 0]), ([0, 0], [-8, 7])):
        await h.set_vals(a, b)
        await h.step()
        await h.check(f"zero operand step a={a} b={b}")
    await h.set_vals([7, -8], [-8, 7])     # operand writes alone: no change
    await h.check("operand writes only")
    await h.clear()
    await h.check("cleared")
    await h.wr(CTRL, CLEAR | STEP)          # clear and step together: only clears
    h.ref.clear()
    await h.check("clear+step")
    for op in range(5):                     # consecutive operations without reset
        k = h.rnd.randint(1, 40)
        await h.clear()
        for _ in range(k):
            await h.set_vals([h.rnd.randint(-8, 7) for _ in range(2)], [h.rnd.randint(-8, 7) for _ in range(2)])
            await h.step()
        await h.check(f"operation {op}, K={k}")
    # back-to-back steps without operand changes
    for _ in range(10):
        await h.step()
    await h.check("back-to-back steps")


@cocotb.test()
async def t05_reset_cases(dut):
    """Reset while idle, reset asserted asynchronously at a random phase during an active
    step write / accumulation, first operation after reset."""
    h = await setup(dut, 5)
    await h.reset()
    await h.check("reset while idle")
    for trial in range(12):
        await h.set_vals([h.rnd.randint(-8, 7) for _ in range(2)], [h.rnd.randint(-8, 7) for _ in range(2)])
        await h.step()
        await h.step()
        # start a step write, assert rst_n somewhere inside it (any phase, any cycle)
        await FallingEdge(dut.clk)
        h.uio = (h.uio & ~0x0F) | CTRL | STROBE
        dut.ui_in.value = STEP
        h.drive()
        await Timer(h.rnd.randrange(1, 6 * CLK_PS), "ps")
        dut.rst_n.value = 0
        h.uio &= ~STROBE
        h.drive()
        await ClockCycles(dut.clk, h.rnd.randint(3, 12))
        await Timer(h.rnd.randrange(1, CLK_PS), "ps")
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 5)
        h.ref.reset()
        await h.check(f"after reset during activity {trial}")
        assert [await h.rd_sel(0x80 | k) for k in range(4)] == [0x4E, 0x22, 0x10, 0x01]
        await h.step()                          # A = B = 0 after reset
        await h.check("A/B are zero after reset")
        await h.set_vals([-8, 7], [7, -8])      # first real operation after reset
        await h.step()
        await h.check("first operation after reset")


@cocotb.test()
async def t06_lane_isolation_and_read_port(dut):
    """Distinct per-lane values under every ROWEN mask; unimplemented lanes 4..15 read 0;
    RSEL[6] is ignored; ID select ignores RSEL[6:2]."""
    h = await setup(dut, 6)
    for mask in (0b01, 0b10, 0b00, 0b11, 0b10, 0b01):
        await h.set_rowen(mask)
        for _ in range(3):
            await h.set_vals([h.rnd.randint(-8, 7) for _ in range(2)], [h.rnd.randint(-8, 7) for _ in range(2)])
            await h.step()
        await h.check(f"ROWEN {mask:#04b}")
    vals = [h.ref.read32(*divmod(l, 2)) for l in range(4)]
    assert len(set(vals)) > 1, "lanes should differ for this check to mean anything"
    for lane in range(4, 16):
        assert await h.read32(lane) == 0, f"unimplemented lane {lane} must read 0"
    for lane in range(4):
        for byte in range(4):
            want = (h.ref.read32(*divmod(lane, 2)) >> (8 * byte)) & 0xFF
            assert await h.rd_sel(0x40 | byte << 4 | lane) == want, "RSEL[6] must be ignored"
    for k, idb in enumerate([0x4E, 0x22, 0x10, 0x01]):
        assert await h.rd_sel(0xFC | k) == idb, "ID select uses RSEL[1:0] only"


@cocotb.test()
async def t07_matmul_reference(dut):
    """C = A.B for 2x2 results with K up to 511, plus a 4x4 = (4x8).(8x4) product computed by
    host-side tiling into four 2x2 tiles, compared with a plain Python triple loop."""
    h = await setup(dut, 7)
    r = h.rnd
    for k in (1, 2, 3, 8, 64, 511):
        A = [[r.randint(-8, 7) for _ in range(k)] for _ in range(2)]
        B = [[r.randint(-8, 7) for _ in range(2)] for _ in range(k)]
        await h.clear()
        for t in range(k):
            await h.set_vals([A[0][t], A[1][t]], [B[t][0], B[t][1]])
            await h.step()
        C = [[sum(A[i][t] * B[t][j] for t in range(k)) for j in range(2)] for i in range(2)]
        for lane in range(4):
            i, j = divmod(lane, 2)
            got = await h.read32(lane)
            got = got - (1 << 32) if got & 0x80000000 else got
            assert got == C[i][j], f"K={k} C[{i}][{j}] = {got}, expected {C[i][j]}"
    M, K, N = 4, 8, 4
    A = [[r.randint(-8, 7) for _ in range(K)] for _ in range(M)]
    B = [[r.randint(-8, 7) for _ in range(N)] for _ in range(K)]
    C = [[0] * N for _ in range(M)]
    for ti in range(0, M, 2):
        for tj in range(0, N, 2):
            await h.clear()
            for t in range(K):
                await h.set_vals([A[ti][t], A[ti + 1][t]], [B[t][tj], B[t][tj + 1]])
                await h.step()
            for lane in range(4):
                i, j = divmod(lane, 2)
                v = await h.read32(lane)
                C[ti + i][tj + j] = v - (1 << 32) if v & 0x80000000 else v
    want = [[sum(A[i][t] * B[t][j] for t in range(K)) for j in range(N)] for i in range(M)]
    assert C == want, f"tiled 4x4 product {C} != {want}"


@cocotb.test()
async def t08_auto_step_and_write_counting(dut):
    """Auto mode: B1 writes step with the newly written B; a CTRL write rewrites auto (it is
    'sticky' only until the next CTRL write); a strobe held for 200 clocks is one write."""
    h = await setup(dut, 8)
    await h.wr(CTRL, AUTO)
    h.ref.auto = True
    for _ in range(20):
        a = [h.rnd.randint(-8, 7) for _ in range(2)]
        b = [h.rnd.randint(-8, 7) for _ in range(2)]
        await h.wr(A0, code4(a[0]) | code4(a[1]) << 4)
        await h.wr(B0, code4(b[0]) | code4(b[1]) << 4)
        h.ref.a, h.ref.b = a, b
        await h.wr(B1, h.rnd.randrange(256))   # data unused at 2x2, write steps
        h.ref.step()
    await h.check("auto steps")
    await h.wr(CTRL, STEP)                    # CTRL write without bit 2 turns auto off
    h.ref.auto = False
    h.ref.step()
    await h.wr(B1, 0)
    await h.check("auto cleared by CTRL write")
    await h.wr(CTRL, STEP, hold=200)          # long strobe: exactly one step
    h.ref.step()
    await h.check("200-clock strobe = one step")


@cocotb.test()
async def t09_strobe_high_across_reset(dut):
    """Characterisation (host rule): if the strobe is high while rst_n is released, the
    synchronizer sees a rising edge after reset and performs one write. This test pins that
    behaviour down so RTL and GL agree; docs must tell the host to keep uio[3] low in reset."""
    h = await setup(dut, 9)
    # Reset clears A/B, so a spurious step would add 0. Observe through ROWEN instead:
    # strobe high on ROWEN with data 0 during reset and across its release.
    h.uio = (h.uio & ~0x0F) | ROWEN | STROBE
    dut.ui_in.value = 0
    h.drive()
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    h.uio &= ~STROBE
    h.drive()
    await ClockCycles(dut.clk, 3)
    h.ref.reset()
    await h.set_vals([3, 2], [1, -1])
    await h.step()
    observed_rowen0 = all([await h.read32(l) == 0 for l in range(4)])
    dut._log.warning(f"strobe high across reset release -> write performed after reset: {observed_rowen0}")
    assert observed_rowen0, "expected: synchronizer creates one write after reset release"
