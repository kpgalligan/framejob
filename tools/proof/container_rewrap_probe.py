#!/usr/bin/env python3
"""Issue batch B73 — a WebM or Matroska file copied into a movie by the
built-in rewrap (spec §11 #216-R), probed through the product's own
`ContainerRewrap.rewrap`.

Makes ffmpeg fixtures (640x360 `testsrc2`, 2 s, with a 440 Hz sine), builds
container_rewrap_probe.swift with every app/Sources/*.swift except main.swift
over harness/build.sh's swiftc line, and rewraps each into its own scratch
destination under tools/proof/work/container-rewrap-probe/scratch/.

Fixtures: P1 VP9+Opus WebM (no CodecPrivate) · P2 the same at 30000/1001 ·
P3 H.264+AAC MKV (B-frames) · P4 HEVC+AAC MKV · P5 a `-live 1` WebM through
a pipe (no Cues, no Duration) · P6 P1 cut at 60 % · P7 AV1+Opus · P8 VP9
Profile 1 (yuv444p) · P9 VP8 · P10 VP9+Vorbis · P11 P1 with the free space
set to required − 1, then to required · P12 P1 with `stopAfter: 10` · P13
Opus in 60 ms packets · P14 Opus alone · P15 variable-rate VP9+Opus (0–13 ms
of jitter, with `settb=1/1000` and `-enc_time_base:v 1/1000`, without which
ffmpeg 9 regrids the jitter away) · P16 P1 into a destination whose folder
does not exist yet · P17 H.264+AAC MKV and P18 VP9+Opus WebM whose sound is
one 2 ms impulse at exactly 1.000 s · P19 a 20 s VP9+Opus WebM with
`refuseAudioAt: 10`, its tenth audio packet declared 4096 bytes longer than
its data, which fails the writer (-12703) some appends later, mid-copy.
Issue batch B77 (spec §11 #228-V): P10's Vorbis is now copied; P20 VP9 +
Vorbis whose sound is P17's impulse; P21 P10 with its one `\x05vorbis` (the
setup header's magic) made `\x05vorbiz`, so its headers cannot be read;
P22 P20's Vorbis through an Ogg and back beside P20's video, so the muxer
moves both 22 ms later and the first audio Block is at 0 ms.

Rows (see `score`): W* written files probe at the right size, rate and sound
with their atom; F* the exact-time frame 47 answers its own time; S5/S6/S14
the live, cut and sound-only files; R7–R10 the refusals by sentence, with
nothing written (R10 on P21: unreadable Vorbis headers keep #216-R's
sentence and its ffmpeg offer); N11 the space check; K12 no partial; A13 Opus 60 ms timing;
V15 the variable-rate file (retime FALSE asserted first); D16 the new
folder; X19 the refused append returns `.failed` within 60 s (a pump the
failed writer never asks again must not hang the copy) and leaves nothing;
T17/T18/T20 the impulse decodes from the copy (AVFoundation) within 1 ms
of where it decodes from the source (ffmpeg) — the sound's place against the
picture; B*v frame 47's written bytes (its passthrough time moved onto the
movie's timeline by the track's edit) equal the source's at the index entry
with that time; B*a the whole written audio track, in order, equals the
source's packets byte for byte (by PTS alone an AAC packet cannot be paired:
the writer puts AAC's 2112 priming samples before its edit where ffmpeg's
MKV has 1024, so T17 is what holds AAC's timing). B77: W10 also reads the
written audio's subtype `vorb`; B10v/B10a are P10's payload rows; T22
P22's impulse decodes from the copy within 1/600 s + 1 ms (the movie's edit
grid, #232, and the Block's) of where ffmpeg places it on the source's
timeline, which only the lead (spec §11 #228-V) makes true.

Issue batch B76 (spec §11 #228-P), the copy's progress and Cancel, on P1
(and P2 for C29's .mov): C20 a whole copy's `copiedBytes` never decreases
and ends equal to `totalBytes`, the described video and audio bytes, at
fraction 1; C21 `cancelAt = 0.3` throws `.cancelled`, leaves no partial and
no movie, the last fraction under 1, at most one append per pump after the
Cancel; C22 a Cancel before the copy writes nothing; C23 `assist` with a
cancelling watch leaves no copy in `Rewrapped/`, and a second `assist`
writes one that probes; C24 `probeBlocking(url:watch:)` off main passes the
watch; C25 inside `withoutAsking` it never calls it and the copy lands; C26
`ProjectDocument.probeForOpening` off main answers `CocoaError(.userCancelled)`;
C27 on main it calls no watch; C28 `isCancelledCopy` and `detail(for:)`;
C29 `importMedia([P1, a .mov])` with `copyWatch` cancelling at 30 %: one
media lands, nothing reaches `presentError`, `RewrapProgressWindowController.live`
held the copy's controller and is empty after; C30 the window's Cancel.
Every `assist` row removes the digest names it made through
`FFmpegRewrap.discard`.

Issue batch B78 (spec §11 #228-O), a copy's original, on a scratch copy of
P1 named o1.webm (one job of `kind: "original"`): O31 off main,
`probeBlocking(o1)` answers a `Rewrapped/` path with `original.path` = o1
and a bookmark, `dictionary["original"]` has that path and `probeDictionary`
keeps `original` with no `path` or `bookmark`; O32 the copy's own probe has
no original; O33 `MediaSnapshot.name` is "o1.webm", the path's with none;
O34 `revealURL` is o1, then the copy once o1 is deleted; O35 the tooltip's
three forms, exact; O36 off main with a recording watch,
`recopyingMissingCopies` points a missing copy (`/nonexistent-b78/…`) at a
new `Rewrapped/` copy, keeps the original, calls the watch once and takes
O31's duration and size; O37 the same on main calls no watch; O38 a Cancel
at 30 % leaves the same JSON and no copy or partial; O39 with o1 gone,
unchanged; O40 `ProjectDocument().read(from:ofType:)` of a package holding
O36's project, on main, ends with no missing media and the original kept;
O41 a `.mov` original with a movie already at its digest name is not
copied again; O42 `isInside`'s exact cases and `isTrashed` of the home
Trash's `b78-probe.mov` (never listed or written) and of the copy; O43 a
copy in a scratch `fakeTrash` through the `trashed` seam is copied again,
and with `trashed` false left alone. Every row discards the digest names it
made.

Mutants edit a copy of app/Sources; each must fail exactly its rows (then
MUTANT PASS, exit 0): no-retime, no-precheck, no-space-check, keep-partial,
fixed-opus-frames, audio-dropped, fps-timescale-always, no-mkdir,
offset-shift, deaf-pump (fails nothing), deaf-pump-unbounded-wait; B76's
ignore-cancel, no-user-cancelled, quiet-watch, present-cancel and
door-no-watch; B77's audio-early (every audio packet 1024 samples
early) and vorbis-as-aac (the old Opus-or-AAC `mFormatID`); and B78's
no-original, copy-name, reveal-copy, no-recopy, main-watch, recopy-any-file
and trash-plays.

    python3 tools/proof/container_rewrap_probe.py [--mutant NAME]
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
import bounded  # noqa: E402

WORK = ROOT / "tools/proof/work/container-rewrap-probe"
FIX = WORK / "fixtures"
SCRATCH = WORK / "scratch"


def src(rate="30", seconds=2):
    return ["-f", "lavfi", "-i", f"testsrc2=size=640x360:rate={rate}:duration={seconds}",
            "-f", "lavfi", "-i", f"sine=frequency=440:sample_rate=48000:duration={seconds}"]


VP9 = ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p", "-b:v", "500k"]
OPUS = ["-c:a", "libopus"]
# ffmpeg's native Vorbis encoder: experimental, and stereo only.
VORBIS_ARGS = ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"]
# settb and the encoder's 1 ms time base: without them ffmpeg 9 regrids the
# jittered times to 1/30 s and the fixture snaps (measured).
VFR = "settb=1/1000,setpts=(N/30+0.013*mod(N*7\\,5)/4)/TB"

# An impulse at exactly 1.000 s, 2 ms long: where it decodes is where the
# copy's sound sits against its picture.
CLICK = ["-f", "lavfi", "-i",
         "aevalsrc=if(between(t\\,1\\,1.002)\\,0.9\\,0):s=48000:c=stereo:d=2"]

# id: (file, ffmpeg arguments after the inputs, inputs)
FIXTURES = {
    "P1": ("p1.webm", VP9 + OPUS, src()),
    "P2": ("p2.webm", VP9 + OPUS, src("30000/1001")),
    "P3": ("p3.mkv", ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-bf", "2", "-c:a", "aac"],
           src()),
    "P4": ("p4.mkv", ["-c:v", "libx265", "-pix_fmt", "yuv420p", "-c:a", "aac"], src()),
    "P7": ("p7.webm", ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p"] + OPUS, src()),
    "P8": ("p8.webm", ["-c:v", "libvpx-vp9", "-pix_fmt", "yuv444p", "-profile:v", "1"] + OPUS,
           src()),
    "P9": ("p9.webm", ["-c:v", "libvpx", "-pix_fmt", "yuv420p"] + OPUS, src()),
    "P10": ("p10.webm", VP9 + VORBIS_ARGS, src()),
    "P13": ("p13.webm", VP9 + OPUS + ["-frame_duration", "60"], src()),
    "P14": ("p14.webm", ["-vn"] + OPUS, src()),
    "P17": ("p17.mkv", ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-bf", "2", "-c:a", "aac"],
            src()[:4] + CLICK),
    "P18": ("p18.webm", VP9 + OPUS, src()[:4] + CLICK),
    # B77: encoded directly, so the first decoded sample is at 0.
    "P20": ("p20.webm", VP9 + VORBIS_ARGS, src()[:4] + CLICK),
    # 20 s, so the refused packet fails the writer while both inputs still
    # have samples to give (on 2 s it can surface only at the finish).
    "P19": ("p19.webm", VP9 + ["-deadline", "realtime", "-cpu-used", "8"] + OPUS,
            src(seconds=20)),
    "P15": ("p15.webm", ["-vf", VFR, "-fps_mode", "vfr", "-enc_time_base:v", "1/1000"]
            + VP9 + OPUS, src()),
}

DEAF = [("ContainerRewrapWriter.swift",
         "guard shared.failure == nil, shared.progress?.isCancelled != true,",
         "if writer?.status == .failed { return }\n"
         "                guard shared.failure == nil, shared.progress?.isCancelled != true,"),
        ("ContainerRewrapWriter.swift",
         "guard self.input.append(buffer) else {",
         "guard self.input.append(buffer) else { return }\n"
         "                    guard true else {")]
UNBOUNDED = ("ContainerRewrapWriter.swift",
             "while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {",
             "group.wait()\n        while group.wait(timeout: .now()) == .timedOut {")

SOURCE_MUTANTS = {
    "no-retime": [("ContainerRewrap.swift",
                   "_ = container.retime(MediaImporter.rationalFrameRate(nominal))", "_ = 0")],
    "no-precheck": [("ContainerRewrap.swift", "try precheck(description, source)",
                     "if description.video?.fourcc == nil || description.audio?.fourcc == nil"
                     " { try precheck(description, source) }")],
    "no-space-check": [("ContainerRewrap.swift",
                        "try checkSpace(for: description, source, at: destination,"
                        " freeBytes: freeBytes)", "_ = 0")],
    "keep-partial": [("ContainerRewrap.swift",
                      "            try? manager.removeItem(at: partial)\n"
                      "            if error is ContainerRewrapError { throw error }",
                      "            if error is ContainerRewrapError { throw error }")],
    "fixed-opus-frames": [("ContainerRewrapWriter.swift",
                           "mVariableFramesInPacket: s.frames,",
                           "mVariableFramesInPacket: s.frames == 0 ? 0 : 960,")],
    "audio-dropped": [("ContainerRewrapWriter.swift",
                       "if let audio = d.audio, audio.samples > 0 {",
                       "if let audio = d.audio, audio.samples < 0 {")],
    "fps-timescale-always": [("ContainerRewrapWriter.swift",
                              "if let scale = CMTimeScale(exactly: video.timescale) {"
                              " input.mediaTimeScale = scale }",
                              "input.mediaTimeScale = CMTimeScale("
                              "MediaImporter.rationalFrameRate(video.nominalFps ?? 30).num)")],
    "no-mkdir": [("ContainerRewrap.swift",
                  "try AppSupport.ensureDirectory(destination.deletingLastPathComponent())",
                  "_ = 0")],
    "offset-shift": [("ContainerRewrapWriter.swift", "try handle.seek(toOffset: s.offset)",
                      "try handle.seek(toOffset: s.offset + 1)")],
    # A failed writer asks each input again on macOS 26.5 and each pending
    # append answers false (measured: with only the wait put back, P19 still
    # returns), so the hang X19 guards needs an input that never acts on the
    # failure: `deaf-pump` makes every pump return without finishing once
    # the writer has failed — on a refused append or on its next call — and
    # must fail nothing (the sliced wait halts them); with the wait put back
    # to one unbounded `group.wait()` as well, P19 hangs.
    "deaf-pump": DEAF,
    "deaf-pump-unbounded-wait": DEAF + [UNBOUNDED],
    # B76 (spec §11 #228-P).
    "ignore-cancel": [("ContainerRewrapWriter.swift",
                       "guard shared.failure == nil, shared.progress?.isCancelled != true,",
                       "guard shared.failure == nil,")],
    "no-user-cancelled": [("ProjectDocument+Import.swift",
                           "throw CocoaError(.userCancelled)", "throw ContainerRewrapError"
                           ".cancelled(url)")],
    "quiet-watch": [("MediaImporter+Probe.swift", "watch: quiet ? nil : watch)",
                     "watch: watch)")],
    "present-cancel": [("ProjectDocument+Import.swift",
                        "if case ContainerRewrapError.cancelled = error { return true }",
                        "_ = error")],
    "door-no-watch": [("ProjectDocument+Import.swift",
                       "MediaImporter.probe(url: urls[index], mayAsk: true, watch: Self.copyWatch)",
                       "MediaImporter.probe(url: urls[index], mayAsk: true)")],
    # B77 (spec §11 #228-V). The AUDIO branch's time, its next line taken in
    # so it matches once.
    "audio-early": [("ContainerRewrapWriter.swift",
                     "presentationTimeStamp: CMTime(value: s.pts, timescale: timescale),\n"
                     "                packetDescriptions:",
                     "presentationTimeStamp: CMTime(value: s.pts - 1024, timescale: timescale),\n"
                     "                packetDescriptions:")],
    "vorbis-as-aac": [("ContainerRewrapWriter.swift",
                       "asbd.mFormatID = ContainerRewrap.fourCharCode(a.fourcc ?? \"\")",
                       "asbd.mFormatID = a.fourcc == \"opus\" ? kAudioFormatOpus"
                       " : kAudioFormatMPEG4AAC")],
    # B78 (spec §11 #228-O).
    "no-original": [("MediaImporter+Probe.swift",
                     "descriptor.original = MediaOriginal(of: source)", "_ = source")],
    "copy-name": [("MediaSnapshot.swift", "((original?.path ?? path) as NSString)",
                   "(path as NSString)")],
    "reveal-copy": [("MediaDescriptor.swift", "originalURL(for: media) ?? mediaURL(for: media)",
                     "mediaURL(for: media) ?? originalURL(for: media)")],
    "no-recopy": [("ProjectDocument+MissingCopies.swift",
                   "return recopyingMissingCopies(anchored)", "return anchored")],
    "main-watch": [("ProjectDocument+MissingCopies.swift",
                    "let shown = Thread.isMainThread ? nil : watch", "let shown = watch")],
    "recopy-any-file": [("ProjectDocument+MissingCopies.swift",
                         "guard let source = originalURL(for: media), "
                         "ContainerRewrap.isMatroska(source) else {",
                         "guard let source = originalURL(for: media) else {")],
    "trash-plays": [("ProjectDocument+MissingCopies.swift",
                     "guard copy == nil || copy.map(trashed) == true else { continue }",
                     "guard copy == nil else { continue }")],
}

# The rows each mutant must fail, and only those (measured on an M2 Max,
# hw_av1 false; `no-precheck` adds R7 there, where AV1 would be copied).
# `no-retime` also fails W3: an un-snapped H.264 track in ms probes as
# 29985/1000. `audio-dropped` fails every row that reads sound, and X19,
# whose refused packet is audio. `keep-partial` fails X19 too: its failed
# copy leaves `p19.partial.mov`. It does NOT fail C21 (B76, measured): a
# Cancel's `cancelWriting()` on a writer still writing deletes the movie
# itself, where X19's on a writer that has already failed does not, so
# the caller's removal is what X19 and K12 hold and a Cancel leaves nothing
# either way.
#
# B77 (measured on 2026-10-03): P10's B10v fails with B1v under `no-retime`
# and `offset-shift`, and every P10/P20 sound row with the other sound rows
# under `audio-dropped` and `offset-shift`. `audio-dropped` also fails C20,
# a B76 row B76 did not re-measure against it: with no audio input the copy
# reports only the video's bytes ("copied 95852 of 115100"). `audio-early`
# fails T17, T18, T22 and B3a (an AAC packet moved before 0 is trimmed) but
# not T20: P20's impulse decodes at 1.000 s with every audio packet 1024
# samples early too. The writer lays a Vorbis track out back to back from
# its first packet, which a time before 0 puts at 0 (the copy's packets read
# 0, 1024, 2048, …), and P20's first Block is at −21 ms, so with the lead it
# starts at 16 samples, without it before 0, and the decode is the same.
# P22's first Block is at 0 ms: with the lead its copy's click reads 1.020 s
# against ffmpeg's timeline 1.022, without it 1.000, so T22 holds the lead.
# `vorbis-as-aac` fails W10 (no audio track is written), T20, T22 and B10a.
EXPECTED = {
    "no-retime": {"W3", "F1", "F2", "F3", "F4", "B1v", "B3v", "B10v"},
    "no-precheck": {"R7", "R8", "R9"},
    "no-space-check": {"N11"},
    "keep-partial": {"K12", "X19"},
    "fixed-opus-frames": {"A13"},
    "audio-dropped": {"W1", "W2", "W3", "W4", "W10", "S5", "S14", "A13", "T17", "T18", "T20",
                      "T22", "B1a", "B3a", "B10a", "X19", "C20"},
    "fps-timescale-always": {"V15"},
    "no-mkdir": {"D16"},
    # A frame read one byte late no longer decodes, so the frame and impulse
    # rows fail with the payload rows.
    "offset-shift": {"B1v", "B1a", "B3v", "B3a", "B10v", "B10a", "F1", "F2", "F3", "F4", "T17",
                     "T18", "T20", "T22"},
    "deaf-pump": set(),
    "deaf-pump-unbounded-wait": {"X19"},
    "ignore-cancel": {"C21"},
    "no-user-cancelled": {"C26"},
    "quiet-watch": {"C25"},
    "present-cancel": {"C28", "C29"},
    "door-no-watch": {"C29"},
    "audio-early": {"T17", "T18", "T22", "B3a"},
    "vorbis-as-aac": {"W10", "T20", "T22", "B10a"},
    # B78 (measured on 2026-10-03): `no-original` also fails O40 and O43,
    # whose re-copy relinks with a probe that now carries no original, which
    # clears the one the project held.
    "no-original": {"O31", "O33", "O36", "O40", "O43"},
    "copy-name": {"O33"},
    "reveal-copy": {"O34"},
    "no-recopy": {"O40"},
    "main-watch": {"O37"},
    "recopy-any-file": {"O41"},
    "trash-plays": {"O43"},
}

PROFILE1 = ("p8.webm is VP9 Profile 1 video, which this Mac cannot decode; "
            "VP9 Profiles 0 and 2 import.")
VP8 = "p9.webm is VP8 video, which this Mac cannot decode."
AV1 = "p7.webm is AV1 video, which needs an M3 or later Mac."
VORBIS = "p21.webm has Vorbis audio, which Reelcut cannot copy out of a WebM or Matroska file."


def tail(text, limit=300):
    text = " ".join((text or "").split())
    return text[-limit:] if text else "(no stderr)"


def make_fixtures():
    if FIX.exists():
        shutil.rmtree(FIX)
    FIX.mkdir(parents=True)
    made, problems = {}, {}
    for row_id, (name, args, inputs) in FIXTURES.items():
        path = FIX / name
        result = bounded.run(["ffmpeg", "-y", "-v", "error", *inputs, *args, str(path)], 120)
        if result["rc"] or result["expired"] or not path.exists():
            problems[row_id] = "expired" if result["expired"] else tail(result["stderr"])
        else:
            made[row_id] = path
    live = FIX / "p5.webm"
    with open(live, "wb") as out:
        proc = subprocess.run(["ffmpeg", "-v", "error", *src(), *VP9, *OPUS, "-live", "1",
                               "-f", "webm", "pipe:1"], stdout=out, stderr=subprocess.PIPE,
                              timeout=120)
    if proc.returncode == 0 and live.stat().st_size > 0:
        made["P5"] = live
    else:
        problems["P5"] = tail(proc.stderr.decode(errors="replace"))
    if "P10" in made:
        # B77: P10 with its setup header's magic broken, and nothing else.
        whole = made["P10"].read_bytes()
        found = whole.count(b"\x05vorbis")
        if found == 1:
            broken = FIX / "p21.webm"
            broken.write_bytes(whole.replace(b"\x05vorbis", b"\x05vorbiz"))
            made["P21"] = broken
        else:
            problems["P21"] = f"p10.webm holds b'\\x05vorbis' {found} times, not once"
    if "P20" in made:
        # B77: P20's Vorbis through an Ogg and back beside its own video, so
        # the muxer moves both 22 ms later and the first audio Block is at 0.
        ogg, remux = FIX / "p22.ogg", FIX / "p22.webm"
        result = bounded.run(["ffmpeg", "-y", "-v", "error", "-i", str(made["P20"]), "-vn",
                              "-c", "copy", str(ogg)], 120)
        if not result["rc"] and not result["expired"]:
            result = bounded.run(["ffmpeg", "-y", "-v", "error", "-i", str(made["P20"]), "-i",
                                  str(ogg), "-map", "0:v", "-map", "1:a", "-c", "copy",
                                  str(remux)], 120)
        first = bounded.run(["ffprobe", "-v", "error", "-select_streams", "a", "-read_intervals",
                             "%+#1", "-show_entries", "packet=pts", "-of", "csv=p=0",
                             str(remux)], 60)["stdout"].strip() if remux.exists() else ""
        if result["rc"] or result["expired"] or not remux.exists():
            problems["P22"] = "expired" if result["expired"] else tail(result["stderr"])
        elif first != "0":
            problems["P22"] = f"p22.webm's first audio Block is at {first!r} ms, not 0"
        else:
            made["P22"] = remux
    if "P1" in made:
        whole = made["P1"].read_bytes()
        cut = FIX / "p6.webm"
        cut.write_bytes(whole[:len(whole) * 6 // 10])
        made["P6"] = cut
    return made, problems


def build(sources):
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/container_rewrap_probe.swift", entry)
    binary = WORK / "container-rewrap-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    result = bounded.run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                          "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                          "-import-objc-header",
                          str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                          "-L", str(ROOT / "core/target/release"), "-lreelcut_core",
                          *swift, str(entry), "-o", str(binary)], 900)
    if result["expired"]:
        return None, "swiftc expired after 900 s"
    if result["rc"]:
        lines = [line for line in result["stderr"].splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [tail(result["stderr"], 600)])
    return binary, ""


def mutate(name, dest):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(ROOT / "app/Sources", dest)
    for file, before, after in SOURCE_MUTANTS[name]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def jobs_for(made):
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    jobs = []

    def job(row_id, fixture, **extra):
        if fixture not in made:
            return
        out = SCRATCH / row_id / "out"
        if row_id == "P16":
            dest = out / "new" / "deeper" / "p16.mov"
            (SCRATCH / row_id).mkdir(parents=True)
        else:
            out.mkdir(parents=True)
            dest = out / f"{row_id.lower()}.mov"
        jobs.append({"id": row_id, "source": str(made[fixture]), "dest": str(dest), **extra})

    for row_id in ("P1", "P3"):
        job(row_id, row_id, inspect=True, frame47=True, payload=True)
    job("P10", "P10", inspect=True, payload=True)
    for row_id in ("P2", "P4"):
        job(row_id, row_id, inspect=True, frame47=True)
    for row_id in ("P5", "P6", "P13", "P14", "P15"):
        job(row_id, row_id, inspect=True)
    for row_id in ("P7", "P8", "P9", "P21"):
        job(row_id, row_id, inspect=True)
    for row_id in ("P17", "P18", "P20", "P22"):
        job(row_id, row_id, click=True)
    job("P11", "P1", free_delta=-1)
    job("P11b", "P1", free_delta=0)
    job("P12", "P1", stop_after=10)
    job("P19", "P19", refuse_audio_at=10)
    job("P16", "P1", inspect=True)
    if "P1" in made:
        # B78: the original rows, on a scratch copy of P1 named o1.webm.
        jobs.append({"id": "ORIGINAL", "kind": "original", "source": str(made["P1"]),
                     "dest": str(SCRATCH / "original")})
    if "P1" in made and "P2" in made:
        cancel = SCRATCH / "cancel"
        cancel.mkdir(parents=True)
        jobs.append({"id": "CANCEL", "kind": "cancel", "source": str(made["P1"]),
                     "p2": str(made["P2"]), "dest": str(cancel)})
    return jobs


def ffprobe_video_duration(path):
    """The source's video stream from ffprobe's packets: last pts plus its
    duration, less the first pts."""
    result = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "packet=pts_time,duration_time", "-of", "json", str(path)], 60)
    packets = json.loads(result["stdout"] or "{}").get("packets", [])
    times = sorted((float(p["pts_time"]), p.get("duration_time")) for p in packets
                   if p.get("pts_time") not in (None, "N/A"))
    if not times:
        return None
    last, duration = times[-1]
    gap = times[-1][0] - times[-2][0] if len(times) > 1 else 0.0
    last_duration = float(duration) if duration not in (None, "N/A") else gap
    return last + last_duration - times[0][0]


def decoded_click(path, timeline=False):
    """When the source's sound, decoded by ffmpeg, first passes 0.3: from the
    first decoded sample, or (`timeline`) on the file's own timeline, each
    packet's samples placed at its time (`aresample=async=1:first_pts=0`)."""
    if path is None:
        return None
    placed = ["-af", "aresample=async=1:first_pts=0"] if timeline else []
    result = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vn", *placed,
                             "-f", "f32le", "-ac", "1", "-ar", "48000", "-"],
                            capture_output=True, timeout=120)
    samples = memoryview(result.stdout).cast("f")
    for k, value in enumerate(samples):
        if abs(value) > 0.3:
            return k / 48000
    return None


