<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A small int4 neural-network accelerator: a 2×2 array of multiply-accumulate (MAC) units with 16-bit
accumulators. The host (e.g. the RP2040/RP2350 on the demo board) writes operands over a byte-wide register
bus on the pins, the chip does all four multiply-accumulates in one clock, and the host reads the results back
one byte at a time.

One **step** is an outer product: for every enabled row `i` and every column `j`,

    acc[i][j] += a[i] * b[j]        a, b: signed int4 (-8..7), acc: signed 16-bit, wraps on overflow

A matrix product `C = A·B` with inner dimension `K` is `K` steps, each loading one column of `A` and one row of
`B`. The largest product is (-8)·(-8) = 64, so 511 steps can never overflow.

**Clock gating.** Each row of MAC units has its own integrated clock gate (`sky130_fd_sc_hd__dlclkp_1`). A row's
accumulators are clocked only on the cycle after a step (if the row is enabled in `ROWEN`) or a clear, so the
array is idle almost all the time. Test mode forces the row clocks on.

**Scan (DFT).** Every flop except the two reset synchronizer flops is on one mux-D scan chain of 96 flops, from
`uio[6]` to `uio[7]`, so the whole internal state can be read and written on the bench.

### Register map

Write-only registers, address on `uio[2:0]`.

| Addr | Name | Bits | Reset |
|---|---|---|---|
| 0 | A0 | `a[0]` = [3:0], `a[1]` = [7:4] | 0 |
| 1 | A1 | unused in the 2×2 array | — |
| 2 | B0 | `b[0]` = [3:0], `b[1]` = [7:4] | 0 |
| 3 | B1 | data unused in the 2×2 array; the write steps when `CTRL.auto` is set | — |
| 4 | CTRL | [0] clear all accumulators, [1] step, [2] auto (sticky: a B1 write also steps). Clear and step in the same write: only clears | auto = 0 |
| 5 | ROWEN | [1:0] row enable; a disabled row's clock stops and its accumulators hold | 0b11 |
| 6 | RSEL | [7] = 0: `uo` = byte [5:4] of accumulator [3:0] (index `2·i + j`, sign-extended to 32 bit); [7] = 1: `uo` = ID byte [1:0] | 0x00 |
| 7 | — | reserved | |

ID bytes: 0 = `0x4E` ('N'), 1 = `0x22` (rows, columns), 2 = `0x10` (accumulator width 16), 3 = `0x01` (version).
Reset clears all accumulators and operand registers.

### Write protocol

The host is asynchronous to the chip clock. Only the strobe `uio[3]` is synchronized (2 flops + edge detect);
address and data are sampled directly.

1. Set `uio[2:0]` (address) and `ui[7:0]` (data), raise `uio[3]` (at the same time is fine).
2. Hold address, data and strobe for at least **4 clock cycles**.
3. Drop `uio[3]` and keep it low for at least **2 clock cycles** before the next write.

The register changes 2–3 clocks after the strobe rises; a step or clear acts one clock later. `uo[7:0]` shows the
selected byte combinationally from the registers, so it is valid once the `RSEL` write has completed.

## How to test

Set the clock to 50 MHz (any lower frequency works too) and reset the design.

1. Check the ID: write `RSEL = 0x80..0x83`, read `0x4E, 0x22, 0x10, 0x01` on `uo[7:0]`.
2. Multiply two 2×2 matrices `A·B` (`K` = 2):

        CTRL  <- 0x01                         clear
        for k in 0, 1:
            A0 <- (A[1][k] & 0xF) << 4 | (A[0][k] & 0xF)
            B0 <- (B[k][1] & 0xF) << 4 | (B[k][0] & 0xF)
            CTRL <- 0x02                      step
        for n in 0..3:                        C[n // 2][n % 2]
            v = 0
            for byte in 0..3: RSEL <- byte << 4 | n;  v |= uo << (8 * byte)
            (v is a 32-bit two's-complement number)

   With `CTRL <- 0x04` (auto) a write to B1 steps, so a step costs one write fewer.
3. Clock gating: run the same workload with `ROWEN = 0b11` and `0b01` and compare the core current;
   with `ROWEN = 0b01` row 1's accumulators keep their value.

Python (MicroPython on the demo board) pseudocode:

    def wr(addr, data):
        set_pins(ui=data, uio_addr=addr, strobe=1)   # hold >= 4 chip clocks
        wait_chip_clocks(4)
        set_pins(strobe=0)                           # low >= 2 chip clocks
        wait_chip_clocks(2)

### Scan chain (test mode)

`uio[4]` = test_mode (forces the row clocks on, enables `scan_out` on `uio[7]`), `uio[5]` = scan_en (only with
test_mode), `uio[6]` = scan_in. While test_mode and scan_en are high, every clock shifts the chain by one; `uio[7]`
shows the last flop of the chain before each shift. Change the test pins with the clock slow or stopped. Reset
(`rst_n`) works in test mode.

Chain order, position 0 next to `scan_in` (each field LSB first; position 95 drives `scan_out`):

| Positions | Field |
|---|---|
| 0–2 | write strobe synchronizer `wr_sync[0..2]` |
| 3–10 | A operand register (`a[0]` at 3–6, `a[1]` at 7–10) |
| 11–18 | B operand register (`b[0]` at 11–14, `b[1]` at 15–18) |
| 19 | `CTRL.auto` |
| 20–21 | `ROWEN[0..1]` |
| 22–29 | `RSEL[0..7]` |
| 30 | step pending |
| 31 | clear pending |
| 32–47 | `acc[0][0]` bits 0–15 |
| 48–63 | `acc[0][1]` bits 0–15 |
| 64–79 | `acc[1][0]` bits 0–15 |
| 80–95 | `acc[1][1]` bits 0–15 |

To read the state: enter test mode with scan_en high, sample `uio[7]` before each of 96 clocks; the first sample is
position 95. To load a state, shift position 95 in first. The map is generated by `test/scan_map.py`.

## External hardware

None. The demo board's microcontroller drives `ui[7:0]` and `uio[6:0]` and reads `uo[7:0]` and `uio[7]`.
