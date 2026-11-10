#!/usr/bin/env python3
"""Docs bugs, batch c4 (#491 #503 #505 #506 #514 #516 #517 #518, spec §11 VR-64 (b)): Follow Speaker
takes a microphone clip that sounds, and a missing module, the nest note, the graphic `in` refusal,
the Record shortcuts note, the microphone prompt, nineteen tool descriptions and seven comments say
what the code does.

    python3 tools/proof/docs_bugs_c4_proof.py [--only V1,G1,T7,…] [--mutant NAME] [--app PATH]
                                              [--base-rev SHA] [--expect-red]
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_c4_proof.py
    RC_PROOF_APP=<a base .app> python3 tools/proof/docs_bugs_c4_proof.py --base-rev <its sha> --expect-red

The built app (`proof_app`'s choice) under a scratch home, driven over MCP, over F-TURNS
(`vr6b_proof.py`'s `Doc`, W's analyses canned) with Mic A split at 80 %, so a long piece and a short
one. `(c)` marks a CONTROL, which passes on the base too; every other row is red on the frozen base
app with `--base-rev` set to the base's commit, and `--expect-red` exits 0 only when that holds and
no row failed for want of running.

Launch 1 (`vr6b_proof.LAUNCH_1`):
- V1 (#491) the long piece muted, `mics [short, B]`, `mic_faces [1, 2]`: `speaker` is W on [short,
  B] with [1, 2], W has no reason, the summary's " Follows whoever is talking in 1 clip.", W has
  actions.
- V2 (c) nothing muted: `speaker` names the long piece.
- V3 (c) both pieces muted: `speaker` [], W's reason names the long piece's "sound is off" sentence.
- G1 (#503) the module's file deleted, Properties reads "No module named …" and not "did not
  compile". G2 (c) a real syntax error keeps the compile sentence. G3 (c) a good module shows
  neither.
- B1 (#514) the note in the Picture sub-tab's `snapshot_ui` dump.
- R1 (#516) the whole refusal sentence over MCP.
- T1–T19 (#505) per item, in `tools/list`: the old fragment absent and the new one present.
Launch 2 (`-RCDevAnalysisCanned YES -FrameJobFollowKind speaker`):
- V4 (#491) the filed fixture's sheet shows no "sound is off" text. V5 (c) the unmuted fixture's
  sheet shows "Follows whoever is talking in 1 clip."
No launch:
- K1 (#517) the note's span in the app binary's bytes. P1 (#518) the bundle's
  `NSMicrophoneUsageDescription`, by `plistlib`.
- C10, C18, C23, C24, C32, C33, C47 (#506) the source's old phrase absent and new phrase present,
  from the tree, or through `git show <rev>:<path>` under `--base-rev`. W4 (#505 item 4) "(fast
  start)" and "(slow start)" absent from `model_audio.rs` and spec §4.3. W10 (#505 item 10) "Title
  preset" absent from the core's and the app's comments and the spec's four files, read the same way.
- Z1 (c) `grep "Frame Job: "` of each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a tree copy from `tree_copy.py`, its app built, and
only its row run (with Z1). CAUGHT exits 1 (the named row failed), SURVIVED exits 0, and a control
that could not be performed (the copy did not build, an anchor not found once) exits 2.
"""

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
import vr6b_proof as vr6b  # noqa: E402

WORK = ROOT / "tools/proof/work/docs-bugs-c4"
HOME = WORK / "home"
MEDIA = ROOT / "tools/proof/media"
CALL_BOUND = 900
BUILD_BOUND = 1800
SHEET_BOUND = 60
FRAME = 600_000 // 30
PINS = ["-FrameJobInspectorCollapsed", "NO",
        "-FrameJobInspectorSection.graphic.properties", "<false/>",
        "-FrameJobInspectorSection.video.transform", "<false/>"]
LAUNCH_2 = ["-RCDevAnalysisCanned", "YES", "-FrameJobFollowKind", "speaker"]

