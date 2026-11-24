#!/usr/bin/env python3
"""
ais31.py -- AIS-31 (BSI, Killmann & Schindler v2.0, 2011) test procedures A and B.

  python ais31.py A trng.bin        # Procedure A: T0 + 257 x (T1..T5)
  python ais31.py B trng.bin        # Procedure B: T6a, T6b, T7a, T7b, T8 (entropy)
  python ais31.py AB trng.bin

Bits are read MSB-first from each byte (the board sends the first bit in the MSB).
Rule (both procedures): all tests pass -> PASS; exactly one failure -> the whole
procedure is repeated once on fresh bits and must then pass completely; else FAIL.
Cross-check: the original repo's scripts/ais_test.rb, or BSI's own AIS 31 test suite.
"""
import sys
import numpy as np


class Bits:
    def __init__(self, path):
        self.b = np.unpackbits(np.fromfile(path, dtype=np.uint8))
        self.pos = 0

    def take(self, n):
        if self.pos + n > len(self.b):
            raise EOFError(f"need {n} more bits at offset {self.pos}, file has {len(self.b)}")
        r = self.b[self.pos:self.pos + n]
        self.pos += n
        return r


# ------------------------------------------------------------------ Procedure A
def t0(bits):                                   # disjointness, 2^16 x 48-bit
    w = bits.reshape(65536, 48)
    v = np.zeros(65536, dtype=np.uint64)
    for i in range(48):
        v = (v << np.uint64(1)) | w[:, i].astype(np.uint64)
    return len(np.unique(v)) == 65536


def t1(b):                                      # monobit
    s = int(b.sum()); return 9654 < s < 10346, s


def t2(b):                                      # poker
    c = b.reshape(5000, 4) @ np.array([8, 4, 2, 1])
    f = np.bincount(c, minlength=16)
    x = 16.0 / 5000 * np.sum(f.astype(float) ** 2) - 5000
    return 1.03 < x < 57.4, x


def runs(b):
    d = np.flatnonzero(np.diff(b)) + 1
    starts = np.concatenate(([0], d))
    lens = np.diff(np.concatenate((starts, [len(b)])))
    vals = b[starts]
    return lens, vals


T3_BOUNDS = {1: (2267, 2733), 2: (1079, 1421), 3: (502, 748), 4: (223, 402), 5: (90, 223), 6: (90, 223)}


def t3(b):                                      # runs
    lens, vals = runs(b)
    ok = True
    for v in (0, 1):
        L = lens[vals == v]
        for k in range(1, 7):
            n = int(np.sum(L == k)) if k < 6 else int(np.sum(L >= 6))
            lo, hi = T3_BOUNDS[k]
            if not (lo <= n <= hi):
                ok = False
    return ok, None


def t4(b):                                      # long run
    lens, _ = runs(b)
    return int(lens.max()) < 34, int(lens.max())


def _z_all_tau(b10000):
    """Z_tau = sum_{j=0}^{4999} b_j xor b_{j+tau}, tau = 1..5000 (FFT)."""
    s = 1.0 - 2.0 * b10000.astype(float)        # 0 -> +1, 1 -> -1
    a = np.zeros(16384); a[:5000] = s[:5000]
    c = np.zeros(16384); c[:10000] = s
    corr = np.fft.irfft(np.conj(np.fft.rfft(a)) * np.fft.rfft(c), 16384)
    corr = np.rint(corr[1:5001])
    return (5000 - corr) / 2.0                   # xor = (1 - s_j s_{j+tau}) / 2


def t5(b20000):                                 # autocorrelation with tau search
    z = _z_all_tau(b20000[:10000])
    tau = int(np.argmax(np.abs(z - 2500))) + 1
    second = b20000[10000:]
    zt = int(np.sum(second[:5000] ^ second[tau:tau + 5000]))
    return 2326 < zt < 2674, (tau, zt)


def procedure_a(src):
    fails = []
    if not t0(src.take(65536 * 48)):
        fails.append("T0")
    for r in range(257):
        b = src.take(20000)
        for name, fn in (("T1", t1), ("T2", t2), ("T3", t3), ("T4", t4), ("T5", t5)):
            ok, _ = fn(b)
            if not ok:
                fails.append(f"{name}@round{r}")
    return fails


# ------------------------------------------------------------------ Procedure B
def t6a(src):                                   # k=1, n=100000, a=0.025
    b = src.take(100000)
    p = b.mean()
    return abs(p - 0.5) < 0.025, p


