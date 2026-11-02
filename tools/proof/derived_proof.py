#!/usr/bin/env python3
"""Road map "creator-jobs" CJ5b — File ▸ New Project from Range…, the derived
document and `new_project_from_range` (spec §11 CJ-51, CJ-52).

    python3 tools/proof/derived_proof.py [--only D1,D3,…] [--mutant NAME] [--app PATH]

Every launch runs on a scratch `CFFIXED_USER_HOME`; packages are saved under
`tools/proof/work/derived-proof/`. Every row is a read-back: a tool's answer,
`get_project`, `undo`'s name, a file's bytes, a folder listing, a decoded
export or a `render_frame` PNG.

**Launch 1** (plain). Fixture F1 (1280 × 720, 30 fps), saved at a package,
range [2 s, 6 s): on track 1 `A.mov` [0, 6.2 s) and `B.mov` from 6.2 s with a
1 s dissolve centred on the cut (its overlap holds 6 s); on track 2 `C.mov`
[1 s, 4 s) under `add_speed_ramp` ramp_up ×2, and `silence.mov` [4.2 s, 5.8 s)
reversed; on track 3 the graphic `drawn` [5 s, 7 s) (a second module,
`unused`, is written and drawn by no clip; a font and an asset imported); on
track 4 a timed caption page [1 s, 3 s); `AV.mov` [1 s, 4 s) on track 5 with
its sound detached (a linked pair). Before the call the proof waits (bounded)
for every media's cache markers, the shots analysis of `A.mov`
(`get_media_analysis`) and the reversed render, and writes two fake cloud
transcripts into the source's `cache/transcripts/`: `A`'s with
`remote_deleted: false`, `AV`'s with `true`. Then ONE
`new_project_from_range {from, to, path}`:
- D1 the derived project: every track passes the proof's own half-shorter
  overlap check (`core/tests/common/overlap_oracle.rs`' rule); its duration
  is to − from; every track a source clip crossed `from` on starts a clip at
  0, and every track one crossed `to` on ends one at to − from.
- D3 every carried file byte-identical to the source's; each carried kind
  present; a listing (path, size, inode, mtime) of the derived `cache/` at
  the answer equals one 15 s later (no pass wrote).
- D4 `A`'s transcript and its marker absent from the copy and present in the
  source; `AV`'s carried.
- D5 the reversed `.mov` present at the answer, byte-identical, and
  `render_frame` of the derived project at 3 s equals the source's at 5 s.
- D6 the derived `graphics/` holds exactly `drawn.js`, the font and the asset
  (beside the store's own manual, `API.md` and `API.d.ts`); the source holds
  `unused.js`.
- D8 a recursive listing of `$TMPDIR/FrameJob/` just before the call and just
  after: no entry the call created holds the reversed file's name, and no
  `*-derived` staging folder is left.
- D10 the source's `get_project` project and its undo top unchanged by the
  call; then File ▸ New Project from Range… (`perform_menu_item`) over the
  source's In–Out range opens "d1-source (range)" untitled and dirty, and
  the source is unchanged again.
Fixture F2 (no transition, duck or leveller near either edge): `A.mov` and
`toneA.m4a`, range [1 s, 4 s):
- D2 the derived project's `prores_422` export (`range: "project"`) against
  the source's (`set_range`, `range: "in_out"`), decoded: every frame's md5
  equal; PCM equal sample for sample away from 0.1 s at each end.
Fixture F9, two movies and two sound files (`A.mov`, `B.mov`, `toneA.m4a`,
`toneB.m4a`):
- D9 `carried` files, bytes and seconds of two calls, recorded; S-PC1 from
  `tools/proof/media/creator/` when present, else skipped by name and owed.

**Launch 2** (`-RCDevDerivedHidden YES`):
- D7 the tool with `path`: `snapshot_ui {project: path, window: "editor"}`'s
  `window_facts.visible` false, the window listing (`snapshot_ui {}`) has no
  window for it, and `get_project {project: path}` answers it.

**Launch 3** (the assistant against `anthropic_fake.py`, a dummy key in a
scratch `-RCSecretFolder`, `assistant_session_proof.py`'s shape):
- D11 a turn whose model calls `new_project_from_range` with `path` waits on
  the question "new_project_from_range writes <path>"; `assistant_answer
  deny` answers the model "The person declined: …" and nothing is at the path.

Z1 is each launch's `grep "Frame Job: "`.

`--mutant NAME`: the named decision broken in a tree copy built by
`tree_copy.py`, and only its row run (with Z1). CAUGHT exits 1 (its row
failed), SURVIVED exits 0, and a control that could not be performed (the
copy did not build, an anchor not found once) exits 2.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/derived-proof"
HOME = WORK / "home"
MEDIA = ROOT / "tools/proof/media"
CREATOR = MEDIA / "creator"
FONT = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
ASSET = ROOT / "graphic/tests/assets/red.png"
FAKE = HERE / "anthropic_fake.py"
CALL_BOUND = 600
BUILD_BOUND = 1500
WAIT_BOUND = 180
SEC = 600_000
FRAME = 20_000
FROM, TO = 2 * SEC, 6 * SEC
PLAIN = ["D1", "D2", "D3", "D4", "D5", "D6", "D8", "D9", "D10"]
HIDDEN = ["D7"]
ASSISTANT = ["D11"]
ROWS = PLAIN + HIDDEN + ASSISTANT + ["Z1"]
F1_ROWS = {"D1", "D3", "D4", "D5", "D6", "D8", "D10"}
MANUAL = {"API.md", "API.d.ts"}
CARRIED_KINDS = ["thumbs", "peaks", "loudness", "speech", "sync", "analysis", "transcripts",
                 "reversed"]
CHAT_PINS = ["-FrameJobAssistantAutoCompact", "YES",
             "-FrameJobAssistantAutoCompactTokens", "300000",
             "-FrameJobAssistantClearToolResults", "NO"]
MODULE = ("export const meta = { name: \"Drawn\", durationInFrames: 60 };\n"
          "export const schema = {\n"
          "  x: { type: \"number\", default: 40, min: 0, max: 600 },\n"
          "};\n"
          "export function render(frame, props, ctx) {\n"
          "  return svg(ctx, `<rect x=\"${props.x + frame * 3}\" y=\"240\" width=\"80\" "
          "height=\"60\" fill=\"#22aa66\"/>`);\n"
          "}\n")
TRANSCRIPT = (
    '{"audio_duration":5,"audio_track_start_ms":0,"extracted_seconds":5.0,'
    '"fetched_at":"x","language_code":"en_us","language_confidence":0.99,'
    '"provider":"assemblyai","remote_deleted":%s,'
    '"requested":{"disfluencies":true,"keyterms_prompt":[],"language_code":null,'
    '"speaker_labels":false,"speech_models":["universal-3-5-pro"]},'
    '"speech_model_used":"universal-3-5-pro","transcript_id":"t_derived%d",'
    '"uploaded_format":"flac","words":[]}')

DERIVED = "app/Sources/ProjectDocument+Derived.swift"
MUTANTS = {
    "deleted-transcript-carried": (["D4"], [(
        "app/Sources/DerivedCarry.swift",
        "if MediaTranscript.read(for: m, in: cacheDir)?.header.remoteDeleted == true {",
        "if MediaTranscript.read(for: m, in: cacheDir) != nil {")]),
    "reverse-not-carried": (["D5"], [(
        "app/Sources/DerivedCarry.swift",
        "            keep(\"\\(ReverseCache.directoryName)/\\(name)\")\n",
        "            _ = name\n")]),
    "windows-before-caches": (["D3"], [(
        DERIVED,
        "            carried = try carryCaches(from: source, into: document)\n"
        "            document.makeWindowControllers()\n",
        "            document.makeWindowControllers()\n"
        "            carried = try carryCaches(from: source, into: document)\n")]),
    "every-module-carried": (["D6"], [(
        DERIVED,
        "names: DerivedCarry.drawnGraphicNames(document.project.snapshot),",
        "names: Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])"
        ".filter { $0.hasSuffix(\".js\") }.map { String($0.dropLast(3)) }),")]),
    "caches-in-temp-then-saved": (["D8"], [
        (DERIVED, "document = try open(package, saved: path != nil, name: name)",
         "document = try open(package, saved: false, name: name)"),
        (DERIVED, "if let path { NSDocumentController.shared.noteNewRecentDocumentURL(path) }",
         "if let path {\n"
         "            document.save(to: path, ofType: projectTypeIdentifier, for: .saveAsOperation)"
         " { _ in }\n        }")]),
    "source-edited": (["D10"], [(
        "app/Sources/AgentServer+Derived.swift",
        "                made = try ProjectDocument.derived(\n",
        "                document.applyEdit(\"Keep Range\", [.keepRange(from: from, to: to)])\n"
        "                made = try ProjectDocument.derived(\n")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, detail):
    if name in selected:
        print(f"  SKIP {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


# ---- reading files ---------------------------------------------------------------

def files_under(folder):
    """{relative path: Path} of every regular file under `folder`."""
    folder = Path(folder)
    if not folder.exists():
        return {}
    return {str(p.relative_to(folder)): p for p in sorted(folder.rglob("*")) if p.is_file()}


def listing(folder):
    """[(path, size, inode, mtime_ns)] of every entry under `folder`."""
    folder = Path(folder)
    if not folder.exists():
        return []
    out = []
    for p in sorted(folder.rglob("*")):
        st = p.lstat()
        out.append((str(p.relative_to(folder)), st.st_size, st.st_ino, st.st_mtime_ns))
    return out


def entries(folder):
    """Every relative path under `folder`, files and folders."""
    folder = Path(folder)
    return {str(p.relative_to(folder)) for p in folder.rglob("*")} if folder.exists() else set()


def overlap_rule_holds(project):
    """The tests' oracle: no two clips on one track overlap by more than half
    of the shorter one (integer halving)."""
    clips = project.get("clips") or []
    for a in clips:
        for b in clips:
            if a["id"] == b["id"] or a["track"] != b["track"]:
                continue
            overlap = (min(a["start"] + a["duration"], b["start"] + b["duration"])
                       - max(a["start"], b["start"]))
            if overlap > min(a["duration"], b["duration"]) // 2:
                return False
    return True


# ---- a document ------------------------------------------------------------------

class Doc:
    """One saved package on a 1280 × 720, 30 fps canvas."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=1280, height=720, fps=[30, 1])
        self.call("save_project")

    @property
    def cache(self):
        return self.path / "cache"

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, path):
        return self.call("import_media", path=str(path))["media"]

    def track(self, index):
        tracks = self.state()["tracks"]
        while len(tracks) <= index:
            self.call("add_track")
            tracks = self.state()["tracks"]
        return tracks[index]["id"]

    def place(self, media, track, at):
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def undo_top(self):
        name = self.call("undo").get("undone")
        self.call("redo")
        return name

    def wait_caches(self, bound=WAIT_BOUND):
        """Every media's markers, then a cache listing steady for 2 s."""
        began = time.monotonic()
        while time.monotonic() - began < bound:
            missing = self.missing_markers()
            if not missing:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError(f"{self.path.name}: markers missing after {bound} s: "
                               f"{self.missing_markers()}")
        last = None
        while time.monotonic() - began < bound:
            now = listing(self.cache)
            if now == last:
                return
            last = now
            time.sleep(2)
        raise RuntimeError(f"{self.path.name}: the cache never settled")

    def missing_markers(self):
        missing = []
        for media in self.state()["media"]:
            m = media["id"]
            wanted = []
            if media.get("kind") != "audio" and media.get("width"):
                wanted.append(f"thumbs/{m}/complete.json")
            if media.get("has_audio"):
                wanted += [f"{k}/{m}.complete.json" for k in ("peaks", "loudness", "speech",
                                                                "sync")]
            missing += [w for w in wanted if not (self.cache / w).exists()]
        return missing

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def derive(doc, path, start=FROM, end=TO):
    if path.exists():
        shutil.rmtree(path)
    return doc.call("new_project_from_range", **{"from": start, "to": end, "path": str(path)})


