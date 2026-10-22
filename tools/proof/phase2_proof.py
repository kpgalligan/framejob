"""Road map 2, phase 2 — clip identity (schema v3), driven against the built
binary over MCP.

Every claim is a placement read back through `get_project`, a BYTE comparison
of two `render_frame` PNGs, or a sample-for-sample comparison of two exports
decoded to raw PCM. Nothing here reads the source. Every check is one that
would FAIL against a build where the op did nothing.

Media: A.mov (the silent test card), AV.mov (the test card with a 440 Hz tone
under it — a clip with BOTH a video and an audio group), toneA.m4a (440 Hz)
and toneB.m4a (880 Hz); the recipe is in README.md.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from array import array

from mcp import MCP, ToolError, target

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
HEADER = os.path.join(HERE, "..", "..", "core", "include", "framejob_core.h")


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes stale at every bump."""
    with open(HEADER) as f:
        text = f.read()
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", text)
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


CURRENT_VERSION = format_version()

# Everything on a clip OUTSIDE the four property groups: what
# `paste_attributes` must leave byte-identical.
OUTSIDE_GROUPS = [
    "id", "track", "start", "duration", "source", "enabled", "speed", "actions",
    "transition_in", "name", "label",
]

failures = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def canonical(value):
    """One spelling of a JSON value, so two documents compare as text."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def copy_package(source, destination):
    """A byte copy of a `.framejob` package, tolerating the cache's churn.

    The package being copied is OPEN in the instance under proof, and that
    instance writes thumbnails while the copy runs: each one goes to
    `cache/thumbs/<media>/.<n>.jpg-<random>` and is renamed into place, so a
    plain `shutil.copytree` fails on a name that was listed a moment earlier
    and is already gone (measured: `[Errno 2] .8.jpg-nKhR`). A file that
    vanishes under `cache/` is therefore skipped — it is a thumbnail, a peaks
    file or a reversed render, all regenerable and no part of any claim made
    here. Everything else is copied byte for byte, and a file that vanishes
    ANYWHERE else is still an error.

    `cache/` itself is copied rather than skipped: the app creates the
    directory when it opens a package that has none, which changed the
    package directory's modification date, and `save_project` then refused
    the document as "changed by another application" (also measured; fixed
    by #138, which re-reads the date when `cache/` is created)."""
    for root, _, files in os.walk(source):
        relative = os.path.relpath(root, source)
        target = destination if relative == "." else os.path.join(destination, relative)
        os.makedirs(target, exist_ok=True)
        for name in files:
            try:
                shutil.copy2(os.path.join(root, name), os.path.join(target, name))
            except FileNotFoundError:
                if relative.split(os.sep)[0] != "cache":
                    raise


class Session:
    """One project, with frame rendering reduced to a hash."""

    def __init__(self, mcp, name, open_from=None):
        self.mcp = mcp
        # Every package is `<name>-<pid>.framejob`, never a fixed name, because
        # a `project` path is matched against EVERY open document and there
        # is no tool that closes one: once two earlier runs have left SAVED
        # documents at a fixed path, the app answers for an old one (measured
        # — a fresh `new_project` at such a path was followed by `set_canvas`
        # refusing as "already in that state"; phase 1 never saves, and its
        # third run is fine). Older runs' packages under the same name go, as
        # phase 1's do.
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.framejob")
        if open_from is None:
            mcp.call("new_project", path=self.path)
            self.mcp.call("set_canvas", project=self.path, width=640, height=360)
            return
        # A byte copy of a saved package, opened from disk: `open_project` on
        # a path that is ALREADY open answers "already_open" without
        # re-reading the file, so a read-back-from-disk claim needs a path of
        # its own.
        copy_package(open_from, self.path)
        answer = self.mcp.call("open_project", path=self.path)
        check(
            not answer.get("already_open"),
            f"{name}: the copy was opened from disk, not matched to an open document",
        )

    def op(self, name, **kwargs):
        if name == "export":  # an id since #326; the helper follows it to the file
            return self.mcp.export(project=self.path, **kwargs)
        return self.mcp.call(name, project=self.path, **kwargs)

    def call_with(self, tool, arguments):
        """`op` with the arguments as a dict, for a tool ARGUMENT spelled
        `name` — `MCP.call`'s own first parameter (tools/proof/mcp.py)."""
        return self.mcp.call_with(tool, dict(arguments, project=self.path))

    def raw(self, tool, arguments):
        """(is_error, text) of a `call_with`, for the checks that send a
        TOP-LEVEL `name` and want the refusal's wording."""
        try:
            return False, str(self.call_with(tool, arguments))
        except ToolError as error:
            return True, str(error)

    def frame(self, t):
        """The hash of the PNG `render_frame` wrote — the tool answers with a
        sentence naming the file, so the path is read out of it."""
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return digest(found.group(1))

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        """The whole project as one canonical string — the oracle for
        "undo restores everything" and "nothing else moved"."""
        return canonical(self.project())

    def clips(self):
        return {c["id"]: c for c in self.project()["clips"]}

    def clip(self, clip):
        return self.clips()[clip]

    def tracks(self):
        return {t["id"]: t for t in self.project()["tracks"]}

    def track_ids(self):
        return [t["id"] for t in self.project()["tracks"]]

    def place(self, track, media, at):
        return self.op("add_clip", track=track, media=media, at=int(at))["new_clips"][0]

    def media(self, name):
        return self.op("import_media", path=os.path.join(MEDIA, name))["media"]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def refuses(self, tool, **kwargs):
        """An IDENTITY comes back as an in-band error whose message begins
        "<Op> made no change" — the app's wording for an op that was valid
        and had nothing to change, which registers no undo step. Since road
        map 7's D2 a rule's REFUSAL says "was refused at <op>: …" instead and
        would not match here; every call below is an identity."""
        message = self.error(tool, **kwargs)
        return message is not None and "made no change" in message

    def undo(self):
        return self.op("undo")["undone"]

    def save(self, path=None):
        if path is None:
            return self.op("save_project")
        return self.op("save_project", path=path)

    def export(self, name):
        """An audio-only export into work/; the tool replaces the extension
        with the container's, so the path is read out of the result."""
        target = os.path.join(WORK, f"{name}.m4a")
        if os.path.exists(target):
            os.remove(target)
        result = self.op("export", preset="audio_m4a", path=target)
        return result["path"], result


def project_json(package):
    with open(os.path.join(package, "project.json"), encoding="utf-8") as handle:
        return handle.read()


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
            "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out,
        ],
        check=True,
    )
    with open(out, "rb") as handle:
        return handle.read()


