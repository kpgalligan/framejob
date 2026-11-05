#!/usr/bin/env python3
"""Docs bugs, batch c3 (#479 #480 #499 #512 #513 #515, spec §11 GR-36, GR-37, GR-38): the LUT warning
asks for a real Camera Log, a qualifier range keys off at an action's end, the LUT Remove button names
what it clears, and the filter, Camera Log and pick-hint wording is true.

    python3 tools/proof/docs_bugs_c3_proof.py [--only L1,Q1,…] [--mutant NAME] [--app PATH]
                                              [--base-sources PATH]
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_c3_proof.py

The built app (`proof_app`'s choice) under a scratch home, driven over MCP. Presses run in
`docs_bugs_c3_probe.swift`, built through `swift_build.build()` over `app/Sources`, on packages the
app saved: a real control's `mouseDown`, a real menu item's action, no event posted, no window on any
display, an alert read through a recorder. `(c)` marks a CONTROL, which passes on the base too; every
other row is red on the frozen base app with `--base-sources` set to the base's `app/Sources`.

- L (#479, app) a LUT look's warning row in the Look section's layout dump. L1 a PQ file: none. L2 (c)
  Apple Log: the row. L3 (c) a `{lut}` Camera Log: the row. L4 (c) an SDR file: none.
- Q (#480, app) Q1 `off: ["video.qualifier.hue"]` applied, end `{"video":{"qualifier":{"hue":null}}}`.
  Q2 pictures equal ON at 0.5 and 1.5 s, no-range at 4.5 s. Q3 `.saturation` and `.luma` likewise. Q4
  (c) `off: ["video.qualifier"]` refused.
- P (#480, probe) P1 the Hue box pressed: that end, box unticked, undo "Undo Hue". P2 the row reads ◆
  and "at end". P3 the row's Set end value to default: the same, the item then disabled. P4 Remove
  from action: the end back, the box ticked; a menu with no such item fails the row. P5 a grey pick:
  hue null and a saturation range, hue off past the end. P6 re-tick: the box unticked with `hue:
  null` stored before the press, ticked with `{"hue":{}}` after it. P7 a stored ramp on hue, unticked:
  null replaces it.
- R (#512, probe) R1 a Camera-Log-only LUT's title, and its button clears the file's Camera Log. R2
  (c) look-only. R3 both. R4 (c) a used video: `Remove and Delete Clips`. R5 (c) an unused LUT: no
  alert.
- F (#499) F1 the order tooltip in the layout dump. F2 `tools/list`'s `filters` clause, no "applied
  in order". F3 (c) blur/sepia both orders byte-identical, noir/sepia differ.
- T (#513) T1 the Camera Log tooltip in an SDR and an HLG project. T2 `tools/list`'s first sentence.
- H (#515, probe) H1 the qualifier hint. H2 Pick's tooltip. H3 (c) the key hint unchanged.

Z1 is `grep "Frame Job: "` over the launch's log.

`--mutant NAME`: the named decision broken in a tree copy from `tree_copy.py`, and only its rows run
(with Z1): the app and the probe are built from the copy when a row drives the app, the probe alone
otherwise; a mutant of the core runs `core/tests/action_off.rs` in a CoW copy of the core. CAUGHT
exits 1 (a named row failed), SURVIVED exits 0, and a control that could not be performed (the copy
did not build, an anchor not found once) exits 2.
"""

import argparse
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
import editor_keys_undo_proof as eku  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs-bugs-c3"
HOME = WORK / "home"
FILES = WORK / "files"
PACKAGES = WORK / "packages"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_c3_probe.swift"
SEC = 600_000
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_BOUND = 200
PINS = ["-FrameJobInspectorCollapsed", "NO",
        "-FrameJobInspectorSection.video.look", "<false/>",
        "-FrameJobInspectorSection.video.filters", "<false/>",
        "-FrameJobInspectorSection.media.camera_log", "<false/>"]

