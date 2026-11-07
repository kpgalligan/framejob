#!/usr/bin/env python3
"""ai-docs batch r2c (#538 #539, spec §11 #526 as extended by #538, and #539): the rest of the
British spellings in what the app says, and `snapshot_ui` at a forced capture scale.

    python3 tools/proof/ai_docs_r2c_proof.py [--only S1,C1,…] [--app PATH] [--expect-red]
    RC_PROOF_APP=release python3 tools/proof/ai_docs_r2c_proof.py
    RC_PROOF_APP=<a base .app> python3 tools/proof/ai_docs_r2c_proof.py --expect-red

The built app (`proof_app`'s choice) under a scratch home, driven over MCP, on projects built from
media made into `tools/proof/work/ai-docs-r2c/media/`: a `say`-voiced WAV (speech.wav, about 14 s)
and a 3 s 30 fps clip with sound (short3.mov, ffmpeg). `(c)` marks a CONTROL, which passes on the
base too; `(t)` marks a TREE row, which reads files rather than the app (red on eab6adf2's tree)
and is skipped by `--expect-red`; every other row is red on the frozen base app, and
`--expect-red` exits 0 only when that holds and no row failed for want of running.

The word map (spec §11 #526 as extended by #538): analyse, analysed, analysing, normalise,
normalised, normalises, normalising, recognise, recognised, recogniser, neighbour, neighbours,
grey, greys, labelled, summarise, standardised — whole words, any case. "analyses" is counted
apart, because the noun is right and only the verb changed.

Launch 1 (`-FrameJobCaptionEngine apple`, so a Release build's remembered engine cannot change
the Generate Captions sheet):
- S1 `tools/list` holds no map form in any tool's or argument's text (the base: 54).
- S2 "analyses" occurs once, in `analysis_job`'s `clips` (the base: 5).
- S3 (c) "cancelled" occurs 5 times in `tools/list`, as on the base: the status value and the
  prose that names it keep their spelling.
- S4 File ▸ Export…'s sheet dump holds "Loudness normalizes the" (the hint's words up to the
  dump's 200-character cap) and no map form, hidden views included.
- S5 File ▸ Generate Captions…'s sheet dump holds "The words are recognized ON THIS MAC" and no
  map form, hidden views included.
- S6 `detect_silence {clips: [a shape clip]}` notes "None of those clips plays any sound, so
  nothing was analyzed."
- S7 `normalize_clip {mode: "peak", target_lufs: -16}` is refused "… Pass mode \"loudness\" to
  normalize to a loudness."
- S8 the speech clip's `cache/loudness/<media>.*` removed, `normalize_clip {mode: "loudness"}`
  fails "Nothing could be normalized." and "is still being analyzed — its loudness has not been
  measured".
- S9 `add_transition` at a cut whose two clips show their whole file (refusal_proof.py 7b's
  setup) is refused naming "their neighbors and the overlap rule".
- S10 `render_graphic` of a module whose `interpolateColors` gets "bluish" names `cannot parse
  color "bluish"`.
- S11 (c) an h264 export, `cancel_export` at once, `export_status`: `cancelled` with the reason
  "Cancelled.".
- C4 (c) the editor's inspector captured with no capture default: `scale` equals
  `window_facts.scale` and `width_px` is round(points × scale).
Launch 2 (`-RCDevCaptureScale 3`, which no host has):
- C1 the inspector capture answers scale 3, `width_px`/`height_px` are 3 × points (rounded), the
  dump says 3 and the PNG's IHDR holds the same size.
- C2 File ▸ Export…'s sheet the same, then `cancel_sheet`.
Launch 3 (`-RCDevCaptureScale 5`):
- C3 the log holds "RCDevCaptureScale must be 1, 2 or 3 (got \"5\"); captures keep the window's
  scale." and a capture answers the window's scale.
Tree:
- T1 (t) a literal scan of `app/Sources`, `core/src` and `graphic/src` (Swift `"…"`, `\"\"\"…\"\"\"`
  and interpolations, Rust `"…"` and raw strings, JS quotes and templates; comments skipped)
  finds no map form, and no colour or centre form, outside the survivors spec §11 #526 keeps.
- I1 (t) `sips`: the four inspector webps `05h-clip-qualifier` and `11-document-inspector` are
  608 × 1078, `12-export-sheet.sheet.*` 960 × 1614 and `15-generate-captions-sheet.sheet.*`
  840 × 1076.
All:
- Z1 (c) `grep "Frame Job: "` of each launch's log prints nothing.
"""

