#!/usr/bin/env python3
"""A document's close shuts its editors' players (#568, spec §11 #568), and its
window gives its editor up (#592, spec §11 #592).

What happened. `ProjectDocument.close()` released the recipe key and left the
player to `EditorViewController.deinit`. AppKit keeps a closed window for as
long as it likes (the main thread's autorelease pool and
`NSApplication.currentEvent` hold it), and the window held its editor as its
content view controller: in an instance driven in the background each closed
document kept its `AVPlayerItem`, its taps and five CoreMedia threads until
another window opened (`open_documents_proof.py` O4). #568's fix: the close
itself shuts each of the document's editors' players (`shutDownForClose`,
through the document's weak `editors` table), and a shut player stays shut.
The editor, its `Playback` and its whole view tree still waited on the window
(`open_documents_proof.py` O5, O6). #592's fix: `EditorWindow.close()` sets its
content view controller to nil after `super.close()`, so only the bare window
waits, and a field being typed in has its editing aborted first, because the
tree leaving the window would otherwise end it, and its end is its commit.

Why a probe. When an editor is deallocated after a close was AppKit's
choice, so no row but P6 reads a deinit: the probe HOLDS each editor and its
`Playback` strongly across the close, the worst case, and reads what the close
itself did; the rebuild in flight is forced through `Playback.rebuildHop`, not
waited for. P6 holds the WINDOW strongly instead, as AppKit does, and the
editor weakly. The window's close button cannot be driven over MCP
(`perform_menu_item` refuses File ▸ Close, a framework item), so its door is
driven here: `NSWindow.performClose(_:)`, what the button sends.
`scope_playhead_probe.py`'s build: `document_close_probe.swift` compiled as
`main.swift` against the whole of `app/Sources` through `swift_build.py`; a
build failure or a missing answer is a FAILURE on every row. No window is
shown and nothing is activated.

Fixture, rewritten every run under `work/document-close/`: six empty
640 × 360 packages; the probe adds one shape clip to each, so each player has
an item (the builder's placeholder track). No media, so no ffmpeg.

Rows:

  P0  the fixture: P1's, P2's and P4's documents each had an item on its
      player and one editor in its `editors` table before its door.
  P1  `document.close()` (what `close_project` calls): the moment it returns,
      the held player is shut, has no item and no built composition, and the
      recipe key holds no project.
  P2  the window's close button (`performClose`): the door that ran was
      `performClose` (the probe falls back to the question the button asks
      the document, and says so, when AppKit will not close an unshown window
      that way), the document is closed and the same holds.
  P3  a shut player stays shut: `update(project:urls:isLive:)` called on P1's
      player after the close registers nothing on the released key and, 2 s
      later, has built no item.
  P4  a rebuild in flight at the close: with the build held on the seam the
      document closes, the held block is run, and 1 s later the player has no
      item.
  P5  P1's and P2's windows, once their doors returned: no content view
      controller, the content view not the editor's root view, the root view
      in no window and under no superview, the first responder not in it.
  P6  the window held strongly and the editor, its `Playback` and its root
      view only weakly, the document opened and closed inside an
      `autoreleasepool`: within 5 s of the close all three are freed.
  P7  text being typed at the close, in a field of the probe's own (the field
      editor, as every inspector field, the timeline's rename and the timecode
      are) and in a text view of its own (as the Text tab's area and the
      canvas's inline editor are), each added to an editor's root view: the
      close ends no editing (no `controlTextDidEndEditing`, no
      `textDidEndEditing`, no `resignFirstResponder`), and the tree leaves.

Mutants (`--mutant NAME`: the probe built over a copy of `app/Sources` with
one edit; exit 0 when every row named fails):

  no-close-shutdown    `releaseOnClose()` without its `shutDownForClose()`
                       loop → P1, P2, P3, P4
  window-controllers   the loop over `windowControllers` in place of
                       `editors` → P2 (the button removes the window
                       controller before `close()`)
  no-latch             `update` without its `isShutDown` return → P3
  no-generation-bump   `shutDown()` without `generation += 1` → P4
  no-detach            `EditorWindow.close()` without its `releaseEditor()`
                       → P5, P6, P7
  no-abort             `releaseEditor()` without `abortEditing()` → P7 (the
                       field's editing ended by the detach)

Needs `swiftc`, `xcrun metal` and `core/target/release/libframejob_core.a`.

    python3 tools/proof/document_close_probe.py [--mutant NAME]
"""

