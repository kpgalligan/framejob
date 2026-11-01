"""EQ magnitude: stepped sine through the tap, wet/dry by least-squares sine fit.

The analytic response is the RBJ cookbook transfer function computed HERE, in
numpy, from the band parameters (not from the Swift coefficients), so a match
checks the Swift design and the Swift filter at once.
Usage: python3 -I analyze_resp.py <S1 dir>
"""
import json
import sys

import numpy as np

D = sys.argv[1]
FS = 48000.0
meta = json.load(open(f"{D}/sig/stepped.json"))
freqs = meta["freqs"]
n_log = meta["n_log"]
seg = int(meta["seg"] * FS)
coeffs = json.load(open(f"{D}/out/resp_coeffs.json"))


def amp(x, f, k):
    """Amplitude of the sinusoid at f in the last half of step k (lstsq)."""
    a = k * seg + seg // 2
    y = x[a:(k + 1) * seg].astype(np.float64)
    t = (np.arange(a, (k + 1) * seg)) / FS
    M = np.stack([np.sin(2 * np.pi * f * t), np.cos(2 * np.pi * f * t), np.ones_like(t)], 1)
    c, *_ = np.linalg.lstsq(M, y, rcond=None)
    return np.hypot(c[0], c[1])


def rbj(kind, f0, q=0.7071067811865476, g=0.0, slope=1.0):
    w0 = 2 * np.pi * f0 / FS
    cw, sw = np.cos(w0), np.sin(w0)
    al = sw / (2 * q)
    A = 10 ** (g / 40)
    if kind == "highPass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "peaking":
        b = [1 + al * A, -2 * cw, 1 - al * A]; a = [1 + al / A, -2 * cw, 1 - al / A]
    elif kind == "notch":
        b = [1, -2 * cw, 1]; a = [1 + al, -2 * cw, 1 - al]
    else:
        als = sw / 2 * np.sqrt((A + 1 / A) * (1 / slope - 1) + 2)
        sa = 2 * np.sqrt(A) * als
        if kind == "lowShelf":
            b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sa)]
            a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa]
        else:
            b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)]
            a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
    return np.array(b) / a[0], np.array(a) / a[0]


def mag_db(sections, f):
    z = np.exp(-1j * 2 * np.pi * np.asarray(f) / FS)
    h = np.ones_like(z)
    for b, a in sections:
        h = h * (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    return 20 * np.log10(np.abs(h))


def sections_for(key, apple_doc=False):
    out = []
    for band in coeffs[key]:
        q = band["q"]
        out.append(rbj(band["kind"], band["freq"], q, band["gain"]))
    return out


dry = np.fromfile(f"{D}/out/resp_dry.f32", dtype="<f4")
dry_amp = [amp(dry, f, k) for k, f in enumerate(freqs)]
allf = np.array(freqs)
rows = []
print("Magnitude response, measured through the tap (wet/dry, dB) against RBJ analytic\n")
for key in ["hpf2", "hpf4", "peak", "lowshelf", "highshelf", "notch"]:
    secs = sections_for(key)
    analytic = mag_db(secs, allf)
    # Swift's own coefficients, to separate a design slip from a filter slip.
    swift = [(np.array(c["coef"][:3]), np.array([1.0] + c["coef"][3:])) for c in coeffs[key]]
    swift_db = mag_db(swift, allf)
    print(f"== {key} ==  design/numpy vs Swift coefficients: max {np.max(np.abs(analytic - swift_db)):.2e} dB")
    res = {}
    for who in ["own", "au", "aveq"]:
        try:
            x = np.fromfile(f"{D}/out/resp_{who}.{key}.f32", dtype="<f4")
        except FileNotFoundError:
            continue
        m = np.array([20 * np.log10(amp(x, f, k) / dry_amp[k]) for k, f in enumerate(freqs)])
        res[who] = m
    # Apple's documented form for hpf4 is two Butterworth 2nd-order sections at
    # the same frequency (a Linkwitz-Riley 4th order), not Butterworth 4th.
    doc = analytic
    if key == "hpf4":
        doc = mag_db([rbj("highPass", 80.0)] * 2, allf)
    print(f"{'f Hz':>9} {'analytic':>9} {'own':>9} {'own-an':>8} {'AU':>9} {'AU-an':>8} {'AU-doc':>8} {'AVEQ-AU':>8}")
    for k, f in enumerate(freqs):
        o = res["own"][k]; u = res["au"][k]; v = res.get("aveq", res["au"])[k]
        tag = " (anchor)" if k >= n_log else ""
        print(f"{f:9.1f} {analytic[k]:9.3f} {o:9.3f} {o - analytic[k]:8.4f} {u:9.3f} {u - analytic[k]:8.3f} {u - doc[k]:8.3f} {v - u:8.4f}{tag}")
    lg = slice(0, n_log)
    # Exclude points where the analytic response is below -60 dB (the notch
    # centre), where the measurement floor, not the filter, is read.
    ok = analytic > -60
    own_err = np.max(np.abs(res["own"] - analytic)[ok])
    au_err = np.max(np.abs(res["au"] - analytic)[ok])
    au_doc = np.max(np.abs(res["au"] - doc)[ok])
    aveq_au = np.max(np.abs(res.get("aveq", res["au"]) - res["au"]))
    print(f"  max |own − analytic| {own_err:.4f} dB; max |AU − RBJ same params| {au_err:.3f} dB; "
          f"max |AU − documented form| {au_doc:.3f} dB; max |AVAudioUnitEQ − AUNBandEQ| {aveq_au:.4f} dB\n")
    rows.append((key, own_err, au_err, au_doc, aveq_au))

json.dump([dict(zip(["key", "own_err", "au_rbj_err", "au_doc_err", "aveq_vs_au"], map(lambda v: v if isinstance(v, str) else float(v), r))) for r in rows],
          open(f"{D}/out/resp_summary.json", "w"), indent=1)