MODULE = """export const schema = { title: { type: "string", default: "Hello" } };
export function render(ctx, props) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${ctx.width} ${ctx.height}"><rect width="100" height="100" fill="red"/></svg>`;
}
"""
BROKEN = "export function ("
NAME = "lower-third"
MISSING_NOTE = (f'No module named "{NAME}" in graphics/ — see Source. Stored values are listed '
                "below.")
COMPILE_NOTE = "The module did not compile — see Source. Stored values are listed below."
NEST_NOTE = ("A nest has no pixels of its own to blend — un-nest it (⇧⌘G) to blend the clips "
             "inside.")
IN_REFUSAL = ('"in" cannot be patched: trim_start, roll, split and add_transition move a graphic\'s '
              "in point")
SHORTCUTS_SPAN = "or ⌥ with an arrow, Delete, Forward Delete, Return, Enter, Tab or Esc"
MICROPHONE = ("Frame Job records the microphone you choose, into a file of its own. Nothing is "
              "sent anywhere.")
TALKING = " Follows whoever is talking in 1 clip."

# row → [(tool, the old fragment or None, the new fragment or None)]
TOOLS = {
    "T1": [("set_transition_style", "neither key given changes nothing at all",
            "a call with none of curve, audio or audio_shape is an error")],
    "T2": [("record_screen", " (the pointer is still in the picture too)", None)],
    "T3": [("switch_by_speaker", "The angle shown when nobody or everybody talks; null for none.",
            "The wide angle, which opens the cut and shows during crosstalk (while nobody talks "
            "the current shot holds); null for none.")],
    "T4": [("set_audio", "plus_3db for a fast start, minus_3db for a slow one",
            "plus_3db, which moves fastest near silence, or minus_3db, which moves fastest near "
            "full level")],
    "T5": [("set_video",
            "height and falloff are fractions of the layer's cropped height, gap is source px",
            "height is a fraction of the layer's cropped height, falloff how far it fades across "
            "that height (0 not at all, 1 transparent at its end), gap is source px")],
    "T6": [("add_transition", "duration is snapped down to whole frames and CLAMPED",
            "duration is rounded to the nearest frame (one that rounds to 0 is an error) and "
            "CLAMPED")],
    "T7": [("export", "the export sheet's six controls (format, size, frame rate, quality, "
                      "loudness, range)",
            "the export sheet's controls in the sheet's own vocabulary, all but a saved Preset "
            "(this tool's preset is the sheet's Format), Quality, which is exact rates here, and "
            "the frame rate: this exports at the document's rate"),
           ("export", "An av1, av1_webm or vp9_webm job",
            "An av1, av1_webm, vp9_webm or vp9_alpha_webm job")],
    "T8": [("export_captions",
            "with none or with more than one the call is refused and the candidates listed by id "
            "and name",
            "with none the call is refused, and with more than one it is refused with the "
            "candidates listed by id and name")],
    "T9": [("import_graphic_asset", "any of / : \" ' < > &", "any of : \" ' < > &"),
           ("import_graphic_asset", None, "A name holding / is refused.")],
    "T10": [("add_text_clip", "5 s of the Title preset, centred",
             "5 s of white, centred text in Source Sans 3 Bold at 72 px"),
            ("add_text_clip", "merged over the Title preset", "merged over that default"),
            ("add_text_clip", "Default: the Title preset's placeholder.",
             'Default: the placeholder "Title".'),
            ("text_behind_subject", "with the Title preset on it",
             "in add_text_clip's default look on it"),
            ("text_behind_subject", "the Title preset's when left out",
             '"Title" when left out')],
    "T11": [("transcribe",
             "abut the next page where the gap is under 0.25 s, else hold 0.5 s after the last "
             "word",
             "hold 0.5 s after the last word, or abut the next page where that starts sooner")],
    # T12's old half is the frozen base binary's `transcribe.clips` text (`strings` over
    # docs-bugs/base-app), so its absence is red there.
    "T12": [("transcribe", "Omit for every clip in the project that has recorded sound",
             "Omit for every clip the open timeline or nest plays out loud")],
    "T13": [("normalize_clip", "a stereo clip through its own mono and pan",
             "a stereo clip through its own channel pick, mono and pan"),
            ("normalize_clip", "a gate, a de-esser, a compressor or a voice effect",
             "a gate, a de-esser, a leveler, a compressor or a voice effect")],
    "T14": [("detach_audio", "media with no audio, or audio already detached",
             "media with no audio, audio already detached, or a sound that would overlap what is "
             "on the track below"),
            ("match_audio", "or (with eq) has under 1 s of speech is refused by name",
             "or (with eq) has under 1 s of speech or under 12 third-octave bands within 50 dB of "
             "its loudest is refused by name"),
            ("match_audio", "for one of those reasons, or is the reference, is reported",
             "for one of those reasons, shares under 12 such bands with the reference, or is the "
             "reference, is reported")],
    "T15": [("reframe_clip",
             "a clip with no camera layout, a clip laid out both as a camera and as a screen, a "
             "screen layout",
             "a clip with no camera layout or laid out both as a camera and as a screen, each "
             "naming the clip, then a screen layout with no camera switch in front of it or the "
             "first switch not a layout Frame Job made on from_width × from_height (edited by "
             "hand), each naming the clip and action"),
            ("reframe_clip", "Read by the following kinds and center",
             "Read by the following kinds, cursor, speaker and center"),
            ("reframe_clip", "Not read by keep.", "Not read by keep or layout."),
            ("reframe_clip", "a nest clip, then a still or image clip, with a following kind or "
                             "cursor;",
             "a nest clip, then a still or image clip, with a following kind, cursor or speaker")],
    "T16": [("switch_by_speaker", "when an angle track holds clips outside the range, its clips "
                                  "split",
             "when an angle track holds clips outside the range or a clip without a picture, its "
             "clips split")],
    "T17": [("make_vertical_version",
             "each a clip of a sound file on its own track standing for that track as one "
             "person's microphone.",
             "each a clip of a sound file (or a detached camera sound) on its own track standing "
             "for that track as one person's microphone. Under each shot the track's clip that "
             "overlaps it most is used, one with its sound on before one with it off.")],
    "T18": [("write_graphic", "(e.g. asset() outside render)",
             "(e.g. asset() naming a file not in graphics/assets/)")],
    "T19": [("get_transcript", "which takes seconds per minute of speech",
             "which takes about 0.7 s per minute of speech on an M2 Max")],
}