# ---- F1 ---------------------------------------------------------------------------

def build_f1(client):
    doc = Doc(client, "d1-source")
    ids = {name: doc.media(MEDIA / f"{name}.mov") for name in ("A", "B", "C", "silence", "AV")}
    # Track 4 (index 3) stays empty for AV's detached sound: `detach_audio`
    # puts the twin on the track below.
    t1, t2, t3, _, t5, t4 = (doc.track(i) for i in range(6))
    cut = round(6.2 * SEC / FRAME) * FRAME
    a = doc.place(ids["A"], t1, 0)
    doc.call("trim_end", clip=a, to=cut)
    b = doc.place(ids["B"], t1, cut)
    # B slides left by the overlap: [5.2 s, 6.2 s) holds `to`.
    doc.call("add_transition", clip=b, duration=SEC, kind="cross_dissolve", ripple=True)
    c = doc.place(ids["C"], t2, SEC)
    doc.call("trim_end", clip=c, to=4 * SEC)
    doc.call("add_speed_ramp", clip=c, shape="ramp_up", rate=2, curve="linear")
    r = doc.place(ids["silence"], t2, round(4.2 * SEC / FRAME) * FRAME)
    doc.call("trim_end", clip=r, to=round(5.8 * SEC / FRAME) * FRAME)
    doc.call("set_reversed", clip=r, reversed=True)
    doc.call("write_graphic", name="drawn", source=MODULE)
    doc.call("write_graphic", name="unused", source=MODULE.replace("Drawn", "Unused"))
    doc.call("import_graphic_font", path=str(FONT))
    doc.call("import_graphic_asset", path=str(ASSET))
    doc.call("add_graphic_clip", track=t3, at=5 * SEC, name="drawn", duration=2 * SEC)
    page = doc.call("add_text_clip", track=t4, at=SEC, duration=2 * SEC,
                    text="so here’s the thing")["new_clips"][0]
    doc.call("set_text", clips=[page], patch={"words": [
        {"start": 0, "end": 100_000}, {"start": 420_000, "end": 580_000},
        {"start": 600_000, "end": 640_000}, {"start": 660_000, "end": 920_000}]})
    av = doc.place(ids["AV"], t5, SEC)
    doc.call("trim_end", clip=av, to=4 * SEC)
    doc.call("detach_audio", clip=av)
    doc.call("save_project")
    doc.call("get_media_analysis", kind="shots", media=ids["A"])
    began = time.monotonic()
    while time.monotonic() - began < WAIT_BOUND:
        reversed_ = [p for p in (doc.cache / "reversed").glob("*.mov")]
        sheet = (doc.call("perform_menu_item").get("window") or {}).get("sheet")
        if reversed_ and sheet is None:
            break
        time.sleep(0.5)
    else:
        raise RuntimeError(f"the reversed render did not land in {WAIT_BOUND} s")
    doc.wait_caches()
    transcripts = doc.cache / "transcripts"
    transcripts.mkdir(parents=True, exist_ok=True)
    for media, deleted in ((ids["A"], "false"), (ids["AV"], "true")):
        (transcripts / f"{media}.json").write_text(TRANSCRIPT % (deleted, media))
        (transcripts / f"{media}.complete.json").write_text("{}")
    return doc, ids, r