import argparse
import bisect
import json
import re
import shutil
import struct
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

WORK = ROOT / "tools/proof/work/ai-docs-r2c"
HOME = WORK / "home"
MEDIA = WORK / "media"
CALL_BOUND = 600
SEC = 600_000

ROWS = ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "C4", "C1", "C2",
        "C3", "T1", "I1", "Z1"]
CONTROLS = {"S3", "S11", "C4", "Z1"}
TREE = {"T1", "I1"}
LAUNCH_ONE = {"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "C4"}
LAUNCH_TWO = {"C1", "C2"}
LAUNCH_THREE = {"C3"}

MAP = re.compile(r"\b(analys(?:e|ed|ing)|normalis(?:e|ed|es|ing)|recognis(?:e|ed|er)|"
                 r"neighbours?|greys?|labelled|summarise|standardised)\b", re.I)
ANALYSES = re.compile(r"\banalyses\b", re.I)
CANCELLED = re.compile(r"\bcancelled\b", re.I)
C2_FORMS = re.compile(r"\b(colour\w*|centre[sd]?)\b", re.I)
BAD_COLOUR_JS = """export const meta = {};
export function render(frame, props, ctx) {
  const fill = interpolateColors(0, [0, 1], ["bluish", "#000"]);
  return svg(ctx, `<rect width="10" height="10" fill="${fill}"/>`);
}
"""
SCALE_LINE = ("RCDevCaptureScale must be 1, 2 or 3 (got \"5\"); captures keep the window's "
              "scale.")

results = {}
broken = set()
selected = set(ROWS)


def check(row, ok, detail):
    if row not in selected:
        return
    results.setdefault(row, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {row}: {detail}", flush=True)


def attempt(fn):
    """The answer, or the error's text: a refusal is a tool error over MCP."""
    try:
        return fn()
    except mcp.ToolError as error:
        return {"ERROR": str(error)}


class Doc:
    """One project on the instance, closed (discarded) by `close`."""

    def __init__(self, client, name):
        self.c = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))

    def call(self, tool, **a):
        return self.c.call_with(tool, {"project": str(self.path), **a})

    def state(self):
        return self.call("get_project")["project"]

    def track0(self):
        return self.state()["tracks"][0]["id"]

    def add(self, file, at=0.0):
        media = self.call("import_media", path=str(MEDIA / file))["media"]
        answer = self.call("add_clip", track=self.track0(), media=media, at=round(at * SEC))
        return media, answer["new_clips"][0]

    def shape(self, at, seconds=3):
        return self.call("add_shape_clip", track=self.track0(), at=round(at * SEC),
                         duration=seconds * SEC,
                         shape={"kind": "rectangle", "fill": [1, 0, 0, 1]})["new_clips"][0]

    def capture(self, name, **a):
        """`snapshot_ui`'s answer, its layout dump and its PNG's path."""
        png = WORK / f"{name}.png"
        answer = self.call("snapshot_ui", path=str(png), **a)
        dump = json.loads(png.with_suffix(".layout.json").read_text())
        return answer, dump, png

    def close(self):
        try:
            self.c.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def strings_of(dump):
    return [s for v in dump.get("views", []) for s in (v.get("text"), v.get("tooltip")) if s]


def map_forms(strings):
    return sorted({m.group(0) for s in strings for m in MAP.finditer(s)})