def score(answers, made, problems, host):
    results = []

    def row(row_id, ok, detail):
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ") + f"{row_id} {detail}", flush=True)

    def get(job_id):
        return answers.get(job_id, {})

    def absent(row_id, job_id):
        why = problems.get(job_id.rstrip("b"), "no answer")
        row(row_id, False, f"{job_id}: {why}")

    def written(row_id, job_id, fps, atom, subtype=None):
        a = get(job_id)
        if not a:
            return absent(row_id, job_id)
        p = a.get("probe", {})
        tracks = a.get("tracks") or {}
        atoms = (tracks.get("video") or {}).get("atoms", [])
        shape = (a.get("rewrap"), p.get("width"), p.get("height"), p.get("fps"),
                 p.get("has_audio"), atom in atoms)
        heard = (tracks.get("audio") or {}).get("subtype")
        row(row_id, shape == ("ok", 640, 360, fps, True, True)
            and (subtype is None or heard == subtype),
            f"{job_id}: rewrap, size, fps, has_audio, {atom} = {shape}"
            + (f", audio subtype {heard!r}" if subtype else "") + f" {a.get('error', '')}")

    written("W1", "P1", [30, 1], "vpcC")
    written("W2", "P2", [30000, 1001], "vpcC")
    written("W3", "P3", [30, 1], "avcC")
    written("W4", "P4", [30, 1], "hvcC")
    written("W10", "P10", [30, 1], "vpcC", subtype="vorb")
    for n, job_id in ((1, "P1"), (2, "P2"), (3, "P3"), (4, "P4")):
        a = get(job_id)
        wanted, actual = a.get("frame47_wanted"), a.get("frame47_actual")
        good = wanted is not None and actual is not None and abs(wanted - actual) < 1e-6
        row(f"F{n}", good, f"{job_id}: frame 47 asked at {wanted}, answered {actual}")
    full = (get("P1").get("probe") or {}).get("duration_ticks")
    for row_id, job_id, check in (
            ("S5", "P5", lambda p, t: p.get("has_video") and p.get("has_audio")),
            ("S6", "P6", lambda p, t: full and 0 < p.get("duration_ticks", 0) < full),
            ("S14", "P14", lambda p, t: p.get("kind") == "audio" and not p.get("has_video"))):
        a = get(job_id)
        if not a:
            absent(row_id, job_id)
            continue
        p = a.get("probe") or {}
        row(row_id, a.get("rewrap") == "ok" and check(p, a.get("tracks")),
            f"{job_id}: rewrap {a.get('rewrap')} {a.get('error', '')}; probe {p}")

    def refused(row_id, job_id, sentence, invites):
        a = get(job_id)
        if not a:
            return absent(row_id, job_id)
        e = a.get("error") or {}
        good = (a.get("rewrap") == "error" and e.get("message") == sentence
                and e.get("invites_ffmpeg") == invites and a.get("listing") == []
                and not a.get("dest_exists"))
        row(row_id, good, f"{job_id}: {e.get('type')} {e.get('message')!r}, invites ffmpeg "
            f"{e.get('invites_ffmpeg')}; scratch {a.get('listing')}")

    if host.get("hw_av1"):
        a = get("P7")
        row("R7", a.get("rewrap") == "ok" and (a.get("probe") or {}).get("has_video"),
            f"P7 (hw_av1 true): {a.get('rewrap')} {a.get('error', '')}")
    else:
        refused("R7", "P7", AV1, False)
    refused("R8", "P8", PROFILE1, False)
    refused("R9", "P9", VP8, False)
    refused("R10", "P21", VORBIS, True)

    a, b = get("P11"), get("P11b")
    if a and b:
        sentence = (f"Not enough free space to open p1.webm: its video and sound need about "
                    f"{a.get('need_text')} on “{a.get('volume')}”, which has "
                    f"{a.get('free_text')} free. Nothing was copied.")
        e = a.get("error") or {}
        good = (e.get("type") == "noSpace" and e.get("message") == sentence
                and a.get("listing") == [] and b.get("rewrap") == "ok")
        row("N11", good, f"required − 1: {e.get('message')!r}, scratch {a.get('listing')}; "
            f"required: {b.get('rewrap')} {b.get('error', '')}")
    else:
        absent("N11", "P11")
    a = get("P12")
    e = a.get("error") or {}
    row("K12", a.get("rewrap") == "error" and e.get("type") == "failed"
        and not a.get("partial_exists") and not a.get("dest_exists") and a.get("listing") == [],
        f"P12: {e.get('type')} {e.get('message')!r}; scratch {a.get('listing')}")
    a = get("P19")
    e = a.get("error") or {}
    row("X19", a.get("rewrap") == "error" and e.get("type") == "failed"
        and "stopped after" not in (e.get("message") or "")
        and not a.get("partial_exists") and not a.get("dest_exists") and a.get("listing") == [],
        f"P19: {a.get('rewrap')} {e.get('type')} {e.get('message')!r}; scratch "
        f"{a.get('listing')}")
    a = get("P13")
    tracks = a.get("tracks") or {}
    video = (tracks.get("video") or {}).get("duration")
    audio = (tracks.get("audio") or {}).get("duration")
    row("A13", video is not None and audio is not None and audio >= video - 0.060,
        f"P13: audio {audio} s against video {video} s")
    a = get("P15")
    source_duration = ffprobe_video_duration(made["P15"]) if "P15" in made else None
    tracks = a.get("tracks") or {}
    vt = tracks.get("video") or {}
    checks = [a.get("retimed") is False, a.get("rewrap") == "ok",
              vt.get("samples") == a.get("index_video_samples"),
              source_duration is not None and vt.get("duration") is not None
              and abs(vt["duration"] - source_duration) <= 0.002]
    row("V15", all(checks), f"P15: retimed {a.get('retimed')} (must be false first), rewrap "
        f"{a.get('rewrap')} {a.get('error', '')}, samples {vt.get('samples')} vs index "
        f"{a.get('index_video_samples')}, duration {vt.get('duration')} vs ffprobe "
        f"{source_duration}")
    a = get("P16")
    row("D16", a.get("rewrap") == "ok" and a.get("dest_exists"),
        f"P16: {a.get('rewrap')} {a.get('error', '')}; destination exists "
        f"{a.get('dest_exists')}")
    for row_id, job_id in (("T17", "P17"), ("T18", "P18"), ("T20", "P20")):
        a = get(job_id)
        heard, source = a.get("click"), decoded_click(made.get(job_id))
        row(row_id, heard is not None and source is not None and abs(heard - source) <= 0.001,
            f"{job_id}: the impulse decodes at {heard} s from the copy, {source} s from the "
            f"source (ffmpeg); {a.get('error', '')}")
    # B77: P22's picture and sound both start 22 ms in, so the source's click
    # is read on its timeline, within the movie's 1/600 s edit grid (#232)
    # plus the Block's 1 ms: without the lead it decodes 22 ms early.
    a = get("P22")
    heard, source = a.get("click"), decoded_click(made.get("P22"), timeline=True)
    row("T22", heard is not None and source is not None
        and abs(heard - source) <= 1 / 600 + 0.001,
        f"P22: the impulse decodes at {heard} s from the copy, {source} s on the source's "
        f"timeline (ffmpeg); {a.get('error', '')}")
    for n, job_id in ((1, "P1"), (3, "P3"), (10, "P10")):
        p = get(job_id).get("payload") or {}
        row(f"B{n}v", p.get("video_found") and p.get("video_equal"),
            f"{job_id}: frame 47's written bytes equal the source's: {p.get('video_found')}, "
            f"{p.get('video_equal')} ({p.get('video_size')} bytes)")
        row(f"B{n}a", p.get("audio_sequence_equal"),
            f"{job_id}: every written audio packet, in order, less the "
            f"{p.get('audio_prepended')} priming copies the writer put first, equals the "
            f"source's ({p.get('audio_written')} written, {p.get('audio_source')} indexed); "
            f"by PTS the packet nearest 1.0 s ({p.get('audio_time')} s) "
            f"{'equals' if p.get('audio_equal') else 'is not'} the index's at "
            f"{p.get('audio_index_time')} s")
    score_cancel(get, row)
    score_original(get, row)
    return results