def f1_rows(client):
    doc, ids, reversed_clip = build_f1(client)
    source_before = doc.state()
    undo_before = doc.undo_top()
    tmp_root = Path(os.environ.get("TMPDIR", "/tmp")) / "FrameJob"
    tmp_before = entries(tmp_root)
    derived = WORK / "d1-derived.framejob"
    answer, error = None, None
    try:
        answer = derive(doc, derived)
    except mcp.ToolError as failure:
        error = str(failure)
    tmp_after = entries(tmp_root)
    at_answer = listing(derived / "cache")
    source_after = doc.state()
    undo_after = doc.undo_top()
    if answer is None:
        for row in F1_ROWS - {"D10"}:
            check(row, False, f"the call failed: {error}")
        d10(doc, source_before, source_after, undo_before, undo_after, error)
        return doc
    reversed_name = next(iter(p.name for p in (doc.cache / "reversed").glob("*.mov")), None)
    project = client.call_with("get_project", {"project": str(derived)})["project"]
    attempt(lambda: d1(source_before, project), "D1")
    if "D3" in selected:
        time.sleep(15)
    attempt(lambda: d3(doc, derived, at_answer, answer), "D3")
    attempt(lambda: d4(doc, derived, ids), "D4")
    attempt(lambda: d5(client, doc, derived, reversed_name), "D5")
    attempt(lambda: d6(doc, derived), "D6")
    attempt(lambda: d8(tmp_before, tmp_after, reversed_name), "D8")
    attempt(lambda: d10(doc, source_before, source_after, undo_before, undo_after, None), "D10")
    return doc