def samples(data):
    values = array("h")
    values.frombytes(data)
    return values


def wobble(a, b):
    """(max |Δ|, count of differing samples) between two PCM dumps, or None
    when they are not even the same length."""
    if len(a) != len(b):
        return None
    if a == b:
        return (0, 0)
    diffs = [abs(p - q) for p, q in zip(samples(a), samples(b)) if p != q]
    return (max(diffs), len(diffs))


def same(a, b, tolerance):
    """Sample-for-sample equal, within the measured wobble (0 = byte-equal)."""
    w = wobble(a, b)
    return w is not None and w[0] <= tolerance


def describe(a, b):
    w = wobble(a, b)
    if w is None:
        return f"lengths differ ({len(a)} vs {len(b)} bytes)"
    return f"max |Δ| {w[0]}, {w[1]} samples differ, of {len(a) // 2}"


def strip_v3(text):
    """A saved project.json rewritten as a version-2 file: the three keys
    phase 2 added are removed outright, not set to their defaults."""
    root = json.loads(text)
    root["version"] = 2
    for clip in root["clips"]:
        clip.pop("name", None)
        clip.pop("label", None)
    for track in root["tracks"]:
        track.pop("solo", None)
    return json.dumps(root, indent=2)


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(SOCKET)

    # ---- A. the catalog ---------------------------------------------------
    print("catalog")
    names = mcp.tools()
    # A floor, not the count: phase 2 found 65, and every later phase adds
    # tools (phase 3 made it 68). The EXACT count is the newest phase's
    # script's to assert — it is what tells a stale binary on the port from
    # the build under test — and it moved on when phase 3 landed; the earlier
    # scripts keep a floor, so a later phase's tools never fail an older proof.
    check(len(names) >= 65, f"the catalog holds phase 2's 65 tools or more (got {len(names)})")
    for tool in ["set_clip", "paste_attributes"]:
        check(tool in names, f"{tool} is a tool")

    # ---- B. schema v3 -----------------------------------------------------
    print("\nschema")
    s = Session(mcp, "schema")
    a_id = s.media("A.mov")
    back = s.track_ids()[0]
    s.op("add_track", index=1)
    front = s.track_ids()[1]
    a = s.place(back, a_id, 0)
    t = s.op("add_text_clip", track=front, at=2 * SEC)["new_clips"][0]
    clips = s.clips()
    check(
        all(c["name"] is None and c["label"] is None for c in clips.values())
        and all(not tr["solo"] for tr in s.tracks().values()),
        "a fresh project's clips have no name or label and its tracks no solo",
    )
    s.op("set_clip", clips=[a], patch={"name": "Talk", "label": "blue"})
    s.op("set_track", track=front, solo=True)
    # A tool argument spelled `name` has no keyword path through `MCP.call`
    # (its own first parameter); `call_with` is the public one.
    s.call_with("set_track", {"track": back, "name": "Voice"})
    check(s.tracks()[back]["name"] == "Voice", "set_track {name} sent through call_with reads back")
    clip = s.clip(a)
    check(
        (clip["name"], clip["label"]) == ("Talk", "blue"),
        "set_clip {name, label} reads back through get_project",
    )
    check(s.tracks()[front]["solo"] is True, "set_track {solo: true} reads back")
    check(s.clip(t)["name"] is None, "the other clip is untouched")
    s.save()
    text = project_json(s.path)
    root = json.loads(text)
    check(f'"version": {CURRENT_VERSION}' in text and root["version"] == CURRENT_VERSION,
          f"the saved project.json is version {CURRENT_VERSION}")
    check(
        all(list(c.keys())[-2:] == ["name", "label"] for c in root["clips"]),
        "every clip object ends with name then label",
    )
    check(
        all(list(tr.keys())[-1] == "solo" for tr in root["tracks"]),
        "every track object ends with solo",
    )
    saved = {c["id"]: (c["name"], c["label"]) for c in root["clips"]}
    check(saved[a] == ("Talk", "blue") and saved[t] == (None, None), "the file holds the values")
    check(
        {tr["id"]: tr["solo"] for tr in root["tracks"]} == {back: False, front: True},
        "and the solo flag",
    )

    reopened = Session(mcp, "schema-reopened", open_from=s.path)
    clip = reopened.clip(a)
    check(
        (clip["name"], clip["label"]) == ("Talk", "blue")
        and reopened.tracks()[front]["solo"] is True
        and reopened.project()["version"] == CURRENT_VERSION,
        "a byte copy of the package opens from disk with name, label and solo intact",
    )

    # A version-2 fixture: the same package with the three keys REMOVED.
    fixture = os.path.join(WORK, "schema-v2-source.framejob")
    if os.path.exists(fixture):
        shutil.rmtree(fixture)
    copy_package(s.path, fixture)
    with open(os.path.join(fixture, "project.json"), "w", encoding="utf-8") as handle:
        handle.write(strip_v3(text))
    v2_text = project_json(fixture)
    v2_root = json.loads(v2_text)
    check(
        '"version": 2' in v2_text
        and all("name" not in c and "label" not in c for c in v2_root["clips"])
        and all("solo" not in tr for tr in v2_root["tracks"]),
        "the fixture on disk is version 2 with no name, label or solo key",
    )
    v2 = Session(mcp, "schema-v2", open_from=fixture)
    project = v2.project()
    check(project["version"] == CURRENT_VERSION,
          f"a version-2 file opens and reports version {CURRENT_VERSION}")
    check(
        {c["id"] for c in project["clips"]} == {a, t}
        and [tr["id"] for tr in project["tracks"]] == [back, front],
        "with the same clips and tracks",
    )
    check(
        all(c["name"] is None and c["label"] is None for c in project["clips"]),
        "every clip reads name null and label null",
    )
    check(all(tr["solo"] is False for tr in project["tracks"]), "every track reads solo false")
    v2.save()
    root = json.loads(project_json(v2.path))
    check(root["version"] == CURRENT_VERSION, f"saving it writes version {CURRENT_VERSION}")
    check(
        all(list(c.keys())[-2:] == ["name", "label"] for c in root["clips"])
        and all(list(tr.keys())[-1] == "solo" for tr in root["tracks"]),
        "with the three keys in place",
    )
    check(
        all(c["name"] is None and c["label"] is None for c in root["clips"])
        and all(tr["solo"] is False for tr in root["tracks"]),
        "at their defaults",
    )

    # ---- C. set_clip semantics --------------------------------------------
    print("\nset_clip")
    s = Session(mcp, "identity")
    a_id = s.media("A.mov")
    track = s.track_ids()[0]
    a = s.place(track, a_id, 0)

    s.op("set_clip", clips=[a], patch={"name": "Talk"})
    check(s.clip(a)["name"] == "Talk", "a name is stored")
    s.op("set_clip", clips=[a], patch={"name": None})
    check(s.clip(a)["name"] is None, "null clears it")
    s.op("set_clip", clips=[a], patch={"name": "Talk"})
    s.op("set_clip", clips=[a], patch={"name": ""})
    check(s.clip(a)["name"] is None, "an empty string clears it")
    s.op("set_clip", clips=[a], patch={"name": "Talk"})
    s.op("set_clip", clips=[a], patch={"name": "   "})
    check(s.clip(a)["name"] is None, "a blank string clears it")
    s.op("set_clip", clips=[a], patch={"name": "  Talk, take 2\t"})
    check(s.clip(a)["name"] == "Talk, take 2", "a padded name is stored trimmed")

    before = s.clip(a)
    s.op("set_clip", clips=[a], patch={"label": "blue"})
    after = s.clip(a)
    check(after["label"] == "blue", "a label is stored")
    check(
        canonical(after) == canonical(dict(before, label="blue")),
        "a label-only patch changes nothing else on the clip (whole-clip compare)",
    )

    check(
        s.refuses("set_clip", clips=[a], patch={"name": "Talk, take 2"}),
        "the same name again is a refusal (made no change)",
    )
    check(
        s.refuses("set_clip", clips=[a], patch={"name": "  Talk, take 2  ", "label": "blue"}),
        "and so is the same name padded, with the same label",
    )
    # The three refusals below are the CORE's since deepening D1·4
    # (kpgalligan/framejob#5): `set_clip` forwards the caller's patch and the
    # Swift reader that used to answer `patch.label must be a string` is
    # gone. The whole sentence is asserted rather than a keyword, because a
    # keyword check for "nmae" or "string" passed against both doors and so
    # proved nothing about which one answered — `tools/proof/patch_door_proof.py`
    # §5 is where this door is proved in full.
    message = s.error("set_clip", clips=[a], patch={"nmae": "x"}) or ""
    check(
        'unknown key "nmae" in a clip patch' in message,
        f"an unknown patch key is an error naming it: {message!r}",
    )
    message = s.error("set_clip", clips=[a], patch={"label": 7}) or ""
    check(
        '"label" in a clip patch must be a string or null, not 7' in message,
        f"{{label: 7}} is refused by name: {message!r}",
    )
    check(s.clip(a)["label"] == "blue", "and the label is unchanged afterwards")
    message = s.error("set_clip", clips=[a], patch={"name": ["Talk"]}) or ""
    check(
        '"name" in a clip patch must be a string or null, not ["Talk"]' in message,
        f"{{name: [..]}} is refused by name too: {message!r}",
    )
    check(s.clip(a)["name"] == "Talk, take 2", "and the name is unchanged")

    is_error, message = s.raw("set_clip", {"clips": [a], "name": "Stray"})
    check(is_error, f"a top-level name argument (no patch) is refused: {message[:60]!r}")
    check(s.clip(a)["name"] == "Talk, take 2", "and nothing changed")
    # A stray top-level `name` BESIDE a valid patch. Until
    # kpgalligan/framejob#21 this was measured rather than checked — the
    # server had no unknown-argument guard, so the key was dropped and the
    # identity patch made the call a "made no change" refusal. The argument
    # gate now refuses the stranger by name before the patch is read.
    is_error, message = s.raw(
        "set_clip", {"clips": [a], "patch": {"label": "blue"}, "name": "Stray"}
    )
    check(is_error and "does not take name" in message and s.clip(a)["name"] == "Talk, take 2",
          f"a stray top-level name beside a valid patch is refused by the gate, naming it: "
          f"{message[:70]!r}")

    text_before = s.text()
    s.op("set_clip", clips=[a], patch={"name": "Other"})
    check(s.clip(a)["name"] == "Other", "a rename lands")
    check(s.undo() == "Clip Properties", "undo names the step")
    check(s.clip(a)["name"] == "Talk, take 2", "and restores the previous name")
    check(s.text() == text_before, "the whole project is what it was; one step per set_clip")

    made = s.op("split", clips=[a], at=3 * SEC)["new_clips"]
    check(len(made) == 1, "a split makes one new clip")
    halves = [s.clip(a)] + [s.clip(c) for c in made]
    check(
        all((h["name"], h["label"]) == ("Talk, take 2", "blue") for h in halves),
        "both halves carry the name and the label",
    )

    # ---- D. paste_attributes ----------------------------------------------
    print("\npaste_attributes")
    s = Session(mcp, "attributes")
    av_id = s.media("AV.mov")
    track = s.track_ids()[0]
    src = s.place(track, av_id, 0)
    tgt = s.place(track, av_id, 6 * SEC)
    txt = s.op("add_text_clip", track=track, at=12 * SEC)["new_clips"][0]
    s.op("set_clip", clips=[tgt, txt], patch={"name": "Target", "label": "green"})
    s.op(
        "set_video", clips=[src],
        patch={"x": 40, "y": -30, "scale": 0.8, "rotation": 12, "opacity": 0.7},
    )
    s.op("set_audio", clips=[src], patch={"volume": 0.5, "pan": -0.5})
    clips = s.clips()
    source = clips[src]
    check(
        source["video"] is not None and source["audio"] is not None
        and clips[tgt]["video"] is not None and clips[tgt]["audio"] is not None
        and clips[txt]["text"] is not None and clips[txt]["audio"] is None,
        "the source has video and audio, the media target both, the text target text only",
    )
    check(
        source["video"] != clips[tgt]["video"] and source["audio"] != clips[tgt]["audio"]
        and source["video"] != clips[txt]["video"],
        "the fixture differs from the source in every group that will travel",
    )
    # The Copy payload's shape (edit_paste.rs): the clip verbatim with its
    # track rewritten to a depth from the front, plus the media rows it names.
    media_rows = [m for m in s.project()["media"] if m["id"] == av_id]
    payload = {"clips": [dict(source, track=0)], "media": media_rows}

    before = clips
    text_before = s.text()
    frame_before = s.frame(7 * SEC)
    s.op("paste_attributes", clips=[tgt, txt], payload=payload)
    after = s.clips()
    check(
        canonical(after[tgt]["video"]) == canonical(source["video"]),
        "the media target's video equals the source's",
    )
    check(
        canonical(after[tgt]["audio"]) == canonical(source["audio"]),
        "the media target's audio equals the source's",
    )
    check(
        canonical(after[txt]["video"]) == canonical(source["video"]),
        "the text target's video equals the source's",
    )
    check(
        canonical(after[txt]["text"]) == canonical(before[txt]["text"]),
        "the text target's text is byte-identical to before",
    )
    check(after[txt]["audio"] is None and after[txt]["shape"] is None, "and it gained no group")
    for target, label in [(tgt, "media target"), (txt, "text target")]:
        kept = [
            k for k in OUTSIDE_GROUPS
            if canonical(after[target][k]) == canonical(before[target][k])
        ]
        check(
            kept == OUTSIDE_GROUPS,
            f"the {label}'s {len(OUTSIDE_GROUPS)} keys outside the groups are byte-identical",
        )
    check(canonical(after[src]) == canonical(before[src]), "the source itself is untouched")
    frame_after = s.frame(7 * SEC)
    check(frame_after != frame_before, "the frame on the media target changed with its transform")

    check(
        s.refuses("paste_attributes", clips=[tgt, txt], payload=payload),
        "pasting the same attributes again is a refusal (made no change)",
    )
    message = s.error("paste_attributes", clips=[txt], payload=payload, groups=["audio"]) or ""
    check(
        f"clip {txt} has no audio properties" in message,
        f"[audio] onto the text clip is an error naming the clip: {message!r}",
    )
    message = s.error("paste_attributes", clips=[tgt], payload=payload, groups=["shape"]) or ""
    check(
        "payload clip has no shape properties" in message,
        f"[shape] from a media source is an error naming the payload: {message!r}",
    )
    message = s.error("paste_attributes", clips=[tgt], payload=payload, groups=[]) or ""
    check(
        message.startswith("paste_attributes:") and "groups is empty" in message,
        f"[] is refused by the tool: {message!r}",
    )
    check(s.text() != text_before, "(the paste is still in place after the refused calls)")
    check(s.undo() == "Paste Attributes", "undo names the step")
    check(s.text() == text_before, "and restores the whole project JSON; the paste was one step")
    check(s.frame(7 * SEC) == frame_before, "the frame after undo is byte-identical to before")

    # ---- E. solo ----------------------------------------------------------
    print("\nsolo")
    s = Session(mcp, "solo")
    tone_a = s.media("toneA.m4a")
    tone_b = s.media("toneB.m4a")
    back = s.track_ids()[0]
    s.op("add_track", index=1)
    front = s.track_ids()[1]
    ca = s.place(back, tone_a, 0)
    cb = s.place(front, tone_b, 0)
    clips = s.clips()
    check(
        all(
            c["audio"]["volume"] == 1 and c["audio"]["fade_in"] == 0
            and c["audio"]["fade_out"] == 0 and c["audio"]["duck"] is None
            and not c["audio"]["muted"]
            for c in clips.values()
        )
        and clips[ca]["duration"] == clips[cb]["duration"],
        "two tones of one length, unity gain, no fades, no ducks",
    )
    base = s.text()

    e0, r0 = s.export("E0")
    e0b, r0b = s.export("E0b")
    check(r0["duration"] == r0b["duration"], "two plain exports report one duration")

    s.op("set_track", track=back, solo=True)
    check(s.tracks()[back]["solo"] is True and s.tracks()[front]["solo"] is False, "back soloed")
    e1, r1 = s.export("E1")
    check(s.undo() == "Track Properties" and s.text() == base, "undo of the solo is one step")

    s.op("set_track", track=front, muted=True)
    check(s.tracks()[front]["muted"] is True, "front muted")
    e2, r2 = s.export("E2")
    check(s.undo() == "Track Properties" and s.text() == base, "undo of the mute is one step")

    s.op("set_track", track=back, solo=True, muted=True)
    tr = s.tracks()[back]
    check(tr["solo"] is True and tr["muted"] is True, "back soloed AND muted, in one op")
    e3, r3 = s.export("E3")
    check(s.undo() == "Track Properties" and s.text() == base, "undo of the pair is one step")

    s.op("set_track", track=back, muted=True)
    s.op("set_track", track=front, muted=True)
    em, rm = s.export("EM")
    s.undo()
    s.undo()
    check(s.text() == base, "two undos return the base")

    only_a = Session(mcp, "solo-a")
    only_a.place(only_a.track_ids()[0], only_a.media("toneA.m4a"), 0)
    ea, ra = only_a.export("EA")
    check(
        {r["duration"] for r in [r0, r0b, r1, r2, r3, rm, ra]} == {r0["duration"]},
        "every export reports the same duration",
    )

    p0, p0b, p1, p2, p3, pm, pa = (pcm(p) for p in [e0, e0b, e1, e2, e3, em, ea])
    check(len(p0) > 0 and len(p0) == len(p1) == len(p2) == len(p3) == len(pm) == len(pa), (
        f"every decode is the same length ({len(p0) // 4} frames)"
    ))
    w = wobble(p0, p0b)
    check(w == (0, 0), f"two exports of one project are byte-identical ({describe(p0, p0b)})")
    tolerance = 0 if w is None else w[0]
    if tolerance:
        print(f"  note comparisons below tolerate the measured wobble of {tolerance} LSB")

    check(
        same(p1, p2, tolerance),
        f"solo back == mute front, sample for sample ({describe(p1, p2)})",
    )
    check(not same(p1, p0, tolerance), f"solo back != plain ({describe(p1, p0)})")
    check(
        same(p1, pa, tolerance),
        f"solo back == a project holding only toneA ({describe(p1, pa)})",
    )
    peak3 = max(abs(v) for v in samples(p3))
    check(
        peak3 <= tolerance or same(p3, pm, tolerance),
        f"solo + mute on one track is silent — mute wins (peak {peak3}; vs both muted: "
        f"{describe(p3, pm)})",
    )
    check(
        max(abs(v) for v in samples(p0)) > 1000 and max(abs(v) for v in samples(p1)) > 1000,
        "(and the tones are audible, so silence is not the trivial answer)",
    )

    a_id = s.media("A.mov")
    s.op("add_track", index=2)
    picture = s.track_ids()[2]
    s.place(picture, a_id, 0)
    frame_before = s.frame(1 * SEC)
    s.op("set_track", track=back, solo=True)
    check(s.tracks()[back]["solo"] is True, "the tone track is soloed under a picture track")
    check(s.frame(1 * SEC) == frame_before, "and the frame is byte-identical: solo is audio only")
    check(s.undo() == "Track Properties", "undo of that solo is one step")

    summary()


def summary(aborted=None):
    """The last line, and the exit status. An op that unexpectedly refused or
    errored (a `ToolError` no check was waiting for) aborts the run: it is
    reported as the failure it is, with the checks that had passed by then,
    rather than as a bare traceback with no count."""
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed{tail}")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
    if failures or aborted:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, RuntimeError, OSError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