def score_cancel(get, row):
    """B76's rows C20–C30 (spec §11 #228-P)."""
    def kind(a):
        return (a.get("error") or {}).get("type")

    a = get("C20")
    row("C20", a.get("rewrap") == "ok" and a.get("monotonic") is True
        and a.get("expected", 0) > 0 and a.get("copied") == a.get("total") == a.get("expected")
        and a.get("fraction") == 1,
        f"rewrap {a.get('rewrap')} {a.get('error', '')}; copied {a.get('copied')} of "
        f"{a.get('total')} (described {a.get('expected')}), fraction {a.get('fraction')}, "
        f"never decreasing over {a.get('readings')} readings: {a.get('monotonic')}")
    a = get("C21")
    fraction, late, pumps = a.get("fraction"), a.get("adds_after_cancel"), a.get("pumps")
    row("C21", kind(a) == "cancelled" and not a.get("dest_exists")
        and not a.get("partial_exists") and a.get("listing") == []
        and fraction is not None and fraction < 1
        and late is not None and pumps and late <= pumps,
        f"cancelAt 0.3: {kind(a)} {(a.get('error') or {}).get('message')!r}; last fraction "
        f"{fraction}; {late} appends after the Cancel ({pumps} pumps); scratch "
        f"{a.get('listing')}")
    a = get("C22")
    row("C22", kind(a) == "cancelled" and a.get("listing") == [],
        f"cancelled before: {kind(a)}; scratch {a.get('listing')}")
    a = get("C23")
    row("C23", kind(a) == "cancelled" and a.get("watch_calls") == 1
        and a.get("copy_exists") is False and a.get("copy_partial_exists") is False
        and a.get("second") == "ok" and a.get("second_exists") and a.get("second_probes"),
        f"assist with a cancelling watch: {kind(a)}, watch called {a.get('watch_calls')}, "
        f"copy left {a.get('copy_exists')}, partial {a.get('copy_partial_exists')}; again with "
        f"none: {a.get('second')} {a.get('second_error', '')}, probes {a.get('second_probes')}")
    a = get("C24")
    row("C24", kind(a) == "cancelled" and a.get("watch_calls") == 1
        and a.get("copy_exists") is False,
        f"probeBlocking off main: {kind(a)}, watch called {a.get('watch_calls')}, copy left "
        f"{a.get('copy_exists')}")
    a = get("C25")
    row("C25", a.get("rewrap") == "ok" and a.get("watch_calls") == 0
        and a.get("copy_exists") is True,
        f"probeBlocking inside withoutAsking: {a.get('rewrap')} {kind(a) or ''}, watch called "
        f"{a.get('watch_calls')}, copy written {a.get('copy_exists')}")
    a = get("C26")
    row("C26", kind(a) == "userCancelled" and a.get("watch_calls") == 1
        and a.get("copy_exists") is False,
        f"probeForOpening off main: {kind(a)} {(a.get('error') or {}).get('message')!r}, watch "
        f"called {a.get('watch_calls')}, copy left {a.get('copy_exists')}")
    a = get("C27")
    row("C27", a.get("on_main") is True and a.get("rewrap") == "ok" and a.get("watch_calls") == 0,
        f"probeForOpening on main ({a.get('on_main')}): {a.get('rewrap')} {kind(a) or ''}, "
        f"watch called {a.get('watch_calls')}")
    a = get("C28")
    facts = (a.get("cancelled"), a.get("failed"), a.get("no_space"), a.get("unreadable"))
    details = (a.get("detail_before"), a.get("detail_after"))
    row("C28", facts == (True, False, False, False)
        and details == ("Reading the file…", "400 MB of 1 GB"),
        f"isCancelledCopy cancelled/failed/noSpace/unreadable = {facts}; detail {details}")
    a = get("C29")
    row("C29", a.get("completed") is True and len(a.get("ids") or []) == 1
        and a.get("media_paths") == ["p2.mov"] and a.get("presents") == 0
        and a.get("max_live") == 1 and a.get("live_after") == 0
        and a.get("copy_exists") is False and a.get("copy_partial_exists") is False,
        f"importMedia([p1.webm, p2.mov]): completed {a.get('completed')}, ids {a.get('ids')}, "
        f"media {a.get('media_paths')}, presented {a.get('presents')}, controllers live "
        f"{a.get('max_live')} during and {a.get('live_after')} after, copy left "
        f"{a.get('copy_exists')}, partial {a.get('copy_partial_exists')} "
        f"{a.get('setup', '')}")
    a = get("C30")
    row("C30", a.get("cancelled") is True and a.get("title") == "Cancelling…"
        and a.get("enabled") is False and a.get("visible") is False,
        f"cancelCopy: cancelled {a.get('cancelled')}, button {a.get('title')!r} enabled "
        f"{a.get('enabled')}, window visible {a.get('visible')} ({a.get('window_title')!r})")


