#!/usr/bin/env python3
"""
analyze_search.py -- evaluate parameter-search files (paper Section V.A, Fig. 7)

  python analyze_search.py search_tc_X4Y16.bin                  # summary + candidates
  python analyze_search.py search_tc_X4Y16.bin --target 112 7   # like hex_param_dist.rb
  python analyze_search.py --fig7 TC:X4Y16=search_tc_X4Y16.bin TC:X8Y64=... C:X4Y16=...

Record = 8 bytes big-endian: bit63 = 0xFF seen, bits62..32 = sum, bits31..0 = sum of squares
over 4096 counter values.
"""
import argparse, sys
import numpy as np

N = 4096
BINS = [(224, 255), (192, 223), (160, 191), (128, 159), (96, 127), (64, 95), (32, 63), (0, 31)]


def load(path, start=0):
    raw = np.fromfile(path, dtype=">u8")
    sat = (raw >> np.uint64(63)).astype(bool)
    s = ((raw >> np.uint64(32)) & np.uint64(0x7FFFFFFF)).astype(np.float64)
    q = (raw & np.uint64(0xFFFFFFFF)).astype(np.float64)
    mean = s / N
    std = np.sqrt(np.maximum(q / N - mean ** 2, 0.0))
    ids = np.arange(start, start + len(raw))
    return ids, mean, std, sat


def bin_props(mean):
    return [100.0 * np.mean((mean >= lo) & (mean < hi + 1)) for lo, hi in BINS]


def summary(path, start, target):
    ids, mean, std, sat = load(path, start)
    n = len(ids)
    print(f"{path}: {n} parameters")
    print("  Distribution of average counter value (paper Fig. 7):")
    for (lo, hi), p in zip(BINS, bin_props(mean)):
        print(f"    {lo:3d}-{hi:3d}: {p:6.2f} %")
    ext = (mean >= 96) & (mean < 128) & (~sat)
    print(f"  Extracted (96 <= avg <= 127 and never saturated): {ext.sum()} = {100*ext.mean():.2f} %"
          f"   (paper avg: C-TERO 2.62 %, TC-TERO 5.18 %)")
    if target:
        ta, ts = target
        good = (~sat)
        d = np.where(good, (mean - ta) ** 2 / 4 + (std - ts) ** 2, np.inf)
        order = np.argsort(d)[:15]
        print(f"  Best candidates near avg={ta}, std={ts} (never saturated):")
        for i in order:
            if not np.isfinite(d[i]):
                break
            print(f"    ## ID = {ids[i]:8d} (0x{ids[i]:05x}), avg = {mean[i]:7.2f}, std = {std[i]:6.2f}")
    np.savetxt(path + ".extracted.csv",
               np.column_stack([ids[ext], mean[ext], std[ext]]),
               fmt=["%d", "%.3f", "%.3f"], delimiter=",", header="param,avg,std", comments="")
    print(f"  Extracted list written to {path}.extracted.csv")


def fig7(items):
    import matplotlib.pyplot as plt
    labels, props = [], []
    for it in items:
        lab, path = it.split("=", 1)
        _, mean, _, _ = load(path)
        labels.append(lab)
        props.append(bin_props(mean))
    props = np.array(props)
    fig, ax = plt.subplots(figsize=(max(6, 0.6 * len(labels)), 4))
    bottom = np.zeros(len(labels))
    cmap = plt.get_cmap("viridis", len(BINS))
    for k, (lo, hi) in enumerate(BINS[::-1]):
        col = props[:, len(BINS) - 1 - k]
        ax.bar(labels, col, bottom=bottom, color=cmap(k), label=f"{lo}-{hi}")
        bottom += col
    ax.set_ylabel("Proportion [%]")
    ax.set_title("Distribution of the average counter value (cf. paper Fig. 7)")
    ax.legend(bbox_to_anchor=(1.01, 1), loc="upper left", fontsize=8)
    plt.xticks(rotation=60, ha="right")
    plt.tight_layout()
    plt.savefig("fig7_reproduction.png", dpi=150)
    print("Saved fig7_reproduction.png")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?")
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--target", type=float, nargs=2, default=[112, 7])
    ap.add_argument("--fig7", nargs="+", help="LABEL=file entries")
    a = ap.parse_args()
    if a.fig7:
        fig7(a.fig7)
    elif a.file:
        summary(a.file, a.start, a.target)
    else:
        ap.print_help(); sys.exit(1)
