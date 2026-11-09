"""Road map "audio" AP8a — the volume line (spec §11 AU-80…AU-84): its probe
and its mutants.

    python3 tools/proof/volume_line_proof.py --probe
    python3 tools/proof/volume_line_proof.py --mutants

No instance: the line is drawing, a hit test and a gesture over ops the core
already has, so every row is in-process. `--probe` runs V1–V10 over
`app/Sources`; `--mutants` runs M1–M14 (or only the mutants named after it,
`--mutants M14`), each over its own copy of `app/Sources`, killed when its
named row fails (a mutant that does not build is scored a failure). Output is under `tools/proof/work/volume_line/`.

**The probe**, `volume_line_probe.swift`, compiled AS `main.swift` over every
file in `app/Sources` but the app's own `main.swift` on `swift_build.py`'s
line, with the app's `Compositor.metal` built into a `default.metallib`
beside it (`editor_keys_undo_proof.build_shader`). Its fixture is built by
ops — a 10 s tone it writes, on three tracks: track A at volume 0.5 with the
main clip (volume 0.5, a 0.5 s fade in, a linear volume action [1 s, 2 s) to
2.0, a pan-only action [3 s, 4 s)), track B a clip at 6 s ducking by extent,
track C muted with a second clip.

- **V1** the drawn polyline's vertices equal the plan's ramps through the
  scale (≤ 0.01 pt) on a rect computed by the probe (the audio region below
  the action lane, inset 1 pt); one point, at the volume action's end; the
  muted track's clip's line on the floor.
- **V2** `VolumeScale`: y(32) the top, y(1) 30.103/90.103 down, y(0) the
  bottom, `decibels` the inverse within 1e-9 dB.
- **V3** targets: 0.5 s the base; 1.5, 2.5, 3.5 (inside the pan-only action)
  and 4.5 s (after it) the volume action.
- **V4** a +6.0206 dB drag on the base → `set_audio` volume 1.0 (1e-9); the
  clamp at 32; below the press at the bottom → 0; from 0 → 0.001·10^(Δ/20);
  the muted clip's floor line pressed with a 0 pt move stays, 1 pt up rises.
- **V5** ⌥ at 5 s → `add_action(at: 4 s, duration: 1 s)` and the end on
  `next_id`; applied, the plan's gain unchanged at every frame; ⌥ at 2 s and
  at 4 s → nil.
- **V6** ⌥ at 1.25 s splits the volume action and the evaluated volume at 20
  times in [1 s, 2 s) is unchanged (1e-9); ⌥ at 1 s and at 3.5 s → nil; eased,
  both halves carry the curve and the values at t and 2 s are kept; the clip
  trimmed to 1.5 s (the volume action left past its end), ⌥ at 1.25 s → nil.
- **V7** an offscreen `EditorViewController`: a drag on the line is one undo
  step "Set Volume" that one undo reverses to the original JSON; a ⌥ click is
  one step "Add Volume Point", likewise.
- **V8** the fade handle, the action band and the edge grab win over the line
  (the last where the line alone would take the point); 3 pt off the line is
  `.volumeLine`, 6 pt `.clip`; `resolvingVolumeLine` for ⇧, ⌥⇧, a
  double-click, plain and ⌥; a ⇧-press on an unselected clip's line adds it
  to the selection and starts no volume session.
- **V9** the clip painted by `cacheDisplay` with and without the line: the
  pixels differ at three points on it and are equal 4 pt above them.
- **V10** a ⌥-press in a clip's last partial frame (#392, AU-83 as amended):
  on a new 30 fps project, a clip whose duration is 2 s + 15,000 ticks
  (written into the project's JSON and read back, since `add_clip` floors a
  clip onto the grid) pressed at
  1,212,000 adds `[0, 1,200,000)`, and one over a 2 s media pressed at
  1,195,000 adds `[0, 1,180,000)`; each prefix applies.

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff all pass.
"""

from pathlib import Path
import shutil
import subprocess
import sys

import editor_keys_undo_proof as eku  # noqa: E402  (build_shader)
import swift_build  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / "work" / "volume_line"
PROBE_ROWS = [f"V{n}" for n in range(1, 11)]

