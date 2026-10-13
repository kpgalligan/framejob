#!/usr/bin/env python3
"""`archive/reelcut-remaining.md` §2a — the cache completion marker, measured
against the built binary over MCP.

§2a recorded `ProjectDocument.generateCaches`'s doc — "a cache already on
disk is not rebuilt" — as FALSE: every call re-decoded every media's
filmstrip and re-read its audio, and the measurement was a filmstrip frame's
modification date moving on a second pass. The fix is a completion marker
keyed to the source file's identity (`MediaImporter.CacheStamp`,
`MediaCacheFiles.swift`): `thumbs/<id>/complete.json` inside the strip's own
directory and `peaks/<id>.complete.json` beside the `.bin`, each written by a
finished pass LAST and holding the file's byte size and modification second
plus the record fields and constants that size the caches — and NOT the
path, so a moved package, a consolidated copy and a byte copy on another
disk keep every filmstrip. A pass skips when the marker decodes equal to the
stamp of the file the media points at now, and rebuilds otherwise: a
relinked, changed, partial or unmarked cache. This script is that sentence,
claim by claim, on a saved package, because the untitled document's
temporary cache directory is reachable from no tool.

**The instrument is `os.stat`'s inode and `st_mtime_ns`**, not the marker's
say-so. ImageIO stages every thumbnail to `.<n>.jpg-<random>` and renames it
into place, and the peaks file is written `.atomic`, so a rebuilt file is a
NEW inode; "nothing moved" is therefore a claim about four inodes and four
nanosecond mtimes across every sample of a 3 s window, taken against a
baseline read BEFORE the trigger — a rebuild at any moment from the trigger
to the end of the window is caught. **The window is bounded by a positive
control in the same section, and the bound is a NUMBER**: the same trigger
with the marker deleted moves the inode, `wait_until` answers the LATENCY
from the trigger to that move, and the control asserts it is at most the
3 s the negative claims sample, printing it. The poll gives up at 10 s,
which is the cap and not the bound — a build whose rebuild landed at 4–9 s
would pass the cap and be invisible to the window, and until the latency
was measured that is exactly what "bounded" did not rule out. On this
machine the latency is a fraction of a second; a run that reports one over
3 s has not shown the window is wide enough and should be repeated on a
quieter machine rather than read as a marker failure.

**The trigger is an import of a fresh copy of `C.mov`.** `import_media` of a
path already in the list is an identity edit and is refused before the cache
line is reached, so the whole-media loop is re-run by adding a DIFFERENT
file — each trigger is a new 8 KB copy under a new name — and waited for by
that new media's own marker. The other media's passes are separate detached
tasks, which is why the negative claims sample for 3 s after it rather than
reading once. One task runs BOTH halves of one media, thumbnails first and
peaks second, and that order is what decides which negative claims may be a
single read: "thumbs not rebuilt" read after the peaks marker landed is
sound, because thumbnails had finished (or skipped) before peaks began;
"peaks not rebuilt" read at the moment the thumbs marker was rewritten is
NOT, because the peaks phase had not yet run — so 1c samples it over the
window like the other negative claims.

Fixtures are COPIED into `work/` under new names before anything touches
them: `os.utime` is one of the claims, and a shared fixture's mtime is not
this script's to move. Earlier pids' packages, package copies and media
copies under `work/` are swept at start, as every other MCP proof's Session
sweeps its own name (`README.md`'s rule); before the sweep existed three
runs had left thirty-one entries behind.

Every sub-section runs through `section()`, so a raise in one — a marker
that reads as `None` where a number was expected, say — scores ONE failure
and the next sub-section still runs (phase 7's idiom); before that a `None`
marker at 1e aborted every check after it. 1e also guards that marker by
name, because its four claims are about the number inside it and are not
made against nothing. A missing parity log is a scored failure, not a note.

Section 0 reads the parity log and the catalog. Section 1 is the marker,
in the order the remaining document argues it:

  * both markers land after an import (`AV.mov`: video AND audio, so both
    halves exist), are JSON whose keys include `size`, `modified` and
    `duration`, carry NO key or value naming a path, agree with the copy's
    own stat, and are byte-identical to each other (sorted keys, one stamp);
  * a second whole-media pass (importing `A.mov`, video-only) moves none of
    the four — the check the deleted-head-check mutant fails, and exactly
    the mtime §2a measured moving;
  * the positive control: the thumbs marker deleted, the same trigger
    rebuilds `0.jpg` (new inode) at a measured latency of at most 3 s from
    the trigger, rewrites a byte-identical marker — the pass's LAST write,
    so the thumbs pass has finished — and then, sampled over 3 s from that
    point, the peaks half stays unmoved: the two halves are independent;
  * the `.bin` deleted with its marker KEPT is rebuilt (the peaks head check
    asks for both) and its marker rewritten, byte-identical, because the
    same file was measured;
  * `os.utime` of `A`'s copy by +2 s rebuilds `A`'s strip and moves the
    marker's `modified` by exactly 2 — the first check the forced-`modified`
    mutant fails;
  * `relink_media` to a byte copy of `A` at another path with a LATER mtime
    rebuilds (`modified` differs, size does not), and relinking back rebuilds
    again — the second check that mutant fails; then `A` → `B` rebuilds with
    DIFFERENT `0.jpg` bytes (testsrc against testsrc2) and a different marker,
    and `B` → `A` brings `A`'s bytes back;
  * a byte copy of the whole package (`shutil.copytree` over `shutil.copy2`,
    times preserved — asserted for every cache file of BOTH copies) opened
    under a new path is not rebuilt in 3 s, and a second copy with its `AV`
    thumbs marker deleted IS rebuilt at a measured latency of at most 3 s
    from the open — the positive control for the moved-package claim;
  * `consolidate_media` copies every file into `<package>/media/`, and the
    marker must then MATCH the consolidated file: either untouched because
    `copyItem` preserved the modification date (no rebuild), or rewritten
    because it did not. Both are correct and only a stale marker is wrong;
    which one happened is asserted and printed;
  * (1i) `relink_media` of AV to a copy of `A` — video-only — RE-PROBES
    it (spec §11 #63): the record says `has_audio` false with A's duration,
    and `detect_silence` over a clip on AV, which answered from the peaks
    before the relink, now measures no clip (`clips: []`) and has nothing
    pending, rather than measuring the old file's audio; relinked back, the
    `.bin` is byte-identical, both markers agree, and nothing is pending.
    Since issue batch B29 (#180.1) a pass for a media with no audio
    withdraws what the old file left, and 1i watches it again: AV's speech
    `.bin` is there before the relink, and after it AV's peaks `.bin` and
    marker and its speech `.bin` and marker are each GONE inside the 10 s
    cap and all four stay ABSENT across a 3 s sample. The timeline's
    notification of the withdrawal is `remaining_probe.py`'s 5e, which
    counts the post for a file replaced in place.

**One thing the first run of 1g taught, kept as a check**: the passes
write the cache straight to disk but `project.json` is written only by a
SAVE, so a copy of the package taken before one opens with `new_project`'s
blank project — no media, nothing to rebuild — and "nothing moved" passed
against a build that rebuilds everything. 1g now saves first, asserts the
saved and the copied `project.json` list the media, and takes its baseline
after the save (which rewrites every cache file into the new package; the
markers surviving that swap byte-identical is a claim of its own). The copy
is taken once two consecutive samples of the six cache files' stats agree —
the harness's settle rule applied to files — and not after a guessed pause:
`save_project` returns only when NSDocument's completion has fired, so
nothing should be moving, and asking the package is how that is known
rather than assumed.

**The gate**, each mutant a COPY of the tree with the app built in the copy
(`xcodegen generate` + the Makefile's `xcodebuild` line over HEAD's
`libframejob_core.a`) and the copy's binary relaunched on its own port. The
first four were scored against the **69** checks this file had before 1i.
The head check deleted from `thumbnails` scores **65/69**: 1b's "none of
AV's four files moved" (`0.jpg`'s inode moved on the first sample), 1d's
"the thumbs half was NOT rebuilt", 1g's "none of the copy's 6 cache files
moved" and 1h's "nothing was rebuilt" — every negative claim and nothing
else. `CacheStamp.modified` forced to 0 scores **59/69**: both markers'
`modified` (0), the utime row's own precondition and its two rebuild claims,
the four `A` → touched copy → `A` relink claims (every one of which differs
only by mtime), and the consolidated file's match. A 4 s `Task.sleep` after
`thumbnails`' head check — a rebuild that starts late — scores **67/69**,
failing exactly the two latency bounds (1c's at 4.19 s and 1g's at 4.32 s)
while every 10 s cap still passes, which is the gap the bounds exist to
close. The ledger removed and the timeline's hit clearing removed are
`remaining_probe.py`'s sections 3 and 4 (**107/108** and **105/108** there,
against the 108 it then had; its docstring names the rows).

Two more, against this file's **79** checks with 1i in it, both run after
`peaks` learned to withdraw the `.bin`. The head check deleted from `peaks`
scores **75/79**: 1b's "none of AV's four files moved" — caught through
`peaks.bin`'s inode, since every pass now clears and rebuilds it — 1c's
sampled "the peaks half was NOT rebuilt", 1g's "none of the copy's 6 cache
files moved" (`AV peaks.bin` gone mid-rebuild) and 1h's "nothing was
rebuilt"; 1i itself PASSES against it, because a build that always rebuilds
also always withdraws. Measured beside it earlier, the single read 1c used
to take at the thumbs marker's rewrite ALSO failed against that mutant on
this machine — three seconds of audio is rebuilt inside the poll's step —
so the sample corrects the claim's SHAPE rather than a row that was
measurably missing: a read taken before the peaks phase of the same task
has run is a race won here and not everywhere, and the window is what
makes it a claim on any machine. And `clearPeaks` back to marker-only —
the `.bin` left in place, nothing posted — scores **76/79**: 1i's "AV's
`.bin` is GONE inside the 10 s cap", "the `.bin` and its marker stayed
ABSENT" (the old inode present at the first sample) and "`detect_silence`
now reports AV as PENDING", which is the old file's peaks being served as
the new file's answer, the thing 1i exists to rule out. The same mutant
takes `remaining_probe.py`'s 5e (**139/141** there). No survivors then.

Since spec §11 #63 (issue batch B16) a relink re-probes, and 1i's three
rows above were rewritten; the scores in the last two paragraphs are
historical, against the 79 checks this file had. Issue batch B29 (#180.1)
gave 1i four withdrawal rows back, and the file has **80** checks: 80/80
on the tree's app, and the two no-audio arms put back to their HEAD lines
(`guard media.hasAudio, media.duration > 0 else { return true }` /
`… else { return }`, the app built in a `tree_copy` copy) score **77/80**,
exit 1 — the peaks pair GONE, the speech pair GONE, and all four ABSENT
across the window (`peaks.bin` present at the first sample). `clearPeaks`
back to marker-only was not run against the 80 (tools/proof/README.md says
the same).

Nothing here decodes a picture and no `ffmpeg` runs at proof time. It opens
THREE documents in the instance (one `new_project`, two `open_project`);
relaunch between full runs, as every proof here asks.

    python3 tools/proof/remaining_proof.py <dir>/agent.sock [log path]
"""