HINT = "Drag to a timeline track, or onto the canvas. Hold ⌥ to insert, ⇧⌥ to overwrite."
TALK = "/Users/x/Movies/talk.webm"


def score_original(get, row):
    """B78's rows O31–O43 (spec §11 #228-O)."""
    o1 = str(SCRATCH / "original" / "o1.webm")
    a = get("O31")
    row("O31", a.get("in_rewrapped") is True and a.get("original_path") == o1
        and a.get("original_bookmark") is True and a.get("dictionary_original_path") == o1
        and a.get("probe_original") is True and a.get("probe_path_or_bookmark") is False,
        f"probeBlocking(o1.webm): path {a.get('path')!r} (Rewrapped {a.get('in_rewrapped')}), "
        f"original {a.get('original_path')!r} with a bookmark {a.get('original_bookmark')}, "
        f"dictionary's {a.get('dictionary_original_path')!r}; probeDictionary keeps original "
        f"{a.get('probe_original')}, has path or bookmark {a.get('probe_path_or_bookmark')} "
        f"{a.get('error', '')}")
    a = get("O32")
    row("O32", a.get("probed") is True and a.get("original_nil") is True
        and a.get("dictionary_has_original") is False,
        f"the copy's own probe: probed {a.get('probed')}, original nil {a.get('original_nil')}, "
        f"dictionary has original {a.get('dictionary_has_original')}")
    a = get("O33")
    row("O33", a.get("name") == "o1.webm" and a.get("plain_name") == a.get("copy_name")
        and a.get("copy_name"),
        f"name {a.get('name')!r}; with no original {a.get('plain_name')!r} "
        f"(the copy is {a.get('copy_name')!r})")
    a = get("O34")
    row("O34", a.get("before") == a.get("o1") and a.get("o1") and a.get("o1_gone") is True
        and a.get("after") == a.get("copy") and a.get("copy"),
        f"revealURL {a.get('before')!r} (o1 {a.get('o1')!r}); o1 deleted {a.get('o1_gone')}: "
        f"{a.get('after')!r} (the copy {a.get('copy')!r})")
    a = get("O35")
    wanted = {"none": HINT,
              "rewrapped": f"{TALK} — copied into Reelcut's Rewrapped folder.\n{HINT}",
              "packaged": f"{TALK} — copied into this project's package.\n{HINT}"}
    row("O35", a.get("hint") == HINT and all(a.get(k) == v for k, v in wanted.items()),
        f"tooltips {[a.get(k) for k in ('none', 'rewrapped', 'packaged')]!r}")

    def landed(a):
        return a.get("path_exists") is True and a.get("in_rewrapped") is True

    a = get("O36")
    row("O36", a.get("set_up") is True and landed(a) and a.get("original_path") == o1
        and a.get("watch_calls") == 1 and a.get("duration") == a.get("want_duration")
        and a.get("width") == a.get("want_width") and a.get("height") == a.get("want_height"),
        f"off main: path {a.get('path')!r} exists {a.get('path_exists')}, original "
        f"{a.get('original_path')!r}, watch called {a.get('watch_calls')}, duration "
        f"{a.get('duration')}/{a.get('want_duration')}, size {a.get('width')}x{a.get('height')}")
    a = get("O37")
    row("O37", a.get("on_main") is True and a.get("watch_calls") == 0 and landed(a),
        f"on main ({a.get('on_main')}): watch called {a.get('watch_calls')}, path "
        f"{a.get('path')!r} exists {a.get('path_exists')}")
    a = get("O38")
    row("O38", a.get("returned") is True and a.get("unchanged") is True
        and a.get("copy_exists") is False and a.get("partial_exists") is False,
        f"cancelAt 0.3: returned {a.get('returned')}, unchanged {a.get('unchanged')}, watch "
        f"called {a.get('watch_calls')}, copy left {a.get('copy_exists')}, partial "
        f"{a.get('partial_exists')}")
    a = get("O39")
    row("O39", a.get("o1_gone") is True and a.get("unchanged") is True,
        f"original deleted {a.get('o1_gone')}: unchanged {a.get('unchanged')}")
    a = get("O40")
    row("O40", a.get("written") is True and a.get("read") == "ok" and a.get("missing") == []
        and landed(a) and a.get("original_path") == o1,
        f"read(from:ofType:) on main: {a.get('read')} {a.get('error', '')}; missing "
        f"{a.get('missing')}, path {a.get('path')!r}, original {a.get('original_path')!r}")
    a = get("O41")
    row("O41", a.get("original_exists") is True and a.get("decoy_made") is True
        and a.get("set_up") is True and a.get("unchanged") is True,
        f"a .mov original with a movie at its digest name: unchanged {a.get('unchanged')} "
        f"(original {a.get('original_exists')}, decoy {a.get('decoy_made')})")
    a = get("O42")
    facts = tuple(a.get(k) for k in ("inside", "sibling", "itself", "trash_found", "trashed",
                                     "copy_trashed"))
    row("O42", facts == (True, False, False, True, True, False),
        f"isInside c/sibling/itself, Trash found, isTrashed Trash/copy = {facts}")
    a = get("O43")
    row("O43", a.get("held") is True and a.get("set_up") is True and landed(a)
        and a.get("original_path") == o1 and a.get("kept_unchanged") is True,
        f"a copy in fakeTrash: path {a.get('path')!r} exists {a.get('path_exists')}, original "
        f"{a.get('original_path')!r}; with trashed false unchanged {a.get('kept_unchanged')}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=list(SOURCE_MUTANTS))
    args = parser.parse_args()
    sources = ROOT / "app/Sources"
    if args.mutant:
        sources = WORK / f"Sources-{args.mutant}"
        why = mutate(args.mutant, sources)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    made, problems = make_fixtures()
    for row_id, why in problems.items():
        print(f"fixture {row_id} not made: {why}")
    binary, problem = build(sources)
    if binary is None:
        print(f"  FAIL B0 the probe builds from {sources}: {problem}")
        print("passed 0/1")
        return 1
    jobs = jobs_for(made)
    job_file = WORK / "jobs.json"
    job_file.write_text(json.dumps(jobs, indent=2))
    result = bounded.run([str(binary), str(job_file)], 900)
    host, answers = {}, {}
    for line in result["stdout"].splitlines():
        tag, _, body = line.partition(" ")
        try:
            parsed = json.loads(body) if tag in ("HOST", "ROW") else None
        except json.JSONDecodeError:
            continue
        if tag == "HOST":
            host = parsed
        elif tag == "ROW":
            answers[parsed["id"]] = parsed
    print(f"host: macOS {host.get('macos', '?')}, hw_av1 {host.get('hw_av1')}")
    if result["expired"]:
        print(f"probe binary expired after 900 s; {len(answers)} rows received")
    elif result["rc"]:
        print(f"probe binary exited {result['rc']}: {tail(result['stderr'], 600)}")
    (WORK / "answers.json").write_text(json.dumps({"host": host, "answers": answers},
                                                  indent=2) + "\n")
    results = score(answers, made, problems, host)
    failed = {row_id for row_id, ok in results if not ok}
    print(f"passed {len(results) - len(failed)}/{len(results)}")
    if not args.mutant:
        return 1 if failed else 0
    expected = set(EXPECTED[args.mutant])
    if args.mutant == "no-precheck" and host.get("hw_av1"):
        expected.discard("R7")
    verdict = "MUTANT PASS" if failed == expected else "MUTANT FAIL"
    print(f"{verdict}: {args.mutant} failed {sorted(failed)}, expected {sorted(expected)}")
    return 0 if failed == expected else 1


if __name__ == "__main__":
    sys.exit(main())
