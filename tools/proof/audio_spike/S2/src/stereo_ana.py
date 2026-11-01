"""Stereo: cross-talk between channels, and L vs R on identical input."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import ana

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = ana.load("audio/dry.f32")
dr = d[::-1].copy()
for t, L in (("0", 6360), ("1", 3664)):
    y = ana.load(f"fmt/t{t}_stereo_lr.f32", 2)
    l = ana.align(y[:, 0], L, len(d))
    r = ana.align(y[:, 1], L, len(d))

    def proj(sig, ref):
        """Energy of sig explained by ref (least-squares gain), in dB below sig."""
        g = np.dot(sig, ref) / np.dot(ref, ref)
        return ana.db(np.mean((g * ref) ** 2)) - ana.rms_db(sig), g

    pl_own, gl = proj(l, d)
    pl_x, gx = proj(l, dr)
    pr_own, _ = proj(r, dr)
    pr_x, _ = proj(r, d)
    print(f"type {t} stereo_lr: L explained by dry {pl_own:.1f} dB (g {gl:.2f}), by R's source {pl_x:.1f} dB; "
          f"R explained by its source {pr_own:.1f} dB, by L's source {pr_x:.1f} dB")
    print(f"   L rms {ana.rms_db(l):.1f}  R rms {ana.rms_db(r):.1f}  dry rms {ana.rms_db(d):.1f}")
    ys = ana.load(f"fmt/t{t}_stereo_same.f32", 2)
    ls = ana.align(ys[:, 0], L, len(d))
    rs = ana.align(ys[:, 1], L, len(d))
    print(f"   stereo_same: L-R residual {ana.rms_db(ls - rs) - ana.rms_db(ls):.1f} dB; L rms {ana.rms_db(ls):.1f} R rms {ana.rms_db(rs):.1f}; "
          f"(L+R)/2 rms {ana.rms_db((ls + rs) / 2):.1f}")
    mono = ana.load(f"audio/probe_{'hq' if t == '0' else 'v'}.f32")
    am = ana.align(mono, 4440 if t == "0" else 2704, len(d))
    print(f"   stereo_same mid (L+R)/2 vs mono render residual {ana.rms_db((ls + rs) / 2 - am) - ana.rms_db(am):.1f} dB; "
          f"mono render rms {ana.rms_db(am):.1f}")