import json
import os
import re
import shutil
import sys
import time

from mcp import MCP, ToolError, target, log_beside

SOCKET = target(sys.argv)
LOG = sys.argv[2] if len(sys.argv) > 2 else log_beside(SOCKET)

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
MEDIA = os.path.join(HERE, "media")
FIXTURES = {"AV": "AV.mov", "A": "A.mov", "B": "B.mov", "C": "C.mov"}

# The window a NEGATIVE claim samples, and the cap a POSITIVE one polls to.
# The control in 1c is what makes the first a claim: the same trigger, with
# the marker gone, moves the inode at a latency the control MEASURES and
# asserts to be inside the window. The cap is only how long the poll is
# willing to wait before calling the rebuild absent.
QUIET_SECONDS = 3.0
REBUILD_SECONDS = 10.0
MARKER_SECONDS = 60.0

# The keys a marker must carry (a subset — the constants ride too) and the
# substring no key may contain.
STAMP_KEYS = {"size", "modified", "duration"}

failures = []
checks = 0


def check(ok_, what):
    global checks
    checks += 1
    if ok_:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def section(name, run, *args):
    """One section, isolated: a section that raises scores ONE failure and
    the run goes on (phase 7's idiom). A crash is a worse detection than a
    failure. Section 1's sub-sections run through this too, each on its
    own, so a raise in 1e no longer takes 1f–1h down with it."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.strip().split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


# ---- files ---------------------------------------------------------------


def stat_of(path):
    """(inode, st_mtime_ns) of a file, or None when it is not there — which
    during a rebuild it briefly is not."""
    try:
        st = os.stat(path)
    except FileNotFoundError:
        return None
    return (st.st_ino, st.st_mtime_ns)


def read_json(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def peaks_source(path):
    marker = read_json(path)
    if not isinstance(marker, dict) or marker.get("version") != 1:
        return None
    return marker.get("source")


def read_bytes(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        return None


def wait_until(predicate, seconds, since=None, step=0.05):
    """The seconds from `since` (default: this call) to the first sample at
    which `predicate()` held, or None when it had not by `seconds`. A number
    and not a bool, because a control is worth exactly the latency it
    measured: a poll that only says "yes, inside the cap" bounds nothing
    tighter than the cap. `since` lets a caller date the latency from the
    TRIGGER rather than from the poll, which is the honest origin when the
    trigger itself blocked for a while. An immediate hit is 0.0, which is
    falsy — callers that only want the yes test `is not None`."""
    start = time.monotonic() if since is None else since
    deadline = time.monotonic() + seconds
    while True:
        if predicate():
            return time.monotonic() - start
        if time.monotonic() >= deadline:
            return None
        time.sleep(step)


def moved(path, before):
    """The file is there and is not the inode it was — a rebuild, which
    ImageIO's rename and the peaks file's `.atomic` write both mint."""
    now = stat_of(path)
    return now is not None and before is not None and now[0] != before[0]


def sample_unmoved(paths, baseline, seconds):
    """Every 100 ms for `seconds`, compare each path's (inode, mtime_ns) to
    `baseline`. Returns (all unmoved, samples taken, first offender)."""
    samples = 0
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        samples += 1
        for name, path in paths.items():
            now = stat_of(path)
            if now != baseline[name]:
                return False, samples, f"{name}: {baseline[name]} → {now}"
        time.sleep(0.1)
    return True, samples, ""


def settle_stats(paths, seconds=REBUILD_SECONDS):
    """True once two consecutive samples, 100 ms apart, of every path's
    (inode, mtime_ns) agree and none is missing — the harness's settle rule
    applied to files: ask the package whether it is quiet rather than guess
    how long the last write takes."""
    previous = None
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        now = {name: stat_of(path) for name, path in paths.items()}
        if now == previous and all(v is not None for v in now.values()):
            return True
        previous = now
        time.sleep(0.1)
    return False


def mtime_second(path):
    return int(round(os.stat(path).st_mtime))


def sweep_earlier_runs():
    """Earlier pids' packages, package copies and media copies under `work/`
    go, as every other MCP proof's Session sweeps its own name (the README's
    rule): a `project` path is matched against every open document and no
    tool closes one, so a package is `<name>-<pid>.framejob` and never a
    fixed name — and without a sweep each run leaves its three packages
    behind for ever (measured: thirty-one entries from three runs). The
    media copies go with them, because a copy of `A.mov` at a pid-named
    path means nothing to any package but that pid's."""
    mine = str(os.getpid())
    patterns = (
        r"remaining-cache-(\d+)(-copy\d)?\.framejob",
        r"remaining-cache-(\d+)-C\d+\.mov",
        r"remaining-(\d+)-[A-Za-z-]+\.mov",
    )
    for stale in sorted(os.listdir(WORK)):
        for pattern in patterns:
            match = re.fullmatch(pattern, stale)
            if match and match.group(1) != mine:
                path = os.path.join(WORK, stale)
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
                break


