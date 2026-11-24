#!/usr/bin/env python3
"""
analyze_counter.py -- statistics of counter-mode data (Table I, Section V.B, Fig. 8)

  python analyze_counter.py cnt_X4Y16.bin            # mean / S.D. (Table I) + model fit + plot

Stochastic model (Bernard et al., J. Cryptology 2019, used by the paper):
the relative half-period difference after k turns is x_k = R*x_{k-1} + noise,
x_0 = dr. Unrolling, x_k ~= R^k * Y with Y ~ Normal(dr, s^2),
s = sigma_r / sqrt(R^2 - 1). Oscillation stops when |x_k| >= 1, so
    P(N = n) = P( R^-n <= |Y| < R^-(n-1) ).
The three parameters (R, sigma_r, dr) are fitted by maximum likelihood.
(The paper used the median-based procedure of [2]; numbers can differ slightly.)
"""
import argparse, sys
import numpy as np
from scipy.optimize import minimize
from scipy.stats import norm


def pmf(n, lnR, dr, s):
    a = np.exp(-lnR * n)          # R^-n
    b = np.exp(-lnR * (n - 1))    # R^-(n-1)
    p = (norm.cdf(b, dr, s) - norm.cdf(a, dr, s)) + (norm.cdf(-a, dr, s) - norm.cdf(-b, dr, s))
    return np.maximum(p, 1e-300)


def fit(vals):
    """Bounded maximum-likelihood fit. Physical ranges: dr in [0.01, 0.5]
    (design value 0.2), ln R in [1e-4, 0.2] (R slightly above 1)."""
    ks, cnts = np.unique(vals, return_counts=True)
    m, sd = float(np.mean(vals)), float(np.std(vals))
    bounds = [(1e-4, 0.2), (0.01, 0.5), (1e-6, 0.5)]
    def nll(x):
        lnR, dr, s = x
        return -np.sum(cnts * np.log(pmf(ks, lnR, dr, s)))
    best = None
    for dr0 in (0.03, 0.06, 0.1, 0.15, 0.2, 0.3, 0.45):
        lnR0 = min(max(-np.log(dr0) / max(m, 1.0), 1.1e-4), 0.19)
        s0 = min(max(sd * lnR0 * dr0, 1e-5), 0.4)
        r = minimize(nll, [lnR0, dr0, s0], method="L-BFGS-B", bounds=bounds)
        if best is None or r.fun < best.fun:
            best = r
    lnR, dr, s = best.x
    R = np.exp(lnR)
    sigma_r = s * np.sqrt(R ** 2 - 1)
    at_bound = any(abs(v - lo) < 1e-6 or abs(v - hi) < 1e-6 for v, (lo, hi) in zip(best.x, bounds))
    return R, sigma_r, dr, lnR, s, at_bound


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--no-plot", action="store_true")
    a = ap.parse_args()
    vals = np.fromfile(a.file, dtype=np.uint8)
    n = len(vals)
    satn = int(np.sum(vals == 255))
    print(f"{a.file}: {n} counter values")
    print(f"  Avg = {vals.mean():.2f}   S.D. = {vals.std():.2f}   (Table I format)")
    print(f"  min = {vals.min()}  max = {vals.max()}  saturated (0xFF) = {satn} ({100*satn/n:.3f} %)")
    good = vals[vals != 255]
    if len(good) < 1000:
        print("  Too few non-saturated values for a model fit."); return 0
    med = np.median(good)
    print(f"  median = {med:.0f},  P(N <= median) = {np.mean(good <= med):.4f}   (paper observed 0.5325)")
    lsb = good & 1
    p1 = lsb.mean()
    h = -(p1 * np.log2(p1) + (1 - p1) * np.log2(1 - p1)) if 0 < p1 < 1 else 0.0
    print(f"  LSB: P(1) = {p1:.5f}  -> Shannon entropy per raw bit = {h:.5f}")

    R, sigma_r, dr, lnR, s, at_bound = fit(good)
    print(f"  Model fit:  R = {R:.5f}   sigma_r = {sigma_r:.5f}   dr = {dr:.4f}")
    print(f"              (paper, its own device: R = 1.01908, sigma_r = 0.00192, dr = 0.1159)")
    if at_bound:
        print("  note: a parameter sits at its physical limit -> the histogram is almost symmetric,")
        print("        so the 3 model parameters are only weakly determined (shape still checked below).")
    ks = np.arange(good.min(), good.max() + 1)
    model = pmf(ks, lnR, dr, s) * len(good)
    hist = np.array([(good == k).sum() for k in ks])
    chi = np.sum((hist - model) ** 2 / np.maximum(model, 1e-9)) / len(ks)
    print(f"  mean squared normalised residual per bin = {chi:.2f}")

    if not a.no_plot:
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(6, 3.5))
        ax.bar(ks, hist, width=1.0, color="#9db4d8", label="Experimental")
        ax.plot(ks, model, "k-", lw=1.5, label="Modeled")
        ax.set_xlabel("# of Oscillations"); ax.set_ylabel("# of Samples")
        ax.set_title(f"TC-TERO counter distribution (cf. Fig. 8)  R={R:.5f}, "
                     f"$\\sigma_r$={sigma_r:.5f}, $\\Delta_r$={dr:.4f}", fontsize=8)
        ax.legend()
        plt.tight_layout()
        out = a.file + ".fig8.png"
        plt.savefig(out, dpi=150)
        print(f"  Plot saved to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