WARNING = "This clip's file is converted by Camera Log; a camera LUT here converts it twice."
ORDER_TIP = ("Where this filter sits in the stack. Sepia, Noir, Vignette and Invert apply in stack "
             "order; Blur, Sharpen and Pixelate always apply first.")
FILTERS_CLAUSE = ("filters (an ARRAY of {kind, amount}, at most 4; sepia, noir, vignette and invert "
                  "apply in list order, after blur, sharpen and pixelate, which apply first wherever "
                  "they sit — kind is ")
LOG_TIP = "How this file's log footage is converted to the project's color"
COLOR_SENTENCE = ("Sets how a video file's camera log footage is converted to the project's colour, "
                  "Rec. 709 or HLG in an HDR project — the Media tab's Camera Log popup.")
QUALIFIER_HINT = "Click to pick the color to qualify · Esc to cancel"
PICK_TIP = "Click the preview to centre the ranges on a color (Esc cancels)"
KEY_HINT = "Click to pick the key color · Esc to cancel"
HUE_OFF = {"video": {"qualifier": {"hue": None}}}

HUE = {"center": 120, "width": 60, "softness": 10}
SATURATION = {"low": 0.9, "high": 1.0, "softness": 0.0}
LUMA = {"low": 0.3, "high": 0.6, "softness": 0.05}
RAMP = {"center": 200, "width": 60, "softness": 10}
T_BEFORE, T_DURING, T_AFTER = int(0.5 * SEC), int(1.5 * SEC), int(4.5 * SEC)
TIMES = (T_BEFORE, T_DURING, T_AFTER)

APP_ROWS = ["L1", "L2", "L3", "L4", "Q1", "Q2", "Q3", "Q4", "F1", "F2", "F3", "T1", "T2"]
PROBE_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "R1", "R2", "R3", "R4", "R5", "H1", "H2",
              "H3"]
CORE_ROW = "action_off"
ROWS = APP_ROWS + PROBE_ROWS + ["Z1"]

LIFT = ('            // So is a qualifier range turned off (GR-36).\n'
        '            if group == "video", var qualifier = fields["qualifier"] as? [String: Any] {\n'
        '                for (range, value) in qualifier where value is NSNull {\n'
        '                    off.append("video.qualifier.\\(range)")\n'
        '                    qualifier[range] = nil\n'
        '                }\n'
        '                fields["qualifier"] = qualifier\n'
        '            }\n')
TITLE = ('                ? "Remove and Clear " + cleared.joined(separator: " and ")\n')
# name: (the rows it must turn red, whether a row drives the app, the edits).
MUTANTS = {
    "unknown-range-arm": ([CORE_ROW], False, [(
        "core/src/edit_action_end.rs",
        '            ["video", "qualifier", range] => {\n'
        '                return Err(format!(\n'
        '                    "off path \\"{path}\\" names no qualifier range: \\"{range}\\" is not one '
        'of {}",\n'
        '                    QUALIFIER_RANGES.join(", ")\n'
        '                ))\n'
        '            }\n', "")]),
    "lift-removed": (["P1", "P5"], False, [("app/Sources/ReelOps.swift", LIFT, "")]),
    "decoder-absent": (["P2"], False, [(
        "app/Sources/QualifierProps.swift",
        "        let read: QualifierWrite<T>?? = c.nullable(key)\n"
        "        return read.map { $0 ?? .off }\n",
        "        return c.lenient(key)\n")]),
    "any-color-warns": (["L1"], True, [(
        "app/Sources/VideoPane+Look.swift",
        "snapshot.media(media)?.color.flatMap(InputConversion.choose(input:)) != nil",
        "snapshot.media(media)?.color != nil")]),
    "title-by-kind": (["R1"], False, [(
        "app/Sources/MediaPaneCommands.swift", TITLE,
        '                ? "Remove and Clear Looks"\n')]),
    "both-title-dropped": (["R3"], False, [(
        "app/Sources/MediaPaneCommands.swift",
        '(converted > 0 ? ["Camera Log"] : [])',
        '(converted > 0 && users.isEmpty ? ["Camera Log"] : [])')]),
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


# ---- the fixtures -----------------------------------------------------------------------

def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *arguments], check=True,
                   timeout=180)


