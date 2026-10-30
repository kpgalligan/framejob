"""Where and how does the preview's tap output depart from the export path's?
Usage: python3 -I analyze_preview.py <S1 dir> <key> <channels>
"""
import sys

import numpy as np

D, key, ch = sys.argv[1], sys.argv[2], int(sys.argv[3])
cap = np.fromfile(f"{D}/out/preview_{key}.f32", dtype="<f4").reshape(-1, ch)
exp = np.fromfile(f"{D}/out/preview_export_{key}.f32", dtype="<f4").reshape(-1, ch)
rows = [l.split("\t") for l in open(f"{D}/out/preview_{key}_callbacks.tsv").read().split("\n") if l]
off = 0
for i, (st, sz) in enumerate(rows):
    st, sz = int(st), int(sz)
    seg = cap[off:off + sz]
    off += sz
    if st < 0 or len(seg) < sz or st + sz > len(exp):
        continue
    e = exp[st:st + sz]
    d = np.abs(seg - e)
    if d.max() == 0:
        continue
    k = int(np.argmax(d.max(1) > 0))
    # Is it the export shifted? Search lags -8192..8192 for an exact match of the first differing 64 frames.
    probe = seg[k:k + 64]
    found = None
    for lag in range(-8192, 8193):
        a = st + k + lag
        if 0 <= a and a + 64 <= len(exp) and np.array_equal(exp[a:a + 64], probe):
            found = lag
            break
    ratio = np.median(np.abs(seg[k:]) / (np.abs(e[k:]) + 1e-12))
    print(f"callback {i} start {st}: first diff at +{k} (frame {st + k}), max |Δ| {d.max():.3g}; "
          f"exact match in export at lag {found}; median |preview|/|export| after it {ratio:.3f}")
    if i > 60:
        break