import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = os.path.join(HERE, "work", "document-close")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "document_close_probe.swift")
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
FONTS = os.path.join(ROOT, "app", "Resources", "Fonts")
PLACEHOLDER = os.path.join(ROOT, "app", "Resources", "Blank.mp4")
HEADER = os.path.join(ROOT, "core", "include", "framejob_core.h")

LOOP = "            for editor in editors.allObjects { editor.shutDownForClose() }\n"
MUTANTS = {
    "no-close-shutdown": (["P1", "P2", "P3", "P4"], [("ProjectDocument+Close.swift", LOOP, "")]),
    "window-controllers": (["P2"], [(
        "ProjectDocument+Close.swift", LOOP,
        "            for controller in windowControllers {\n"
        "                (controller.contentViewController as? EditorViewController)?"
        ".shutDownForClose()\n"
        "            }\n")]),
    "no-latch": (["P3"], [("Playback.swift", "        if isShutDown { return }\n", "")]),
    "no-generation-bump": (["P4"], [(
        "Playback.swift", "        isShutDown = true\n        generation += 1\n",
        "        isShutDown = true\n")]),
    "no-detach": (["P5", "P6", "P7"], [("EditorWindow.swift", "        releaseEditor()\n", "")]),
    "no-abort": (["P7"], [(
        "EditorWindow.swift", "            field.abortEditing()\n", "            _ = field\n")]),
}

results = {}


def check(row, ok, detail=""):
    results[row] = bool(ok)
    print(f"  {'ok  ' if ok else 'FAIL'} {row}" + (f"\n       {detail}" if detail else ""))


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy."""
    with open(HEADER) as f:
        match = re.search(r"#define RC_FORMAT_VERSION (\d+)", f.read())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def make_fixture():
    """(packages, None) or (None, reason)."""
    os.makedirs(WORK, exist_ok=True)
    try:
        version = format_version()
    except (OSError, RuntimeError) as error:
        return None, f"no format version: {error}"
    packages = []
    for name in ("a", "b", "c", "d", "e", "f"):
        package = os.path.join(WORK, f"{name}.framejob")
        shutil.rmtree(package, ignore_errors=True)
        os.makedirs(package)
        project = {
            "version": version,
            "canvas": {"width": 640, "height": 360, "fps": [30, 1],
                       "background": [0, 0, 0, 1], "fit_new_clips": True},
            "media": [],
            "tracks": [{"id": 1, "name": "Track 1"}],
            "clips": [], "markers": [], "next_id": 2, "nests": [],
        }
        with open(os.path.join(package, "project.json"), "w") as f:
            json.dump(project, f, indent=1)
        packages.append(package)
    return packages, None


def mutated_sources(name):
    """A copy of `app/Sources` with the mutant's edits. (path, None) or (None, reason)."""
    target = os.path.join(WORK, f"{name}-sources")
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(SOURCES, target)
    for file, old, new in MUTANTS[name][1]:
        path = os.path.join(target, file)
        text = open(path).read()
        if text.count(old) != 1:
            return None, f"mutant {name}: its anchor is in {file} {text.count(old)} times, not once"
        with open(path, "w") as f:
            f.write(text.replace(old, new))
    return target, None


def build_shader(probe):
    lib = os.path.join(probe, "default.metallib")
    air = os.path.join(probe, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air], 300)
    if step["rc"] != 0:
        return None, "xcrun metal failed: " + step["stderr"].strip()[:300]
    step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib], 300)
    if step["rc"] != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step["stderr"].strip()[:300]
    return lib, None


def build_probe(sources, tag):
    """The probe over `sources`, in a directory of its own. (binary, None) or (None, reason)."""
    probe = os.path.join(WORK, tag)
    os.makedirs(probe, exist_ok=True)
    binary = os.path.join(probe, "document_close_probe")
    entry = os.path.join(probe, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    fonts = os.path.join(probe, "Fonts")
    if not os.path.isdir(fonts) or os.path.getmtime(FONTS) > os.path.getmtime(fonts):
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(FONTS, fonts)
    placeholder = os.path.join(probe, "Blank.mp4")
    if not os.path.exists(placeholder):
        shutil.copy2(PLACEHOLDER, placeholder)
    shader, why = build_shader(probe)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, name) for name in os.listdir(sources)
                   if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift + [entry], output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'} "
                      f"(expired {error.expired}): "
                      + " | ".join(error.diagnostics[:6] or ["(no output)"]))
    print(f"probe: {binary} " + ("(up to date)" if built.reused
                                 else f"(built in {built.seconds:.1f} s)"))
    return binary, None