def d1(source, project):
    duration = TO - FROM
    starts, ends, problems = {}, {}, []
    for clip in project.get("clips") or []:
        starts.setdefault(clip["track"], set()).add(clip["start"])
        ends.setdefault(clip["track"], set()).add(clip["start"] + clip["duration"])
    for clip in source.get("clips") or []:
        s, e = clip["start"], clip["start"] + clip["duration"]
        if s < FROM < e and 0 not in starts.get(clip["track"], set()):
            problems.append(f"track {clip['track']}: clip {clip['id']} crossed from, no start 0")
        if s < TO < e and duration not in ends.get(clip["track"], set()):
            problems.append(f"track {clip['track']}: clip {clip['id']} crossed to, no end "
                            f"{duration}")
    end = max((c["start"] + c["duration"] for c in project.get("clips") or []), default=0)
    holds = overlap_rule_holds(project)
    check("D1", holds and end == duration and not problems,
          f"overlap rule {holds} over {len(project.get('clips') or [])} clips on "
          f"{len(project.get('tracks') or [])} tracks; end {end} (want {duration}); "
          f"edges {problems or 'all where asked'}")


def d3(doc, derived, at_answer, answer):
    carried = files_under(derived / "cache")
    differ = [rel for rel, path in carried.items()
              if not (doc.cache / rel).exists() or (doc.cache / rel).read_bytes()
              != path.read_bytes()]
    kinds = {rel.split("/")[0] for rel in carried}
    absent = [k for k in CARRIED_KINDS if k not in kinds]
    later = listing(derived / "cache")
    report = answer.get("carried") or {}
    check("D3", carried and not differ and not absent and later == at_answer
          and report.get("files") == len(carried),
          f"{len(carried)} files carried (answer {report.get('files')}), {len(differ)} differ "
          f"{differ[:3]}; kinds {sorted(kinds)}, absent {absent}; listing 15 s later "
          f"{'unchanged' if later == at_answer else 'CHANGED'} ({len(at_answer)} → "
          f"{len(later)} entries)")


