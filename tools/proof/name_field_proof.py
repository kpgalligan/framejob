#!/usr/bin/env python3
"""kpgalligan/reelcut#171 — the inspector's name field is the inspector's
value field: filled, a 1 pt `DS.border` stroke, 7 pt padding, the line
centred (spec §11 SH-3).

    python3 tools/proof/name_field_proof.py
    python3 tools/proof/name_field_proof.py --baseline <commit>
    python3 tools/proof/name_field_proof.py --mutant NAME

**The probe**, `name_field_probe.swift`, compiled AS `main.swift` over every
file in `app/Sources` but the app's own `main.swift` on `swift_build.py`'s
line, `-D FRAMEJOB_DEV_TOOLS` included (a probe that will not build is
a scored FAILURE, never an exit), and run once per look, `light` then `dark`
(`NSApp.appearance` set before any view is built, the app's fonts
registered). In an offscreen window: an `InspectorNameField` "HHHH" at 170 ×
`DS.controlHeight`, a header-configured one (12 semibold, re-pinned to
20 pt) and an `OptionFieldControl`, captured by `cacheDisplay` into PNGs kept
in `work/name-field/probe/`:

  N1 the name field's border and interior pixels are the number field's,
     within 2 per channel;
  N2 the cap ink's vertical centre is within 1 pt of the field's;
  N3 the height constraint + 20 pt moves the ink by 10 ± 0.5 pt;
  N4 N3 for the header field;
  N5 N2 and N3 with the field editor attached and the caret at the end,
     measured on the first glyph's columns;
  N6 the ink starts 7–11 pt from the left edge;
  N7 exactly one height constraint of its own, `DS.controlHeight`;
  N8 (control) `UISnapshotLayout.report` over the host finds no problem with
     "Director of Photography";
  N9 and one `truncated` with a string wider than the field. Both read the
     field not editable, as a dimmed row is: an editable `NSTextField` reports
     no intrinsic width (measured -1), so the rule never reaches it. N9 is not
     a control: the rule skips a field whose cell wraps, and the unfixed field
     (not single-line, a wrapping cell) wrapped a long name out of sight.

Then (B32, #186 item 4) an `OptionFieldControl` joins the host under the
name field, at the same leading constraint:

  N13 the name field's box starts within 0.5 pt of the number field's
      (its alignment rect is its frame): scanning right from x 12 at each
      view's mid-height, the first pixel more than 6 from the host's
      background at x 5.

Then (B50, #199) two more name fields with the placeholder "Marker", one
empty and one named "Director of Photography", at leading 220, width 170,
measured with PLACEHOLDER INK (> 20 from the sampled fill; the 60 cannot
see a 25 % placeholder in dark), each extent with its peak channel distance:

  N15 (control) the empty field draws its placeholder at rest;
  N16 with the field editor attached and nothing typed, the placeholder's
      top, bottom and right edges are N15's within 0.5 pt (measured from
      N15's left edge + 4 pt, clear of the caret), and its peak within 10
      of N15's (one copy, not two);
  N17 "i" inserted: the whole interior's ink ends ≥ 10 pt left of N15's
      right edge; deleted: N16 holds again;
  N18 the named field, its field editor attached, select all and delete:
      N16's test against N15, so the old name is not drawn;
  N19 (control) and N20, last, with the window ordered in: `display()`
      leaves the empty field's layer `needsDisplay()` false, and `insertText`
      on its field editor sets it. The layer's flag, because the view's own
      getter reads false here even straight after `needsDisplay = true`.

A probe that dies scores every row it did not write as FAIL.

**The harness** (`harness/build.sh`, the tree's own build, 1440 × 1500) over a
package with one text clip and one marker: the Document tab (H1 light, H2
dark) and the Clip tab with the clip selected (H3 light, H4 dark), each
rendered twice — byte-identical, and light ≠ dark — and kept under
`work/name-field/` to be LOOKED AT.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` in `work/name-field/baseline/` (no harness) and follows rule R:
exit 1 is CAUGHT — exactly N1–N7 and N9 fail in each look and N8 passes in
both; 0
is SURVIVED; 2 is NOT PERFORMED (the archive, the build or a run failed, a
row was never written, or a control failed), printed as `baseline <commit>:
the control could not be performed — <why>`. N13 and N15–N20 (`B32_ROWS`)
are left out of that verdict; their catches are the mutants.

`--mutant NAME` builds the same probe over a copy of `app/Sources` in
`work/name-field/mutant-<name>/` with one edit to `InspectorNameField.swift`
(`MUTANTS`; no harness) and follows rule R: 1 caught when every row it names
failed in both looks, 0 survived when one passed, 2 not performed (an anchor
not found exactly once, the build or a run failed, a row was never written,
or a control failed). `frame-insets` deletes the `alignmentRectInsets`
override: N13 must fail. `cell-placeholder` deletes both placeholder
overrides, so the cell holds it and the field editor draws a second copy:
N16 and N18. `rest-only` puts back HEAD's return while the field editor is
attached: N16 and N17. `always-placeholder` draws the placeholder under the
field editor whatever its string: N17. `no-redisplay` deletes the
`textDidChange` override: N20.
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
import reference_build  # noqa: E402
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "name-field")
PROBE_SWIFT = os.path.join(HERE, "name_field_probe.swift")
HARNESS_BUILD = os.path.join(HERE, "harness", "build.sh")
HEADER = os.path.join(ROOT, "core", "include", "framejob_core.h")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
TICKS = e2.TICKS
LOOKS = ["light", "dark"]

ROW_NAMES = [
    "N1 the name field's border and interior pixels are the number field's, within 2",
    "N2 the cap ink's vertical centre is within 1 pt of the field's",
    "N3 the name field 20 pt taller: the ink moves by 10 ± 0.5 pt",
    "N4 the header's field (12 semibold, 20 pt) 20 pt taller: the ink moves by 10 ± 0.5 pt",
    "N5 with the field editor attached: the first glyph's centre is within 1 pt of the "
    "field's, and 20 pt taller moves it by 10 ± 0.5 pt",
    "N6 the ink starts 7–11 pt from the field's left edge",
    "N7 the name field has exactly one height constraint of its own, DS.controlHeight",
    "N8 the layout dump finds no problem with \"Director of Photography\" (a CONTROL)",
    "N9 the layout dump finds a name wider than the field truncated",
    "N13 the name field's box starts where a number field's box under the same leading "
    "constraint starts, within 0.5 pt",
    "N15 an empty field draws its placeholder \"Marker\" at rest (a CONTROL)",
    "N16 with the field editor attached and nothing typed, the placeholder is drawn once on "
    "its rest rows and right edge, within 0.5 pt",
    "N17 one letter typed: the placeholder is gone; deleted: N16 holds again",
    "N18 a named field cleared with the field editor attached draws the placeholder once on "
    "N15's rows and right edge, within 0.5 pt, and not the old name",
    "N19 with the window ordered in, display() leaves the empty field's needsDisplay false "
    "(a CONTROL)",
    "N20 a letter inserted into the field editor marks the field for display",
]
# B32's row and B50's (N13, N15–N20): left out of `--baseline`'s verdict,
# which is #171's; their catches are the mutants.
B32_ROWS = ROW_NAMES[9:]
ROWS = [f"{name} [{look}]" for look in LOOKS for name in ROW_NAMES]
B32_LOOK_ROWS = [f"{name} [{look}]" for look in LOOKS for name in B32_ROWS]
BASELINE_EXPECTED = [f"{name} [{look}]" for look in LOOKS for name in ROW_NAMES
                     if "(a CONTROL)" not in name and name not in B32_ROWS]

N13 = ROW_NAMES[9]
N16, N17, N18, N20 = ROW_NAMES[11], ROW_NAMES[12], ROW_NAMES[13], ROW_NAMES[15]
FIELD = "InspectorNameField.swift"
SHOWN = "        let shown = editor.map { $0.string } ?? stringValue\n"

# name: (the rows it must fail in both looks, [(file, before, after), ...])
MUTANTS = {
    "frame-insets": ([N13], [
        (FIELD, "    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }\n", "")]),
    "cell-placeholder": ([N16, N18], [
        (FIELD, """    override var placeholderString: String? {
        get { placeholder }
        set {
            placeholder = newValue
            setAccessibilityPlaceholderValue(newValue)
            needsDisplay = true
        }
    }

    override var placeholderAttributedString: NSAttributedString? {
        get { placeholderString.map { NSAttributedString(string: $0) } }
        set { placeholderString = newValue?.string }
    }