APP = "app/Sources/"
# row → [(path, [old phrases], [new phrases])]
SOURCES = {
    "C10": [("core/src/export_table.rs", ["On the session path", "VideoToolbox derives"],
             ["so every rate is the writer's", "`ExportWriter.defaultVideoBitrate`"])],
    "C18": [(APP + "ColorWheelControl.swift", ["every 75 % target within 12°"],
             ["every 75 % target within about 12.5°: 11.76° on Rec. 709, 12.40° on BT.2020"])],
    "C23": [(APP + "AppDelegate+Updates.swift", ["never installs without asking"],
             ['installs only when asked, unless the person ticks Sparkle\'s own "Automatically '
              'download and install updates" box (`SUAllowsAutomaticUpdates` is unset)'])],
    "C24": [(APP + "SettingsWindowController+Verify.swift",
             ["against whatever key would be used for a real run"],
             ["(a run uses it only once saved)", "the resolved credential a run would use"])],
    "C32": [(APP + "EditorViewController+ScrubAudio.swift", ["a marker click, `set_playhead`"],
             ["**Go** in the Document tab's Markers list, Next and Previous Marker, `set_playhead` "
              "and the transport keys are seeks"])],
    "C33": [(APP + "EditorWindowController.swift", ["only dirty indicator"],
             ['the dirty indicator the app writes itself, beside the "— Edited" AppKit adds to '
              "the title bar"]),
            (APP + "ProjectDocument.swift", ["only dirty indicator"],
             ['the dirty indicator the app writes itself, beside the "— Edited" AppKit adds to '
              "the title bar"])],
    "C47": [(APP + "InspectorRowMenu.swift", ["A field's or a popup's own right-click"],
             ["A field keeps its own menu", "a checkbox, a popup, the tags"])],
    "W4": [("core/src/model_audio.rs", ["(fast start)", "(slow start)"], []),
           ("designs/spec/04.3d-inspector-clip-sections-audio-text-shape.md",
            ["(fast start)", "(slow start)"], [])],
    "W10": [(path, ["Title preset"], []) for path in (
        "core/src/edit.rs", "core/src/edit_described.rs", "core/src/model_text.rs",
        APP + "ReelOps.swift", APP + "BehindSubjectPlan.swift", APP + "AgentServer+Clips.swift",
        "designs/spec/06b-edit-operations-clips.md", "designs/spec/07.10-rust-module-map.md",
        "designs/spec/07.9g-agent-behind-subject.md", "designs/spec/09-keys-and-menus.md")],
}

