#!/usr/bin/env python3
"""
postproc_lfsr.py -- the paper's "simple debiasing": XOR the raw TRNG bit stream
with the output sequence of a 4-bit LFSR (maximal length, x^4 + x^3 + 1, period 15).

  python postproc_lfsr.py trng.bin trng_lfsr.bin
"""
import sys
import numpy as np

def lfsr4_sequence(n, state=0b0001):
    seq = np.empty(15, dtype=np.uint8)
    s = state
    for i in range(15):
        seq[i] = s & 1
        fb = ((s >> 0) ^ (s >> 1)) & 1          # taps for x^4 + x^3 + 1 (Fibonacci, right shift)
        s = (s >> 1) | (fb << 3)
    assert len(set(seq.tolist())) == 2
    reps = -(-n // 15)
    return np.tile(seq, reps)[:n]

def main(inp, out):
    raw = np.unpackbits(np.fromfile(inp, dtype=np.uint8))
    y = raw ^ lfsr4_sequence(len(raw))
    np.packbits(y).tofile(out)
    print(f"{inp} -> {out}: {len(raw)} bits, ones before {raw.mean():.5f}, after {y.mean():.5f}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(1)
    main(sys.argv[1], sys.argv[2])