def label(primaries, transfer, matrix):
    """Both labels, in a copying pass: the encode's own flags leave the `colr` atom unknown, and the
    ProRes frame header and that atom are what AVFoundation reads."""
    return ["-bsf:v", f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:"
            f"colorspace={matrix}", "-color_primaries", primaries, "-color_trc", transfer,
            "-colorspace", matrix, "-movflags", "+write_colr"]


def cube(path, table):
    with open(path, "w") as handle:
        handle.write("LUT_3D_SIZE 2\n")
        for b in (0, 1):
            for g in (0, 1):
                for r in (0, 1):
                    handle.write("%g %g %g\n" % table(r, g, b))


def fixtures():
    prores = ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
    plain = FILES / "plain.mov"
    ffmpeg("-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=6", *prores, str(plain))
    media = {}
    for name, tags in (("pattern", ("bt709", "bt709", "bt709")),
                       ("sdr", ("bt709", "bt709", "bt709")),
                       ("second", ("bt709", "bt709", "bt709")),
                       ("pq", ("bt2020", "smpte2084", "bt2020nc"))):
        media[name] = str(FILES / f"{name}.mov")
        ffmpeg("-i", str(plain), "-c", "copy", *label(*tags), media[name])
    plain.unlink()
    for name, table in (("swap", lambda r, g, b: (g, r, b)),
                        ("tint", lambda r, g, b: (r, g * 0.7, b * 0.7)),
                        ("both", lambda r, g, b: (r * 0.7, g, b * 0.7)),
                        ("free", lambda r, g, b: (r * 0.7, g * 0.7, b))):
        media[name] = str(FILES / f"{name}.cube")
        cube(media[name], table)
    return media


class Session:
    """One project in the instance, each call with the project named."""

    count = 0

    def __init__(self, client, name):
        Session.count += 1
        self.client = client
        self.path = str(FILES / f"{name}-{Session.count}.framejob")
        self.client.call_with("new_project", {"path": self.path})

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def project(self):
        return self.op("get_project")["project"]

    def track(self):
        return self.project()["tracks"][0]["id"]

    def media_of(self, path):
        return self.op("import_media", path=str(path))["media"]

    def add(self, media, at=0):
        return self.op("add_clip", track=self.track(), media=media, at=at)["new_clips"][0]

    def clip(self, clip):
        return next(k for k in self.project()["clips"] if k["id"] == clip)

    def frame(self, tag, t):
        path = FILES / f"{Path(self.path).stem}-{tag}-{t}.png"
        self.op("render_frame", t=t, path=str(path))
        return path.read_bytes()

    def views(self, tag):
        png = FILES / f"{Path(self.path).stem}-{tag}.png"
        self.op("snapshot_ui", window="editor", view="inspector", layout=True, path=str(png))
        data = json.load(open(str(png)[:-4] + ".layout.json"))
        return data["views"] if isinstance(data, dict) and "views" in data else data

    def keep(self, name):
        """The project as saved now, as the probe's package `name`, without `cache/`: the instance
        is still writing thumbnails there, through temporary files that vanish under a copy."""
        self.op("save_project")
        target = PACKAGES / f"{name}.framejob"
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(self.path, target, ignore=shutil.ignore_patterns("cache"))

    def close(self):
        self.op("close_project", discard=True)


# ---- the app's rows ---------------------------------------------------------------------

