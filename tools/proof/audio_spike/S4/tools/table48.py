"""The 48 kHz named-window table: direct, ffmpeg, cache at 100/25/10 ms, phase band, TP."""
import sys

def win(p):
    out = []
    for l in open(p):
        if l.startswith('#'):
            continue
        c = [x.split() for x in l.split('|')]
        out.append(dict(a=float(c[0][0]), b=float(c[0][1]), near=float(c[1][0]), direct=float(c[2][0]),
                        pmin=float(c[2][1]), pmax=float(c[2][2]), ctp=float(c[3][0]), dtp=float(c[3][1])))
    return out

d = sys.argv[1]
w100, w25, w10 = win(f"{d}/win48ex_10.txt"), win(f"{d}/win48ex_40.txt"), win(f"{d}/win48ex_100.txt")
ff = [l.split() for l in open(f"{d}/ff48.txt")]
print("| window (s) | length | DIRECT (export of the window) | ffmpeg (Δ) | cache 100 ms (Δ) | cache 25 ms (Δ) | cache 10 ms (Δ) | DIRECT's phase band | TP cache / DIRECT / ffmpeg (dBTP) |")
print("|---|---|---|---|---|---|---|---|---|")
for r100, r25, r10, f in zip(w100, w25, w10, ff):
    D = r10['direct']
    fI = float(f[3])
    print(f"| {r10['a']:.3f}–{r10['b']:.3f} | {r10['b']-r10['a']:.1f} | {D:.3f} | {fI:.3f} ({fI-D:+.3f}) | "
          f"{r100['near']:.3f} ({r100['near']-D:+.3f}) | {r25['near']:.3f} ({r25['near']-D:+.3f}) | "
          f"{r10['near']:.3f} ({r10['near']-D:+.3f}) | {r10['pmin']:.3f} … {r10['pmax']:.3f} | "
          f"{r10['ctp']:.3f} / {r10['dtp']:.3f} / {float(f[5]):.3f} |")