def descriptions(node, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "description" and isinstance(value, str):
                out.append(value)
            else:
                descriptions(value, out)
    elif isinstance(node, list):
        for value in node:
            descriptions(value, out)
    return out


def ihdr(png):
    data = Path(png).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    return list(struct.unpack(">II", data[16:24]))


# ---- launch 1 --------------------------------------------------------------------------------

def catalog_rows(client):
    texts = {}
    for name, tool in client.schemas().items():
        texts[name] = [tool.get("description", "")] + descriptions(tool.get("inputSchema", {}), [])
    forms = {}
    for name, strings in texts.items():
        for s in strings:
            for m in MAP.finditer(s):
                forms.setdefault(m.group(0), set()).add(name)
    count = sum(len(MAP.findall(s)) for strings in texts.values() for s in strings)
    check("S1", count == 0, f"tools/list: {count} map forms "
          f"{ {k: sorted(v)[:4] for k, v in sorted(forms.items())} or ''}")
    analyses = [(name, s[max(0, m.start() - 30):m.end() + 20]) for name, strings in texts.items()
                for s in strings for m in ANALYSES.finditer(s)]
    clips = (client.schemas().get("analysis_job", {}).get("inputSchema", {})
             .get("properties", {}).get("clips", {}).get("description", ""))
    check("S2", len(analyses) == 1 and analyses[0][0] == "analysis_job"
          and "framing analyses to want" in clips, f"'analyses' ×{len(analyses)}: {analyses}")
    cancelled = sum(len(CANCELLED.findall(s)) for strings in texts.values() for s in strings)
    check("S3", cancelled == 5, f"'cancelled' ×{cancelled} (want 5, the base's)")


def sheet_rows(client):
    d = Doc(client, "sheets")
    try:
        _, speech = d.add("speech.wav", at=0)
        if "C4" in selected:
            answer, dump, png = d.capture("c4-inspector", window="editor", view="inspector")
            scale, facts = answer.get("scale"), answer.get("window_facts", {}).get("scale")
            points = answer.get("points") or [0, 0]
            want = [round(points[0] * scale), round(points[1] * scale)] if scale else None
            got = [answer.get("width_px"), answer.get("height_px")]
            check("C4", scale is not None and scale == facts and got == want
                  and dump.get("scale") == scale,
                  f"scale {scale}, window_facts.scale {facts}, points {points}, px {got} "
                  f"(want {want}), dump {dump.get('scale')}")
        if "S4" in selected:
            d.call("perform_menu_item", path=["File", "Export…"])
            _, dump, _ = d.capture("s4-export", window="sheet")
            d.call("cancel_sheet")
            found = strings_of(dump)
            # The dump caps a text at 200 characters, and the hint's 200th ends at "the".
            want = "Loudness normalizes the"
            shown = any(want in s for s in found)
            check("S4", shown and not map_forms(found),
                  f"'{want}' {'shown' if shown else 'MISSING'}; map forms "
                  f"{map_forms(found) or 'none'}")
        if "S5" in selected:
            d.call("set_selection", clips=[speech])
            d.call("perform_menu_item", path=["File", "Generate Captions…"])
            _, dump, _ = d.capture("s5-captions", window="sheet")
            d.call("cancel_sheet")
            found = strings_of(dump)
            want = "The words are recognized ON THIS MAC"
            shown = any(want in s for s in found)
            check("S5", shown and not map_forms(found),
                  f"'{want}' {'shown' if shown else 'MISSING'}; map forms "
                  f"{map_forms(found) or 'none'}")
    finally:
        d.close()


def message_rows(client):
    d = Doc(client, "messages")
    try:
        media, speech = d.add("speech.wav", at=0)
        shape = d.shape(20)
        d.call("save_project")
        if "S6" in selected:
            answer = attempt(lambda: d.call("detect_silence", clips=[shape]))
            note = answer.get("note", "") if isinstance(answer, dict) else ""
            want = "None of those clips plays any sound, so nothing was analyzed."
            check("S6", want in note, f"note {note or answer!r}")
        if "S7" in selected:
            answer = attempt(lambda: d.call("normalize_clip", clips=[speech], mode="peak",
                                            target_lufs=-16))
            text = answer.get("ERROR", "") if isinstance(answer, dict) else ""
            want = 'Pass mode "loudness" to normalize to a loudness.'
            check("S7", want in text, f"{text or answer!r}")
        if "S8" in selected:
            folder = d.path / "cache/loudness"
            deadline = time.monotonic() + 120
            while (not (folder / f"{media}.complete.json").exists()
                   and time.monotonic() < deadline):
                time.sleep(0.25)
            landed = (folder / f"{media}.complete.json").exists()
            for path in folder.glob(f"{media}.*"):
                path.unlink()
            answer = attempt(lambda: d.call("normalize_clip", clips=[speech], mode="loudness"))
            text = answer.get("ERROR", "") if isinstance(answer, dict) else ""
            check("S8", "Nothing could be normalized." in text
                  and "is still being analyzed — its loudness has not been measured" in text,
                  f"cache landed {landed} then removed: {text or answer!r}")
        if "S10" in selected:
            wrote = attempt(lambda: d.call("write_graphic", name="badcolour", source=BAD_COLOUR_JS))
            rendered = attempt(lambda: d.call("render_graphic", name="badcolour", frame=0))
            text = json.dumps(rendered, ensure_ascii=False)
            check("S10", 'cannot parse color \\"bluish\\"' in text
                  or 'cannot parse color "bluish"' in text,
                  f"write {str(wrote)[:80]}; render {text[:300]}")
        if "S11" in selected:
            started = d.call("export", preset="h264", path=str(WORK / "s11.mp4"))
            export_id = started.get("export_id")
            client.call_with("cancel_export", {"export_id": export_id})
            status = {}
            for _ in range(300):
                status = client.call_with("export_status", {"export_id": export_id})
                if status.get("status") not in ("queued", "running"):
                    break
                time.sleep(0.2)
            check("S11", status.get("status") == "cancelled" and status.get("reason") == "Cancelled.",
                  f"export_status {json.dumps(status)[:200]}")
    finally:
        d.close()


def transition_row(client):
    d = Doc(client, "transition")
    try:
        media = d.call("import_media", path=str(MEDIA / "short3.mov"))["media"]
        track = d.track0()
        d.call("add_clip", track=track, media=media, at=0)
        b = d.call("add_clip", track=track, media=media, at=3 * SEC)["new_clips"][0]
        answer = attempt(lambda: d.call("add_transition", clip=b, duration=SEC // 2))
        text = answer.get("ERROR", "") if isinstance(answer, dict) else ""
        check("S9", "their neighbors and the overlap rule" in text and not MAP.search(text),
              f"{text or answer!r}")
    finally:
        d.close()


# ---- launches 2 and 3 ------------------------------------------------------------------------

def forced_rows(client):
    d = Doc(client, "forced")
    try:
        d.add("speech.wav", at=0)
        for row, name, arguments, close in (
                ("C1", "c1-inspector", {"window": "editor", "view": "inspector"}, False),
                ("C2", "c2-export", {"window": "sheet"}, True)):
            if row not in selected:
                continue
            if close:
                d.call("perform_menu_item", path=["File", "Export…"])
            answer, dump, png = d.capture(name, **arguments)
            if close:
                d.call("cancel_sheet")
            points = answer.get("points") or [0, 0]
            want = [round(points[0] * 3), round(points[1] * 3)]
            got = [answer.get("width_px"), answer.get("height_px")]
            check(row, answer.get("scale") == 3 and got == want and dump.get("scale") == 3
                  and ihdr(png) == want,
                  f"scale {answer.get('scale')}, points {points}, px {got} (want {want}), dump "
                  f"{dump.get('scale')}, IHDR {ihdr(png)}, window_facts.scale "
                  f"{answer.get('window_facts', {}).get('scale')}")
    finally:
        d.close()


def ignored_row(client, log):
    d = Doc(client, "ignored")
    try:
        d.add("speech.wav", at=0)
        answer, dump, _ = d.capture("c3-inspector", window="editor", view="inspector")
        facts = answer.get("window_facts", {}).get("scale")
        text = log.read_text(errors="replace") if log.exists() else ""
        check("C3", SCALE_LINE in text and answer.get("scale") == facts
              and dump.get("scale") == facts,
              f"stderr line {'present' if SCALE_LINE in text else 'ABSENT'}; scale "
              f"{answer.get('scale')}, window_facts.scale {facts}, dump {dump.get('scale')}")
    finally:
        d.close()


# ---- tree rows -------------------------------------------------------------------------------

def literals(text, lang):
    """Every string literal's text in `text` with its line, comments skipped. Swift
    interpolations `\\(…)` and JS template substitutions `${…}` are scanned as code, so an
    identifier inside one is never read as a word of the string."""
    out = []
    n = len(text)
    starts = [m.end() for m in re.finditer("\n", text)]

    def line(i):
        return bisect.bisect_right(starts, i) + 1

    def code(i, closer=None):
        depth = 0
        while i < n:
            ch = text[i]
            two = text[i:i + 2]
            if two == "//":
                j = text.find("\n", i)
                i = n if j < 0 else j
                continue
            if two == "/*":
                level, i = 1, i + 2
                while i < n and level:
                    if text[i:i + 2] == "/*" and lang != "js":
                        level, i = level + 1, i + 2
                    elif text[i:i + 2] == "*/":
                        level, i = level - 1, i + 2
                    else:
                        i += 1
                continue
            if closer is not None:
                if ch in "({[":
                    depth += 1
                elif ch in ")}]":
                    if depth == 0 and ch == closer:
                        return i + 1
                    depth -= 1
            if lang == "rust" and ch == "'":
                if text[i + 1:i + 2] == "\\":
                    j = text.find("'", i + 2)
                    i = j + 1 if j > 0 else n
                    continue
                if text[i + 2:i + 3] == "'":
                    i += 3
                    continue
                i += 1          # a lifetime
                continue
            if lang == "rust" and (two in ('r"', "r#") or text[i:i + 3] in ('br"', "br#")):
                k = i + (2 if text[i] == "b" else 1)
                hashes = 0
                while k < n and text[k] == "#":
                    hashes, k = hashes + 1, k + 1
                if k < n and text[k] == '"' and (i == 0 or not (text[i - 1].isalnum()
                                                                  or text[i - 1] == "_")):
                    end = text.find('"' + "#" * hashes, k + 1)
                    end = n if end < 0 else end
                    out.append((line(i), text[k + 1:end]))
                    i = end + 1 + hashes
                    continue
            if lang == "swift" and ch == "#" and text[i:i + 2] in ('#"', "##"):
                k, hashes = i, 0
                while k < n and text[k] == "#":
                    hashes, k = hashes + 1, k + 1
                if k < n and text[k] == '"':
                    multi = text[k:k + 3] == '"""'
                    quote = '"""' if multi else '"'
                    end = text.find(quote + "#" * hashes, k + len(quote))
                    end = n if end < 0 else end
                    out.append((line(i), text[k + len(quote):end]))
                    i = end + len(quote) + hashes
                    continue
            if ch == '"' or (lang == "js" and ch in "'`"):
                i = string(i)
                continue
            i += 1
        return i

    def string(i):
        start_line = line(i)
        if lang == "swift" and text[i:i + 3] == '"""':
            quote, i = '"""', i + 3
        else:
            quote, i = text[i], i + 1
        buf = []
        while i < n:
            if text.startswith(quote, i):
                out.append((start_line, "".join(buf)))
                return i + len(quote)
            ch = text[i]
            if ch == "\\":
                nxt = text[i + 1:i + 2]
                if lang == "swift" and nxt == "(":
                    buf.append(" ")
                    i = code(i + 2, ")")
                    continue
                buf.append(text[i:i + 2])
                i += 2
                continue
            if lang == "js" and quote == "`" and text[i:i + 2] == "${":
                buf.append(" ")
                i = code(i + 2, "}")
                continue
            if quote in ('"', "'") and ch == "\n" and lang != "rust":
                out.append((start_line, "".join(buf)))
                return i + 1
            buf.append(ch)
            i += 1
        out.append((start_line, "".join(buf)))
        return n

    code(0)
    return out


# Spec §11 #526's survivors: a JSON value, an identifier's own string and the core's errors that
# predate it, by file and by the literal's text.
SURVIVORS = (
    ("app/Sources/AgentServer+AnalysisJob.swift", "framing analyses to want"),
    ("app/Sources/ScopeTraces.swift", "centre"),
    ("app/Sources/AudioSyncDrift.swift", "centres"),
    ("core/src/ffi.rs", "is not a colour"),
    ("core/src/ffi.rs", "normalising a colour"),
    ("core/src/container_header.rs", "Colour"),
    ("core/src/webm_layout.rs", "colour bits_per_channel"),
)
SCAN_FORMS = re.compile(MAP.pattern + r"|\banalyses\b|" + C2_FORMS.pattern, re.I)


def tree_scan():
    hits = []
    files = ([(p, "swift") for p in sorted((ROOT / "app/Sources").glob("*.swift"))]
             + [(p, "rust") for p in sorted((ROOT / "core/src").rglob("*.rs"))]
             + [(p, "rust") for p in sorted((ROOT / "graphic/src").rglob("*.rs"))]
             + [(p, "js") for p in sorted((ROOT / "graphic/src").rglob("*.js"))])
    scanned = 0
    for path, lang in files:
        rel = str(path.relative_to(ROOT))
        for number, value in literals(path.read_text(encoding="utf-8"), lang):
            scanned += 1
            for m in SCAN_FORMS.finditer(value):
                if any(rel == f and want in value for f, want in SURVIVORS):
                    continue
                hits.append(f"{rel}:{number} {m.group(0)!r} in {value[:80]!r}")
    check("T1", not hits, f"{len(files)} files, {scanned} literals; {len(hits)} map forms "
          f"outside the survivors {hits[:12] or ''}")


def webp_sizes():
    folder = ROOT / "docs/site/src/assets/screens"
    wants = {}
    for stem in ("05h-clip-qualifier.inspector", "11-document-inspector.inspector"):
        for look in ("light", "dark"):
            wants[f"{stem}.{look}.webp"] = [608, 1078]
    for look in ("light", "dark"):
        wants[f"12-export-sheet.sheet.{look}.webp"] = [960, 1614]
        wants[f"15-generate-captions-sheet.sheet.{look}.webp"] = [840, 1076]
    wrong = []
    for name, want in wants.items():
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(folder / name)],
                             capture_output=True, text=True)
        w = re.search(r"pixelWidth: (\d+)", out.stdout)
        h = re.search(r"pixelHeight: (\d+)", out.stdout)
        got = [int(w.group(1)), int(h.group(1))] if w and h else None
        if got != want:
            wrong.append(f"{name} {got} (want {want})")
    check("I1", not wrong, f"{len(wants)} webps; wrong {wrong or 'none'}")


# ---- launches --------------------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line for line in log.read_text(errors="replace").splitlines()
                 if "Frame Job: " in line]
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
        body(launched.client, log)
    finally:
        launched.stop()
        parity(log, tag)


