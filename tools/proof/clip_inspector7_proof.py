#!/usr/bin/env python3
"""Issue batch B50 (#102) — the section header's hover (spec §11 CI-15 as
amended) and Normalize's boxed mono 9 "clip" tag.

    python3 tools/proof/clip_inspector7_proof.py
    python3 tools/proof/clip_inspector7_proof.py --mutant NAME

Two instruments, `clip_inspector6_proof.py`'s shape, with no MCP section
(nothing here is reachable over MCP, and a hover cannot be seen offscreen):

* **the probe**, `clip_inspector7_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). H1 (a CONTROL) replaces NSWorkspace's Reduce Motion
  getter with a block answering a global, so `DS.reduceMotion` reads as
  forced. H2–H6 host a bare `InspectorSection` in a 304 × 120 window ordered
  in: H2 one owner-filtered tracking area and the rest state; H3 (Reduce
  Motion off) `mouseEntered` / `mouseExited` set the band's alpha at once and
  leave an `opacity` animation of 0.14 s on its layer; H4 (on) the same calls
  leave none; H5 the band is the first subview, (0, 0, w, h − 1), and a hit
  at its centre answers the header; H6 (on) `cacheDisplay` of the header
  hovered and at rest differs at (2, 2) and is equal on the rule's row. Before
  each H3/H4 call and each H6 capture the band's layer is cleaned
  (`removeAllAnimations()`, keys then empty, else the row fails). T1–T4 use
  the `audio` fixture on Sound ▸ Volume: T1 with action 10 selected one
  visible `InspectorClipTag` right after an `OptionButtonControl`; T2 with no
  action selected it is hidden; T3 its intrinsic size is (⌈text width⌉ + 10,
  17) and, captured alone, its border is drawn, (2, 2) is clear and its text
  is drawn; T4 (issue batch B53, #209) one pane refreshed in place — action
  10 selected, cleared, reselected, each followed by `binding.invalidate()`
  and `refresh()` — holds the SAME tag, read through a view walk (never a
  rebuild), visible, hidden, visible. `tag-hidden` and `tag-always` fail T4
  too; `tag-frozen` (the first `refresh()` decides for good) fails T4 alone.
* **the harness** (`e2.build_harness()`, 1440 × 1500) over the same package,
  Sound ▸ Volume expanded: C1 (light) and C2 (dark) at 1.5 s with action 0
  selected, C3 (light) and C4 (dark) at 3 s with none. Each is rendered
  twice: byte-identical, and light ≠ dark. They are determinism rows over
  captures a person reads (`work/clip-inspector7/`), and take no mutant.

`--mutant NAME` builds the probe over a COPY of `app/Sources` with one
mutation, `MUTANTS[NAME]` (each anchor found exactly once), and exit 0 means
EXACTLY that mutant's rows failed in the copy and nothing else did (`MUTANT
PASS`). The harness is not re-run under a mutant.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (project, write_package, AUDIO_MEDIA, build_harness)
import clip_inspector_proof as ci  # noqa: E402  (action, media_clip, build_probe)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector7")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector7_probe.swift")
LOOKS = ["light", "dark"]

HEADER = "InspectorSectionHeader.swift"
MARKS = "InspectorMarks.swift"
ANIMATE = "        DS.animate(DS.hoverDuration) {\n"

H2 = ("H2 after two updateTrackingAreas() the header owns exactly one area, its bounds, "
      "mouseEnteredAndExited and activeInKeyWindow; at rest isHovered is false and the band's "
      "alpha 0")
H3 = ("H3 Reduce Motion off: from a clean layer mouseEntered sets alpha 1 at once and the band's "
      "layer carries an opacity animation of 0.14 s; mouseExited the same to 0")
H4 = ("H4 Reduce Motion on: from a clean layer mouseEntered sets alpha 1 and mouseExited 0, and "
      "the band's layer carries no animation after either")
H5 = ("H5 the band is the header's first subview, framed (0, 0, w, h − 1), and a hit at its "
      "centre answers the header")
H6 = ("H6 Reduce Motion on, from a clean layer: the header captured hovered and at rest differs "
      "at (2, 2) and is equal on the rule's row, y = h − 0.5")
T1 = ("T1 with action 10 selected, Sound ▸ Volume holds exactly one InspectorClipTag, visible, "
      "the arranged subview right after an OptionButtonControl")
T2 = "T2 with no action selected (playhead 3 s), the tag is hidden"
T3 = ("T3 the tag's intrinsic size is (ceil(text width in mono 9) + 10, 17); captured alone, "
      "(0.5, h/2) is drawn, (2, 2) is clear and some interior pixel is drawn")
T4 = ("T4 one pane refreshed in place: the same InspectorClipTag shows with action 10 selected, "
      "hides when the action is cleared, shows again when 10 is reselected")

MUTANTS = {
    "no-tracking": {
        "file": HEADER,
        "anchor": ("        addTrackingArea(\n"
                   "            NSTrackingArea(\n"
                   "                rect: bounds, options: [.mouseEnteredAndExited, "
                   ".activeInKeyWindow],\n"
                   "                owner: self, userInfo: nil))\n"),
        "replacement": "        // mutant: no tracking area\n",
        "expected": [H2],
        "note": "the header's addTrackingArea statement is deleted",
    },
    "unanimated": {
        "file": HEADER,
        "anchor": ANIMATE,
        "replacement": "        do {\n",
        "expected": [H3],
        "note": "the hover's alpha is set outside any animation group",
    },
    "ignores-reduce-motion": {
        "file": HEADER,
        "anchor": ANIMATE,
        "replacement": ("        NSAnimationContext.runAnimationGroup { context in "
                        "context.duration = DS.hoverDuration; "
                        "context.allowsImplicitAnimation = true;\n"),
        "expected": [H4],
        "note": "the hover animates whatever Reduce Motion says",
    },
    "band-hit": {
        "file": HEADER,
        "anchor": ("    override func hitTest(_ point: NSPoint) -> NSView? {\n"
                   "        nil\n"
                   "    }\n"),
        "replacement": "",
        "expected": [H5],
        "note": "the band's hitTest override is deleted",
    },
    "band-blank": {
        "file": HEADER,
        "anchor": ("    override func draw(_ dirtyRect: NSRect) {\n"
                   "        DS.hoverFill.setFill()\n"),
        "replacement": ("    override func draw(_ dirtyRect: NSRect) {\n"
                        "        NSColor.clear.setFill()\n"),
        "expected": [H6],
        "note": "the band fills NSColor.clear",
    },
    "tag-hidden": {
        "file": MARKS,
        "anchor": "        isHidden = binding?.selectedAction == nil\n",
        "replacement": "        isHidden = true\n",
        "expected": [T1, T4],
        "note": "the tag's refresh always hides it",
    },
    "tag-always": {
        "file": MARKS,
        "anchor": "        isHidden = binding?.selectedAction == nil\n",
        "replacement": "        isHidden = false\n",
        "expected": [T2, T4],
        "note": "the tag's refresh always shows it",
    },
    "tag-frozen": {
        "file": MARKS,
        "anchor": ("    func refresh() {\n"
                   "        isHidden = binding?.selectedAction == nil\n"
                   "    }\n"),
        "replacement": ("    private var frozen: Bool?\n"
                        "    func refresh() {\n"
                        "        if frozen == nil { frozen = binding?.selectedAction == nil }\n"
                        "        isHidden = frozen ?? true\n"
                        "    }\n"),
        "expected": [T4],
        "note": "the tag's first refresh decides it for good",
    },
    "tag-blank": {
        "file": MARKS,
        "anchor": ("        DS.border.setStroke()\n"
                   "        let box = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))\n"
                   "        box.lineWidth = 1\n"
                   "        box.stroke()\n"
                   "        let attributes: [NSAttributedString.Key: Any] = [\n"
                   "            .font: DS.mono(9), .foregroundColor: DS.textMuted,\n"
                   "        ]\n"
                   "        let size = Self.text.size(withAttributes: attributes)\n"
                   "        Self.text.draw(\n"
                   "            at: NSPoint(x: (bounds.width - size.width) / 2, "
                   "y: (bounds.height - size.height) / 2),\n"
                   "            withAttributes: attributes)\n"),
        "replacement": "        // mutant: the tag draws nothing\n",
        "expected": [T3],
        "note": "the tag's draw is emptied",
    },
}
PROBE_COUNTS = {"H1": 1, "H2": 1, "H3": 1, "H4": 1, "H5": 1, "H6": 1, "T1": 1, "T2": 1,
                "T3": 1, "T4": 1}

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    clip = ci.media_clip(2, 90, 0, [ci.action(10, 1, 2, {"audio": {"volume": 0.5}})],
                         video=False)
    return {"audio": e2.write_package("ci7-audio", e2.project([clip], media=e2.AUDIO_MEDIA))}


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s swiftc line, over THIS batch's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


def probe_checks(sources, out, paths):
    print("\n1 — the probe: H1–H6 the header's hover, T1–T4 the \"clip\" tag")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
    request = os.path.join(out, "request.json")
    answer = os.path.join(out, "answer.json")
    if os.path.exists(answer):
        os.remove(answer)
    with open(request, "w") as f:
        json.dump(paths, f, indent=2)
    try:
        result = subprocess.run([binary, request, answer], capture_output=True, text=True,
                                timeout=300)
    except subprocess.TimeoutExpired:
        check("the probe runs", False, "expired after 300 s")
        return
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return
    with open(answer) as f:
        rows = json.load(f)["rows"]
    counts = {k: sum(1 for r in rows if r["name"].startswith(k + " ")) for k in PROBE_COUNTS}
    check("the probe answers every row (H1–H6, T1–T4, one each) and no T0 fixture row",
          counts == PROBE_COUNTS and not any(r["name"].startswith("T0 ") for r in rows),
          f"{counts}")
    for row in rows:
        check(row["name"], row["ok"], row["detail"])


# ---------------------------------------------------------------------------
# The harness.

C_ROWS = [
    ("C1", "light", "1.5", "0"),
    ("C2", "dark", "1.5", "0"),
    ("C3", "light", "3", "-"),
    ("C4", "dark", "3", "-"),
]


def harness_checks(package):
    print("\n2 — the harness: Sound ▸ Volume with and without action 10, light and dark, "
          "1440 × 1500")
    binary, error = e2.build_harness()
    renders = {}
    for label, look, playhead, action in C_ROWS:
        for copy in ("a", "b"):
            if error:
                break
            out = os.path.join(WORK, f"{label.lower()}-{look}-{copy}.png")
            if os.path.exists(out):
                os.remove(out)
            try:
                done = subprocess.run(
                    [binary, package, out, look, "1440", "1500", "0", playhead, "1", "clip",
                     "-", "audio.volume", "-", action, "sound"],
                    capture_output=True, text=True, timeout=120)
                rc, text = done.returncode, (done.stdout + done.stderr)
            except subprocess.TimeoutExpired:
                rc, text = None, "expired after 120 s"
            if rc != 0 or not os.path.exists(out):
                error = text.strip()[-400:] or f"rc {rc}"
            renders[(label, copy)] = out

    def data(label, copy):
        with open(renders[(label, copy)], "rb") as f:
            return f.read()
    for label, look, playhead, action in C_ROWS:
        selected = "action 0 selected" if action != "-" else "no action selected"
        name = (f"{label} Sound ▸ Volume at {playhead} s, {selected}, {look}, rendered twice: "
                "byte-identical PNGs, and light ≠ dark")
        if error:
            check(name, False, error)
            continue
        twin = {"C1": "C2", "C2": "C1", "C3": "C4", "C4": "C3"}[label]
        same = data(label, "a") == data(label, "b")
        differs = data(label, "a") != data(twin, "a")
        check(name, same and differs,
              f"{os.path.relpath(renders[(label, 'a')], ROOT)}; twin identical {same}, "
              f"light ≠ dark {differs}")


# ---------------------------------------------------------------------------


def mutant(mode):
    spec = MUTANTS[mode]
    expected = spec["expected"]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-clip-inspector7-{mode}-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, spec["file"])
        with open(path) as f:
            text = f.read()
        if text.count(spec["anchor"]) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(spec['anchor'])} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(spec["anchor"], spec["replacement"], 1))
        print(f"MUTANT {mode}: {spec['note']}, in {sources}")
        paths = packages()
        probe_checks(sources, os.path.join(temp, "probe"), paths)
    failed = [n for n, ok in RESULTS if not ok]
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(expected):
        print(f"MUTANT PASS: {mode} — exactly the {len(expected)} expected row(s) FAILED "
              f"in the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {mode} — built {built}; missing failures "
          f"{[n for n in expected if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in expected]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Issue batch B50 (#102) — the header hover and the \"clip\" tag")
    paths = packages()
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    harness_checks(paths["audio"])
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