LAUNCH_ONE = ["V1", "V2", "V3", "G1", "G2", "G3", "B1", "R1", *TOOLS]
LAUNCH_TWO = ["V4", "V5"]
FILE_ROWS = ["K1", "P1", *SOURCES]
ROWS = LAUNCH_ONE + LAUNCH_TWO + FILE_ROWS + ["Z1"]
CONTROLS = {"V2", "V3", "V5", "G2", "G3", "Z1"}

SPEAKER = "app/Sources/VerticalVersion+Speaker.swift"
PANE = "app/Sources/GraphicPane.swift"
# name: (the row it must turn red, the edits).
MUTANTS = {
    "sound-on-not-first": ("V1", [(
        SPEAKER,
        "(soundOff(a), -overlap(a), a.start, a.id) < (soundOff(b), -overlap(b), b.start, b.id)",
        "(-overlap(a), a.start, a.id) < (-overlap(b), b.start, b.id)")]),
    "muted-filtered-out": ("V3", [(
        SPEAKER,
        "            return overlap(other) > 0\n",
        "            return overlap(other) > 0 && other.enabled.audio\n")]),
    "note-always-missing": ("G2", [(
        PANE, "if let shared, shared.entry == nil {", "if let shared, parsed == nil {")]),
    "note-never-missing": ("G1", [(
        PANE, "if let shared, shared.entry == nil {",
        "if let shared, shared.entry == nil, shared.name.isEmpty {")]),
}

results = {}
broken = set()
selected = set(ROWS)
base_rev = None


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            if name in selected and name not in results:
                broken.add(name)
            check(name, False, f"the row could not run: {error!r}")


# ---- #491 -------------------------------------------------------------------------------