def d4(doc, derived, ids):
    a, av = ids["A"], ids["AV"]
    names = [f"transcripts/{a}.json", f"transcripts/{a}.complete.json"]
    in_copy = [n for n in names if (derived / "cache" / n).exists()]
    in_source = [n for n in names if (doc.cache / n).exists()]
    carried = [(derived / "cache" / f"transcripts/{av}{s}").exists()
               for s in (".json", ".complete.json")]
    check("D4", not in_copy and in_source == names and all(carried),
          f"owed a DELETE (media {a}): in the copy {in_copy or 'none'}, in the source "
          f"{len(in_source)}/2; remote_deleted true (media {av}) carried {carried}")


def d5(client, doc, derived, name):
    copy = derived / "cache/reversed" / (name or "-")
    same = bool(name) and copy.exists() and copy.read_bytes() == (
        doc.cache / "reversed" / name).read_bytes()
    pngs = {}
    for tag, project, t in (("source", doc.path, 5 * SEC), ("derived", derived, 5 * SEC - FROM)):
        out = WORK / f"d5-{tag}.png"
        if out.exists():
            out.unlink()
        client.call_with("render_frame", {"project": str(project), "t": t, "path": str(out)})
        pngs[tag] = out.read_bytes() if out.exists() else None
    equal = pngs["source"] is not None and pngs["source"] == pngs["derived"]
    check("D5", same and equal,
          f"reversed {name}: in the copy at the answer and byte-identical {same}; "
          f"render_frame 5 s vs 3 s equal {equal} ({len(pngs['source'] or b'')} bytes)")


def d6(doc, derived):
    # `API.md` and `API.d.ts` are the store's own manual (`GraphicStore+Manual.swift`),
    # written into every `graphics/` it makes, never carried.
    got = set(files_under(derived / "graphics")) - MANUAL
    want = {"drawn.js", f"fonts/{FONT.name}", f"assets/{ASSET.name}"}
    source = set(files_under(doc.path / "graphics"))
    check("D6", got == want and "unused.js" in source,
          f"derived graphics {sorted(got)} (want {sorted(want)}); the source holds unused.js "
          f"{'unused.js' in source}")


