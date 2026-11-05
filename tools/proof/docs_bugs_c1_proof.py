#!/usr/bin/env python3
"""Docs bugs, batch c1 (#461 #462 #494 #483 #484 #510, spec §11 AI-21): what the Assistant asks
and promises before it writes or uploads.

    python3 tools/proof/docs_bugs_c1_proof.py [--only Q1,N1,…] [--mutant NAME] [--app PATH]
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_c1_proof.py

Real turns in the built app (`proof_app`'s choice) against `anthropic_fake.py`, with the dummy
`proof-key` in a scratch `-RCSecretFolder`: the stand-in scripts the model's `tool_use`, and the
lane, the question, Allow through the tab (`pane: true`) and the handler are the app's own.
Nothing paid is called. Files are hashed before and after. `(c)` marks a CONTROL, which passes on
the base app too; every other row is red on the frozen base.

**Launch A** (Compact off):
- Q0 (c) `export` and `export_captions` to the exact path, a file there: REPLACES it.
- Q1 `export {h264}` path `cut`, `cut.mp4` present: "export REPLACES …/cut.mp4", and Allow
  replaces that file. Q2 path `cut2.mov`, `cut2.mp4` present: the same. Q3 path `talk.mov`, only
  `talk.mov` present: "export writes …/talk.mp4", `talk.mov` unchanged.
- Q4 `export_captions` path `caps`, `caps.srt` present: REPLACES `caps.srt`. Q5 path `caps2.vtt`,
  format srt, only the `.vtt` present: "writes …/caps2.srt", the `.vtt` unchanged.
- Q6 `save_project` path `talk`, closed `talk.framejob`: REPLACES it, and Deny leaves its hash.
- Q7 (c) a bad preset: asked with the given path, refused after Allow, nothing written.
- N1 `new_project {path}` over a closed package: "new_project REPLACES …"; Deny leaves it and
  opens no window. N2 `render_frame {path}` over a sentinel and N3 `render_graphic {path}`: the
  same. N4 `render_frame {path: shot.jpg, format: png}`, `shot.png` present: REPLACES `shot.png`.
- N0 (c) `new_project {}`, `render_frame {}`, `render_graphic {name}`: finished unasked.
- N5 (c) `write_graphic`, `import_graphic_font`, `import_graphic_asset`, `import_graphic`:
  finished unasked (G-47 (i)).
- S1 `render_frame {path: s.png, waveform: true}`, `s.png.waveform.json` a sentinel: asked
  "render_frame writes …/s.png, and REPLACES …/s.png.waveform.json"; Deny keeps the sentinel.
- S2 the same with no JSON there: "render_frame writes …/s2.png"; after Allow the JSON is written.
- R1 `new_project_from_range {path}` taken, R2 `make_vertical_version {path}` taken: finished
  with no question, `is_error`, the tool's own sentence, the package's hash unchanged.
- R3 `save_project {}` on a never-saved project, R4 `export {preset}` with no path, R5
  `export_captions {}`, R6 `save_project {path: 7}` on a saved project, R7 `consolidate_media {}`
  on a never-saved project: the same, nothing written. R8 (c) `render_frame {path: 7}`: the same
  (no row on the base).
- R0 (c) free paths, a named path, `save_project {}` onto its own file and `consolidate_media` on
  a saved project still ask.
- H1 `save_project {path}` onto a second open project: finished with no question, `is_error`, the
  sentence naming that project, its hash unchanged. H0 (c) `new_project {path}` onto it: the same
  (no row on the base, so it is the `no-held` mutant's to catch).
- P1 `new_project_from_range {from, to, path: null}`: finished unasked, not an error, no package.
- I1 `strings -a` over the binary: `asks before writing a file.` and `until you press Generate,
  and` absent, `asks before saving a project` and `you press Generate or Transcribe` present.
- C0 (c) `end_turn` no error entry; `max_tokens` its own line. C1 `model_context_window_exceeded`,
  Compact off: the error entry in the tab.
- T0 (c) `add_marker` onto a taken frame shows whole. T1 scripted `transcribe {engine:
  assemblyai}`: the event's `summary` is the whole refusal, ends `instead.`, holds no `spec §11`.

**Launch B** (Compact on at 300,000, a 1,000,000 window): C2 the same stop with compaction due.

Z1 is each launch's `grep "Frame Job: "`.

`--mutant NAME`: the named decision broken in a tree copy built by `tree_copy.py`, and only its
rows run (with Z1). CAUGHT exits 1 (a named row failed), SURVIVED exits 0, and a control that
could not be performed (the copy did not build, an anchor not found once) exits 2.
"""