# ---- the package -----------------------------------------------------------


class Session:
    """One saved package and the files under its `cache/`. `<name>-<pid>`,
    never a fixed name: a `project` path is matched against every open
    document and no tool closes one. Earlier pids' packages are
    `sweep_earlier_runs`'s, at start."""

    def __init__(self, mcp, name):
        self.mcp = mcp
        self.name = name
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.framejob")
        if os.path.exists(self.path):
            shutil.rmtree(self.path)
        mcp.call("new_project", path=self.path)
        self.triggers = 0

    def op(self, tool, **kwargs):
        return self.mcp.call_with(tool, dict(project=self.path, **kwargs))

    def project(self):
        return self.op("get_project")["project"]

    def media_rows(self):
        return {m["id"]: m for m in self.project()["media"]}

    # The four files of one media, in this package or in a copy of it.
    def thumb0(self, media, package=None):
        return os.path.join(package or self.path, "cache", "thumbs", str(media), "0.jpg")

    def thumbs_marker(self, media, package=None):
        return os.path.join(
            package or self.path, "cache", "thumbs", str(media), "complete.json")

    def peaks_bin(self, media, package=None):
        return os.path.join(package or self.path, "cache", "peaks", f"{media}.bin")

    def peaks_marker(self, media, package=None):
        return os.path.join(package or self.path, "cache", "peaks", f"{media}.complete.json")

    def speech_bin(self, media, package=None):
        return os.path.join(package or self.path, "cache", "speech", f"{media}.bin")

    def speech_marker(self, media, package=None):
        return os.path.join(package or self.path, "cache", "speech", f"{media}.complete.json")

    def four(self, media, package=None):
        return {
            "0.jpg": self.thumb0(media, package),
            "peaks.bin": self.peaks_bin(media, package),
            "thumbs marker": self.thumbs_marker(media, package),
            "peaks marker": self.peaks_marker(media, package),
        }

    def peaks_pair(self, media, package=None):
        return {k: v for k, v in self.four(media, package).items() if k.startswith("peaks")}

    def stats(self, media, package=None):
        return {name: stat_of(path) for name, path in self.four(media, package).items()}

    def import_copy(self, copy):
        return self.op("import_media", path=copy)

    def trigger(self):
        """Re-runs the whole-media loop by importing a fresh copy of `C.mov`
        under a new name, and waits for THAT media's marker so the loop is
        known to have run. Returns the monotonic time just BEFORE the import,
        so a control can date a rebuild's latency from the trigger itself
        and not from the moment this wait let go."""
        self.triggers += 1
        copy = os.path.join(WORK, f"{self.name}-{os.getpid()}-C{self.triggers}.mov")
        shutil.copy2(os.path.join(MEDIA, FIXTURES["C"]), copy)
        started = time.monotonic()
        media = self.import_copy(copy)["media"]
        landed = wait_until(
            lambda: read_json(self.thumbs_marker(media)) is not None, REBUILD_SECONDS)
        check(landed is not None,
              f"trigger {self.triggers}: the C copy's own marker landed (media {media}), so "
              "the whole-media loop ran")
        return started