def d8(before, after, reversed_name):
    created = sorted(after - before)
    holding = [p for p in created if reversed_name and Path(p).name == reversed_name]
    staging = [p for p in after if any(part.endswith("-derived") for part in Path(p).parts)]
    check("D8", reversed_name is not None and not holding and not staging,
          f"{len(created)} entries the call created under $TMPDIR/FrameJob; holding "
          f"{reversed_name}: {holding or 'none'}; staging left {staging or 'none'}")


def d10(doc, before, after, undo_before, undo_after, error):
    tool_same = before == after and undo_before == undo_after
    doc.call("set_range", start=FROM, end=TO)
    menu_before = doc.state()
    menu_undo = doc.undo_top()
    pressed = doc.call("perform_menu_item", path=["File", "New Project from Range…"])
    time.sleep(1)
    front = doc.client.call("get_project")
    windows = [w.get("title") for w in doc.client.call("snapshot_ui").get("windows") or []]
    name = "d1-source (range)"
    opened = (front.get("name") == name and front.get("unsaved_changes") is True
              and front.get("path") is None and name in windows)
    menu_same = doc.state() == menu_before and doc.undo_top() == menu_undo
    check("D10", tool_same and opened and menu_same,
          f"the call ({'answered' if error is None else 'failed: ' + error[:80]}): project "
          f"unchanged {before == after}, undo top {undo_before!r} → {undo_after!r}; the menu "
          f"({pressed.get('ok')}): front {front.get('name')!r} unsaved "
          f"{front.get('unsaved_changes')} path {front.get('path')!r}, window listed "
          f"{name in windows}; source unchanged {menu_same}")


# ---- F2: the exports --------------------------------------------------------------

def frame_md5s(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:v", "-f",
                          "framemd5", "-"], capture_output=True, text=True, timeout=300,
                         env=bounded.child_env()).stdout
    return [line.split(",")[-1].strip() for line in out.splitlines()
            if line and not line.startswith("#")]


def pcm(path):
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a", "-f",
                           "s32le", "-ac", "2", "-ar", "48000", "-"], capture_output=True,
                          timeout=300, env=bounded.child_env()).stdout


def d2(client):
    doc = Doc(client, "d2-source")
    a = doc.media(MEDIA / "A.mov")
    tone = doc.media(MEDIA / "toneA.m4a")
    t1, t2 = doc.track(0), doc.track(1)
    clip = doc.place(a, t1, 0)
    doc.call("trim_end", clip=clip, to=6 * SEC)
    doc.place(tone, t2, 0)
    doc.call("save_project")
    doc.wait_caches()
    start, end = SEC, 4 * SEC
    derived = WORK / "d2-derived.framejob"
    derive(doc, derived, start, end)
    doc.call("set_range", start=start, end=end)
    ours = WORK / "d2-source.mov"
    theirs = WORK / "d2-derived.mov"
    for out in (ours, theirs):
        if out.exists():
            out.unlink()
    client.export_with({"project": str(doc.path), "preset": "prores_422", "path": str(ours),
                        "range": "in_out"})
    client.export_with({"project": str(derived), "preset": "prores_422", "path": str(theirs),
                        "range": "project"})
    fa, fb = frame_md5s(ours), frame_md5s(theirs)
    pa, pb = pcm(ours), pcm(theirs)
    margin = 4800 * 2 * 4  # 0.1 s of stereo s32 at 48 kHz
    n = min(len(pa), len(pb))
    inner_equal = n > 2 * margin and pa[margin:n - margin] == pb[margin:n - margin]
    first_diff = next((i // 8 for i in range(margin, n - margin, 8)
                       if pa[i:i + 8] != pb[i:i + 8]), None) if not inner_equal else None
    check("D2", fa and fa == fb and inner_equal and abs(len(pa) - len(pb)) <= 8 * 4800,
          f"frames {len(fa)} vs {len(fb)}, md5s equal {fa == fb}; samples {len(pa) // 8} vs "
          f"{len(pb) // 8}, equal away from 0.1 s at each end {inner_equal}"
          + (f" (first differing frame {first_diff})" if first_diff is not None else ""))
    doc.close()


# ---- F9: what a carry costs ---------------------------------------------------------

