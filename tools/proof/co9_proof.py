#!/usr/bin/env python3
"""Road map "creator-jobs" CO9 — hide the camera while silent (spec §11 CO-90…CO-95).

    python3 tools/proof/co9_proof.py [--only H1,P2,…] [--mutant M1…M7] [--app PATH]

Media are made under `tools/proof/work/co9/media/` with ffmpeg: `camera.mov`, a solid white
1920 × 1080 movie with no sound, 20 s at 30 fps; `mic.m4a`, a 440 Hz sine, 20 s, audio only;
`voice.m4a`, `say`'s reading of a few sentences, audio only. Every app fixture is a saved
1920 × 1080, 30 fps package on a black canvas: the mic on the back track at 1 s with its in point
at 1 s, trimmed to end at 15 s, and the camera on the front track at 0 for 20 s. The mic's spans
are written with the `set_media_speech` op tool: [2 s, 4 s) and [10 s, 11 s) of source, so in
project time too. The camera's gate is `{media: mic, pre_roll: 0.2 s, hold: 1.2 s, fade: 0.4 s}`
— every edge, pre-roll, hold and half-fade a multiple of two frames, so each tick read is a
frame. The gated opacity is the centre pixel's red over black, /255, ± 3/255.

**Probe rows** (`co9_probe.swift`, built through `swift_build.py` with `FRAMEJOB_DEV_TOOLS`; a
probe that will not build is a scored FAIL):
- P1 `DuckSpeech.ops(forMedia:)`: an empty cache folder throws "not been detected yet", a
  stamped cache one `set_media_speech`, a media with spans `[]`, an unknown id `[]`, a media
  with no sound throws "has no sound".
- P2 `HideSilentSources.candidates`' order: the picture-less media first, then the overlap,
  then the id; a media whose clip does not overlap, and one with no sound, left out.
- P3 the section directly after Layout; its checkbox ONE edit "Hide While Silent" of
  `set_media_speech` then `set_video`; one undo restores the project.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) in one launch on a
scratch `CFFIXED_USER_HOME`, each document closed after its rows:
- H1 opacity 1 at 3 s (inside a widened span), 0 at 7 s (a gap longer than pre-roll + hold +
  2·fade), 0.5 at 5.4 s (e + hold + fade/2) and at 9.6 s (s − pre-roll − fade/2).
- H3 1 at 17 s, where no clip of the mic plays.
- H4 at 7 s, where the render is 0, `get_project`'s camera opacity is 1.
- H6 `set_action_end` with a patch naming `video.hide_silent` (an object and a null) and with
  `off: ["video.hide_silent"]`, each refused in "video.hide_silent is not an animation target".
- H2 after `ripple_delete_ranges [[6 s, 8 s]]` (both tracks): 0.5 at 5.4 s, 0 at 7 s, 0.5 at
  7.6 s and 1 at 8.5 s — the second span followed to [8 s, 9 s).
- H5 `remove_media {mic, with_clips: true}`: no camera clip keeps `hide_silent`, 1 at 7 s.
- H7 a fresh fixture with the camera alone nested (`nest`): 1 at 3 s, 0 at 7 s, 0.5 at 5.4 s —
  the mic read in the enclosing container.
- H8 a fresh fixture with `voice.m4a` in place of the mic: `set_video {hide_silent: {media:
  voice}}` (retried while "not been detected yet", at most 180 s) saves the voice's
  `speech` and the gate in one step (one `undo` removes both); `{media: camera}` refused with
  "has no sound, so a clip cannot hide while it is silent."
- Z1 the launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME` (CO-95): M1–M5 and M7 edit a copy of `core/` (beside a link to `graphic/`) and
run `cargo test --release --test hide_silent`, CAUGHT when a named test fails; M6 edits a
`tree_copy.py` copy's `AgentServer+Properties.swift` and runs H8 on its built app. CAUGHT exits 1,
SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
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
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
import bounded  # noqa: E402
import co2a_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co9"
HOME = WORK / "home"
KEEP = {"media"}
SEC = 600_000
CW, CH = 1920, 1080
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_WALL = 300
SPEECH_WAIT = 180
TOLERANCE = 3
GATE = {"pre_roll": 120_000, "hold": 720_000, "fade": 240_000}
SPANS = [[2 * SEC, 4 * SEC], [10 * SEC, 11 * SEC]]
PROBE_ROWS = ["P1", "P2", "P3"]
APP_ROWS = ["H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8"]
ROWS = ["Z1"] + PROBE_ROWS + APP_ROWS
NOT_TARGET = "video.hide_silent is not an animation target"

GATE_RS = "core/src/video_gate.rs"
ACTIONS_RS = "core/src/actions.rs"
END_RS = "core/src/edit_action_end.rs"
TRACK_RS = "core/src/edit_track.rs"
TOOL = "app/Sources/AgentServer+Properties.swift"
# name → (rows or test-name prefixes, [(path, anchor, replacement)], "core" or "app")
MUTANTS = {
    "M1": (["the_gate_is_one", "the_windowed_gate"], [(
        GATE_RS, "        widened(spans, gate.pre_roll, gate.hold)\n",
        "        let spans = spans.into_iter().map(|(a, b)| (a.saturating_add(2 * "
        "gate.pre_roll), b)).collect();\n        widened(spans, gate.pre_roll, gate.hold)\n")],
        "core"),
    "M2": (["the_windowed_gate"], [(
        GATE_RS, "            let spans = self.gate_spans(&members, gate, Some((lo, hi)));\n",
        "            let shifted: Vec<Instance<'_>> = members.iter().map(|i| Instance { origin: "
        "instance.origin, ..(*i).clone() }).collect();\n"
        "            let members: Vec<&Instance<'_>> = shifted.iter().collect();\n"
        "            let spans = self.gate_spans(&members, gate, Some((lo, hi)));\n")], "core"),
    "M3": (["clip_state_and_get_project"], [(
        ACTIONS_RS,
        "        let evaluated = self.evaluate_clip(clip, clip_t);\n        let in_action",
        "        let mut evaluated = self.evaluate_clip(clip, clip_t);\n"
        "        if let Some(i) = self.all_instances().into_iter().find(|i| i.clip.id == clip.id) "
        "{\n            evaluated.video.opacity *= self.hide_silent_gate(&i, t, "
        "crate::audio::Side::Right);\n        }\n        let in_action")], "core"),
    "M4": (["it_is_not_an_animation_target"], [(
        END_RS, '        ("video", "hide_silent") => Err("video.hide_silent is not an animation '
        'target".to_string()),\n', "")], "core"),
    "M5": (["a_nested_camera"], [(
        GATE_RS, "        for depth in (0..=path.len()).rev() {\n",
        "        for depth in [path.len()] {\n")], "core"),
    "M6": (["H8"], [(
        TOOL, '            document, "Video Properties", ops + [.setVideoRaw(clips: clips, '
        'patch: patch)])\n',
        '            document, "Video Properties", [.setVideoRaw(clips: clips, patch: patch)])\n'
        '        _ = ops\n')], "app"),
    "M7": (["remove_media_clears", "a_nested_camera"], [(
        TRACK_RS, "        next.clear_hide_silent(media);\n", "")], "core"),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


def t(seconds):
    return int(round(seconds * SEC))


# ---- media, the probe ----------------------------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    env = bounded.child_env()
    camera = folder / "camera.mov"
    if not camera.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"color=c=white:size={CW}x{CH}:rate=30:duration=20", "-c:v", "libx264",
                        "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "30", str(camera)],
                       check=True, timeout=600, env=env)
    mic = folder / "mic.m4a"
    if not mic.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        "sine=frequency=440:duration=20", "-c:a", "aac", str(mic)],
                       check=True, timeout=600, env=env)
    voice = folder / "voice.m4a"
    if not voice.exists():
        aiff = folder / "voice.aiff"
        subprocess.run(["say", "-o", str(aiff),
                        "Hello. This is a short test of hiding the camera while I am silent. "
                        "Now I pause for a moment. And now I speak again, a little longer, "
                        "so the voice detection has something to find."],
                       check=True, timeout=120, env=env)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(aiff), "-c:a", "aac",
                        str(voice)], check=True, timeout=600, env=env)
    return {"camera": camera, "mic": mic, "voice": voice}


def probe_rows(files, sources):
    out = WORK / "probe-co9"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co9_probe.swift", entry)
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    binary = out / "co9-probe"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        for row in PROBE_ROWS:
            check(row, False, f"the probe did not build: {'; '.join(error.diagnostics[:6])}")
        return
    request = WORK / "probe-request.json"
    request.write_text(json.dumps({"camera": str(files["camera"]), "mic": str(files["mic"])}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=PROBE_WALL,
                             env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    except subprocess.TimeoutExpired:
        for row in PROBE_ROWS:
            check(row, False, f"the probe gave no answer within {PROBE_WALL} s")
        return
    (WORK / "probe-stderr.txt").write_text(run.stderr)
    lines = [line for line in run.stdout.splitlines() if line.strip().startswith("{")]
    try:
        answers = {r["id"]: r for r in json.loads(lines[-1])["rows"]}
    except (ValueError, KeyError, IndexError):
        answers = {}
    for row in PROBE_ROWS:
        answer = answers.get(row)
        if answer is None:
            check(row, False, f"the probe did not answer it (exit {run.returncode})")
        else:
            check(row, answer["pass"], answer["detail"])


# ---- a document ----------------------------------------------------------------------------

class Doc:
    """One saved package: `sound` (the mic or the voice) on the back track at 1 s, in point
    1 s, ending at 15 s; the camera on the front track at 0 for 20 s."""

    def __init__(self, client, files, name, sound="mic"):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=CW, height=CH, fps=[30, 1],
                          background=[0, 0, 0, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.call("save_project")
            self.sound_media = self.call("import_media", path=str(files[sound]))["media"]
            self.camera_media = self.call("import_media", path=str(files["camera"]))["media"]
            while len(self.state()["tracks"]) < 2:
                self.call("add_track")
            tracks = [tr["id"] for tr in self.state()["tracks"]]
            self.sound = self.call("add_clip", track=tracks[0], media=self.sound_media,
                                   at=0)["new_clips"][0]
            self.call("trim_start", clip=self.sound, to=t(1))
            try:
                self.call("trim_end", clip=self.sound, to=t(15))
            except mcp.ToolError as error:
                # The voice ends before 15 s; the clip already does.
                if "made no change" not in str(error):
                    raise
            self.camera = self.call("add_clip", track=tracks[1], media=self.camera_media,
                                    at=0)["new_clips"][0]
        except Exception:
            self.close()
            raise

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def gate(self):
        """The mic's spans and the camera's gate."""
        self.call("set_media_speech", media=self.sound_media, spans=SPANS)
        self.call("set_video", clips=[self.camera],
                  patch={"hide_silent": {"media": self.sound_media, **GATE}})

    def opacity(self, seconds):
        out = WORK / f"{self.path.stem}-{int(seconds * 1000)}.png"
        if out.exists():
            out.unlink()
        self.call("render_frame", t=t(seconds), path=str(out))
        raw = co2a_proof.decode_png(out) if out.exists() else None
        if raw is None or len(raw) != CW * CH * 4:
            raise RuntimeError(f"render_frame at {seconds} s gave no {CW} × {CH} picture")
        return raw[((CH // 2) * CW + CW // 2) * 4]

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def gates(doc, row, wants):
    """`wants` [(seconds, gate)]: each rendered within TOLERANCE of gate × 255."""
    got = [(s, doc.opacity(s)) for s, _ in wants]
    ok = all(abs(v - g * 255) <= TOLERANCE for (_, v), (_, g) in zip(got, wants))
    check(row, ok, "; ".join(f"{s} s: {v} (want {g * 255:.1f})"
                             for (s, v), (_, g) in zip(got, wants)))


def refused(doc, row, arguments, sentence):
    try:
        doc.call("set_action_end", **arguments)
    except mcp.ToolError as error:
        check(row, sentence in str(error), f"{arguments.get('patch')} off "
              f"{arguments.get('off', [])}: {error}")
        return
    check(row, False, f"{arguments} applied")


def cameras(doc):
    return [c for c in doc.state()["clips"]
            if c.get("source", {}).get("media") == doc.camera_media]


def main_doc(client, files):
    doc = Doc(client, files, "h1")
    try:
        doc.gate()
        if "H1" in selected:
            attempt(lambda: gates(doc, "H1", [(3, 1), (7, 0), (5.4, 0.5), (9.6, 0.5)]), "H1")
        if "H3" in selected:
            attempt(lambda: gates(doc, "H3", [(17, 1)]), "H3")
        if "H4" in selected:
            def h4():
                rendered = doc.opacity(7)
                video = cameras(doc)[0].get("video") or {}
                check("H4", rendered <= TOLERANCE and video.get("opacity", 1.0) == 1.0,
                      f"render at 7 s {rendered}; get_project's opacity "
                      f"{video.get('opacity', 1.0)}, gate {video.get('hide_silent')}")
            attempt(h4, "H4")
        if "H6" in selected:
            def h6():
                doc.call("add_action", clip=doc.camera, at=0, duration=t(1))
                action = next(c for c in doc.state()["clips"]
                              if c["id"] == doc.camera)["actions"][0]["id"]
                base = {"clip": doc.camera, "action": action}
                refused(doc, "H6", {**base, "patch": {"video": {"hide_silent": {"fade": 0}}}},
                        NOT_TARGET)
                refused(doc, "H6", {**base, "patch": {"video": {"hide_silent": None}}},
                        NOT_TARGET)
                refused(doc, "H6", {**base, "patch": {}, "off": ["video.hide_silent"]},
                        NOT_TARGET)
                doc.call("undo")
            attempt(h6, "H6")
        if "H2" in selected:
            def h2():
                doc.call("ripple_delete_ranges", ranges=[[t(6), t(8)]])
                gates(doc, "H2", [(5.4, 0.5), (7, 0), (7.6, 0.5), (8.5, 1)])
            attempt(h2, "H2")
        if "H5" in selected:
            def h5():
                doc.call("remove_media", media=doc.sound_media, with_clips=True)
                kept = [c["id"] for c in cameras(doc) if (c.get("video") or {}).get("hide_silent")]
                rendered = doc.opacity(7)
                check("H5", not kept and abs(rendered - 255) <= TOLERANCE,
                      f"camera clips keeping a gate {kept}; render at 7 s {rendered}")
            attempt(h5, "H5")
    finally:
        doc.close()


def nested_doc(client, files):
    doc = Doc(client, files, "h7")
    try:
        doc.gate()
        doc.call("nest", clips=[doc.camera])
        state = doc.state()
        inside = [c for n in state.get("nests", []) for c in n["clips"]
                  if (c.get("video") or {}).get("hide_silent")]
        if len(inside) != 1:
            check("H7", False, f"the nest holds {len(inside)} gated clips")
            return
        gates(doc, "H7", [(3, 1), (7, 0), (5.4, 0.5)])
    finally:
        doc.close()


def voice_doc(client, files):
    doc = Doc(client, files, "h8", sound="voice")
    try:
        patch = {"hide_silent": {"media": doc.sound_media}}
        deadline = time.monotonic() + SPEECH_WAIT
        tries = 0
        while True:
            tries += 1
            try:
                doc.call("set_video", clips=[doc.camera], patch=patch)
                break
            except mcp.ToolError as error:
                if "not been detected yet" not in str(error) or time.monotonic() > deadline:
                    raise
                time.sleep(1)
        state = doc.state()
        voice = next(m for m in state["media"] if m["id"] == doc.sound_media)
        gate = (next(c for c in state["clips"] if c["id"] == doc.camera).get("video")
                or {}).get("hide_silent")
        saved = bool(voice.get("speech")) and (gate or {}).get("media") == doc.sound_media
        doc.call("undo")
        after = doc.state()
        voice_after = next(m for m in after["media"] if m["id"] == doc.sound_media)
        gate_after = (next(c for c in after["clips"] if c["id"] == doc.camera).get("video")
                      or {}).get("hide_silent")
        undone = voice_after.get("speech") is None and gate_after is None
        check("H8", saved and undone,
              f"after {tries} tries: {len(voice.get('speech') or [])} spans saved, gate {gate}; "
              f"one undo left spans {voice_after.get('speech')} and gate {gate_after}")
        try:
            doc.call("set_video", clips=[doc.camera],
                     patch={"hide_silent": {"media": doc.camera_media}})
            check("H8", False, "a gate on the camera (no sound) applied")
        except mcp.ToolError as error:
            check("H8", "has no sound, so a clip cannot hide while it is silent." in str(error),
                  f"the camera: {error}")
    finally:
        doc.close()


def app_rows(client, files):
    if {"H1", "H2", "H3", "H4", "H5", "H6"} & selected:
        attempt(lambda: main_doc(client, files), *({"H1", "H2", "H3", "H4", "H5", "H6"}
                                                   & selected))
    if "H7" in selected:
        attempt(lambda: nested_doc(client, files), "H7")
    if "H8" in selected:
        attempt(lambda: voice_doc(client, files), "H8")


def with_instance(binary, files):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in set(APP_ROWS) & selected:
                check(row, False, "the app did not listen")
            return False
        print(f"  instance PID {launched.child.pid}", flush=True)
        app_rows(launched.client, files)
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return True


# ---- mutants -------------------------------------------------------------------------------

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def core_mutant(name):
    copy = WORK / "mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    why = edited(name, copy)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK / "mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "hide_silent"],
                         cwd=copy / "core", capture_output=True, text=True,
                         timeout=BUILD_BOUND, env=env)
    (WORK / f"mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def run_mutant(name, files):
    global selected
    named, _, kind = MUTANTS[name]
    print(f"CO9 — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = [f for f in failed if any(f.startswith(p) for p in named)]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    selected = set(named) | {"Z1"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(name, Path(made))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(Path(made), BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    if not with_instance(proof_app.executable(app), files):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    if not all(row in results for row in named):
        print(f"mutant {name}: the control could not be performed — {named} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in named)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


# ---- main ----------------------------------------------------------------------------------

def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP_ROWS):
            selected.add("Z1")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant and MUTANTS[args.mutant][2] == "core":
        return run_mutant(args.mutant, None)
    files = media()
    if args.mutant:
        return run_mutant(args.mutant, files)

    print(f"CO9 — hide the camera while silent ({proof_app.config()} build)", flush=True)
    if selected & set(PROBE_ROWS):
        attempt(lambda: probe_rows(files, ROOT / "app/Sources"), *(selected & set(PROBE_ROWS)))
    if selected & set(APP_ROWS):
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        with_instance(binary, files)

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