def fixture_copy(name, tag):
    """A copy of one fixture under `work/`, times preserved, so nothing here
    ever touches a shared fixture."""
    copy = os.path.join(WORK, f"remaining-{os.getpid()}-{tag}.mov")
    shutil.copy2(os.path.join(MEDIA, FIXTURES[name]), copy)
    return copy


class State:
    """What section 1's sub-sections hand each other: the session, the two
    media ids, the fixture copies, AV's marker bytes and baseline, A's first
    `0.jpg`. Each sub-section is its own `section()` so a raise in one is
    one failure, and this is how the next one still has what it needs."""

    session = None
    av = a = None
    av_copy = a_copy = b_copy = None
    marker_bytes = None
    baseline = None
    a_jpg = None


# ---- section 0 -------------------------------------------------------------


def catalog_part(mcp):
    if os.path.exists(LOG):
        with open(LOG, errors="replace") as handle:
            complaints = [line for line in handle if "Frame Job: " in line]
        check(not complaints,
              f"the parity log at {LOG} has no `Frame Job: ` line — the startup check "
              f"is silent ({len(complaints)} found)")
    else:
        # Scored, not printed: a run against an instance whose log nobody
        # can read has not shown the startup check is silent, and every
        # other claim here is read against a binary that check vouches for.
        check(False, f"the parity log at {LOG} exists — without it the startup check's "
                     "silence cannot be read (launch with `> <dir>/framejob.log`, or "
                     "pass the log path as the second argument)")
    tools = set(mcp.tools())
    needed = {"new_project", "open_project", "import_media", "relink_media",
              "consolidate_media", "get_project", "save_project", "add_clip", "detect_silence"}
    check(needed <= tools, f"the nine tools this script drives are in the catalog "
                           f"(missing: {sorted(needed - tools)})")


# ---- section 1 -------------------------------------------------------------


def part_1a(mcp, s):
    s.session = Session(mcp, "remaining-cache")
    s.av_copy = fixture_copy("AV", "AV")
    s.a_copy = fixture_copy("A", "A")
    s.b_copy = fixture_copy("B", "B")
    session = s.session
    imported = session.import_copy(s.av_copy)
    av = s.av = imported["media"]
    check(imported["has_video"] and imported["has_audio"],
          "AV's copy imported with both a video and an audio track")
    landed = wait_until(
        lambda: read_json(session.thumbs_marker(av)) is not None
        and read_json(session.peaks_marker(av)) is not None, MARKER_SECONDS)
    check(landed is not None, f"both of AV's markers landed within {MARKER_SECONDS:.0f} s")
    check(os.path.exists(session.thumb0(av)), "AV's `thumbs/<id>/0.jpg` is there")
    check(os.path.exists(session.peaks_bin(av)), "AV's `peaks/<id>.bin` is there")
    for label, path in (("thumbs", session.thumbs_marker(av)),
                        ("peaks", session.peaks_marker(av))):
        outer = read_json(path)
        marker = outer if label == "thumbs" else peaks_source(path)
        check(isinstance(marker, dict), f"the {label} marker is a JSON object")
        if not isinstance(marker, dict):
            continue
        check(STAMP_KEYS <= set(marker),
              f"the {label} marker's keys include size, modified and duration "
              f"(has {sorted(marker)})")
        check(not any("path" in key.lower() for key in marker),
              f"the {label} marker has no key naming a path")
        check(not any(isinstance(v, str) for v in marker.values()),
              f"the {label} marker holds no string at all — nothing that could be a path")
        check(marker.get("size") == os.stat(s.av_copy).st_size,
              f"the {label} marker's `size` is the copy's byte size ({marker.get('size')})")
        check(marker.get("modified") == mtime_second(s.av_copy),
              f"the {label} marker's `modified` is the copy's modification second "
              f"({marker.get('modified')})")
        check(marker.get("duration") == imported["duration"],
              f"the {label} marker's `duration` is the record's ({marker.get('duration')})")
    check(peaks_source(session.peaks_marker(av)) == read_json(session.thumbs_marker(av)),
          "peaks version 1 wraps the unchanged thumbnail source stamp")
    s.marker_bytes = read_bytes(session.thumbs_marker(av))
    s.peaks_marker_bytes = read_bytes(session.peaks_marker(av))
    s.baseline = session.stats(av)
    check(all(v is not None for v in s.baseline.values()),
          "all four of AV's files stat (the baseline for every 'unmoved' claim)")