def d9(client):
    doc = Doc(client, "d9-source")
    for i, name in enumerate(("A.mov", "B.mov", "toneA.m4a", "toneB.m4a")):
        media = doc.media(MEDIA / name)
        clip = doc.place(media, doc.track(i), 0)
        if name.endswith(".mov"):
            doc.call("trim_end", clip=clip, to=5 * SEC)
    doc.call("save_project")
    doc.wait_caches()
    runs = []
    for k in (1, 2):
        answer = derive(doc, WORK / f"d9-derived-{k}.framejob", 0, 4 * SEC)
        runs.append(answer.get("carried") or {})
    good = all(r.get("files", 0) > 0 and r.get("bytes", 0) > 0 and r.get("seconds", -1) >= 0
               for r in runs)
    check("D9", good, "two movies and two sound files: " + "; ".join(
        f"run {k + 1} {r.get('files')} files, {r.get('bytes')} bytes, "
        f"{(r.get('seconds') or 0) * 1000:.1f} ms" for k, r in enumerate(runs)))
    samples = sorted(CREATOR.glob("S-PC1*")) if CREATOR.exists() else []
    if not samples:
        skip("D9", f"S-PC1 is not in {CREATOR.relative_to(ROOT)}: its carry is owed")
    else:
        pc = Doc(client, "d9-spc1")
        media = pc.media(samples[0])
        pc.place(media, pc.track(0), 0)
        pc.call("save_project")
        pc.wait_caches(bound=1800)
        answer = derive(pc, WORK / "d9-spc1-derived.framejob", 0, 60 * SEC)
        r = answer.get("carried") or {}
        check("D9", r.get("files", 0) > 0,
              f"S-PC1 ({samples[0].name}): {r.get('files')} files, {r.get('bytes')} bytes, "
              f"{(r.get('seconds') or 0) * 1000:.1f} ms")
        pc.close()
    doc.close()


def plain_rows(client):
    if selected & F1_ROWS:
        doc = attempt(lambda: f1_rows(client), *sorted(selected & F1_ROWS))
        if doc is not None:
            doc.close()
    if "D2" in selected:
        attempt(lambda: d2(client), "D2")
    if "D9" in selected:
        attempt(lambda: d9(client), "D9")


# ---- launch 2: no window ------------------------------------------------------------

def hidden_rows(client):
    def d7():
        doc = Doc(client, "d7-source")
        clip = doc.place(doc.media(MEDIA / "A.mov"), doc.track(0), 0)
        doc.call("trim_end", clip=clip, to=4 * SEC)
        doc.call("save_project")
        derived = WORK / "d7-derived.framejob"
        derive(doc, derived, SEC, 3 * SEC)
        facts = client.call_with("snapshot_ui", {"project": str(derived), "window": "editor",
                                                 "layout": False}).get("window_facts") or {}
        windows = client.call("snapshot_ui").get("windows") or []
        listed = [w for w in windows if w.get("project") == str(derived)]
        read = client.call_with("get_project", {"project": str(derived)})
        check("D7", facts.get("visible") is False and not listed
              and read.get("path") == str(derived),
              f"window_facts visible {facts.get('visible')}; windows listed for it "
              f"{len(listed)} of {len(windows)}; get_project answers {read.get('name')!r} at "
              f"{read.get('path')}")
        doc.close()
    attempt(d7, "D7")


# ---- launch 3: the assistant ----------------------------------------------------------

def assistant_rows(client, fake):
    def d11():
        doc = Doc(client, "d11-source")
        clip = doc.place(doc.media(MEDIA / "A.mov"), doc.track(0), 0)
        doc.call("trim_end", clip=clip, to=4 * SEC)
        doc.call("save_project")
        target = WORK / "d11-derived.framejob"
        if target.exists():
            shutil.rmtree(target)
        sentence = f"new_project_from_range writes {target}"
        fake.scenario([
            {"content": [{"type": "tool_use", "id": "toolu_d11", "name": "new_project_from_range",
                          "input": {"from": SEC, "to": 3 * SEC, "path": str(target)}}],
             "stop_reason": "tool_use"},
            {"content": [{"type": "text", "text": "D11: declined."}], "stop_reason": "end_turn"}])
        sent = doc.call("assistant_send", text="Make a project of the first seconds.",
                        timeout=120)
        question = (sent.get("question") or {}).get("sentence")
        asked = sent.get("state") == "asking" and question == sentence
        nothing_asked = not target.exists()
        answered = doc.call("assistant_answer", answer="deny", timeout=120)
        result = fake.tool_result("toolu_d11")
        check("D11", asked and nothing_asked and answered.get("state") == "finished"
              and result == (True, f"The person declined: {sentence}.") and not target.exists(),
              f"asked {question!r} (want {sentence!r}), state {sent.get('state')}; nothing at "
              f"the path while asking {nothing_asked}; deny → {answered.get('state')}, the "
              f"model's tool_result {result}; nothing at the path {not target.exists()}")
        doc.close()
    attempt(d11, "D11")