""", "")]),
    "rest-only": ([N16, N17], [
        (FIELD, SHOWN, "        if editor != nil { return }\n" + SHOWN)]),
    "always-placeholder": ([N17], [
        (FIELD, SHOWN, SHOWN.replace("{ $0.string }", "{ _ in \"\" }"))]),
    "no-redisplay": ([N20], [
        (FIELD, """    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        needsDisplay = true
    }

""", "")]),
}

RESULTS = []  # (name, ok, instrument)


def check(name, ok, detail="", *, instrument=False):
    RESULTS.append((name, bool(ok), instrument))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def run(command, limit):
    """Rule H: every child under a wall-clock limit; an expiry is the answer."""
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=limit)
        return done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired:
        return None, "", f"expired after {limit} s"


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "name-field-probe")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift + [entry], output=binary,
                                  defines=reference_build.tree_defines(
                                      os.path.dirname(os.path.dirname(sources)),
                                      ["FRAMEJOB_DEV_TOOLS"]), timeout=900)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["\n".join(error.diagnostics)[-300:] or "(no error lines)"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s")
    return binary, None


def probe_checks(sources, out):
    print("\n1 — the probe: N1–N9, N13 and N15–N20, light and dark")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "",
          instrument=binary is None)
    if binary is None:
        for name in ROWS:
            check(name, False, "no row: the probe did not build", instrument=True)
        return
    written = {}
    for look in LOOKS:
        answer = os.path.join(out, f"answer-{look}.json")
        if os.path.exists(answer):
            os.remove(answer)
        rc, stdout, stderr = run([binary, look, FONTS, out], 120)
        check(f"the probe runs to its end [{look}]", rc == 0,
              "" if rc == 0 else (stdout + stderr).strip()[-400:], instrument=rc != 0)
        if os.path.exists(answer):
            try:
                with open(answer) as f:
                    for row in json.load(f)["rows"]:
                        written[row["name"]] = row
            except (ValueError, KeyError) as error:
                check(f"the answer reads [{look}]", False, str(error), instrument=True)
    for name in written:
        if name not in ROWS:
            check(name, False, "a row this proof does not know: " + written[name]["detail"],
                  instrument=True)
    for name in ROWS:
        row = written.get(name)
        if row is None:
            check(name, False, "no row: the probe did not write it", instrument=True)
        else:
            check(name, row["ok"], row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def format_version():
    with open(HEADER) as f:
        found = re.search(r"#define RC_FORMAT_VERSION (\d+)", f.read())
    return int(found.group(1)) if found else 10


def package():
    e2.CHROME = os.path.join(WORK, "fixtures")
    clip = {
        "id": 2, "track": 1, "start": 0, "duration": 6 * TICKS,
        "source": {"kind": "text"}, "enabled": {"video": True, "audio": True},
        "speed": 1.0, "video": e2.video_props(), "audio": None,
        "text": {
            "content": "Opening title", "font": "SourceSans3-SemiBold", "size": 96.0,
            "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
            "width": None,
        },
        "shape": None, "actions": [], "transition_in": None, "name": "Director of Photography",
        "label": None,
    }
    body = e2.project([clip])
    body["version"] = format_version()
    body["markers"] = [{"id": 3, "time": 2 * TICKS, "name": "Interview starts",
                        "color": "orange", "chapter": False}]
    body["next_id"] = 4
    return e2.write_package("names", body)


def harness_checks():
    print("\n2 — the harness: the Document tab and the Clip tab, light and dark, 1440 × 1500")
    rc, stdout, stderr = run([HARNESS_BUILD], 900)
    binary = stdout.strip().splitlines()[-1] if rc == 0 and stdout.strip() else None
    error = None if binary else f"build.sh failed: {(stdout + stderr).strip()[-400:]}"
    path = package() if binary else None
    renders = {}
    for tab, select in (("document", "-1"), ("clip", "0")):
        for look in LOOKS:
            for copy in ("a", "b"):
                if error:
                    break
                out = os.path.join(WORK, f"names-{tab}-{look}-{copy}.png")
                if os.path.exists(out):
                    os.remove(out)
                rc, stdout, stderr = run(
                    [binary, path, out, look, "1440", "1500", select, "0", "1", tab], 120)
                if rc != 0 or not os.path.exists(out):
                    error = (stdout + stderr).strip()[-400:] or f"rc {rc}"
                renders[(tab, look, copy)] = out

    def data(key):
        with open(renders[key], "rb") as f:
            return f.read()
    rows = [("H1", "document", "light"), ("H2", "document", "dark"),
            ("H3", "clip", "light"), ("H4", "clip", "dark")]
    for label, tab, look in rows:
        name = (f"{label} the {'Document' if tab == 'document' else 'Clip'} tab, {look}, "
                "rendered twice: byte-identical PNGs"
                + (", and light ≠ dark" if look == "dark" else ""))
        if error:
            check(name, False, error, instrument=True)
            continue
        same = data((tab, look, "a")) == data((tab, look, "b"))
        if look == "dark":
            same = same and data((tab, "dark", "a")) != data((tab, "light", "a"))
        check(name, same, os.path.relpath(renders[(tab, look, "a")], ROOT))


# ---------------------------------------------------------------------------


def baseline(commit):
    began = time.time()
    tree = os.path.join(WORK, "baseline")
    if os.path.exists(tree):
        shutil.rmtree(tree)
    os.makedirs(tree)

    def not_performed(why):
        print(f"baseline {commit}: the control could not be performed — {why}")
        return 2

    archive = subprocess.run(["git", "-C", ROOT, "archive", commit, "app/Sources",
                              "app/Bridging"],
                             capture_output=True)
    if archive.returncode != 0:
        return not_performed(f"git archive {commit} failed: "
                             f"{archive.stderr.decode(errors='replace').strip()}")
    untar = subprocess.run(["tar", "-x", "-C", tree], input=archive.stdout,
                           capture_output=True)
    if untar.returncode != 0:
        return not_performed(f"tar failed: {untar.stderr.decode(errors='replace').strip()}")
    print(f"BASELINE {commit}: app/Sources in {os.path.relpath(tree, ROOT)}")
    probe_checks(os.path.join(tree, "app", "Sources"), os.path.join(tree, "out"))
    elapsed = time.time() - began
    instruments = [n for n, ok, inst in RESULTS if inst and not ok]
    if instruments:
        return not_performed(f"instrument failures {instruments[:4]}, {elapsed:.0f} s")
    failed = sorted(n for n, ok, _ in RESULTS if not ok and n not in B32_LOOK_ROWS)
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
    probe_checks(sources, os.path.join(here, "out"))
    elapsed = time.time() - began
    instruments = [n for n, ok, inst in RESULTS if inst and not ok]
    if instruments:
        return not_performed(f"instrument failures {instruments[:4]}, {elapsed:.0f} s")
    failed = sorted(n for n, ok, _ in RESULTS if not ok)
    controls = [n for n in failed if "(a CONTROL)" in n]
    if controls:
        return not_performed(f"controls failed: {controls}, {elapsed:.0f} s")
    named = [f"{row} [{look}]" for look in LOOKS for row in MUTANTS[name][0]]
    survived = [n for n in named if n not in failed]
    if survived:
        print(f"mutant {name}: SURVIVED — {survived} passed (all failures: {failed}), "
              f"{elapsed:.0f} s")
        return 0
    print(f"mutant {name}: caught — {len(named)} named rows failed (all failures: {failed}), "
          f"{elapsed:.0f} s")
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
    print("#171 — the inspector's name field is the inspector's value field")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"))
    harness_checks()
    good = sum(1 for _, ok, _ in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