def warning_rows(client, media):
    def body():
        s = Session(client, "warnings")
        files = {name: s.media_of(media[source]) for name, source in (
            ("pq", "pq"), ("sdr", "sdr"), ("log", "pattern"), ("lut", "second"))}
        look = s.media_of(media["swap"])
        conversion = s.media_of(media["tint"])
        s.op("set_media_color", media=files["log"], color={"log": "apple_log"})
        s.op("set_media_color", media=files["lut"], color={"lut": conversion})
        clips = {name: s.add(files[name], at=index * 6 * SEC)
                 for index, name in enumerate(("pq", "sdr", "log", "lut"))}
        for clip in clips.values():
            s.op("set_video", clips=[clip], patch={"look": {"kind": "lut", "media": look}})
        stored = {m["id"]: m.get("color") for m in s.project()["media"]}
        for index, (name, clip) in enumerate(clips.items()):
            s.op("set_selection", clips=[clip])
            s.op("set_playhead", t=index * 6 * SEC + SEC)
            s.op("select_inspector_tab", tab="clip", sub_tab="color", section="video.look")
            rows = [v for v in s.views(f"look-{name}") if v.get("text") == WARNING]
            shown = [v for v in rows if not v.get("hidden")]
            color = stored[files[name]]
            if name == "pq":
                check("L1", not shown and color == {"pq": {}} and rows == [],
                      f"PQ file, color {color}, warning rows {len(shown)}")
            elif name == "log":
                check("L2", len(shown) == 1, f"Apple Log, color {color}, rows {len(shown)}")
            elif name == "lut":
                check("L3", len(shown) == 1, f"Camera Log LUT, color {color}, rows {len(shown)}")
            else:
                check("L4", not shown, f"SDR file, color {color}, rows {len(shown)}")
        s.close()

    attempt(["L1", "L2", "L3", "L4"], body)


def qualifier_rows(client, media, ids):
    def body():
        s = Session(client, "qualifier")
        source = s.media_of(media["pattern"])
        ids["clip"] = s.add(source)
        s.op("add_track", name="Grade")
        grade = next(t["id"] for t in s.project()["tracks"] if t["name"] == "Grade")
        adjust = s.op("add_adjustment_clip", track=grade, at=0, duration=6 * SEC)["new_clips"][0]
        ids["adjust"] = adjust
        s.op("set_video", clips=[adjust], patch={"color": {"saturation": -1}})
        none = {t: s.frame("none", t) for t in TIMES}
        s.op("set_video", clips=[adjust], patch={"qualifier": {"hue": HUE}})
        s.op("set_selection", clips=[adjust])
        s.op("set_playhead", t=SEC)
        s.op("perform_menu_item", path=["Clip", "Add Action"])
        action = s.clip(adjust)["actions"][0]
        ids["action"] = action["id"]
        s.keep("qualifier")

        def end_at(patch, off=None):
            arguments = dict(clip=adjust, action=action["id"], patch=patch)
            if off is not None:
                arguments["off"] = off
            try:
                s.op("set_action_end", **arguments)
            except mcp.ToolError as error:
                return str(error)
            return None

        def cleared():
            end_at({"video": None})

        end_at({"video": {"qualifier": {"hue": RAMP}}})
        s.keep("qualifier-ramp")
        cleared()

        def switched(tag, range_name, value):
            """A range alone on the clip, keyed off: the ON picture, then no range after the end."""
            try:
                s.op("set_video", clips=[adjust], patch={"qualifier": {
                    key: value if key == range_name else None
                    for key in ("hue", "saturation", "luma")}})
            except mcp.ToolError as error:  # the identity arm: the clip already holds it
                if "no change" not in str(error):
                    raise
            on = {t: s.frame(f"on-{tag}", t) for t in TIMES}
            differs = all(on[t] != none[t] for t in TIMES)
            refused = end_at({}, [f"video.qualifier.{range_name}"])
            end = s.clip(adjust)["actions"][0]["end"]
            after = {t: s.frame(f"off-{tag}", t) for t in TIMES}
            held = after[T_BEFORE] == on[T_BEFORE] and after[T_DURING] == on[T_DURING]
            gone = after[T_AFTER] == none[T_AFTER]
            cleared()
            return refused, end, differs, held, gone

        refused, end, differs, held, gone = switched("hue", "hue", HUE)
        check("Q1", refused is None and end == HUE_OFF, f"refused {refused}, end {end}")
        check("Q2", refused is None and differs and held and gone,
              f"ON differs from no range {differs}, held to the end {held}, no range past it {gone}")
        for range_name, value in (("saturation", SATURATION), ("luma", LUMA)):
            refused, end, differs, held, gone = switched(range_name, range_name, value)
            want = {"video": {"qualifier": {range_name: None}}}
            check("Q3", refused is None and end == want and differs and held and gone,
                  f"{range_name}: refused {refused}, end {end}, ON differs {differs}, held {held}, "
                  f"gone {gone}")
        whole = end_at({}, ["video.qualifier"])
        check("Q4", whole is not None and "video.qualifier" in whole, repr(whole))
        s.close()

    attempt(["Q1", "Q2", "Q3", "Q4"] + [r for r in PROBE_ROWS if r[0] in "PH"], body)