class Fake:
    """`anthropic_fake.py` on a port of its own (`assistant_session_proof.py`'s)."""

    def __init__(self, folder):
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
        env = bounded.child_env()
        env.pop("ANTHROPIC_API_KEY", None)
        self.child = subprocess.Popen([sys.executable, str(FAKE), "--dir", str(folder)],
                                      env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL, text=True,
                                      start_new_session=True)
        line = self.child.stdout.readline().strip()
        if not line.startswith("port "):
            self.stop()
            raise RuntimeError(f"the stand-in printed {line!r}, not a port")
        self.base = f"http://127.0.0.1:{int(line.split()[1])}"

    def _http(self, method, path, body=None):
        import urllib.request
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=data, method=method,
                                         headers={"content-type": "application/json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read() or b"null")

    def scenario(self, replies):
        self._http("POST", "/__control/scenario", {"replies": replies})

    def tool_result(self, tool_use_id):
        """(is_error, text) of the tool_result the model was sent, or None."""
        log = self._http("GET", "/__control/log") or {}
        for request in log.get("requests", []):
            if request.get("method") != "POST" or not request.get("path", "").startswith(
                    "/v1/messages"):
                continue
            for message in (request.get("body") or {}).get("messages", []):
                content = message.get("content")
                for block in content if isinstance(content, list) else []:
                    if block.get("type") == "tool_result" and block.get(
                            "tool_use_id") == tool_use_id:
                        inner = block.get("content")
                        text = inner if isinstance(inner, str) else "".join(
                            b.get("text", "") for b in inner or [] if b.get("type") == "text")
                        return bool(block.get("is_error")), text
        return None

    def stop(self):
        if self.child.poll() is None:
            self.child.kill()
            self.child.wait()


def secret_folder():
    folder = WORK / "secrets"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    descriptor = os.open(folder / "anthropic-key", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write("proof-key\n")
    return folder


# ---- launches ---------------------------------------------------------------------

def launch(binary, arguments, tag, extra_env=None):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME), **(extra_env or {})})
    env.pop("ANTHROPIC_API_KEY", None)
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    return launched, log


def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    fake = None
    plans = [("plain", [], {}, plain_rows, set(PLAIN)),
             ("hidden", ["-RCDevDerivedHidden", "YES"], {}, hidden_rows, set(HIDDEN))]
    if selected & set(ASSISTANT):
        try:
            fake = Fake(WORK / "fake")
            secrets = secret_folder()
            plans.append(("assistant", ["-RCSecretFolder", str(secrets)] + CHAT_PINS,
                          {"RC_ASSISTANT_BASE_URL": fake.base},
                          lambda client: assistant_rows(client, fake), set(ASSISTANT)))
        except Exception as error:  # noqa: BLE001
            check("D11", False, f"the stand-in could not start: {error}")
    try:
        for tag, arguments, extra, body, rows in plans:
            if not selected & rows:
                continue
            launched, log = launch(binary, arguments, tag, extra)
            try:
                if launched.client is None:
                    for row in selected & rows:
                        check(row, False, f"the app did not listen ({tag})")
                    continue
                print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
                body(launched.client)
            finally:
                launched.stop()
            parity(log, tag)
    finally:
        if fake is not None:
            fake.stop()


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
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
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"CJ5b — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CJ5b — New Project from Range ({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        if not named & set(results):
            print(f"mutant {args.mutant}: the control could not be performed — its row was "
                  f"never scored")
            return 2
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 1 if caught else 0
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