import argparse
import hashlib
import json
import os
import shutil
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

WORK = ROOT / "tools/proof/work/docs-bugs-c1"
HOME = WORK / "home"
FILES = WORK / "files"
MEDIA = ROOT / "tools/proof/media"
FAKE = HERE / "anthropic_fake.py"
FONT = ROOT / "app/Resources/Fonts/Anton-Regular.ttf"
ASSET = ROOT / "graphic/tests/assets/red.png"
CALL_BOUND = 600
BUILD_BOUND = 1500
SEC = 600_000
CONTEXT_STOP = "model_context_window_exceeded"
CONTEXT_LINE = "The reply was cut off because the conversation filled the model's context window."
OUTPUT_LINE = "The reply was cut off at the output limit."
PINS = ["-FrameJobInspectorCollapsed", "NO", "-FrameJobAssistantClearToolResults", "NO",
        "-FrameJobAssistantAutoCompactTokens", "300000"]
MODULE = ("export function render(ctx) { return `<svg xmlns=\"http://www.w3.org/2000/svg\" "
          "width=\"${ctx.width}\" height=\"${ctx.height}\"><rect width=\"50\" height=\"50\" "
          "fill=\"red\"/></svg>`; }\n")
LAUNCH_B = ["C2"]
LAUNCH_A = ["Q0", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "N0", "N1", "N2", "N3", "N4", "N5",
            "S1", "S2", "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "H0", "H1", "P1",
            "I1", "C0", "C1", "T0", "T1"]
ROWS = LAUNCH_A + LAUNCH_B + ["Z1"]

TABLE = "app/Sources/AssistantToolTable.swift"
NIL_PATH_ASKS = (TABLE, "guard let path else { return nil }",
                 "guard let path = path ?? Optional(\"a file\") else { return nil }")
MUTANTS = {
    "export-given": (["Q1"], [(
        TABLE, "path = (try? server.exportDestination(arguments, on: document))?.path ?? given",
        "path = given")]),
    "captions-given": (["Q4"], [(
        TABLE, "AgentServer.captionDestination($0, requested: requested).url.path", "$0")]),
    "save-given": (["Q6"], [(
        TABLE, "path = given.map(packagePath) ?? document.fileURL?.path",
        "path = given ?? document.fileURL?.path")]),
    "no-new-project-row": (["N1"], [(
        TABLE,
        "\"already there, when the call names a path.\",\n"
        "            askOnlyWith: \"path\"),\n"
        "        AssistantToolRow(\n"
        "            tool: \"render_frame\"",
        "\"already there, when the call names a path.\",\n"
        "            askOnlyWith: \"never\"),\n"
        "        AssistantToolRow(\n"
        "            tool: \"render_frame\"")]),
    "no-render-row": (["N2"], [(
        TABLE,
        "\"there, when the call names a path.\",\n"
        "            askOnlyWith: \"path\"),\n"
        "        AssistantToolRow(\n"
        "            tool: \"render_graphic\"",
        "\"there, when the call names a path.\",\n"
        "            askOnlyWith: \"never\"),\n"
        "        AssistantToolRow(\n"
        "            tool: \"render_graphic\"")]),
    "no-refuses-taken": (["R1"], [(
        TABLE, "        if entry.refusesTaken && exists { return nil }\n", "")]),
    "nil-path-asks": (["R3", "R4"], [NIL_PATH_ASKS]),
    "no-held": (["H1", "H0"], [(
        TABLE, "if packageTools.contains(tool),\n", "if tool == \"never\",\n")]),
    # A null `path` is no path twice over: the `askOnlyWith` test, and the nil path after the
    # switch. Dropping the first alone changes nothing, so this drops both.
    "no-null": (["P1"], [(
        TABLE, "arguments[key] == nil || arguments[key] is NSNull", "arguments[key] == nil"),
        NIL_PATH_ASKS]),
    "no-string-check": (["R6"], [(
        TABLE,
        "        if let raw = arguments[\"path\"], !(raw is NSNull), !(raw is String) "
        "{ return nil }\n", "")]),
    "no-scope-files": (["S1"], [(
        TABLE, ".filter { (try? server.boolArg(arguments, $0.rawValue)) == true }",
        ".filter { _ in false }")]),
    "no-context-arm": (["C1"], [(
        "agent/src/main.ts", "last?.stop_reason === \"model_context_window_exceeded\"",
        "last?.stop_reason === \"never\"")]),
}