def filter_rows(client, media):
    def body():
        s = Session(client, "filters")
        clip = s.add(s.media_of(media["pattern"]))
        s.op("set_selection", clips=[clip])
        s.op("set_playhead", t=2 * SEC)

        def render(kinds):
            filters = [{"kind": kind, "amount": 0.8} for kind in kinds]
            s.op("set_video", clips=[clip], patch={"filters": filters})
            return s.frame("-".join(kinds), 2 * SEC)

        blur = render(["blur", "sepia"]) == render(["sepia", "blur"])
        noir = render(["noir", "sepia"]) != render(["sepia", "noir"])
        check("F3", blur and noir, f"blur/sepia identical {blur}, noir/sepia differ {noir}")
        s.op("select_inspector_tab", tab="clip", sub_tab="picture", section="video.filters")
        tips = {v.get("tooltip") for v in s.views("filters")
                if "in the stack" in (v.get("tooltip") or "")}
        check("F1", tips == {ORDER_TIP}, str(tips))
        text = client.schemas()["set_video"]["inputSchema"]["properties"]["patch"]["description"]
        check("F2", FILTERS_CLAUSE in text and "applied in order" not in text,
              text[text.find("filters (an ARRAY"):][:190])
        s.close()

    attempt(["F1", "F2", "F3"], body)


def camera_log_rows(client, media):
    def body():
        for tag, canvas in (("sdr", None), ("hlg", {"output": "hlg"})):
            s = Session(client, f"log-{tag}")
            if canvas:
                s.op("set_canvas", **canvas)
            source = s.media_of(media["pattern"])
            s.op("set_media_color", media=source, color={"log": "apple_log"})
            s.op("set_selection", clips=[s.add(source)])
            s.op("select_inspector_tab", tab="media", section="media.camera_log")
            tips = {v.get("tooltip") for v in s.views("camera-log")
                    if "log footage" in (v.get("tooltip") or "")}
            check("T1", tips == {LOG_TIP}, f"{tag}: {tips}")
            s.close()
        text = client.schemas()["set_media_color"]["description"]
        check("T2", text.startswith(COLOR_SENTENCE), text[:150])

    attempt(["T1", "T2"], body)


def remove_package(client, media, ids):
    def body():
        s = Session(client, "remove")
        one, two = s.media_of(media["pattern"]), s.media_of(media["second"])
        video = s.media_of(media["sdr"])
        swap, tint, both, free = (s.media_of(media[name])
                                  for name in ("swap", "tint", "both", "free"))
        first, second = s.add(one), s.add(two, at=6 * SEC)
        s.add(video, at=12 * SEC)
        s.op("set_media_color", media=one, color={"lut": swap})
        s.op("set_media_color", media=two, color={"lut": both})
        s.op("set_video", clips=[first], patch={"look": {"kind": "lut", "media": tint}})
        s.op("set_video", clips=[second], patch={"look": {"kind": "lut", "media": both}})
        ids.update(swap=swap, tint=tint, both=both, free=free, file=one, video=video)
        s.keep("remove")
        s.close()

    attempt([r for r in PROBE_ROWS if r[0] == "R"], body)