def part_1b(s):
    session, av = s.session, s.av
    imported_a = session.import_copy(s.a_copy)
    a = s.a = imported_a["media"]
    check(not imported_a["has_audio"], "A's copy is video-only (no peaks half exists for it)")
    check(wait_until(lambda: read_json(session.thumbs_marker(a)) is not None,
                     MARKER_SECONDS) is not None,
          "A's thumbs marker landed — the loop that re-ran over AV has run")
    unmoved, samples, offender = sample_unmoved(session.four(av), s.baseline, QUIET_SECONDS)
    check(unmoved, f"across {samples} samples over {QUIET_SECONDS:.0f} s, none of AV's four "
                   f"files moved: inode and mtime_ns unchanged {offender}")
    check(not os.path.exists(session.peaks_bin(a)) and not os.path.exists(session.peaks_marker(a)),
          "a video-only media gets neither a `.bin` nor a peaks marker — the silent guard "
          "writes no marker")


def part_1c(s):
    session, av = s.session, s.av
    os.remove(session.thumbs_marker(av))
    before = session.stats(av)
    triggered = session.trigger()
    latency = wait_until(lambda: moved(session.thumb0(av), before["0.jpg"]),
                         REBUILD_SECONDS, since=triggered)
    check(latency is not None,
          f"with its thumbs marker deleted, AV's `0.jpg` was rebuilt (new inode) inside the "
          f"{REBUILD_SECONDS:.0f} s cap")
    check(latency is not None and latency <= QUIET_SECONDS,
          f"and the rebuild's latency from the trigger, "
          f"{'—' if latency is None else f'{latency:.2f} s'}, is inside the "
          f"{QUIET_SECONDS:.0f} s window 1b sampled — the control BOUNDS the window, and the "
          f"cap above is only how long the poll waits")
    finished = wait_until(lambda: read_bytes(session.thumbs_marker(av)) == s.marker_bytes,
                          REBUILD_SECONDS)
    check(finished is not None,
          "and the thumbs marker was rewritten byte-identical (same file, same stamp) — the "
          "pass's LAST write, so the thumbs pass has finished")
    # The same task runs `peaks` NEXT, so a read taken here could precede
    # the phase it is about (measured: a single read passed against a
    # build with the peaks head check deleted). Sample the window instead.
    unmoved, samples, offender = sample_unmoved(
        session.peaks_pair(av), before, QUIET_SECONDS)
    check(unmoved,
          f"across {samples} samples over {QUIET_SECONDS:.0f} s after the thumbs pass "
          f"finished, the peaks half was NOT rebuilt — the two markers are independent "
          f"{offender}")
    s.baseline = session.stats(av)


def part_1d(s):
    session, av = s.session, s.av
    bin_bytes = read_bytes(session.peaks_bin(av))
    os.remove(session.peaks_bin(av))
    session.trigger()
    check(wait_until(lambda: stat_of(session.peaks_bin(av)) is not None,
                     REBUILD_SECONDS) is not None,
          "the `.bin` is back — the peaks head check asks for the marker AND the file")
    check(wait_until(
        lambda: stat_of(session.peaks_marker(av)) is not None
        and stat_of(session.peaks_marker(av)) != s.baseline["peaks marker"],
        REBUILD_SECONDS) is not None,
        "and the peaks marker was rewritten (new inode or mtime)")
    check(read_bytes(session.peaks_marker(av)) == s.peaks_marker_bytes,
          "rewritten byte-identical: the same file was measured")
    check(read_bytes(session.peaks_bin(av)) == bin_bytes,
          "the rebuilt `.bin` is byte-identical to the first — same samples, same buckets")
    # A single read is sound HERE, unlike 1c's: the thumbs phase runs
    # BEFORE peaks in the same task, and the peaks marker's rewrite above
    # is what was waited for.
    check(stat_of(session.thumb0(av)) == s.baseline["0.jpg"]
          and stat_of(session.thumbs_marker(av)) == s.baseline["thumbs marker"],
          "the thumbs half was NOT rebuilt (thumbnails ran first in the task whose peaks "
          "marker just landed)")


def part_1e(s):
    session, a = s.session, s.a
    a_marker = read_json(session.thumbs_marker(a))
    s.a_jpg = read_bytes(session.thumb0(a))
    a_before = session.stats(a)
    readable = isinstance(a_marker, dict) and isinstance(a_marker.get("modified"), int)
    check(readable, "A's thumbs marker reads as JSON with an integer `modified` — the number "
                    f"the four claims below are about (read {a_marker!r})")
    if not readable:
        # Nothing to move by 2 and nothing to compare against; the row's
        # claims are not made against nothing. 1f goes on.
        return
    st = os.stat(s.a_copy)
    os.utime(s.a_copy, ns=(st.st_atime_ns, st.st_mtime_ns + 2_000_000_000))
    check(mtime_second(s.a_copy) == a_marker["modified"] + 2,
          "the copy's modification second moved by exactly 2")
    session.trigger()
    check(wait_until(lambda: moved(session.thumb0(a), a_before["0.jpg"]),
                     REBUILD_SECONDS) is not None,
          "A's `0.jpg` was rebuilt (new inode) after its source's mtime moved")
    check(wait_until(
        lambda: (read_json(session.thumbs_marker(a)) or {}).get("modified")
        == a_marker["modified"] + 2, REBUILD_SECONDS) is not None,
        "A's marker's `modified` moved by exactly 2")
    a_marker_2 = read_json(session.thumbs_marker(a)) or {}
    check({k: v for k, v in a_marker_2.items() if k != "modified"}
          == {k: v for k, v in a_marker.items() if k != "modified"},
          "and every other key of A's marker is what it was")
    check(read_bytes(session.thumb0(a)) == s.a_jpg,
          "the rebuilt `0.jpg` is byte-identical to the first — the same film, decoded again")