results = {}
selected = set(ROWS)


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
            check(name, False, f"the row could not run: {error!r}")


# ---- the stand-in -----------------------------------------------------------------------

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

    def scenario(self, replies, window=1_000_000):
        self._http("POST", "/__control/scenario",
                   {"replies": replies, "max_input_tokens": window})

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


def use(tag, tool, arguments):
    return {"content": [{"type": "tool_use", "id": f"toolu_{tag}", "name": tool,
                         "input": arguments}], "stop_reason": "tool_use"}


def say(text, stop="end_turn"):
    return {"content": [{"type": "text", "text": text}], "stop_reason": stop}


def secret_folder(name):
    folder = WORK / name
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    descriptor = os.open(folder / "anthropic-key", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write("proof-key\n")
    return folder


# ---- files ------------------------------------------------------------------------------

def digest(path):
    """A hash of a file or a whole package, or None for nothing there."""
    path = Path(path)
    if not path.exists():
        return None
    total = hashlib.sha256()
    if path.is_dir():
        for root, folders, files in os.walk(path):
            folders.sort()
            for name in sorted(files):
                full = Path(root) / name
                total.update(str(full.relative_to(path)).encode())
                total.update(full.read_bytes())
    else:
        total.update(path.read_bytes())
    return total.hexdigest()[:12]


def sentinel(path):
    Path(path).write_text("SENTINEL: the file the person cares about\n")
    return str(path)


class Stage:
    """One launch's client, stand-in and project: the window the turns run in."""

    def __init__(self, client, fake):
        self.client = client
        self.fake = fake
        self.project = None

    def call(self, tool, arguments=None):
        return self.client.call_with(tool, arguments or {})

    def quiet(self, tool, arguments=None):
        """A tool call whose failure doesn't matter: a clean-up after a row."""
        try:
            return self.call(tool, arguments)
        except mcp.ToolError:
            return None

    def open_work(self, name):
        """AV.mov opened as a project and saved; the Assistant tab showing."""
        self.call("open_project", {"path": str(MEDIA / "AV.mov")})
        self.project = self.call("save_project", {"path": str(FILES / f"{name}.framejob")})["saved"]
        self.call("perform_menu_item", {"project": self.project, "path": ["View", "Assistant"]})
        self.call("select_inspector_tab", {"project": self.project})
        return self.project

    def closed_package(self, path):
        """A real saved package at `path`, a marker and an extra file in it, closed."""
        made = self.call("new_project", {"path": str(path)})["saved"]
        self.client.call_with("add_marker", {"project": made, "at": SEC, "name": "OLD-MARK"})
        self.call("save_project", {"project": made})
        self.call("close_project", {"project": made})
        (Path(path) / "other.txt").write_text("kept by the person\n")
        return str(path)

    def turn(self, tag, tool, arguments, answer="deny", project=None, pane=True):
        """One scripted call: `asked` the sentence or None, `first` the state it first answered,
        `error` and `text` the tool_result, `events` everything the turn emitted."""
        self.fake.scenario([use(tag, tool, arguments), say(f"{tag} done.")])
        where = {"project": project or self.project, "timeout": 120}
        if pane:
            where["pane"] = True
        first = self.call("assistant_send", {**where, "text": f"Please do {tag}."})
        question = first.get("question") or {}
        last = first
        if first.get("state") == "asking":
            last = self.call("assistant_answer", {**where, "answer": answer})
        result = self.fake.tool_result(f"toolu_{tag}")
        events = first.get("events", []) + (last.get("events", []) if last is not first else [])
        return {"asked": question.get("sentence"), "first": first.get("state"),
                "state": last.get("state"), "error": result[0] if result else None,
                "text": result[1] if result else None, "events": events}

    def entries(self, name, project=None):
        """The tab's transcript, from its layout dump: [(kind, text)]."""
        answer = self.call("snapshot_ui", {"window": "editor", "view": "inspector",
                                           "path": str(WORK / f"{name}.png"),
                                           "project": project or self.project})
        with open(answer["layout_path"]) as handle:
            views = json.load(handle)["views"]
        prefix = "assistant.entry."
        return [(v["id"][len(prefix):], v.get("text")) for v in views
                if (v.get("id") or "").startswith(prefix) and not v.get("hidden")]

    def windows(self):
        return [w.get("project") or w.get("title")
                for w in self.call("snapshot_ui", {}).get("windows", [])]


def brief(seen):
    return (f"first {seen['first']}, asked {seen['asked']!r}, state {seen['state']}, "
            f"is_error {seen['error']}, text {(seen['text'] or '')[:110]!r}")


def unasked_refusal(seen, words):
    """The call ran with no question and the tool's own refusal answered."""
    return (seen["first"] == "finished" and seen["asked"] is None and seen["error"] is True
            and words in (seen["text"] or ""))


# ---- launch A ---------------------------------------------------------------------------

def question_rows(s):
    def q0():
        one, two = sentinel(FILES / "right.mp4"), sentinel(FILES / "same.srt")
        before = digest(one), digest(two)
        e = s.turn("q0a", "export", {"preset": "h264", "path": one})
        c = s.turn("q0b", "export_captions", {"path": two})
        check("Q0", e["asked"] == f"export REPLACES {one}"
              and c["asked"] == f"export_captions REPLACES {two}"
              and (digest(one), digest(two)) == before, f"{brief(e)}; {brief(c)}")

    def export_row(row, tag, given, sentence, written, kept):
        def body():
            before = {path: digest(path) for path in kept}
            held = digest(written)
            seen = s.turn(tag, "export", {"preset": "h264", "path": given}, answer="allow")
            answer = json.loads(seen["text"] or "{}")
            done = s.client.wait_export(answer["export_id"], seconds=120) \
                if "export_id" in answer else {}
            same = all(digest(path) == value for path, value in before.items())
            changed = digest(written) not in (None, held)
            check(row, seen["asked"] == sentence and done.get("path") == str(written)
                  and changed and same,
                  f"{brief(seen)}; the job wrote {done.get('path')}; {written} changed {changed}; "
                  f"the others unchanged {same}")
        return body

    def caption_row(row, tag, arguments, sentence, written, kept):
        def body():
            before = {path: digest(path) for path in kept}
            held = digest(written)
            seen = s.turn(tag, "export_captions", arguments, answer="allow")
            same = all(digest(path) == value for path, value in before.items())
            changed = digest(written) not in (None, held)
            check(row, seen["asked"] == sentence and changed and same,
                  f"{brief(seen)}; {written} changed {changed}; the others unchanged {same}")
        return body

    def q6():
        package = s.closed_package(FILES / "talk.framejob")
        before = digest(package)
        seen = s.turn("q6", "save_project", {"path": str(FILES / "talk")})
        check("Q6", seen["asked"] == f"save_project REPLACES {package}"
              and digest(package) == before,
              f"{brief(seen)}; the package {before} → {digest(package)}")

    def q7():
        path = FILES / "bad.mp4"
        seen = s.turn("q7", "export", {"preset": "nope", "path": str(path)}, answer="allow")
        check("Q7", seen["asked"] == f"export writes {path}" and seen["error"] is True
              and "unknown export preset" in (seen["text"] or "") and not path.exists(),
              f"{brief(seen)}; written {path.exists()}")

    srt = FILES / "in.srt"
    srt.write_text("1\n00:00:00,000 --> 00:00:01,000\nHello there\n\n")
    s.call("import_captions", {"project": s.project, "path": str(srt)})
    attempt(["Q0"], q0)
    sentinel(FILES / "cut.mp4")
    attempt(["Q1"], export_row("Q1", "q1", str(FILES / "cut"),
                               f"export REPLACES {FILES / 'cut.mp4'}", FILES / "cut.mp4",
                               [FILES / "cut"]))
    sentinel(FILES / "cut2.mp4")
    attempt(["Q2"], export_row("Q2", "q2", str(FILES / "cut2.mov"),
                               f"export REPLACES {FILES / 'cut2.mp4'}", FILES / "cut2.mp4",
                               [FILES / "cut2.mov"]))
    sentinel(FILES / "talk.mov")
    attempt(["Q3"], export_row("Q3", "q3", str(FILES / "talk.mov"),
                               f"export writes {FILES / 'talk.mp4'}", FILES / "talk.mp4",
                               [FILES / "talk.mov"]))
    sentinel(FILES / "caps.srt")
    attempt(["Q4"], caption_row("Q4", "q4", {"path": str(FILES / "caps")},
                                f"export_captions REPLACES {FILES / 'caps.srt'}",
                                FILES / "caps.srt", [FILES / "caps"]))
    sentinel(FILES / "caps2.vtt")
    attempt(["Q5"], caption_row("Q5", "q5", {"path": str(FILES / "caps2.vtt"), "format": "srt"},
                                f"export_captions writes {FILES / 'caps2.srt'}",
                                FILES / "caps2.srt", [FILES / "caps2.vtt"]))
    attempt(["Q6"], q6)
    attempt(["Q7"], q7)


def new_row_rows(s):
    def n1():
        package = s.closed_package(FILES / "Demo.framejob")
        before = digest(package)
        seen = s.turn("n1", "new_project", {"path": package})
        windows = s.windows()
        check("N1", seen["asked"] == f"new_project REPLACES {package}"
              and digest(package) == before and package not in windows,
              f"{brief(seen)}; the package {before} → {digest(package)}; "
              f"its window open {package in windows}")
        s.quiet("close_project", {"project": package})

    def sentinel_row(row, tag, tool, arguments, sentence, kept):
        def body():
            before = digest(kept)
            seen = s.turn(tag, tool, arguments)
            check(row, seen["asked"] == sentence and digest(kept) == before,
                  f"{brief(seen)}; {Path(kept).name} {before} → {digest(kept)}")
        return body

    def n0():
        one = s.turn("n0a", "new_project", {})
        two = s.turn("n0b", "render_frame", {})
        three = s.turn("n0c", "render_graphic", {"name": "probe"})
        check("N0", all(t["first"] == "finished" and t["asked"] is None and t["error"] is False
                        for t in (one, two, three)),
              f"{brief(one)}; {brief(two)}; {brief(three)}")

    def n5():
        pack = FILES / "probe.fjgraphic"
        s.call("export_graphic", {"project": s.project, "name": "probe", "from": "project",
                                  "path": str(pack)})
        calls = [("n5a", "write_graphic", {"name": "second", "source": MODULE}),
                 ("n5b", "import_graphic_font", {"path": str(FONT)}),
                 ("n5c", "import_graphic_asset", {"path": str(ASSET)}),
                 ("n5d", "import_graphic", {"path": str(pack)})]
        seen = [s.turn(*call) for call in calls]
        check("N5", all(t["first"] == "finished" and t["asked"] is None and t["error"] is False
                        for t in seen), "; ".join(brief(t) for t in seen))

    s.call("write_graphic", {"project": s.project, "name": "probe", "source": MODULE})
    attempt(["N1"], n1)
    frame = sentinel(FILES / "frame.png")
    attempt(["N2"], sentinel_row("N2", "n2", "render_frame", {"path": frame},
                                 f"render_frame REPLACES {frame}", frame))
    sheet = sentinel(FILES / "sheet.png")
    attempt(["N3"], sentinel_row("N3", "n3", "render_graphic", {"name": "probe", "path": sheet},
                                 f"render_graphic REPLACES {sheet}", sheet))
    shot = sentinel(FILES / "shot.png")
    attempt(["N4"], sentinel_row("N4", "n4", "render_frame",
                                 {"path": str(FILES / "shot.jpg"), "format": "png"},
                                 f"render_frame REPLACES {shot}", shot))
    attempt(["N0"], n0)
    attempt(["N5"], n5)


def scope_rows(s):
    def s1():
        image = FILES / "s.png"
        scope = sentinel(FILES / "s.png.waveform.json")
        before = digest(scope)
        seen = s.turn("s1", "render_frame", {"path": str(image), "waveform": True})
        check("S1", seen["asked"] == f"render_frame writes {image}, and REPLACES {scope}"
              and digest(scope) == before and not image.exists(),
              f"{brief(seen)}; the sentinel {before} → {digest(scope)}")

    def s2():
        image = FILES / "s2.png"
        scope = FILES / "s2.png.waveform.json"
        seen = s.turn("s2", "render_frame", {"path": str(image), "waveform": True},
                      answer="allow")
        check("S2", seen["asked"] == f"render_frame writes {image}" and scope.exists(),
              f"{brief(seen)}; the JSON written {scope.exists()}")

    attempt(["S1"], s1)
    attempt(["S2"], s2)


def refusal_rows(s, movie):
    taken = FILES / "cut.framejob"

    def taken_row(row, tag, tool, arguments, words):
        def body():
            before = digest(taken)
            seen = s.turn(tag, tool, arguments)
            check(row, unasked_refusal(seen, words) and digest(taken) == before,
                  f"{brief(seen)}; the package {before} → {digest(taken)}")
        return body

    def refused_row(row, tag, tool, arguments, words, where=None):
        def body():
            seen = s.turn(tag, tool, arguments, project=where, pane=where is None)
            check(row, unasked_refusal(seen, words), brief(seen))
        return body

    def r0():
        free = FILES / "free.framejob"
        vertical = FILES / "vert.framejob"
        named = FILES / "named.framejob"
        media = f"{s.project}/media"
        turns = [
            (s.turn("r0a", "new_project_from_range",
                    {"from": 0, "to": SEC, "path": str(free)}),
             f"new_project_from_range writes {free}"),
            (s.turn("r0b", "make_vertical_version", {"shape": "9:16", "path": str(vertical)}),
             f"make_vertical_version writes {vertical}"),
            (s.turn("r0c", "save_project", {"path": str(named)}, project=movie, pane=False),
             f"save_project writes {named}"),
            (s.turn("r0d", "save_project", {}), f"save_project REPLACES {s.project}"),
            (s.turn("r0e", "consolidate_media", {}),
             f"consolidate_media copies every referenced file into {media}"),
        ]
        check("R0", all(t["asked"] == want for t, want in turns),
              "; ".join(brief(t) for t, _ in turns))

    s.closed_package(taken)
    attempt(["R0"], r0)
    attempt(["R1"], taken_row("R1", "r1", "new_project_from_range",
                              {"from": 0, "to": SEC, "path": str(taken)},
                              "already exists, so new_project_from_range did not write there"))
    attempt(["R2"], taken_row("R2", "r2", "make_vertical_version",
                              {"shape": "9:16", "path": str(taken)},
                              "already exists, so make_vertical_version did not write there"))
    attempt(["R3"], refused_row("R3", "r3", "save_project", {},
                                "This project has never been saved", movie))
    attempt(["R4"], refused_row("R4", "r4", "export", {"preset": "h264"},
                                "Missing required argument: path"))
    attempt(["R5"], refused_row("R5", "r5", "export_captions", {},
                                "Missing required argument: path"))
    attempt(["R6"], refused_row("R6", "r6", "save_project", {"path": 7}, "path must be a string"))
    attempt(["R7"], refused_row("R7", "r7", "consolidate_media", {},
                                "Save the project first", movie))
    attempt(["R8"], refused_row("R8", "r8", "render_frame", {"path": 7},
                                "path must be a string"))


def held_rows(s):
    held = FILES / "Held.framejob"

    def body(row, tag, tool):
        def run():
            before = digest(held)
            seen = s.turn(tag, tool, {"path": str(held)})
            check(row, unasked_refusal(seen, "Another open project (Held")
                  and f"so {tool} did not write there" in (seen["text"] or "")
                  and digest(held) == before,
                  f"{brief(seen)}; the package {before} → {digest(held)}")
        return run

    s.call("new_project", {"path": str(held)})
    attempt(["H1"], body("H1", "h1", "save_project"))
    attempt(["H0"], body("H0", "h0", "new_project"))
    s.quiet("close_project", {"project": str(held)})


def null_row(s):
    def p1():
        seen = s.turn("p1", "new_project_from_range", {"from": 0, "to": SEC, "path": None})
        check("P1", seen["first"] == "finished" and seen["asked"] is None
              and seen["error"] is False and '"saved"' not in (seen["text"] or ""), brief(seen))

    attempt(["P1"], p1)


def info_row(binary):
    def i1():
        dump = subprocess.run(["strings", "-a", str(binary)], capture_output=True, text=True,
                              errors="replace", timeout=120).stdout
        gone = ["asks before writing a file.", "until you press Generate, and"]
        here = ["asks before saving a project", "you press Generate or Transcribe"]
        found = {word: word in dump for word in gone + here}
        check("I1", not any(found[w] for w in gone) and all(found[w] for w in here), str(found))

    attempt(["I1"], i1)


def reply(s, tag, replies, window, project=None):
    """One scripted reply through the tab: its answer, and the entries it added."""
    before = len(s.entries(f"{tag}-before", project))
    s.fake.scenario(replies, window=window)
    answer = s.call("assistant_send", {"project": project or s.project, "pane": True,
                                       "text": f"Write a long reply ({tag}).", "timeout": 60})
    return answer, s.entries(tag, project)[before:]


def window_reply(tokens):
    row = say("Half a sent", stop=CONTEXT_STOP)
    row["input_tokens"] = tokens
    return row


def stop_rows(s):
    def c0():
        _, plain = reply(s, "c0a", [say("All of a sentence.")], 200_000)
        _, output = reply(s, "c0b", [say("Half a sent", stop="max_tokens")], 200_000)
        errors = [[t for k, t in entries if k == "error"] for entries in (plain, output)]
        check("C0", errors == [[], [OUTPUT_LINE]], f"error entries {errors}")

    def c1():
        answer, added = reply(s, "c1", [window_reply(199_990)], 200_000)
        errors = [t for k, t in added if k == "error"]
        check("C1", errors == [CONTEXT_LINE],
              f"state {answer.get('state')}, entries {[k for k, _ in added]}, errors {errors}")

    attempt(["C0"], c0)
    attempt(["C1"], c1)


def summary_of(seen):
    for event in seen["events"]:
        if event.get("type") == "tool_result":
            return event.get("summary") or ""
    return ""


def transcript_rows(s):
    def t0():
        s.turn("t0a", "add_marker", {"at": 2 * SEC, "name": "M"})
        seen = s.turn("t0b", "add_marker", {"at": 2 * SEC, "name": "N"})
        summary = summary_of(seen)
        check("T0", seen["error"] is True and summary == seen["text"],
              f"summary {summary!r}, tool_result {seen['text']!r}")

    def t1():
        seen = s.turn("t1", "transcribe", {"engine": "assemblyai"})
        summary = summary_of(seen)
        check("T1", seen["first"] == "finished" and seen["error"] is True
              and summary == seen["text"] and summary.endswith("instead.")
              and "spec §11" not in summary and "Generate Captions" in summary,
              f"{len(summary)} characters: {summary!r}; tool_result {len(seen['text'] or '')}")

    attempt(["T0"], t0)
    attempt(["T1"], t1)


def launch_a(s, binary):
    s.open_work("Work")
    movie = str(MEDIA / "A.mov")
    s.call("open_project", {"path": movie})
    question_rows(s)
    new_row_rows(s)
    scope_rows(s)
    refusal_rows(s, movie)
    held_rows(s)
    null_row(s)
    info_row(binary)
    stop_rows(s)
    transcript_rows(s)


def launch_b(s, _binary):
    def c2():
        s.fake.scenario([say("Warm.")], window=1_000_000)
        s.open_work("Second")
        summary = {"content": [{"type": "compaction", "content": "summary"}],
                   "stop_reason": "compaction",
                   "iterations": [{"type": "compaction", "input_tokens": 999_990,
                                   "output_tokens": 900, "cache_creation_input_tokens": 0,
                                   "cache_read_input_tokens": 0}]}
        answer, added = reply(s, "c2", [window_reply(999_990), summary], 1_000_000)
        errors = [t for k, t in added if k == "error"]
        check("C2", errors == [CONTEXT_LINE],
              f"state {answer.get('state')}, entries {[k for k, _ in added]}, errors {errors}")

    attempt(["C2"], c2)


# ---- launches ---------------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def run_launch(binary, tag, compact, body, rows):
    if not selected & set(rows):
        return
    fake = Fake(WORK / f"fake-{tag}")
    arguments = ["-RCSecretFolder", str(secret_folder(f"secrets-{tag}")), *PINS,
                 "-FrameJobAssistantAutoCompact", compact]
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME), "RC_ASSISTANT_BASE_URL": fake.base})
    env.pop("ANTHROPIC_API_KEY", None)
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected & set(rows):
                check(row, False, f"the app did not listen ({tag})")
            return
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(Stage(launched.client, fake), binary)
    finally:
        launched.stop()
        fake.stop()
    parity(log, tag)


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
    FILES.mkdir(parents=True)
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"docs bugs c1 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)",
              flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"docs bugs c1 — what the Assistant asks ({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    run_launch(binary, "a", "NO", launch_a, LAUNCH_A)
    run_launch(binary, "b", "YES", launch_b, LAUNCH_B)
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