# ---- the probe's rows -------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-c3-probe"
    _, why = eku.build_shader(str(OUT), str(ROOT))
    if why:
        return None, why
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                                  defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    print(f"  probe {built.key} reused {built.reused}, {built.seconds} s", flush=True)
    return binary, None


def probe_run(binary, stage):
    """The rows the probe printed, by stage; a stage that aborts fails its rows by raising."""
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    done = subprocess.run([str(binary), str(PACKAGES), str(WORK / "ids.json"), stage],
                          capture_output=True, text=True, env=env, timeout=PROBE_BOUND, cwd=OUT,
                          stdin=subprocess.DEVNULL)
    (WORK / f"probe-{stage}.txt").write_text(done.stdout + "\n--- stderr\n" + done.stderr)
    rows = {}
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            row = json.loads(line)
            rows[row["row"]] = row
    if "abort" in rows:
        raise RuntimeError(rows["abort"]["abort"])
    if done.returncode != 0 or "done" not in rows:
        raise RuntimeError(f"exit {done.returncode}: {done.stderr[-400:]}")
    return rows


def has_item(state, prefix):
    return [item for item in state["items"] or [] if item["title"].startswith(prefix)]


def qualifier_probe_rows(binary):
    def body():
        rows = probe_run(binary, "qualifier")
        press = rows["press"]
        off, ticked = press["unticked"], press["ticked"]
        check("P1", press["pressed"] and off["end"] == HUE_OFF and off["box"] is False
              and off["undo"] == "Undo Hue" and not off["past_hue"]
              and press["start"]["box"] is True,
              f"end {off['end']}, box {off['box']}, undo {off['undo']!r}, hue past the end "
              f"{off['past_hue']}, base {off['base']}")
        row = off["row"] or {}
        check("P2", row.get("mark") == "keyedAtEnd" and "at end" in row.get("texts", []),
              f"row {row}, marks {off['marks']}")
        check("P6", off["box"] is False and off["end"] == HUE_OFF and ticked["box"] is True
              and ticked["end"] == {"video": {"qualifier": {"hue": {}}}},
              f"before: box {off['box']}, end {off['end']}; after: box {ticked['box']}, end "
              f"{ticked['end']}")

        removed = rows["remove-key"]
        after = removed["after"]
        check("P4", removed["performed"] and after["box"] is True
              and after["end"] in ({"video": {"qualifier": {}}}, {"video": {}}, {}),
              f"performed {removed['performed']}, box {after['box']}, end {after['end']}")

        made = rows["default"]
        after = made["after"]
        item = has_item(after, "Set end value to default")
        check("P3", made["enabled_before"] and made["performed"] and after["end"] == HUE_OFF
              and after["box"] is False and item and item[0]["enabled"] is False,
              f"performed {made['performed']}, end {after['end']}, box {after['box']}, items "
              f"{after['items']}")

        picked = rows["pick"]
        after = picked["after"]
        qualifier = ((after["end"] or {}).get("video") or {}).get("qualifier") or {}
        check("P5", picked["armed"] and picked["landed"] and "hue" in qualifier
              and qualifier["hue"] is None and isinstance(qualifier.get("saturation"), dict)
              and not after["past_hue"] and after["past_saturation"],
              f"landed {picked['landed']}, end {after['end']}, past the end hue "
              f"{after['past_hue']} saturation {after['past_saturation']}")

        ramp = rows["ramp"]
        check("P7", ramp["before"]["end"] == {"video": {"qualifier": {"hue": RAMP}}}
              and ramp["after"]["end"] == HUE_OFF,
              f"before {ramp['before']['end']}, after {ramp['after']['end']}")

    attempt(["P1", "P2", "P3", "P4", "P5", "P6", "P7"], body)