def part_1f(s):
    session, a, a_copy, a_jpg = s.session, s.a, s.a_copy, s.a_jpg
    a_touched = fixture_copy("A", "A-touched")
    st = os.stat(a_touched)
    os.utime(a_touched, ns=(st.st_atime_ns, os.stat(a_copy).st_mtime_ns + 5_000_000_000))
    check(os.stat(a_touched).st_size == os.stat(a_copy).st_size
          and mtime_second(a_touched) == mtime_second(a_copy) + 5,
          "the touched copy is the same size as A's copy and 5 s later")
    before = session.stats(a)
    session.op("relink_media", media=a, path=a_touched)
    check(wait_until(lambda: moved(session.thumb0(a), before["0.jpg"]),
                     REBUILD_SECONDS) is not None,
          "relinked to the touched copy, A's `0.jpg` was rebuilt — `modified` alone differs")
    check(wait_until(
        lambda: (read_json(session.thumbs_marker(a)) or {}).get("modified")
        == mtime_second(a_touched), REBUILD_SECONDS) is not None,
        "and the marker's `modified` is the touched copy's second")
    before = session.stats(a)
    session.op("relink_media", media=a, path=a_copy)
    check(wait_until(lambda: moved(session.thumb0(a), before["0.jpg"]),
                     REBUILD_SECONDS) is not None,
          "relinked back to A's copy, rebuilt again")
    check(wait_until(
        lambda: (read_json(session.thumbs_marker(a)) or {}).get("modified")
        == mtime_second(a_copy), REBUILD_SECONDS) is not None,
        "and the marker's `modified` is A's copy's second again")
    check(read_bytes(session.thumb0(a)) == a_jpg, "its `0.jpg` is A's bytes")
    a_marker_bytes = read_bytes(session.thumbs_marker(a))
    before = session.stats(a)
    session.op("relink_media", media=a, path=s.b_copy)
    check(wait_until(
        lambda: read_bytes(session.thumbs_marker(a)) not in (None, a_marker_bytes)
        and moved(session.thumb0(a), before["0.jpg"]), REBUILD_SECONDS) is not None,
        "relinked to B's copy, A's strip was rebuilt and its marker differs")
    b_jpg = read_bytes(session.thumb0(a))
    check(b_jpg is not None and b_jpg != a_jpg,
          "and `0.jpg`'s BYTES differ — testsrc2's frame, not testsrc's")
    check((read_json(session.thumbs_marker(a)) or {}).get("size") == os.stat(s.b_copy).st_size,
          "the marker's `size` is B's copy's")
    before = session.stats(a)
    session.op("relink_media", media=a, path=a_copy)
    check(wait_until(
        lambda: read_bytes(session.thumbs_marker(a)) == a_marker_bytes
        and read_bytes(session.thumb0(a)) == a_jpg, REBUILD_SECONDS) is not None,
        "relinked back to A's copy, the marker and `0.jpg` are A's bytes again")
    check(moved(session.thumb0(a), before["0.jpg"]),
          "through a rebuild (new inode), not a memo")