def _collect(src, k, n_per_class, nclasses):
    """Non-overlapping k-bit tuples; classify by the first k-1 bits; for every
    class keep the first n_per_class last-bits. Returns counts[class][lastbit]."""
    cnt = np.zeros((nclasses, 2), dtype=np.int64)
    filled = np.zeros(nclasses, dtype=np.int64)
    w = 1 << np.arange(k - 2, -1, -1)
    while np.any(filled < n_per_class):
        blk = src.take(k * 50000).reshape(-1, k)
        cls = blk[:, :k - 1] @ w
        last = blk[:, k - 1]
        for c in range(nclasses):
            need = n_per_class - filled[c]
            if need <= 0:
                continue
            sel = last[cls == c][:need]
            cnt[c, 1] += int(sel.sum()); cnt[c, 0] += len(sel) - int(sel.sum())
            filled[c] += len(sel)
    return cnt


def t6b(src):                                   # P(1|0) vs P(1|1), n=100000 each
    cnt = _collect(src, 2, 100000, 2)
    p0 = cnt[0, 1] / 100000; p1 = cnt[1, 1] / 100000
    return abs(p0 - p1) < 0.02, (p0, p1)


def _homog(c1, c2):                             # T7 statistic, h=2, s=2
    f = np.vstack([c1, c2]).astype(float)
    n = f.sum(axis=1, keepdims=True)
    pt = f.sum(axis=0) / f.sum()
    e = n * pt
    return float(np.sum((f - e) ** 2 / e))


CHI2_1_1E4 = 15.13                              # chi^2, 1 dof, alpha = 0.0001


def t7a(src):
    cnt = _collect(src, 3, 100000, 4)            # classes 00,01,10,11
    stats = [_homog(cnt[0], cnt[2]), _homog(cnt[1], cnt[3])]
    return all(x <= CHI2_1_1E4 for x in stats), stats


def t7b(src):
    cnt = _collect(src, 4, 100000, 8)
    stats = [_homog(cnt[i], cnt[i + 4]) for i in range(4)]
    return all(x <= CHI2_1_1E4 for x in stats), stats


def t8(src, L=8, Q=2560, K=256000):             # Coron entropy estimator
    b = src.take(L * (Q + K)).reshape(-1, L)
    words = b @ (1 << np.arange(L - 1, -1, -1))
    gtab = np.zeros(Q + K + 2)
    gtab[2:] = np.cumsum(1.0 / np.arange(1, Q + K + 1)) / np.log(2)
    last = np.full(1 << L, -1, dtype=np.int64)
    for i in range(Q):
        last[words[i]] = i
    tot = 0.0
    for i in range(Q, Q + K):
        w = words[i]
        d = i - last[w] if last[w] >= 0 else i + 1
        tot += gtab[d]
        last[w] = i
    f = tot / K
    return f > 7.976, f


def procedure_b(src):
    fails, info = [], {}
    for name, fn in (("T6a", t6a), ("T6b", t6b), ("T7a", t7a), ("T7b", t7b), ("T8", t8)):
        ok, val = fn(src)
        info[name] = val
        if not ok:
            fails.append(name)
    return fails, info


# ------------------------------------------------------------------ driver
def run(proc, path):
    src = Bits(path)
    print(f"{path}: {len(src.b)} bits")
    for which in proc:
        for attempt in (1, 2):
            if which == "A":
                fails = procedure_a(src); info = {}
            else:
                fails, info = procedure_b(src)
            for k, v in info.items():
                print(f"    {k}: {v}")
            if len(fails) == 0:
                print(f"  Procedure {which}: PASS" + (" (after repetition)" if attempt == 2 else ""))
                if which == "B" and "T8" in info:
                    print(f"    entropy per bit (T8 / 8) = {info['T8']/8:.4f}   (paper: 0.9993)")
                break
            if len(fails) == 1 and attempt == 1:
                print(f"  Procedure {which}: one failure ({fails[0]}) -> repeating once")
                continue
            print(f"  Procedure {which}: FAIL  ({len(fails)} failures: {fails[:10]})")
            break


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1].upper() not in ("A", "B", "AB"):
        print(__doc__); sys.exit(1)
    try:
        run(sys.argv[1].upper(), sys.argv[2])
    except EOFError as e:
        print(f"  Not enough data: {e}. Collect a bigger file (>= 2 MB recommended).")