def run_probe(binary, packages):
    ran = bounded.run([binary, *packages], 300, cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, "the probe ran past 300 s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-300:]}"


def is_shut(s):
    """What a door leaves: the player shut and empty, the key released."""
    return (s["isShutDown"] is True and s["hasItem"] is False and s["built"] is False
            and s["registered"] is False)


def is_detached(s):
    """What a closed editor window keeps of its editor (#592): nothing."""
    return (s["controller"] is False and s["contentIsRoot"] is False
            and s["rootInWindow"] is False and s["rootHasSuperview"] is False
            and s["firstResponderInTree"] is False)


def ends_nothing(s):
    """A view typed in at the close: editing was under way, the close ended none of it, and
    the editor left its window all the same."""
    return (s["began"] is True and s["editing"] is True and s["endedAtClose"] == 0
            and s["endedAfter"] == 0 and is_detached(s["detached"]))


def rows():
    yield ("P0", "each document had an item and one editor in its table before its door",
           lambda a: all(a[r]["hadItem"] is True and a[r]["editors"] == 1
                         for r in ("P1", "P2", "P4")),
           lambda a: {r: [a[r]["hadItem"], a[r]["editors"]] for r in ("P1", "P2", "P4")})
    yield ("P1", "close(): the held player is shut, no item, nothing built, the key released",
           lambda a: a["P1"]["open"] is False and is_shut(a["P1"]), lambda a: a["P1"])
    yield ("P2", "the close button (performClose): the document closed and the same holds",
           lambda a: a["P2"]["door"] == "performClose" and a["P2"]["open"] is False
           and is_shut(a["P2"]), lambda a: a["P2"])
    yield ("P3", "a shut player stays shut: update() registers nothing and builds no item",
           lambda a: a["P3"]["registeredAtOnce"] is False and a["P3"]["registered"] is False
           and a["P3"]["hasItem"] is False and a["P3"]["isShutDown"] is True,
           lambda a: a["P3"])
    yield ("P4", "a rebuild held across the close lands on no item",
           lambda a: a["P4"]["held"] is True and is_shut(a["P4"])
           and a["P4"]["hasItemAfterLanding"] is False
           and a["P4"]["builtAfterLanding"] is False, lambda a: a["P4"])
    yield ("P5", "close() and the button leave no editor in the window: no content controller, "
                 "the root view out, the first responder not in it",
           lambda a: all(is_detached(a["P5"][door]) for door in ("close", "button")),
           lambda a: a["P5"])
    yield ("P6", "the window held as AppKit holds it: the close frees the editor, its Playback "
                 "and its root view",
           lambda a: a["P6"]["hadItem"] is True and a["P6"]["windowHeld"] is True
           and a["P6"]["freed"] is True, lambda a: a["P6"])
    yield ("P7", "text typed at the close, a field's and a text view's: the close ends no "
                 "editing, and the tree leaves",
           lambda a: all(ends_nothing(a["P7"][kind]) for kind in ("field", "text"))
           and a["P7"]["text"]["resignedAtClose"] == 0 and a["P7"]["text"]["resignedAfter"] == 0,
           lambda a: a["P7"])


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=sorted(MUTANTS), default=None)
    mutant = parser.parse_args().mutant
    print(f"#568, #592 — a document's close shuts its players and frees its editor"
          + (f" — MUTANT {mutant}" if mutant else ""))
    packages, why = make_fixture()
    sources, binary, answer = SOURCES, None, None
    if packages is not None and mutant:
        sources, why = mutated_sources(mutant)
    if packages is not None and sources is not None:
        binary, why = build_probe(sources, f"probe-{mutant}" if mutant else "probe")
    if binary is not None:
        answer, why = run_probe(binary, packages)
    print()
    for row, name, predicate, detail in rows():
        if answer is None:
            check(f"{row} {name}", False, why)
            results[row] = False
            continue
        try:
            ok, shown = predicate(answer), json.dumps(detail(answer), sort_keys=True)
        except (KeyError, TypeError, IndexError, ValueError) as error:
            ok, shown = False, f"{type(error).__name__}: {error}"
        check(f"{row} {name}", ok, shown)
        results[row] = ok
    names = [row for row, *_ in rows()]
    failed = [row for row in names if not results.get(row)]
    print(f"\n{len(names) - len(failed)}/{len(names)} rows passed")
    if mutant:
        if answer is None:
            print(f"MUTANT {mutant}: no answer, so nothing is shown ({why})")
            sys.exit(1)
        wanted = MUTANTS[mutant][0]
        missed = [row for row in wanted if row not in failed]
        print(f"MUTANT {mutant}: " + (f"caught by {wanted}" if not missed
                                      else f"SURVIVED {missed} (wanted {wanted} to fail)"))
        sys.exit(0 if not missed else 1)
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