def part_1g(mcp, s):
    session, av, a = s.session, s.av, s.a
    # Let every pass settle first: a copy taken while ImageIO is still
    # renaming would find a name that is already gone.
    settled = wait_until(
        lambda: all(read_json(session.thumbs_marker(m)) is not None
                    for m in session.media_rows()), REBUILD_SECONDS)
    check(settled is not None,
          "every media in the package has a thumbs marker (the passes settled)")
    # SAVE first. The cache is written straight to disk by the passes, but
    # `project.json` is written only by a save, and the package on disk still
    # held `new_project`'s blank one — a copy of it opens with NO media, and
    # "nothing was rebuilt" is then true of a build that rebuilds everything
    # (measured: the first run of this section passed that way). The save
    # rewrites every cache file into the new package (NSDocument writes to a
    # temporary location and swaps), so the baseline is read AFTER it, and
    # the markers surviving the swap is a claim of its own.
    session.op("save_project")
    with open(os.path.join(session.path, "project.json")) as handle:
        saved_ids = {m["id"] for m in json.load(handle)["media"]}
    check({av, a} <= saved_ids,
          f"the saved project.json lists AV and A ({sorted(saved_ids)}) — the copies below "
          "open with media in them")
    check(read_bytes(session.thumbs_marker(av)) == s.marker_bytes
          and peaks_source(session.peaks_marker(av)) == read_json(session.thumbs_marker(av)),
          "AV's markers survived the save's package swap byte-identical")
    # `save_project` answers only once NSDocument's completion has fired,
    # so nothing should be writing into the package now — and that is
    # asked rather than assumed: the copy is taken once two consecutive
    # samples of the six cache files agree, not after a guessed pause.
    six = {**{f"AV {k}": v for k, v in session.four(av).items()},
           **{f"A {k}": v for k, v in session.four(a).items()
              if not k.startswith("peaks")}}
    check(settle_stats(six),
          "the six cache files of AV and A are quiet after the save (two samples agree)")
    copies = {}
    for tag in ("copy1", "copy2"):
        copy = os.path.join(WORK, f"remaining-cache-{os.getpid()}-{tag}.framejob")
        if os.path.exists(copy):
            shutil.rmtree(copy)
        shutil.copytree(session.path, copy, copy_function=shutil.copy2)
        copies[tag] = copy
    copy1, copy2 = copies["copy1"], copies["copy2"]
    # Every cache file of BOTH packages — this used to stat copy1 alone under
    # a label that read "(copy2)", which named the copy FUNCTION and was
    # read as the second package.
    check(all(os.stat(path.replace(session.path, copy, 1)).st_mtime_ns
              == os.stat(path).st_mtime_ns
              for copy in (copy1, copy2) for path in six.values()),
          "`shutil.copy2` preserved every cache file's mtime_ns in both copies, so the claim "
          "below is about the marker and not about a fresher file")
    with open(os.path.join(copy1, "project.json")) as handle:
        check({av, a} <= {m["id"] for m in json.load(handle)["media"]},
              "copy1's project.json lists AV and A")
    copy_baseline = {**{f"AV {k}": v for k, v in session.stats(av, copy1).items()},
                     **{f"A {k}": v for k, v in session.stats(a, copy1).items()}}
    copy_baseline = {k: v for k, v in copy_baseline.items() if v is not None}
    mcp.call("open_project", path=copy1)
    paths = {**{f"AV {k}": v for k, v in session.four(av, copy1).items()},
             **{f"A {k}": v for k, v in session.four(a, copy1).items()}}
    paths = {k: v for k, v in paths.items() if k in copy_baseline}
    unmoved, samples, offender = sample_unmoved(paths, copy_baseline, QUIET_SECONDS)
    check(unmoved, f"opened at a new path, across {samples} samples over "
                   f"{QUIET_SECONDS:.0f} s none of the copy's {len(paths)} cache files "
                   f"moved — the marker carries no path {offender}")
    os.remove(session.thumbs_marker(av, copy2))
    before = session.stats(av, copy2)
    opened = time.monotonic()
    mcp.call("open_project", path=copy2)
    latency = wait_until(lambda: moved(session.thumb0(av, copy2), before["0.jpg"]),
                         REBUILD_SECONDS, since=opened)
    check(latency is not None,
          "the second copy, opened with AV's thumbs marker missing, was rebuilt inside the "
          f"{REBUILD_SECONDS:.0f} s cap — the control for the moved-package claim")
    check(latency is not None and latency <= QUIET_SECONDS,
          f"and its latency from the open, {'—' if latency is None else f'{latency:.2f} s'}, "
          f"is inside the {QUIET_SECONDS:.0f} s window copy1 sampled — the control BOUNDS "
          "that window too")
    check(wait_until(lambda: read_bytes(session.thumbs_marker(av, copy2)) == s.marker_bytes,
                     REBUILD_SECONDS) is not None,
          "and its marker came back byte-identical (same file behind the same path)")


def part_1h(s):
    session, av, a = s.session, s.av, s.a
    before = session.stats(av)
    before_a = session.stats(a)
    outcome = session.op("consolidate_media")
    rows = session.media_rows()
    inside = os.path.join(session.path, "media")
    check(all(r["path"].startswith(inside + os.sep) for r in rows.values()),
          f"every media row now points inside `<package>/media/` ({outcome.get('copied')} "
          "copied)")
    av_file = rows[av]["path"]
    a_file = rows[a]["path"]
    preserved = os.stat(av_file).st_mtime_ns == os.stat(s.av_copy).st_mtime_ns
    print(f"       (copyItem {'PRESERVED' if preserved else 'did NOT preserve'} the source's "
          f"mtime_ns: {os.stat(s.av_copy).st_mtime_ns} → {os.stat(av_file).st_mtime_ns})")

    def matches(marker_path, file_path):
        marker = (peaks_source(marker_path) if "/peaks/" in marker_path
                  else read_json(marker_path)) or {}
        return (marker.get("size") == os.stat(file_path).st_size
                and marker.get("modified") == mtime_second(file_path))

    check(wait_until(lambda: matches(session.thumbs_marker(av), av_file)
                     and matches(session.peaks_marker(av), av_file)
                     and matches(session.thumbs_marker(a), a_file),
                     REBUILD_SECONDS) is not None,
          "AV's two markers and A's marker MATCH the consolidated files' size and second")
    time.sleep(QUIET_SECONDS)
    after = session.stats(av)
    after_a = session.stats(a)
    if preserved:
        check(after == before and after_a == before_a,
              "the mtime was preserved, so nothing was rebuilt: all four of AV's files and "
              "A's two are the inodes they were")
        print("       consolidate outcome: mtime preserved → NO rebuild, markers untouched")
    else:
        check(after["thumbs marker"] != before["thumbs marker"]
              and after["0.jpg"][0] != before["0.jpg"][0]
              and after["peaks marker"] != before["peaks marker"],
              "the mtime changed, so the strip and the peaks were rebuilt and both markers "
              "rewritten to the new stamp")
        print("       consolidate outcome: mtime NOT preserved → rebuilt, markers rewritten")
    check(read_json(session.thumbs_marker(av)) == peaks_source(session.peaks_marker(av)),
          "AV's two markers still agree with each other")