def split_mic(doc):
    """Mic A split at 80 % on the frame grid: (the long piece, the short piece)."""
    clip = doc.clip(doc.c_a)
    at = (int(clip["start"] + clip["duration"] * 0.8) // FRAME) * FRAME
    doc.call("split", clips=[doc.c_a], at=at)
    pieces = sorted((c for c in doc.state()["clips"] if c["track"] == doc.mic_a_track),
                    key=lambda c: c["start"])
    return pieces[0]["id"], pieces[1]["id"]


def make(doc, mics):
    """(the answer, None) or (None, the refusal)."""
    try:
        return doc.vertical(mics=mics, mic_faces=[1, 2]), None
    except mcp.ToolError as error:
        return None, str(error)


def speaker_rows(client, manifest):
    def body():
        doc = vr6b.Doc(client, manifest, "follow", second=False)
        try:
            long_piece, short_piece = split_mic(doc)
            mics = [short_piece, doc.c_b]

            answer, refused = make(doc, mics)
            speaker = (answer or {}).get("speaker")
            check("V2", speaker == [{"clip": doc.c_wide, "mics": [long_piece, doc.c_b],
                                     "mic_faces": [1, 2]}],
                  f"nothing muted: speaker {speaker}, refused {refused}, long piece {long_piece}")
            if answer is not None:
                doc.call("undo")

            doc.call_with("set_enabled", {"clip": long_piece, "audio": False})
            answer, refused = make(doc, mics)
            speaker = (answer or {}).get("speaker")
            wide = vr6b.entry(answer or {}, doc.c_wide) or {}
            actions = doc.clip(doc.c_wide).get("actions") or []
            summary = (answer or {}).get("summary") or ""
            check("V1", speaker == [{"clip": doc.c_wide, "mics": [short_piece, doc.c_b],
                                     "mic_faces": [1, 2]}]
                  and "reason" not in wide and TALKING in summary and len(actions) > 0,
                  f"long piece {long_piece} muted: speaker {speaker}, W {wide}, {len(actions)} "
                  f"actions, refused {refused}, summary {summary[:200]!r}")
            if answer is not None:
                doc.call("undo")

            doc.call_with("set_enabled", {"clip": short_piece, "audio": False})
            answer, refused = make(doc, mics)
            speaker = (answer or {}).get("speaker")
            wide = vr6b.entry(answer or {}, doc.c_wide) or {}
            reason = wide.get("reason") or ""
            check("V3", answer is not None and speaker == []
                  and f"clip {long_piece}'s sound is off" in reason,
                  f"both pieces muted: speaker {speaker}, reason {reason[:200]!r}, refused "
                  f"{refused}")
        finally:
            doc.close()

    attempt(["V1", "V2", "V3"], body)


SUMMARY = re.compile(r"Makes a \d+ × \d+ version\.")


def sheet_texts(doc, tag):
    """(every shown text of Make Vertical's sheet, its summary) once the summary is up; the
    summary is the "Makes a W × H version." line, not the sheet's description above it."""
    doc.call("perform_menu_item", path=vr6b.MENU)
    views, waited = vr6b.wait_for(doc, tag, lambda got: any(
        SUMMARY.match(v.get("text") or "") for v in vr6b.shown(got)), SHEET_BOUND)
    if views is None:
        raise RuntimeError(f"the sheet's summary was not up within {SHEET_BOUND} s")
    texts = [v.get("text") or "" for v in vr6b.shown(views)]
    doc.client.call("cancel_sheet", project=str(doc.path))
    return texts, next(t for t in texts if SUMMARY.match(t))


def speaker_sheet_rows(client, manifest):
    def body():
        doc = vr6b.Doc(client, manifest, "follow-sheet", second=False)
        try:
            long_piece, _ = split_mic(doc)
            _, summary = sheet_texts(doc, "unmuted")
            check("V5", TALKING.strip() in summary, f"unmuted: {summary!r}")

            doc.call_with("set_enabled", {"clip": long_piece, "audio": False})
            texts, summary = sheet_texts(doc, "filed")
            check("V4", not any("sound is off" in t for t in texts),
                  f"long piece {long_piece} muted: {summary!r}")
        finally:
            doc.close()

    attempt(["V4", "V5"], body)


# ---- #503, #514, #516 -------------------------------------------------------------------

class Plain:
    """A saved package over MCP."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        client.call("new_project", path=str(self.path))

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def place(self, name, at=0):
        media = self.call("import_media", path=str(MEDIA / name))["media"]
        track = self.state()["tracks"][0]["id"]
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def clip(self, cid):
        return next(c for c in self.state()["clips"] if c["id"] == cid)

    def inspector(self, tag, sub_tab, section=None):
        """Every shown text of the inspector, on `sub_tab`."""
        tab = {"tab": "clip", "sub_tab": sub_tab}
        if section:
            tab["section"] = section
        self.call("select_inspector_tab", **tab)
        got = self.call("snapshot_ui", window="editor", view="inspector",
                        path=str(WORK / f"{tag}.png"))
        views = json.loads(Path(got["layout_path"]).read_text()).get("views") or []
        return [v["text"] for v in views if v.get("text") and not v.get("hidden")]

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def graphic_rows(client):
    def body():
        doc = Plain(client, "graphic")
        try:
            doc.place("A.mov")
            doc.call("write_graphic", name=NAME, source=MODULE)
            doc.client.call_with("insert_graphic", {"project": str(doc.path), "name": NAME,
                                                    "from": "project"})
            cid = next(c["id"] for c in doc.state()["clips"] if c.get("graphic"))
            doc.call("save_project")
            doc.call("set_selection", clips=[cid])

            words = doc.inspector("good", "graphic")
            check("G3", MISSING_NOTE not in words and COMPILE_NOTE not in words
                  and not any("see Source" in w for w in words),
                  f"a good module: no note ({sum('see Source' in w for w in words)} found)")

            try:
                doc.call("set_graphic", clips=[cid], patch={"in": 0})
                check("R1", False, "the patch was taken")
            except mcp.ToolError as error:
                check("R1", str(error).endswith(IN_REFUSAL), str(error))

            doc.call("write_graphic", name=NAME, source=BROKEN)
            words = doc.inspector("broken", "graphic")
            check("G2", COMPILE_NOTE in words and MISSING_NOTE not in words,
                  f"a syntax error: {[w for w in words if 'see Source' in w]}")

            doc.call("write_graphic", name=NAME, source=MODULE)
            doc.call("save_project")
            client.call("close_project", project=str(doc.path))
            (doc.path / "graphics" / f"{NAME}.js").unlink()
            client.call("open_project", path=str(doc.path))
            doc.call("set_selection", clips=[cid])
            words = doc.inspector("missing", "graphic")
            check("G1", MISSING_NOTE in words and not any("did not compile" in w for w in words),
                  f"the file deleted: {[w for w in words if 'see Source' in w]}")
        finally:
            doc.close()

    attempt(["G1", "G2", "G3", "R1"], body)


def nest_rows(client):
    def body():
        doc = Plain(client, "nest")
        try:
            first = doc.place("A.mov")
            clip = doc.clip(first)
            second = doc.place("B.mov", at=clip["start"] + clip["duration"])
            doc.call("nest", clips=[first, second])
            nest = next(c for c in doc.state()["clips"] if c["source"].get("kind") != "media")
            doc.call("set_selection", clips=[nest["id"]])
            words = doc.inspector("nest", "picture", "video.transform")
            check("B1", NEST_NOTE in words, str([w for w in words if "nest" in w]))
        finally:
            doc.close()

    attempt(["B1"], body)


# ---- #505, in tools/list ----------------------------------------------------------------

def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for value in node.values():
            yield from strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from strings(value)


def tool_rows(client):
    names = [row for row in TOOLS if row in selected]

    def body():
        schemas = client.schemas()
        for row in names:
            problems = []
            for tool, old, new in TOOLS[row]:
                if tool not in schemas:
                    raise RuntimeError(f"tools/list has no {tool}")
                text = "\n".join(strings(schemas[tool]))
                if old is not None and old in text:
                    problems.append(f"{tool} still reads {old!r}")
                if new is not None and new not in text:
                    problems.append(f"{tool} lacks {new!r}")
            check(row, not problems, "; ".join(problems) or "old gone, new there")

    attempt(names, body)


# ---- the files --------------------------------------------------------------------------

def source(path):
    """`path` at `--base-rev` or in the tree, its line breaks and comment marks folded away."""
    if base_rev:
        text = subprocess.run(["git", "show", f"{base_rev}:{path}"], cwd=str(ROOT), check=True,
                              capture_output=True, text=True).stdout
    else:
        text = (ROOT / path).read_text()
    return re.sub(r"\s*\n\s*(?:///?!?\s*)?", " ", text)


def source_rows():
    names = [row for row in SOURCES if row in selected]

    def body():
        for row in names:
            problems = []
            for path, olds, news in SOURCES[row]:
                text = source(path)
                problems += [f"{path} still reads {old!r}" for old in olds if old in text]
                problems += [f"{path} lacks {new!r}" for new in news if new not in text]
            check(row, not problems, "; ".join(problems) or "old gone, new there")

    attempt(names, body)


def bundle_rows(binary):
    def body():
        data = Path(binary).read_bytes()
        check("K1", SHORTCUTS_SPAN.encode() in data, f"{SHORTCUTS_SPAN!r} in {binary.name}")
        with open(binary.parents[1] / "Info.plist", "rb") as handle:
            prompt = plistlib.load(handle).get("NSMicrophoneUsageDescription")
        check("P1", prompt == MICROPHONE, repr(prompt))

    attempt(["K1", "P1"], body)


# ---- the run ----------------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def launch(binary, arguments, rows, body, tag):
    log = WORK / f"{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(rows):
                broken.add(row)
                check(row, False, "the instance did not listen")
            return
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)


def run_rows(binary):
    speaker = selected & {"V1", "V2", "V3", "V4", "V5"}
    manifest = None
    if speaker:
        manifest = vr6b.fturns()
        if manifest is None:
            for row in sorted(speaker):
                broken.add(row)
                check(row, False, "F-TURNS needs say's Samantha and Daniel")
    first = selected & set(LAUNCH_ONE)
    if first:
        def body(client):
            tool_rows(client)
            # First: the launch's hold keeps a job on the analysis lane for an hour, and the
            # microphones' caches queue behind one that a plain clip's document starts.
            if manifest is not None:
                speaker_rows(client, manifest)
            graphic_rows(client)
            nest_rows(client)
        launch(binary, vr6b.LAUNCH_1 + PINS, first, body, "launch-1")
    second = selected & set(LAUNCH_TWO)
    if second and manifest is not None:
        launch(binary, LAUNCH_2, second, lambda c: speaker_sheet_rows(c, manifest), "launch-2")
    bundle_rows(binary)
    source_rows()


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


def main():
    global selected, base_rev
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    parser.add_argument("--base-rev")
    parser.add_argument("--expect-red", action="store_true")
    args = parser.parse_args()
    base_rev = args.base_rev
    if args.mutant:
        selected = {MUTANTS[args.mutant][0], "Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    vr6b.WORK = WORK
    (WORK / "sheets").mkdir()

    binary = Path(args.app) if args.app else None
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        print(f"docs bugs c4 — the {args.mutant} MUTANT ({row} must FAIL)", flush=True)
        made, why = mutate(args.mutant)
        if why is None:
            app, why = tree_copy.build_app(made, BUILD_BOUND)
            binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"docs bugs c4 — Follow Speaker's microphone and the words "
              f"({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)

    run_rows(binary)

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    missing = sorted(selected - set(results), key=ROWS.index)
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + (f"; never scored {missing}" if missing else ""))
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        if row not in results or row in broken:
            print(f"mutant {args.mutant}: the control could not be performed — its row did not "
                  f"run")
            return 2
        caught = row in failed
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    if args.expect_red:
        green = [name for name in passed if name not in CONTROLS]
        red_controls = [name for name in failed if name in CONTROLS]
        print(f"expect red: {len(failed) - len(red_controls)} rows red, green {green or 'none'}, "
              f"red controls {red_controls or 'none'}, unrun {sorted(broken) or 'none'}")
        return 0 if not green and not red_controls and not broken and not missing else 1
    return 0 if not failed and not missing and results else 1


if __name__ == "__main__":
    sys.exit(main())