def remove_probe_rows(binary):
    def body():
        rows = probe_run(binary, "remove")

        def first(name):
            return (rows[f"remove-{name}"]["buttons"] or [None])[0]

        pressed = rows.get("remove-swap-pressed", {})
        check("R1", first("swap") == "Remove and Clear Camera Log"
              and "file_color" in pressed and pressed["file_color"] is None,
              f"title {first('swap')!r}, text {rows['remove-swap']['text']!r}, the file's Camera "
              f"Log after the press {pressed.get('file_color', 'not pressed')}")
        check("R2", first("tint") == "Remove and Clear Looks", repr(first("tint")))
        check("R3", first("both") == "Remove and Clear Looks and Camera Log", repr(first("both")))
        check("R4", first("video") == "Remove and Delete Clips", repr(first("video")))
        free = rows["remove-free"]
        check("R5", not free["alert"] and free["after"] == free["before"] - 1,
              f"alert {free['alert']}, media {free['before']} → {free['after']}")

    attempt(["R1", "R2", "R3", "R4", "R5"], body)


def hint_probe_rows(binary):
    def body():
        row = probe_run(binary, "hints")["hints"]
        check("H1", row["qualifier_hint"] == QUALIFIER_HINT, repr(row["qualifier_hint"]))
        check("H2", row["qualifier_tip"] == PICK_TIP, repr(row["qualifier_tip"]))
        check("H3", row["chroma_hint"] == KEY_HINT, repr(row["chroma_hint"]))

    attempt(["H1", "H2", "H3"], body)


# ---- the run ----------------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def run_app(binary, media, ids):
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), PINS, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"Z1"}:
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        client = launched.client
        warning_rows(client, media)
        qualifier_rows(client, media, ids)
        filter_rows(client, media)
        camera_log_rows(client, media)
        remove_package(client, media, ids)
    finally:
        launched.stop()
    parity(log)


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    if any(path.startswith("core/") for path, _, _ in MUTANTS[name][2]):
        link = Path(made) / "core"
        link.unlink()
        subprocess.run(["cp", "-c", "-R", str(ROOT / "core"), str(link)], check=True)
    for path, anchor, replacement in MUTANTS[name][2]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


def core_mutant(name, made):
    """`action_off.rs` against the copy's core: 1 caught, 0 survived, 2 not performed."""
    done = subprocess.run(["cargo", "test", "--release", "--test", "action_off"],
                          cwd=str(made / "core"), capture_output=True, text=True,
                          timeout=BUILD_BOUND)
    text = done.stdout + done.stderr
    (WORK / "core-mutant.txt").write_text(text)
    if "test result:" not in text:
        print(f"mutant {name}: the control could not be performed — no test ran: {text[-400:]}")
        return 2
    failed = sorted(line.split()[1] for line in text.splitlines()
                    if line.startswith("test ") and line.endswith("FAILED"))
    print(f"MUTANT {name} {'CAUGHT' if failed else 'SURVIVED'}: {failed or 'every test passed'}")
    return 1 if failed else 0


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    parser.add_argument("--base-sources")
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
    PACKAGES.mkdir(parents=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        named, drives_app, _ = MUTANTS[args.mutant]
        print(f"docs bugs c3 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        made, why = mutate(args.mutant)
        if why is None and CORE_ROW in named:
            return core_mutant(args.mutant, made)
        if why is None:
            sources = made / "app/Sources"
            if drives_app:
                app, why = tree_copy.build_app(made, BUILD_BOUND)
                binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"docs bugs c3 — colour: warnings, qualifiers, titles and words "
              f"({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)

    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            if args.mutant:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
            selected -= set(PROBE_ROWS)

    media = fixtures()
    ids = {}
    run_app(binary, media, ids)
    (WORK / "ids.json").write_text(json.dumps(ids))
    if probe is not None:
        if selected & {"P1", "P2", "P3", "P4", "P5", "P6", "P7"}:
            qualifier_probe_rows(probe)
        if selected & {"R1", "R2", "R3", "R4", "R5"}:
            remove_probe_rows(probe)
        if selected & {"H1", "H2", "H3"}:
            hint_probe_rows(probe)

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