def part_1i(s):
    session, av = s.session, s.av
    av_file = session.media_rows()[av]["path"]
    bin_bytes = read_bytes(session.peaks_bin(av))
    check(bin_bytes is not None, "AV's `.bin` is there before the relink (the thing withdrawn)")
    check(wait_until(lambda: os.path.exists(session.speech_bin(av)), MARKER_SECONDS) is not None,
          "AV's speech `.bin` is there before the relink (the other thing withdrawn)")
    # A clip on AV, so `detect_silence` has something to measure, and one
    # answer BEFORE the relink so the pending claim below is a change and
    # not a state the detector was in already.
    track = session.project()["tracks"][0]["id"]
    clip = session.op("add_clip", track=track, media=av, at=0)["new_clips"][0]
    before = session.op("detect_silence", clips=[clip])
    check("pending_peaks" not in before and before.get("clips") == [clip],
          "before the relink, `detect_silence` over a clip on AV answers from its peaks — "
          f"nothing pending ({before.get('count')} span(s) proposed)")
    # A copy of A under a name of its own: video-only, and twice AV's
    # length. The relink re-probes it (spec §11 #63), so the record takes
    # A's duration and loses its audio.
    a_for_av = fixture_copy("A", "A-for-AV")
    session.op("relink_media", media=av, path=a_for_av)
    rows = session.media_rows()
    check(rows[av]["has_audio"] is False and rows[av]["duration"] == rows[s.a]["duration"],
          "relinked to the video-only copy, the record says AV has NO audio and has A's "
          f"duration ({rows[av]['duration']}) — the relink re-probed the file")
    check(wait_until(lambda: (read_json(session.thumbs_marker(av)) or {}).get("size")
                     == os.stat(a_for_av).st_size, REBUILD_SECONDS) is not None,
          "the thumbs marker is the video-only copy's — the task ran both halves, thumbs "
          "first, so the peaks half below has had its turn")
    # #180.1: a pass for a media with no audio withdraws what the old file
    # left, peaks and speech alike, rather than leaving it on disk.
    withdrawn = {
        "peaks.bin": session.peaks_bin(av), "peaks marker": session.peaks_marker(av),
        "speech.bin": session.speech_bin(av), "speech marker": session.speech_marker(av),
    }
    check(wait_until(lambda: not os.path.exists(withdrawn["peaks.bin"])
                     and not os.path.exists(withdrawn["peaks marker"]),
                     REBUILD_SECONDS) is not None,
          f"AV's peaks `.bin` and its marker are GONE inside the {REBUILD_SECONDS:.0f} s cap")
    check(wait_until(lambda: not os.path.exists(withdrawn["speech.bin"])
                     and not os.path.exists(withdrawn["speech marker"]),
                     REBUILD_SECONDS) is not None,
          f"AV's speech `.bin` and its marker are GONE inside the {REBUILD_SECONDS:.0f} s cap")
    unmoved, samples, offender = sample_unmoved(
        withdrawn, {name: None for name in withdrawn}, QUIET_SECONDS)
    check(unmoved, f"across {samples} samples over {QUIET_SECONDS:.0f} s, all four stayed "
          f"ABSENT{': ' + offender if offender else ''}")
    after = session.op("detect_silence", clips=[clip])
    check(after.get("clips") == [] and "pending_peaks" not in after,
          "`detect_silence` now measures no clip — AV has no audio to be quiet — and has "
          f"nothing pending (clips {after.get('clips')}, pending {after.get('pending_peaks')})")
    # Back to the file the peaks were built from, re-probed again: the
    # `.bin` holds the same samples, so the same bytes, and its marker
    # agrees with the thumbs marker again.
    session.op("relink_media", media=av, path=av_file)
    returned = wait_until(
        lambda: read_bytes(session.peaks_bin(av)) == bin_bytes
        and peaks_source(session.peaks_marker(av)) == read_json(session.thumbs_marker(av))
        and read_json(session.peaks_marker(av)) is not None, REBUILD_SECONDS)
    check(returned is not None,
          "relinked back, the `.bin` returns byte-identical to the first and both markers "
          "agree again (the same file measured twice)")
    settled = wait_until(
        lambda: "pending_peaks" not in session.op("detect_silence", clips=[clip]),
        REBUILD_SECONDS)
    check(settled is not None,
          "and `detect_silence` answers from the rebuilt peaks — nothing pending")
    # What a tool CANNOT see: that the timeline was told of the withdrawal
    # above — a notification inside the process that `render_frame` never
    # draws and no tool reads. It is `remaining_probe.py`'s 5e, which counts
    # the post for a file replaced in place.


def main():
    for name in FIXTURES.values():
        if not os.path.exists(os.path.join(MEDIA, name)):
            print(f"{os.path.join(MEDIA, name)} is needed; tools/proof/README.md says how to "
                  "make the test media.")
            return 2
    os.makedirs(WORK, exist_ok=True)
    sweep_earlier_runs()
    mcp = MCP(SOCKET)
    print(f"remaining §2a — the cache completion marker, against {SOCKET}")
    section("0 — the parity log and the catalog", catalog_part, mcp)
    print("\n1 — the marker: not rebuilt, rebuilt, and which file it vouches for")
    s = State()
    section("  1a. an import lands both markers, and what they hold", part_1a, mcp, s)
    section("  1b. a second whole-media pass moves none of the four", part_1b, s)
    section("  1c. the positive control: marker gone, the same trigger rebuilds — and how "
            "fast", part_1c, s)
    section("  1d. the `.bin` deleted with its marker kept is rebuilt, marker rewritten",
            part_1d, s)
    section("  1e. os.utime on the source: the stamp's `modified` is the rule", part_1e, s)
    section("  1f. relink: a byte copy with a later mtime, then a different film", part_1f, s)
    section("  1g. a byte copy of the package opened elsewhere is not rebuilt", part_1g, mcp, s)
    section("  1h. consolidate: the marker matches the consolidated file, one way or the "
            "other", part_1h, s)
    section("  1i. relink to a file with no audio track: the record loses its audio, and "
            "nothing is served", part_1i, s)
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
