# SPDX-FileCopyrightText: © 2026 AKLN0401
# SPDX-License-Identifier: Apache-2.0
"""Scan chain map of tt_um_akln0401_npu, mirroring the scan blocks in src/project.v and
src/npu_array.v. Position 0 is the flop next to scan_in (uio[6]), the last position drives
scan_out (uio[7]). Run it to print the map for docs/info.md."""

import sys


def chain(rows, cols, acc_w):
    """List of (field, bit) per chain position, scan_in side first."""
    m = [("wr_sync", i) for i in range(3)]
    m += [("a_reg", i) for i in range(4 * rows)]
    m += [("b_reg", i) for i in range(4 * cols)]
    m += [("auto", 0)]
    m += [("row_en", i) for i in range(rows)]
    m += [("rsel", i) for i in range(8)]
    m += [("step_q", 0), ("clear_q", 0)]
    for i in range(rows):
        for j in range(cols):
            m += [(f"acc[{i}][{j}]", b) for b in range(acc_w)]
    return m


def to_bits(rows, cols, acc_w, fields):
    """Chain image (list of bits by position) from a dict field -> integer value."""
    return [(fields.get(f, 0) >> b) & 1 for f, b in chain(rows, cols, acc_w)]


def from_bits(rows, cols, acc_w, bits):
    """Inverse of to_bits: dict field -> integer value."""
    fields = {}
    for (f, b), v in zip(chain(rows, cols, acc_w), bits):
        fields[f] = fields.get(f, 0) | (v << b)
    return fields


if __name__ == "__main__":
    rows, cols, acc_w = (int(x) for x in (sys.argv[1:] or ["2", "2", "12"]))
    m = chain(rows, cols, acc_w)
    print(f"{rows}x{cols}, ACC_W {acc_w}: {len(m)} flops on the chain")
    start = 0
    for k in range(1, len(m) + 1):
        if k == len(m) or m[k][0] != m[start][0]:
            f = m[start][0]
            print(f"  {start:4d}-{k - 1:4d}  {f}[{m[start][1]}..{m[k - 1][1]}]")
            start = k
