#!/usr/bin/env python3
"""kpgalligan/reelcut#117 — the canvas text editor breaks lines where the
render does (spec §11 K-3).

    python3 tools/proof/text_break_proof.py
    python3 tools/proof/text_break_proof.py --baseline <commit>
    python3 tools/proof/text_break_proof.py --mutant NAME

One instrument, the probe `text_break_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` included, with the
app's `Compositor.metal` built into a `default.metallib` beside it (a probe
that will not build is a scored FAILURE, never an exit). In the app's own
window it opens the in-canvas editor over one text clip per fixture and
compares the editor's line STARTS with the render's
(`LayerRenderers.layout(for:)`), typing by key events through
`NSWindow.sendEvent` and applying through the canvas's `onEdit`. The split
is pinned (an argument-domain inspector width 304, timeline height 300,
inspector shown) and every window is set to content 1600 × 1000 before its
editor opens (B32):

  E0 (control) the font resolves;
  E1 plain, left, fixed width: the render has ≥ 3 lines, and the line starts
     are equal (both controls);
  E2 `tracking` 24: line starts equal;
  E3 E2 after " and more" is typed: equal to the applied render's (the keys
     typed, a control);
  E4 E2 after the window shrinks to 75 % (the canvas scale moving by more
     than 5 %, a control): equal;
  E5 `line_spacing` 1.8: line starts equal (control), and each line pitch
     within 1 pt of the render's × scale;
  E6 size 12 at video scale 0.6, 240 px wide: size × scale < 8 pt
     (control), the frame the box + 2 px within 1 pt (control), line starts
     equal — the detail prints the editor's wrap width and width × scale;
  E7 `case: upper` (control, K-3's premise): the editor holds `content`, not
     `laidContent`, before and after "ab" is typed;
  E8 E2's fixture emptied by Delete over the select-all (empty and first
     responder, control), then "Wrap" typed (control): the storage's font size
     and kern at index 0 are the render's × scale, and the line starts equal
     the applied render's;
  E9 auto-sized, centred, one line at `tracking` 24: the render has one line
     (control), the editor lays out one; after " again" is typed, the applied
     render has one line (control) and the editor still lays out one.

A probe that dies scores every row it did not write as FAIL.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` in `work/text-break/baseline/` and follows rule R: exit 1 is
CAUGHT — exactly the rows in `BASELINE_EXPECTED` fail and every other row
passes; 0 is SURVIVED; 2 is NOT PERFORMED (the archive, the build or the run
failed, a row was never written, or a CONTROL failed), printed as
`baseline <commit>: the control could not be performed — <why>`.

`--mutant NAME` builds the same probe over a copy of `app/Sources` in
`work/text-break/mutant-<name>/` with one edit (`MUTANTS`), and follows rule
R: 1 caught when every row it names failed, 0 survived when one passed, 2
not performed (an anchor not found exactly once, the build or the run
failed, a row was never written, or a CONTROL failed). `pre-fix-width` puts
`widthTracksTextView` back on and deletes the `containerSize` lines (#186
item 1): E6's line-start row must fail.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (video_props, project, write_package)
import text_edit_proof as te  # noqa: E402  (build_shader)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "text-break")
PROBE_SWIFT = os.path.join(HERE, "text_break_probe.swift")
HEADER = os.path.join(ROOT, "core", "include", "reelcut_core.h")
TICKS = e2.TICKS

ROWS = [
    "E0 the fixtures' font SourceSans3-SemiBold resolves (a CONTROL)",
    "E1 plain: the render lays out 3 lines or more (a CONTROL)",
    "E1 plain: the editor's line starts equal the render's (a CONTROL)",
    "E2 tracking 24: the editor's line starts equal the render's",
    "E3 tracking 24: every key of \" and more\" was typed into the editor (a CONTROL)",
    "E3 tracking 24, after typing \" and more\": the editor's line starts equal the applied "
    "render's",
    "E4 tracking 24, window at 75 %: the canvas scale moved by more than 5 % (a CONTROL)",
    "E4 tracking 24, window at 75 %: the editor's line starts equal the render's",
    "E5 line spacing 1.8: the editor's line starts equal the render's (a CONTROL)",
    "E5 line spacing 1.8: each line pitch is within 1 pt of the render's × scale",
    "E6 size 12: size × scale is under 8 pt (a CONTROL)",
    "E6 size 12: the editor is not floored — its frame is the box + 2 px within 1 pt "
    "(a CONTROL)",
    "E6 size 12: the editor's line starts equal the render's",
    "E7 case upper: the editor holds content, not laidContent, before and after typing "
    "\"ab\" (a CONTROL)",
    "E8 emptied: Delete over the select-all leaves the editor empty and first responder "
    "(a CONTROL)",
    "E8 emptied, then \"Wrap\" typed: the editor holds \"Wrap\" (a CONTROL)",
    "E8 emptied, then \"Wrap\" typed: the storage's font size and kern at index 0 are the "
    "render's × scale",
    "E8 emptied, then \"Wrap\" typed: the editor's line starts equal the applied render's",
    "E9 auto-sized, tracking 24: the render lays out exactly one line (a CONTROL)",
    "E9 auto-sized, tracking 24: the editor lays out exactly one line",
    "E9 after typing \" again\": the applied render has exactly one line (a CONTROL)",
    "E9 after typing \" again\": the editor still lays out exactly one line",
]

E6_STARTS = "E6 size 12: the editor's line starts equal the render's"
FRAME = "PreviewCanvasView+TextEditFrame.swift"

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "pre-fix-width": ([E6_STARTS], [
        (FRAME, "        editor.textContainer?.widthTracksTextView = false",
         "        editor.textContainer?.widthTracksTextView = true"),
        (FRAME, "        editor.textContainer?.containerSize = NSSize(\n"
                "            width: width - 2 * editor.textContainerInset.width,\n"
                "            height: CGFloat.greatestFiniteMagnitude)\n", "")]),
}

# What the unfixed editor gets wrong; every other row passes on both trees.
BASELINE_EXPECTED = [
    "E2 tracking 24: the editor's line starts equal the render's",
    "E3 tracking 24, after typing \" and more\": the editor's line starts equal the applied "
    "render's",
    "E4 tracking 24, window at 75 %: the editor's line starts equal the render's",
    "E5 line spacing 1.8: each line pitch is within 1 pt of the render's × scale",
    "E6 size 12: the editor's line starts equal the render's",
    "E8 emptied, then \"Wrap\" typed: the storage's font size and kern at index 0 are the "
    "render's × scale",
]

RESULTS = []  # (name, ok, instrument)


def check(name, ok, detail="", *, instrument=False):
    RESULTS.append((name, bool(ok), instrument))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def format_version():
    with open(HEADER) as f:
        found = re.search(r"#define RC_FORMAT_VERSION (\d+)", f.read())
    return int(found.group(1)) if found else 10


SENTENCE = "The quick brown fox jumps over the lazy dog while the band plays on"
SMALL = ("Small print runs on and on across the box, line after line, so the editor "
         "has many lines to break at twelve pixels, far under the old eight point clamp, "
         "and every one of them must break where the render breaks it, word for word, "
         "to the last full stop.")


def text_clip(content, width=900.0, align="left", size=96.0, tracking=0.0, spacing=1.0,
              case=None):
    text = {
        "content": content, "font": "SourceSans3-SemiBold", "size": size,
        "color": [1.0, 1.0, 1.0, 1.0], "align": align, "valign": "middle",
        "line_spacing": spacing, "tracking": tracking, "outline": None, "backdrop": None,
        "width": width,
    }
    if case:
        text["case"] = case
    return {
        "id": 2, "track": 1, "start": 0, "duration": 6 * TICKS,
        "source": {"kind": "text"}, "enabled": {"video": True, "audio": True},
        "speed": 1.0, "video": e2.video_props(), "audio": None, "text": text,
        "shape": None, "actions": [], "transition_in": None, "name": None, "label": None,
    }


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = os.path.join(WORK, "fixtures")
    version = format_version()

    def package(name, clip):
        body = e2.project([clip])
        body["version"] = version
        return e2.write_package(name, body)

    # At video scale 0.6 the view size is near 5 pt, far enough under the old
    # 8 pt clamp that the clamped font breaks elsewhere.
    small = text_clip(SMALL, width=240.0, size=12.0)
    small["video"]["scale"] = 0.6
    return {
        "fonts": os.path.join(ROOT, "app", "Resources", "Fonts"),
        "plain": package("plain", text_clip(SENTENCE)),
        "tracking": package("tracking", text_clip(SENTENCE, tracking=24.0)),
        "spacing": package("spacing", text_clip(SENTENCE, spacing=1.8)),
        "small": package("small", small),
        "upper": package("upper", text_clip("Hello world", case="upper")),
        "auto": package("auto", text_clip("Hello world", width=None, align="center",
                                          tracking=24.0)),
    }


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "text-break-probe")
    shader, why = te.build_shader(out)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary) for f in swift + [entry, lib]):
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    start = time.time()
    try:
        result = subprocess.run(
            ["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk, "-target",
             "arm64-apple-macos26.0", "-module-name", "Reelcut",
             "-import-objc-header", os.path.join(ROOT, "app", "Bridging",
                                                 "Reelcut-Bridging-Header.h"),
             "-L", os.path.dirname(lib), "-lreelcut_core"] + swift + [entry, "-o", binary],
            capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return None, "swiftc expired after 900 s"
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    print(f"  probe built in {time.time() - start:.0f} s")
    return binary, None


def probe_checks(sources, out, paths):
    print("\n1 — the probe: E0–E9, in the app's own window")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "",
          instrument=binary is None)
    if binary is None:
        return False
    request = os.path.join(out, "request.json")
    answer = os.path.join(out, "answer.json")
    if os.path.exists(answer):
        os.remove(answer)
    with open(request, "w") as f:
        json.dump(paths, f, indent=2)
    try:
        result = subprocess.run([binary, request, answer], capture_output=True, text=True,
                                timeout=300)
        ran, tail = result.returncode == 0, (result.stdout + result.stderr).strip()[-400:]
    except subprocess.TimeoutExpired:
        ran, tail = False, "the probe expired after 300 s"
    rows = []
    if os.path.exists(answer):
        try:
            with open(answer) as f:
                rows = json.load(f)["rows"]
        except (ValueError, KeyError) as error:
            tail += f"; the answer did not read: {error}"
    check("the probe runs to its end", ran, "" if ran else tail, instrument=not ran)
    written = {r["name"]: r for r in rows}
    for row in rows:
        if row["name"] not in ROWS:
            check(row["name"], False, "a row this proof does not know: " + row["detail"],
                  instrument=True)
    for name in ROWS:
        row = written.get(name)
        if row is None:
            check(name, False, "no row: the probe did not write it", instrument=True)
        else:
            check(name, row["ok"], row["detail"])
    return True


def baseline(commit):
    began = time.time()
    tree = os.path.join(WORK, "baseline")
    if os.path.exists(tree):
        shutil.rmtree(tree)
    os.makedirs(tree)

    def not_performed(why):
        print(f"baseline {commit}: the control could not be performed — {why}")
        return 2

    archive = subprocess.run(["git", "-C", ROOT, "archive", commit, "app/Sources"],
                             capture_output=True)
    if archive.returncode != 0:
        return not_performed(f"git archive {commit} failed: "
                             f"{archive.stderr.decode(errors='replace').strip()}")
    untar = subprocess.run(["tar", "-x", "-C", tree], input=archive.stdout,
                           capture_output=True)
    if untar.returncode != 0:
        return not_performed(f"tar failed: {untar.stderr.decode(errors='replace').strip()}")
    print(f"BASELINE {commit}: app/Sources in {os.path.relpath(tree, ROOT)}")
    probe_checks(os.path.join(tree, "app", "Sources"), os.path.join(tree, "out"), packages())
    elapsed = time.time() - began
    instruments = [n for n, ok, inst in RESULTS if inst and not ok]
    if instruments:
        return not_performed(f"instrument failures {instruments}, {elapsed:.0f} s")
    failed = sorted(n for n, ok, _ in RESULTS if not ok)
    controls = [n for n in failed if "(a CONTROL)" in n]
    if controls:
        return not_performed(f"controls failed on {commit}: {controls}, {elapsed:.0f} s")
    if failed == sorted(BASELINE_EXPECTED):
        print(f"BASELINE CAUGHT: exactly the {len(BASELINE_EXPECTED)} expected rows FAILED on "
              f"{commit} and every other row passed, {elapsed:.0f} s")
        return 1
    print(f"BASELINE SURVIVED: failed {failed} (want {sorted(BASELINE_EXPECTED)}), "
          f"{elapsed:.0f} s")
    return 0


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; the reason when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = os.path.join(dest, file)
        text = open(path).read() if os.path.exists(path) else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        with open(path, "w") as f:
            f.write(text.replace(before, after))
    return None


def mutant(name):
    began = time.time()
    here = os.path.join(WORK, f"mutant-{name}")
    if os.path.exists(here):
        shutil.rmtree(here)
    os.makedirs(here)

    def not_performed(why):
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2

    sources = os.path.join(here, "Sources")
    why = mutate(os.path.join(ROOT, "app", "Sources"), name, sources)
    if why:
        return not_performed(why)
    print(f"MUTANT {name}: app/Sources in {os.path.relpath(sources, ROOT)}")
    probe_checks(sources, os.path.join(here, "out"), packages())
    elapsed = time.time() - began
    instruments = [n for n, ok, inst in RESULTS if inst and not ok]
    if instruments:
        return not_performed(f"instrument failures {instruments}, {elapsed:.0f} s")
    failed = sorted(n for n, ok, _ in RESULTS if not ok)
    controls = [n for n in failed if "(a CONTROL)" in n]
    if controls:
        return not_performed(f"controls failed: {controls}, {elapsed:.0f} s")
    named = MUTANTS[name][0]
    survived = [n for n in named if n not in failed]
    if survived:
        print(f"mutant {name}: SURVIVED — {survived} passed (all failures: {failed}), "
              f"{elapsed:.0f} s")
        return 0
    print(f"mutant {name}: caught — {named} failed (all failures: {failed}), {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant":
        if sys.argv[2] not in MUTANTS:
            print(f"mutant {sys.argv[2]}: the control could not be performed — no such "
                  f"mutant; one of {sorted(MUTANTS)}")
            return 2
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#117 — the canvas text editor breaks lines where the render does")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