# (name, killing row, file, old, new)
MUTANTS = [
    ("M1", "V2", "VolumeLine.swift",
     "static let topDB: Double = 20 * log10(AudioNormalize.maxGain)",
     "static let topDB: Double = 12"),
    ("M2", "V4", "VolumeLine.swift",
     "        if atBottom { return 0 }\n",
     "        if atBottom { return 0.001 }\n"),
    ("M3", "V4", "VolumeLine.swift",
     "min(max(max(start, 0.001) * pow(10, decibels / 20), 0), AudioNormalize.maxGain)",
     "min(max(start * pow(10, decibels / 20), 0), AudioNormalize.maxGain)"),
    ("M4", "V3", "VolumeLine.swift",
     "if let inside = naming.first(where: { $0.start <= clipTime && clipTime < $0.endTime }),",
     "if let inside = naming.first(where: { _ in false }),"),
    ("M5", "V3", "VolumeLine.swift",
     "if let held = naming.filter({ $0.endTime <= clipTime })",
     "if let held = clip.actions.filter({ $0.endTime <= clipTime })"),
    ("M6", "V5", "VolumeLine.swift",
     "let prevEnd = clip.actions.map(\\.endTime).filter { $0 <= t }.max() ?? 0",
     "let prevEnd: Ticks = 0"),
    ("M7", "V6", "VolumeLine.swift",
     "            if inside.curve != .linear {\n"
     "                prefix.append(.setAction(clip: clip.id, action: nextId, curve: inside.curve))\n"
     "            }\n",
     ""),
    ("M8", "V8", "TimelineView.swift",
     "            if let hit = actionHit(clip, rect: rect, at: point) { return hit }\n",
     "            if let hit = actionHit(clip, rect: rect, at: point) { return hit }\n"
     "            if let hit = volumeLineHit(clip, rect: rect, at: point) { return hit }\n"),
    ("M9", "V1", "TimelineView+VolumeLine.swift",
     "        if lane.height > 0, lane.maxY > audio.minY, lane.minY < audio.maxY {",
     "        if false, lane.height > 0, lane.maxY > audio.minY, lane.minY < audio.maxY {"),
    ("M10", "V6", "VolumeLine.swift",
     "                  t - inside.start >= frame, inside.endTime <= clip.duration\n",
     "                  t - inside.start >= 0, inside.endTime <= clip.duration\n"),
    ("M11", "V4", "VolumeLine.swift",
     "atBottom: y > pressY && y >= scale.rect.maxY - 1)",
     "atBottom: y >= scale.rect.maxY - 1)"),
    ("M12", "V8", "VolumeLine.swift",
     "              flags.contains(.shift) || clicks == 2\n",
     "              clicks == 2\n"),
    ("M13", "V6", "VolumeLine.swift",
     "t - inside.start >= frame, inside.endTime <= clip.duration\n",
     "t - inside.start >= frame\n"),
    ("M14", "V10", "VolumeLine.swift",
     "        guard clipTime >= 0, clipTime < clip.duration else { return nil }\n"
     "        let t = min(\n"
     "            ReelTime.snapToFrame(clipTime, fps: fps),\n"
     "            TimelineTranscript.frameFloor(clip.duration - 1, fps: fps))\n"
     "        guard let volume = ",
     "        let t = ReelTime.snapToFrame(clipTime, fps: fps)\n"
     "        guard t >= 0, t < clip.duration, let volume = "),
]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, bool(ok)))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run_probe(sources, name):
    """({row: (passed, detail)}, problem) — None rows when it did not build."""
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "volume_line_probe.swift", entry)
    shader, why = eku.build_shader(str(out))
    if shader is None:
        return None, why
    binary = out / "volume-line-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + " | ".join((errors or list(error.diagnostics) or [str(error)])[:6])
    scratch = out / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch)], capture_output=True, text=True,
                                timeout=300, cwd=str(out))
    except subprocess.TimeoutExpired:
        return {}, "the probe ran past 300 s and was killed"
    (out / "stderr.txt").write_text(result.stderr)
    found = {}
    for line in result.stdout.splitlines():
        parts = line.split(" ", 2)
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            detail = parts[2][2:] if len(parts) > 2 and parts[2].startswith("— ") else ""
            found[parts[1]] = (parts[0] == "ok", detail)
    return found, result.stderr.strip()[-600:]


def probe_rows(sources=ROOT / "app/Sources"):
    found, problem = run_probe(sources, "probe")
    for name in PROBE_ROWS:
        if found is None:
            row(name, False, "the probe does not build: " + problem)
        elif name not in found:
            row(name, False, "the probe did not answer: " + problem)
        else:
            row(name, found[name][0], found[name][1])


def mutants(only=()):
    killed = 0
    sources = ROOT / "app/Sources"
    chosen = [m for m in MUTANTS if not only or m[0] in only]
    for name, target, file, old, new in chosen:
        tree = OUT / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        if text.count(old) != 1:
            print(f"{name} FAIL — anchor not found once in {file}", flush=True)
            continue
        path.write_text(text.replace(old, new))
        found, problem = run_probe(tree, f"mutant-{name}")
        if found is None:
            print(f"{name} FAIL — did not build: {problem}", flush=True)
            continue
        dead = found.get(target, (True, ""))[0] is False
        killed += dead
        failing = sorted(r for r, (ok, _) in found.items() if not ok)
        print(f"{name} {'killed' if dead else 'SURVIVED'} by {target} — failing rows: "
              f"{', '.join(failing) or 'none'}", flush=True)
    print(f"{killed}/{len(chosen)} mutants killed", flush=True)
    return bool(chosen) and killed == len(chosen)


def main():
    if sys.argv[1:] == ["--probe"]:
        shutil.rmtree(OUT / "probe", ignore_errors=True)
        probe_rows()
    elif sys.argv[1:2] == ["--mutants"]:
        return 0 if mutants(set(sys.argv[2:])) else 1
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