def make_media():
    MEDIA.mkdir(parents=True)
    words = ("Every morning the harbour fills with small boats and loud gulls, and the fishermen "
             "call to each other across the water. Please write the totals in the third column "
             "of the sheet before the meeting on Thursday afternoon.")
    subprocess.run(["say", "-o", str(MEDIA / "speech.wav"), "--file-format=WAVE",
                    "--data-format=LEI16@16000", words], check=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return False
    subprocess.run([ffmpeg, "-y", "-v", "error", "-f", "lavfi", "-i",
                    "testsrc2=size=1280x720:rate=30:duration=3", "-f", "lavfi", "-i",
                    "sine=frequency=440:duration=3", "-pix_fmt", "yuv420p", "-c:v", "libx264",
                    "-preset", "ultrafast", "-c:a", "aac", "-shortest",
                    str(MEDIA / "short3.mov")], check=True)
    return True


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--app")
    parser.add_argument("--expect-red", action="store_true")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected - TREE:
            selected.add("Z1")
    if args.expect_red:
        selected -= TREE
    if WORK.exists():
        shutil.rmtree(WORK)
    HOME.mkdir(parents=True)

    if "T1" in selected:
        tree_scan()
    if "I1" in selected:
        webp_sizes()

    app_rows = selected & (LAUNCH_ONE | LAUNCH_TWO | LAUNCH_THREE)
    if app_rows:
        if not make_media():
            print("ffmpeg is not on PATH: the clips cannot be made")
            return 1
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        print(f"ai-docs r2c — spellings and the capture scale ({binary})", flush=True)

        first = selected & LAUNCH_ONE
        if first:
            def body(client, _log):
                if first & {"S1", "S2", "S3"}:
                    catalog_rows(client)
                if first & {"S4", "S5", "C4"}:
                    sheet_rows(client)
                if first & {"S6", "S7", "S8", "S10", "S11"}:
                    message_rows(client)
                if "S9" in first:
                    transition_row(client)
            # The engine is pinned in the argument domain (nothing persisted): a Release build
            # shares the person's defaults, where AssemblyAI may be the remembered engine.
            launch(binary, ["-FrameJobCaptionEngine", "apple"], first, body, "launch-1")
        if selected & LAUNCH_TWO:
            launch(binary, ["-RCDevCaptureScale", "3"], selected & LAUNCH_TWO,
                   lambda client, _log: forced_rows(client), "launch-2")
        if selected & LAUNCH_THREE:
            launch(binary, ["-RCDevCaptureScale", "5"], selected & LAUNCH_THREE,
                   ignored_row, "launch-3")

    scored = {name: all(ok for ok, _ in runs) for name, runs in results.items()}
    failed = [name for name, ok in scored.items() if not ok]
    passed = [name for name, ok in scored.items() if ok]
    missing = sorted(selected - set(results), key=ROWS.index)
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + (f"; never scored {missing}" if missing else ""))
    if args.expect_red:
        green = [name for name in passed if name not in CONTROLS]
        red_controls = [name for name in failed if name in CONTROLS]
        print(f"expect red: {len(failed) - len(red_controls)} rows red, green {green or 'none'}, "
              f"red controls {red_controls or 'none'}, unrun {sorted(broken) or 'none'}")
        return 0 if not green and not red_controls and not broken and not missing else 1
    return 0 if not failed and not missing and results else 1


if __name__ == "__main__":
    sys.exit(main())
