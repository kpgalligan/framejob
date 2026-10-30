"""usage: mirror_table.py <mirror 10 ms out> <mirror 100 ms out> <ffref --reverse out>"""
import sys

def rows(p):
    out = []
    for l in open(p):
        if l.startswith('#'):
            continue
        c = [x.split() for x in l.split('|')]
        out.append((c[0][0], c[0][1], float(c[1][0]), float(c[2][0]), float(c[3][0]),
                    float(c[4][0]), float(c[4][1])))
    return out

a = rows(sys.argv[1])
b = rows(sys.argv[2])
ff = [l.split() for l in open(sys.argv[3])]
print("| reversed window (s) | direct on reversed | cache 10 ms mirrored (diff) | cache 100 ms mirrored (diff) | ffmpeg on reversed (diff) | TP cache / direct / ffmpeg |")
print("|---|---|---|---|---|---|")
for r10, r100, f in zip(a, b, ff):
    d = r10[3]
    fI = float(f[3])
    print(f"| {float(r10[0]):.3f}–{float(r10[1]):.3f} | {d:.3f} | {r10[2]:.3f} ({r10[2]-d:+.3f}) | "
          f"{r100[2]:.3f} ({r100[2]-d:+.3f}) | {fI:.3f} ({fI-d:+.3f}) | {r10[5]:.3f} / {r10[6]:.3f} / {float(f[5]):.3f} |")
