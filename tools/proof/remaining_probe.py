#!/usr/bin/env python3
"""`designs/reelcut-remaining.md` — the fixes it lists, measured in the app.

The remaining-work document is the debt two road maps left behind, and the
items in it that are APP arithmetic get their permanent proof here rather
than in a phase script whose count is quoted in five places. One section per
item, each a function below, and one probe binary answering all of them by
`mode` — section 1 is §2b's naming, and sections 2–5 are §2a's cache
completion marker, added as four `case`s and four `section_…` functions
without touching section 1 (their paragraphs are after §2b's; section 5,
the pass's own rules, came with the review of the marker).

Why a probe and not an MCP script, for §2b. Both of the sites it names are
PANEL-only: `CaptionExportOptions.formatChanged` rewrites the save panel's
name field when the Format popup moves, and `exportCaptionsCommand` seeds
that field from the document's title. A save panel cannot be driven over MCP
or put up offscreen, and the MCP path never comes near either site —
`export_captions` goes through `AgentServer.destinationURL`, which strips
only a member of `replaceableExtensions` and appends otherwise, so
`{path: "Board v1.2"}` wrote `Board v1.2.srt` before the fix and after it.
An MCP check for that name therefore PASSES against the unfixed build and
cannot be its evidence. What can is the shape `FrameWriter.renamed` chose in
phase 7 for the same defect: a pure function of a string, compiled out of
`app/Sources` and run over a table of names — `phase9_probe.py`'s
instrument, `harness/build.sh`'s own swiftc line, cached on modification
times, and a build failure scored as a FAILURE rather than an exit.

Section 1 (naming) runs three helpers over that kind of table:

  * `CaptionExporter.renamed` — the popup's rewrite, whose known set is the
    two caption spellings and nothing else. `Board v1.2` + SubRip →
    `Board v1.2.srt` is the row a bare `deletingPathExtension` fails.
  * `ProjectDocument.displayStem(of:)` — the title-bar stem the three save
    panels (Export…, Save Frame…, Export Captions…) put their extension
    after. Its known set is `{reelcut}`, the package's own extension, and
    NOT the caption set: a saved `Board v1.2.reelcut` must come back as
    `Board v1.2`, an untitled document imported from `Board v1.2.mov` is
    titled `Board v1.2` and must keep its `.2`. The instance accessor is
    read off a live `ProjectDocument` as well, because a static function
    nobody calls is not a fix.
  * `FrameWriter.renamed` — the phase-7 original, whose docstring has said
    since it landed that "a probe compiled from `app/Sources` calls it with
    a table of names", and none did until this one: `grep renamed( tools/`
    found only the definition and its one caller. The same table shape
    closes that gap here, and the docstring now names this file.
  * `AgentServer.destinationURL` — the MCP side of the one rule (1f). Three
    docs state that `CaptionExporter.knownExtensions` is a SUBSET of
    `AgentServer.replaceableExtensions`, and until this row nothing pinned
    it: the set is `private`, `phase4_proof.py` sends a `.srt` path asked
    for as `vtt` and no script anywhere sends a `.vtt` path asked for as
    `srt`, so `vtt`'s membership was pinned by nothing. `destinationURL`
    is internal and a probe over `app/Sources` reaches it, so the table
    asks, for EVERY member of `knownExtensions`, that `x.<member>` asked
    for as the other format is stripped and replaced (`x.srt` + vtt →
    `x.vtt`, `x.vtt` + srt → `x.srt`, upper-case too) while a non-member
    is appended to (`x.txt` + srt → `x.txt.srt`), and a structural check
    that the rows cover the whole set the probe read off the type — so a
    third caption format would fail here by name until it joined the
    other list.

And one thing no behavioural probe can see, read STRUCTURALLY (1e): that
the four sites actually CALL the helpers. A correct `displayStem(of:)` with
`exportCaptionsCommand` still stripping bare is the unfixed defect with a
proof beside it, and every one of those sites is a panel's private method
or the line that seeds one — so 1e reads the four function bodies out of
the sources it compiled and asserts each names its helper and none carries
a `deletingPathExtension` of its own. `phase7_chrome.py`'s
`destinationProperties != nil` is the precedent for a source read where
nothing else can reach; it is weaker than a behaviour and is said to be.

The gate, as the repository requires it, ran three mutants on COPIES of
`app/Sources` under `work/`, the script pointed at each with `--sources`:
`CaptionExporter.renamed` reverted to the bare strip (the `Board v1.2`,
`talk.txt`, `shot.final` and `chart.png` rows fail); `displayStem(of:)`
reverted to the bare strip (the `Board v1.2`, `talk.srt` and `talk.mov` stem
rows fail — and 1d's live document did NOT, because this Mac shows
extensions and a bare strip of `Board v1.2.reelcut` is right by accident,
which is why the static table is the killer and the live read is a wiring
check); and `exportCaptionsCommand` alone put back on the bare strip with
both helpers intact (only 1e fails, which is what 1e is for). The scores
belong in `designs/reelcut-remaining.md` §2b's record and in `README.md`'s
section for this file, beside the tree's own count. A fourth mutant is
1f's: `"vtt"` removed from `replaceableExtensions` scores **106/108** —
exactly the two `x.vtt` + srt rows (`x.vtt.srt` comes back, the doubled
name the subset rule exists to prevent), while every row about `srt` still
passes, which is precisely the half the tree had pinned before. 1f's
coverage check is about the SCRIPT, not the build — it fails when a member
of `knownExtensions` has no strip row here — so no build mutant takes it.

Sections 2–4 (§2a) are the app-side half of the cache completion marker,
whose MCP half is `remaining_proof.py`. Nothing a running instance can be
asked reaches any of the three: `CacheStamp.stamp(for:url:)` has no tool,
the ledger under `generateCaches` is only visible as the COUNT of
`.mediaCacheDidChange` posts, and the timeline's memo is a picture. So:

  * section 2 calls the stamp over four files the script prepares — an
    original, a byte copy at another path with times preserved (EQUAL, so
    the path is not in it), the same bytes with a later mtime (differs in
    `modified` alone, by the 7 s the script moved it), and a missing path
    (nil) — and reads the key set off the encoding the marker carries, plus
    the two marker paths' shape;
  * section 3 calls `generateCaches` ONCE into a fresh directory and counts
    the `thumbs` posts until 1.5 s of quiet, then THREE times in a row into
    a second one: under the ledger the count is one pass's worth (the second
    and third queue behind the first and find its marker), and a fourth call
    after the quiet posts nothing and leaves `0.jpg`'s inode alone;
  * section 4 renders a bare `TimelineView` (phase 9's chrome probe's scene)
    over one media whose `0.jpg` the probe wrote solid RED, turns the file
    BLUE, and posts `.mediaCacheDidChange` for the media twice — WITHOUT the
    `replaced` flag the tile stays red (the memo rule, pinned), WITH it the
    tile is blue — comparing the four PNGs inside the clip's rectangle, with
    the differing box printed.

Their gate, on copies of the tree pointed at with `--sources`: the ledger
removed (`generateCaches` back to a bare `Task.detached`) scores **107/108**
— three rapid calls post 3 where one pass posts 1, and only that row fails;
the timeline's hit clearing removed (the one `if replaced` line in
`TimelineCaches.invalidate`) scores **105/108** — the tile stays red after the
flagged post, so the "is BLUE", "no longer red" and whole-render rows fail
(both re-scored after 1f grew the total from 101, and before section 5 grew
it to 141; the rows they take are the same).
The head-check and forced-`modified` mutants are `remaining_proof.py`'s.
Sections 2 AND 3 read `media/A.mov` (never write it): section 2 stamps
copies of it, section 3 decodes it (video only, ten frames, one post per
pass); section 4 needs no media at all.

Section 5 is the PASS: the rules the review put into `thumbnails` and
`peaks` after the marker landed — when a pass may write its marker, and
what it tells — each driven straight at a directory, because no tool can
delete a frame under a running pass, hand the app a text file with a
movie's record, or count a notification. Five passes, over copies of
`A.mov` and `AV.mov` (the one fixture with a peaks half) and two text files
the script writes under a movie's name and an image's:

  * 5a: `A.mov` with `0.jpg` deleted the instant it appears — a 1 ms poll on
    a thread of its own, the frame a titled document's save loses between
    NSDocument's listing and its swap. NO marker, the other nine frames on
    disk, a post; and the SAME pass again, untouched, rebuilds all ten and
    writes the marker, its first post carrying `replaced` (a partial strip
    finished). The marker's absence is what buys the retry.
  * 5b: a record with `hasVideo` over a text file — no frame, NO marker
    (a pass that wrote nothing is a failed reader to retry, not a strip
    with holes), and still a post.
  * 5c: an IMAGE record over a text file with a `0.jpg` seeded — the old
    tile cleared, no marker, and exactly ONE post carrying `replaced`, on
    the decode-failure path.
  * 5d: `A.mov` under a 20 s record with a `0.jpg` seeded — a relink never
    re-probes, so a record longer than its file is a state the app can be
    in, and a request past the end fails as a hole (measured: eleven
    frames, the one at 10 s landing inside the tolerance) while every
    result counts toward the every-16 post, so ONE replacing pass makes TWO
    posts, which no fixture is long enough to give: `replaced` on the first
    and on no later one.
  * 5e: `AV.mov`'s peaks built (one `peaks` post, the landing); the same
    record over a video-only file — `hasAudio` still true — WITHDRAWS the
    `.bin` and its marker at the head and posts `peaks` exactly once, the
    withdrawal, before the track load returns early; `AV.mov` again brings
    the `.bin` back at its first size with one post. That the timeline is
    TOLD is the claim `remaining_proof.py`'s 1i cannot make over MCP, and
    this row is where it lives.

Section 5's gate, each a copy of the tree pointed at with `--sources`,
against this file's **141** checks. `stripHolds` without its presence
check (`return !frames.isEmpty`) scores **138/141**: 5a's "writes NO
marker" and, because the marker it wrongly wrote makes the retry skip,
5a's two retry rows ("marker written, all ten frames on disk" and "its
first post carries `replaced`"). `stripHolds` without its at-least-one-frame
rule (an empty set holding vacuously) scores **139/141**: 5b's "writes NO
marker" and 5c's "no marker". The image branch's post put back inside the
decode's success arm scores **140/141**: 5c's "exactly ONE thumbs post,
carrying `replaced`". The `replaced = false` after the every-16 post
removed — the flag on every post — scores **140/141**: 5d's "NO later post
does", which is the row the 20 s record exists to make fallible. And
`clearPeaks` back to marker-only, the `.bin` left in place and nothing
posted (`remaining_proof.py`'s 1i mutant, run here as well) scores
**139/141**: 5e's "the `.bin` is GONE" and "exactly ONE peaks post". No
survivors; every section-5 row but the preconditions and the settle rows
is taken by at least one of the five.

Run it from anywhere; it needs no port and no window server grant. The
environment override is `RC_APP_SOURCES`, the name `phase9_chrome.py`
uses for the same thing — one spelling for the two probes that take one,
after this file had spelled it `REELCUT_SOURCES`:

    python3 tools/proof/remaining_probe.py
    python3 tools/proof/remaining_probe.py --sources <dir>   # a mutant copy
    RC_APP_SOURCES=<dir> python3 tools/proof/remaining_probe.py
"""

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work")
PROBE = os.path.join(WORK, "remainingprobe")
TREE_SOURCES = os.path.join(ROOT, "app", "Sources")
MEDIA = os.path.join(ROOT, "tools", "proof", "media")
# The files sections 2–4 make: fixture copies, cache directories, PNGs.
FILES = os.path.join(WORK, "remaining-probe-files")

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def check_table(label, rows, answers, keys, got_key, expect_key="expect"):
    """One check per row of a table. `rows` is what the request carried, each
    with an `expect` and an optional `why`; `answers` is what the probe sent
    back for the same rows, matched by `keys` — never by position, so a probe
    that dropped or reordered a row fails by name rather than shifting every
    later check onto the wrong answer."""
    by = {tuple(a.get(k) for k in keys): a for a in answers}
    for row in rows:
        answer = by.get(tuple(row.get(k) for k in keys), {})
        got = answer.get("error") or answer.get(got_key)
        spelled = " + ".join(str(row[k]) for k in keys if row.get(k) is not None)
        why = f" — {row['why']}" if row.get("why") else ""
        check(f"{label}: {spelled!r} → {row[expect_key]!r}{why}",
              got == row[expect_key], f"got {got!r}")


# --------------------------------------------------------------------------
# The probe. One binary, one JSON request in, one JSON answer out, dispatched
# on the request's `mode`, so a later section is a new `case` and nothing
# else moves. A mode the binary does not know is answered BY NAME, which is
# what makes a stale binary a scored failure with a reason rather than a
# silent pass.

PROBE_SOURCE = r'''
import AppKit
import Foundation

// ---- mode "naming": the three stem helpers over tables of names ----------
func naming(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]

    // 1a. The caption popup's rewrite. The row's `format` is the enum's
    // rawValue, which for captions IS the extension.
    let caption = request["caption"] as? [[String: Any]] ?? []
    out["caption"] = caption.map { row -> [String: Any] in
        let name = row["name"] as? String ?? ""
        let fallback = row["fallback"] as? String ?? ""
        let spelled = row["format"] as? String ?? ""
        var answer: [String: Any] = ["name": name, "format": spelled, "fallback": fallback]
        guard let format = CaptionExporter.Format(rawValue: spelled) else {
            answer["error"] = "no caption format named \(spelled)"
            return answer
        }
        answer["renamed"] = CaptionExporter.renamed(name, as: format, fallback: fallback)
        return answer
    }
    out["captionKnown"] = Array(CaptionExporter.knownExtensions).sorted()
    out["captionFormats"] = CaptionExporter.Format.allCases.map { $0.rawValue }

    // 1b. The still popup's rewrite — the model the caption helper copies.
    // Here `format` is the rawValue (`jpeg`) and the extension written is
    // `fileExtension` (`jpg`), which the answer reports so the table can
    // assert the REAL spelling rather than assume it.
    let frame = request["frame"] as? [[String: Any]] ?? []
    out["frame"] = frame.map { row -> [String: Any] in
        let name = row["name"] as? String ?? ""
        let fallback = row["fallback"] as? String ?? ""
        let spelled = row["format"] as? String ?? ""
        var answer: [String: Any] = ["name": name, "format": spelled, "fallback": fallback]
        guard let format = FrameWriter.Format(rawValue: spelled) else {
            answer["error"] = "no still format named \(spelled)"
            return answer
        }
        answer["renamed"] = FrameWriter.renamed(name, as: format, fallback: fallback)
        return answer
    }
    out["frameKnown"] = Array(FrameWriter.knownExtensions).sorted()
    out["frameExtensions"] = Dictionary(
        uniqueKeysWithValues: FrameWriter.Format.allCases.map { ($0.rawValue, $0.fileExtension) })

    // 1f. The MCP side of the one rule: `AgentServer.destinationURL` over
    // paths whose suffix is a caption spelling or is not. `replaceableExtensions`
    // is private; the function that consults it is not, and its answer's
    // last path component is the name that would be written.
    let destinations = request["destinations"] as? [[String: Any]] ?? []
    out["destinations"] = destinations.map { row -> [String: Any] in
        let path = row["path"] as? String ?? ""
        let ext = row["extension"] as? String ?? ""
        return [
            "path": path, "extension": ext,
            "written": AgentServer.destinationURL(path, extension: ext).lastPathComponent,
        ]
    }

    // 1c. The document's title-bar stem, as a pure function.
    let stems = request["stems"] as? [String] ?? []
    out["stems"] = stems.map { ["name": $0, "stem": ProjectDocument.displayStem(of: $0)] }
    out["projectExtension"] = ProjectDocument.projectFileExtension
    out["untitled"] = ProjectDocument.untitledDisplayName

    // 1d. The instance accessor over live documents, so the static function
    // is proved to be what the panels actually read. A fresh document has
    // whatever title AppKit gives one outside a document controller — that
    // is REPORTED, and the assertion is only that the accessor is the
    // function over it. A document told its file is
    // `<dir>/Board v1.2.reelcut` reads a `displayName` that depends on
    // whether Finder shows extensions, and must answer `Board v1.2` either
    // way — which is the whole point of the `{reelcut}` set.
    let fresh = ProjectDocument()
    out["freshDisplayName"] = fresh.displayName.map { $0 as Any } ?? NSNull()
    out["freshStem"] = fresh.displayStem
    if let dir = request["dir"] as? String {
        let named = ProjectDocument()
        named.fileURL = URL(fileURLWithPath: dir).appendingPathComponent("Board v1.2.reelcut")
        out["namedDisplayName"] = named.displayName.map { $0 as Any } ?? NSNull()
        out["namedStem"] = named.displayStem
    }
    return out
}

// ---- mode "cachestamp": §2a's stamp as pure calls -------------------------
//
// `CacheStamp.stamp(for:url:)` over a table of files the script prepared:
// an original, a byte copy at another path with its times preserved, the
// same bytes with a later mtime, and a path that is not there. The record
// is the same for all four, so what differs is the FILE's identity alone.
// Each stamp is answered as the dictionary its JSON encoding decodes to —
// the encoding the marker on disk carries — so the script reads the real
// key set rather than one typed here.
func cachestamp(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let record = request["record"] as? [String: Any] ?? [:]
    let media = MediaSnapshot(
        id: 7, path: "", kind: .video,
        duration: Ticks(record["duration"] as? Int ?? 0),
        width: record["width"] as? Int ?? 0, height: record["height"] as? Int ?? 0,
        fps: Fps(num: 30, den: 1),
        hasVideo: record["hasVideo"] as? Bool ?? true,
        hasAudio: record["hasAudio"] as? Bool ?? false)
    let files = request["files"] as? [String: String] ?? [:]
    var stamps: [String: Any] = [:]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for (name, path) in files {
        guard let stamp = MediaImporter.CacheStamp.stamp(
            for: media, url: URL(fileURLWithPath: path))
        else {
            stamps[name] = NSNull()
            continue
        }
        guard let data = try? encoder.encode(stamp),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            stamps[name] = ["error": "the stamp did not round-trip through JSON"]
            continue
        }
        stamps[name] = object
    }
    out["stamps"] = stamps
    // The two marker paths, so the script can pin their shape (a `.json`
    // inside the strip's directory; a sidecar beside the `.bin`).
    let cache = URL(fileURLWithPath: "/cache")
    out["thumbsMarker"] = MediaImporter.thumbsMarkerURL(for: 7, in: cache).path
    out["peaksMarker"] = MediaImporter.peaksMarkerURL(for: 7, in: cache).path
    out["peaksBin"] = MediaImporter.peaksURL(for: 7, in: cache).path
    return out
}

// ---- mode "cacheledger": one pass per media, counted by its posts ---------
//
// `generateCaches` is called for one media ONCE into a fresh directory and
// its `thumbs` posts counted until the notification has been quiet for
// 1.5 s; then THREE times in a row into a second fresh directory. Under the
// ledger the second and third passes queue behind the first and find its
// marker at their head, so the count is one pass's worth; without it all
// three run at once and it is about three times that. A fourth call after
// the quiet is the head check on its own: no post, and `0.jpg`'s inode
// unchanged. The observer is on `nil` queue: the post is already a hop to
// the main thread, which the spin below drains.
func cacheledger(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let record = request["record"] as? [String: Any] ?? [:]
    let media = MediaSnapshot(
        id: 7, path: request["source"] as? String ?? "", kind: .video,
        duration: Ticks(record["duration"] as? Int ?? 0),
        width: record["width"] as? Int ?? 0, height: record["height"] as? Int ?? 0,
        fps: Fps(num: 30, den: 1),
        hasVideo: record["hasVideo"] as? Bool ?? true,
        hasAudio: record["hasAudio"] as? Bool ?? false)
    let source = URL(fileURLWithPath: request["source"] as? String ?? "")
    let dirOne = URL(fileURLWithPath: request["dirOne"] as? String ?? "", isDirectory: true)
    let dirThree = URL(fileURLWithPath: request["dirThree"] as? String ?? "", isDirectory: true)

    var posts: [[String: Any]] = []
    var lastPost = Date()
    let token = NotificationCenter.default.addObserver(
        forName: .mediaCacheDidChange, object: nil, queue: nil
    ) { note in
        let info = note.userInfo ?? [:]
        posts.append([
            "media": Int(info[MediaImporter.mediaIDKey] as? UInt32 ?? 0),
            "kind": info[MediaImporter.cacheKindKey] as? String ?? "",
            "replaced": info[MediaImporter.replacedKey] as? Bool ?? false,
        ])
        lastPost = Date()
    }
    defer { NotificationCenter.default.removeObserver(token) }

    /// Spins until no post has arrived for `quiet` seconds (cap 60 s).
    func settle(_ quiet: TimeInterval) -> Bool {
        let cap = Date().addingTimeInterval(60)
        lastPost = Date()
        while Date() < cap {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if Date().timeIntervalSince(lastPost) >= quiet { return true }
        }
        return false
    }
    func thumbsPosts(since index: Int) -> Int {
        posts[index...].filter { ($0["kind"] as? String) == MediaImporter.thumbsKind }.count
    }
    func jpgCount(_ dir: URL) -> Int {
        MediaImporter.thumbnailCount(for: 7, in: dir)
    }
    func inode(_ dir: URL) -> Int {
        let path = MediaImporter.thumbsDirectory(for: 7, in: dir).appendingPathComponent("0.jpg").path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.intValue ?? -1
    }

    // One pass.
    var mark = posts.count
    MediaImporter.generateCaches(for: media, url: source, in: dirOne)
    out["oneSettled"] = settle(1.5)
    out["one"] = thumbsPosts(since: mark)
    out["oneJPEGs"] = jpgCount(dirOne)
    out["oneMarker"] = MediaImporter.readStamp(
        at: MediaImporter.thumbsMarkerURL(for: 7, in: dirOne)) != nil

    // Three, as fast as the calls can be made.
    mark = posts.count
    MediaImporter.generateCaches(for: media, url: source, in: dirThree)
    MediaImporter.generateCaches(for: media, url: source, in: dirThree)
    MediaImporter.generateCaches(for: media, url: source, in: dirThree)
    out["threeSettled"] = settle(1.5)
    out["three"] = thumbsPosts(since: mark)
    out["threeJPEGs"] = jpgCount(dirThree)
    out["threeMarker"] = MediaImporter.readStamp(
        at: MediaImporter.thumbsMarkerURL(for: 7, in: dirThree)) != nil
    out["threeReplacedPosts"] = posts[mark...].filter { ($0["replaced"] as? Bool) == true }.count

    // A fourth, after everything settled: the head check alone.
    let before = inode(dirThree)
    mark = posts.count
    MediaImporter.generateCaches(for: media, url: source, in: dirThree)
    out["fourthSettled"] = settle(1.5)
    out["fourth"] = thumbsPosts(since: mark)
    out["fourthInodeBefore"] = before
    out["fourthInodeAfter"] = inode(dirThree)
    out["posts"] = posts
    return out
}

// ---- mode "staletile": the timeline's memo, as pixels ----------------------
//
// A bare `TimelineView` (phase 9's chrome probe's scene) over one video
// media and one clip, with a cache directory the probe fills: `0.jpg` solid
// RED. Rendered; then `0.jpg` overwritten solid BLUE and rendered again in
// a FRESH view (the reference for "the tile is blue"); then the first view
// is told `.mediaCacheDidChange` for that media WITHOUT the replaced flag
// and rendered — the memo rule says the tile it already decoded is the same
// tile, so it stays red — and then WITH the flag, after which it must be
// blue. The script compares the four PNGs inside the clip's rectangle,
// which is answered here in pixels.
func staletile(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let cacheDir = URL(fileURLWithPath: request["cacheDir"] as? String ?? "", isDirectory: true)
    let outDir = URL(fileURLWithPath: request["outDir"] as? String ?? "", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let thumbs = MediaImporter.thumbsDirectory(for: 1, in: cacheDir)
    try? FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
    let jpg = thumbs.appendingPathComponent("0.jpg")

    func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: 284, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 284, height: 160))
        return context.makeImage()
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    NSApp.appearance = NSAppearance(named: .aqua)

    let projectJSON = """
    {"version": 6,
     "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                "background": [0,0,0,1], "fit_new_clips": true, "timecode_frames": true},
     "media": [{"id": 1, "path": "/nowhere/red.mov", "kind": "video", "duration": 3600000,
                "width": 640, "height": 360, "fps": [30, 1], "has_video": true,
                "has_audio": false}],
     "tracks": [{"id": 2, "name": "V"}],
     "clips": [{"id": 3, "track": 2, "start": 0, "duration": 3600000,
                "source": {"kind": "media", "media": 1, "in": 0}, "video": {}}],
     "markers": [], "next_id": 10, "nests": []}
    """
    struct Scene {
        let timeline: TimelineView
        let window: NSWindow
    }
    func makeScene(_ snapshot: ProjectSnapshot) -> Scene {
        let timeline = TimelineView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 360),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 360))
        window.contentView = host
        timeline.frame = host.bounds
        timeline.autoresizingMask = [.width, .height]
        host.addSubview(timeline)
        host.layoutSubtreeIfNeeded()
        timeline.trackHeightIndex = 1
        timeline.update(
            snapshot: snapshot, selection: [], playhead: 0, inOutRange: nil,
            cacheDirectory: cacheDir)
        timeline.layoutSubtreeIfNeeded()
        return Scene(timeline: timeline, window: window)
    }
    func capture(_ view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
    func settled(_ view: NSView) -> (NSBitmapImageRep, Bool) {
        var rep = capture(view)
        var previous = rep.representation(using: .png, properties: [:])!
        for _ in 0..<40 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            rep = capture(view)
            let next = rep.representation(using: .png, properties: [:])!
            if next == previous { return (rep, true) }
            previous = next
        }
        return (rep, false)
    }
    func shoot(_ name: String, _ view: NSView) -> [String: Any] {
        let (rep, didSettle) = settled(view)
        var record: [String: Any] = ["settled": didSettle, "pixelsWide": rep.pixelsWide,
                                     "pixelsHigh": rep.pixelsHigh]
        do {
            try rep.representation(using: .png, properties: [:])!
                .write(to: outDir.appendingPathComponent("\(name).png"))
            record["path"] = outDir.appendingPathComponent("\(name).png").path
        } catch {
            record["error"] = "\(error)"
        }
        return record
    }
    func post(replaced: Bool) {
        var info: [String: Any] = [
            MediaImporter.mediaIDKey: UInt32(1), MediaImporter.cacheKindKey: MediaImporter.thumbsKind,
        ]
        if replaced { info[MediaImporter.replacedKey] = true }
        NotificationCenter.default.post(name: .mediaCacheDidChange, object: nil, userInfo: info)
        for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    do {
        guard let red = solid(1, 0, 0), let blue = solid(0, 0, 1) else {
            out["error"] = "could not draw the two solid tiles"
            return out
        }
        MediaImporter.writeJPEG(red, to: jpg)
        let project = try ReelProject.from(json: projectJSON)
        let snapshot = project.snapshot
        let first = makeScene(snapshot)
        let timeline = first.timeline
        let clip = snapshot.clips[0]
        let rect = timeline.convert(timeline.layout.clipRect(clip, row: 0), from: timeline.content)
        out["red"] = shoot("red", timeline)
        let scale = CGFloat((out["red"] as? [String: Any])?["pixelsWide"] as? Int ?? 0)
            / timeline.bounds.width
        out["scale"] = scale
        out["clipPx"] = [
            Int((rect.minX * scale).rounded()),
            Int(((timeline.bounds.height - rect.maxY) * scale).rounded()),
            Int((rect.width * scale).rounded()),
            Int((rect.height * scale).rounded()),
        ]
        // The film changes under the view: blue where red was.
        try? FileManager.default.removeItem(at: jpg)
        MediaImporter.writeJPEG(blue, to: jpg)
        let reference = makeScene(snapshot)
        out["blue"] = shoot("blue", reference.timeline)
        // The first view is told, without the flag — its memo holds.
        post(replaced: false)
        out["memo"] = shoot("memo", timeline)
        // And with it — the memo is dropped.
        post(replaced: true)
        out["replaced"] = shoot("replaced", timeline)
        _ = first.window
        _ = reference.window
    } catch {
        out["error"] = "\(error)"
    }
    return out
}

// ---- mode "cachepass": when a pass may certify a strip, and what it tells --
//
// Five passes of `generateCaches`, each into a fresh directory the script
// prepared, each answered as what is on disk afterwards and every
// `.mediaCacheDidChange` post it made in order:
//
//   hole       A.mov, with `0.jpg` deleted the instant it appears — a 1 ms
//              poll on a thread of its own, the frame a titled document's
//              save loses between NSDocument's listing and its swap — and
//              then the SAME pass again, untouched: the retry.
//   unreadable a record with `hasVideo` over a file that is text, which
//              AVFoundation cannot open — a pass that writes nothing.
//   image      an IMAGE record over a text file, with a `0.jpg` seeded — a
//              relink whose decode fails, with the old tile on disk.
//   twice      A.mov under a 20 s record, with a `0.jpg` seeded. A relink
//              never re-probes, so a record longer than its file is a state
//              the app can be in. A request past the file's end FAILS (a
//              hole; measured — only the one at 10 s lands, inside the
//              half-second tolerance, so eleven frames), but every result
//              counts toward the every-16 post, so the pass posts at 16
//              results and at the end — two posts from one replacing pass,
//              which no fixture of the right length can give.
//   withdrawn  AV.mov's peaks built; then the same record over a video-only
//              file (a relink to a file with no audio track, `hasAudio` still
//              true on the record); then AV.mov again.
//
// The observer is on `nil` queue, as `cacheledger`'s is: the post is a hop
// to the main thread, which the spin drains.
func cachepass(_ request: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    let manager = FileManager.default
    func snapshot(_ record: [String: Any], path: String, kind: MediaKind) -> MediaSnapshot {
        MediaSnapshot(
            id: 7, path: path, kind: kind,
            duration: Ticks(record["duration"] as? Int ?? 0),
            width: record["width"] as? Int ?? 0, height: record["height"] as? Int ?? 0,
            fps: Fps(num: 30, den: 1),
            hasVideo: record["hasVideo"] as? Bool ?? true,
            hasAudio: record["hasAudio"] as? Bool ?? false)
    }
    let record = request["record"] as? [String: Any] ?? [:]
    let avRecord = request["avRecord"] as? [String: Any] ?? [:]
    let source = request["source"] as? String ?? ""
    let avSource = request["avSource"] as? String ?? ""
    let unreadable = request["unreadable"] as? String ?? ""
    let garbageImage = request["garbageImage"] as? String ?? ""
    let dirs = request["dirs"] as? [String: String] ?? [:]
    func dir(_ name: String) -> URL { URL(fileURLWithPath: dirs[name] ?? "", isDirectory: true) }

    var posts: [[String: Any]] = []
    var lastPost = Date()
    let token = NotificationCenter.default.addObserver(
        forName: .mediaCacheDidChange, object: nil, queue: nil
    ) { note in
        let info = note.userInfo ?? [:]
        posts.append([
            "kind": info[MediaImporter.cacheKindKey] as? String ?? "",
            "replaced": info[MediaImporter.replacedKey] as? Bool ?? false,
        ])
        lastPost = Date()
    }
    defer { NotificationCenter.default.removeObserver(token) }
    func settle(_ quiet: TimeInterval) -> Bool {
        let cap = Date().addingTimeInterval(60)
        lastPost = Date()
        while Date() < cap {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if Date().timeIntervalSince(lastPost) >= quiet { return true }
        }
        return false
    }
    /// One pass, answered as its posts and the directory's state after it.
    func pass(_ media: MediaSnapshot, url: String, into cacheDir: URL) -> [String: Any] {
        let mark = posts.count
        MediaImporter.generateCaches(for: media, url: URL(fileURLWithPath: url), in: cacheDir)
        let settled = settle(1.5)
        let thumbs = MediaImporter.thumbsDirectory(for: 7, in: cacheDir)
        let bin = MediaImporter.peaksURL(for: 7, in: cacheDir)
        return [
            "settled": settled,
            "posts": Array(posts[mark...]),
            "thumbsMarker": manager.fileExists(
                atPath: MediaImporter.thumbsMarkerURL(for: 7, in: cacheDir).path),
            "jpgCount": MediaImporter.thumbnailCount(for: 7, in: cacheDir),
            "zeroExists": manager.fileExists(atPath: thumbs.appendingPathComponent("0.jpg").path),
            "binExists": manager.fileExists(atPath: bin.path),
            "binBytes": (try? Data(contentsOf: bin))?.count ?? -1,
            "peaksMarker": manager.fileExists(
                atPath: MediaImporter.peaksMarkerURL(for: 7, in: cacheDir).path),
        ]
    }
    func seedZero(in cacheDir: URL) {
        let thumbs = MediaImporter.thumbsDirectory(for: 7, in: cacheDir)
        try? manager.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try? Data(repeating: 0xAB, count: 512).write(to: thumbs.appendingPathComponent("0.jpg"))
    }

    // hole. The poller is a Thread rather than a task: the pass runs on the
    // cooperative pool and the main thread is spinning, so a third thread
    // is the one place a 1 ms loop can sit without holding either up.
    final class ZeroDeleter {
        let path: String
        private let lock = NSLock()
        private var deleted: Bool?
        private var stop = false
        init(path: String) { self.path = path }
        func start() {
            let thread = Thread { [self] in
                while true {
                    lock.lock()
                    let stopped = stop
                    lock.unlock()
                    if stopped { return }
                    if FileManager.default.fileExists(atPath: path) {
                        let removed = (try? FileManager.default.removeItem(atPath: path)) != nil
                        lock.lock()
                        deleted = removed
                        lock.unlock()
                        return
                    }
                    usleep(1000)
                }
            }
            thread.start()
        }
        /// Stops the poll and answers whether `0.jpg` was seen and removed
        /// (nil: it never appeared while the poll ran).
        func finish() -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            stop = true
            return deleted
        }
    }
    let holeDir = dir("hole")
    let holeMedia = snapshot(record, path: source, kind: .video)
    let deleter = ZeroDeleter(
        path: MediaImporter.thumbsDirectory(for: 7, in: holeDir).appendingPathComponent("0.jpg").path)
    deleter.start()
    var hole = pass(holeMedia, url: source, into: holeDir)
    hole["deletedZero"] = deleter.finish().map { $0 as Any } ?? NSNull()
    out["hole"] = hole
    out["holeRetry"] = pass(holeMedia, url: source, into: holeDir)

    // unreadable.
    out["unreadable"] = pass(snapshot(record, path: unreadable, kind: .video),
                             url: unreadable, into: dir("unreadable"))

    // image.
    let imageDir = dir("image")
    seedZero(in: imageDir)
    out["image"] = pass(snapshot(["duration": 0, "width": 640, "height": 360, "hasVideo": true],
                                 path: garbageImage, kind: .image),
                        url: garbageImage, into: imageDir)

    // twice.
    let twiceDir = dir("twice")
    seedZero(in: twiceDir)
    var long = record
    long["duration"] = 20 * Int(ReelTime.perSecond)
    out["twice"] = pass(snapshot(long, path: source, kind: .video), url: source, into: twiceDir)

    // withdrawn.
    let withdrawnDir = dir("withdrawn")
    let av = snapshot(avRecord, path: avSource, kind: .video)
    out["withdrawnBuilt"] = pass(av, url: avSource, into: withdrawnDir)
    out["withdrawn"] = pass(av, url: source, into: withdrawnDir)
    out["withdrawnBack"] = pass(av, url: avSource, into: withdrawnDir)
    return out
}

// ---- dispatch -------------------------------------------------------------
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: probe <request.json> <answer.json>\n".utf8))
    exit(2)
}
var answer: [String: Any] = [:]
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let mode = request["mode"] as? String ?? ""
    switch mode {
    case "naming":
        answer = naming(request)
    case "cachestamp":
        answer = cachestamp(request)
    case "cacheledger":
        answer = cacheledger(request)
    case "staletile":
        answer = staletile(request)
    case "cachepass":
        answer = cachepass(request)
    default:
        answer["error"] = "unknown mode \"\(mode)\" — the binary predates the section asking"
    }
    answer["mode"] = mode
} catch {
    answer["error"] = "\(error)"
}
let out = try JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
try out.write(to: URL(fileURLWithPath: args[2]))
'''


def probe_dir(sources):
    """The tree's probe lives at `work/remainingprobe/tree/`; a mutant copy
    gets its own directory named by a digest of its path, so pointing the
    script at a copy never invalidates — or, worse, reuses — the tree's
    cached binary."""
    if os.path.realpath(sources) == os.path.realpath(TREE_SOURCES):
        return os.path.join(PROBE, "tree")
    digest = hashlib.sha1(os.path.realpath(sources).encode()).hexdigest()[:10]
    return os.path.join(PROBE, f"mutant-{digest}")


def build_probe(sources):
    """`phase9_probe.py`'s builder: the same swiftc line as `harness/build.sh`,
    the same staleness rule, and a reason instead of an exit when it will
    not build."""
    here = probe_dir(sources)
    os.makedirs(here, exist_ok=True)
    binary = os.path.join(here, "remainingprobe")
    entry = os.path.join(here, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    if not os.path.isdir(sources):
        return None, f"{sources} is not a directory"
    files = sorted(
        os.path.join(sources, name)
        for name in os.listdir(sources)
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in files + [entry, lib]
    ):
        print(f"remaining probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + files + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"remaining probe: {binary} (built in {time.time() - start:.1f} s from {sources})")
    return binary, None


def run_probe(binary, tag, request):
    """One request in, one answer out, both kept beside the binary under
    the section's tag so a failed row can be read back after the run."""
    here = os.path.dirname(binary)
    req = os.path.join(here, f"request-{tag}.json")
    out = os.path.join(here, f"answer-{tag}.json")
    with open(req, "w") as f:
        json.dump(request, f, indent=1)
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, req, out], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, "the probe did not answer within 120 s"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


# --------------------------------------------------------------------------
# Section 1 — §2b: the three stem helpers.

# `why` is printed with the check and is the argument for the row; a row with
# none is a plain pin. Every expectation is the value the FIXED build gives;
# the bare-strip mutants' answers are in the docstring's gate paragraph.
CAPTION_ROWS = [
    {"name": "Board v1.2", "format": "srt", "fallback": "X", "expect": "Board v1.2.srt",
     "why": "the `.2` survives — the row a bare `deletingPathExtension` fails "
            "(it answers `Board v1.srt`)"},
    {"name": "talk", "format": "srt", "fallback": "X", "expect": "talk.srt"},
    {"name": "talk.srt", "format": "srt", "fallback": "X", "expect": "talk.srt",
     "why": "same format is the identity"},
    {"name": "talk.srt", "format": "vtt", "fallback": "X", "expect": "talk.vtt",
     "why": "a caption spelling is replaced"},
    {"name": "talk.vtt", "format": "srt", "fallback": "X", "expect": "talk.srt"},
    {"name": "talk.SRT", "format": "vtt", "fallback": "X", "expect": "talk.vtt",
     "why": "the suffix is compared lower-cased, as `destinationURL` compares"},
    {"name": "Board v1.2.srt", "format": "vtt", "fallback": "X", "expect": "Board v1.2.vtt"},
    {"name": "talk.txt", "format": "srt", "fallback": "X", "expect": "talk.txt.srt",
     "why": "a foreign extension is part of the NAME — `destinationURL` writes "
            "`talk.txt.srt` for the same path over MCP"},
    {"name": "shot.final", "format": "vtt", "fallback": "X", "expect": "shot.final.vtt",
     "why": "a bare strip answers `shot.vtt`"},
    {"name": "chart.png", "format": "srt", "fallback": "X", "expect": "chart.png.srt",
     "why": "another of the app's OWN containers is not a caption spelling — "
            "the one row where the panel (keeps) and MCP (`chart.srt`, `png` being "
            "replaceable there) part company, pinned as a recorded limit"},
    {"name": "", "format": "srt", "fallback": "X", "expect": "X.srt",
     "why": "an emptied field falls back to the document's stem"},
    {"name": ".srt", "format": "vtt", "fallback": "X", "expect": ".srt.vtt",
     "why": "Foundation reads NO extension off a dot-leading name — pinned, "
            "not special-cased"},
    {"name": "talk.", "format": "vtt", "fallback": "X", "expect": "talk..vtt",
     "why": "a trailing dot is not an extension either — an edge, unchanged"},
    {"name": "a.b.srt", "format": "vtt", "fallback": "X", "expect": "a.b.vtt",
     "why": "only the LAST suffix is looked at"},
]

FRAME_ROWS = [
    {"name": "Board v1.2", "format": "png", "fallback": "X", "expect": "Board v1.2.png",
     "why": "the `.2` survives here too — phase 7's fix, proved for the first time"},
    {"name": "shot.heic", "format": "jpeg", "fallback": "X", "expect": "shot.jpg",
     "why": "JPEG writes `jpg` — `fileExtension`, not the rawValue"},
    {"name": "shot.jpeg", "format": "png", "fallback": "X", "expect": "shot.png",
     "why": "JPEG's second spelling is read"},
    {"name": "shot.JPG", "format": "heic", "fallback": "X", "expect": "shot.heic",
     "why": "compared lower-cased"},
    {"name": "shot.heif", "format": "png", "fallback": "X", "expect": "shot.heif.png",
     "why": "`heif` is left out of the set on both sides, so it is part of the name"},
    {"name": "shot.png", "format": "png", "fallback": "X", "expect": "shot.png"},
    {"name": "shot.final", "format": "jpeg", "fallback": "X", "expect": "shot.final.jpg"},
    {"name": "", "format": "png", "fallback": "X", "expect": "X.png"},
    {"name": ".png", "format": "jpeg", "fallback": "X", "expect": ".png.jpg",
     "why": "a dot-leading name has no extension to Foundation"},
]

# 1f. `destinationURL` rows are BUILT from `CaptionExporter.knownExtensions`
# rather than typed: one strip-and-replace pair per member, in both cases,
# and one append row per member for a suffix outside the set. The set the
# rows were built from is compared against the set the probe read off the
# type, so a member with no row is a named failure and not a silent gap.
def destination_rows(known):
    rows = []
    for member in sorted(known):
        others = sorted(set(known) - {member}) or [member]
        for other in others:
            rows.append({"path": f"/tmp/x.{member}", "extension": other,
                         "expect": f"x.{other}",
                         "why": f"`{member}` is a member of `replaceableExtensions`, so it "
                                f"is STRIPPED and `{other}` put in its place — not "
                                f"`x.{member}.{other}`"})
            rows.append({"path": f"/tmp/x.{member.upper()}", "extension": other,
                         "expect": f"x.{other}",
                         "why": "membership is read lower-cased"})
        rows.append({"path": "/tmp/x.txt", "extension": member,
                     "expect": f"x.txt.{member}",
                     "why": "a suffix outside the set is part of the NAME and the "
                            "extension is appended — the other half of the rule"})
    return rows


STEM_ROWS = [
    {"name": "Board v1.2.reelcut", "expect": "Board v1.2",
     "why": "a saved package with its extension shown"},
    {"name": "Board v1.2", "expect": "Board v1.2",
     "why": "an untitled document from `Board v1.2.mov`, or a package with its "
            "extension hidden — the row a bare strip fails (`Board v1`)"},
    {"name": "Untitled Project", "expect": "Untitled Project"},
    {"name": "x.REELCUT", "expect": "x", "why": "compared lower-cased"},
    {"name": ".reelcut", "expect": ".reelcut",
     "why": "Foundation reads no extension off a dot-leading name"},
    {"name": "talk.srt", "expect": "talk.srt",
     "why": "a caption spelling is NOT this helper's to strip — the set is "
            "`{reelcut}`, so a document literally so named is offered `talk.srt.srt`"},
    {"name": "talk.mov", "expect": "talk.mov",
     "why": "nor is a movie's — `defaultDraftName()` already stripped the real one"},
    {"name": "a.reelcut.reelcut", "expect": "a.reelcut", "why": "one suffix, once"},
    {"name": "", "expect": ""},
]


def section_naming(binary, sources):
    print("\n1. Naming — §2b, the three stem helpers")
    # 1f's rows are built from the set 1a pins (`{srt, vtt}`); the probe's
    # own reading of the set is compared against them below.
    destinations = destination_rows(["srt", "vtt"])
    request = {
        "mode": "naming",
        "caption": [{k: r[k] for k in ("name", "format", "fallback")} for r in CAPTION_ROWS],
        "frame": [{k: r[k] for k in ("name", "format", "fallback")} for r in FRAME_ROWS],
        "stems": [r["name"] for r in STEM_ROWS],
        "destinations": [{k: r[k] for k in ("path", "extension")} for r in destinations],
        "dir": os.path.dirname(binary),
    }
    answer, error = run_probe(binary, "naming", request)
    check("the probe answers mode `naming`", answer is not None and "error" not in answer,
          error or (answer or {}).get("error", ""))
    if answer is None:
        return

    print("\n  1a. `CaptionExporter.renamed` — the format popup's rewrite")
    check("`CaptionExporter.knownExtensions` is exactly the two caption spellings, "
          "read off the type — `{srt, vtt}`, not `FrameWriter`'s image set",
          answer.get("captionKnown") == ["srt", "vtt"], f'{answer.get("captionKnown")}')
    check("and it is derived from `Format.allCases`, so a third container would join it "
          "without a second list to keep in step",
          sorted(answer.get("captionFormats", [])) == answer.get("captionKnown"),
          f'{answer.get("captionFormats")}')
    check_table("caption", CAPTION_ROWS, answer.get("caption", []),
                ("name", "format", "fallback"), "renamed")

    print("\n  1b. `FrameWriter.renamed` — phase 7's original, over the same table shape")
    check("`FrameWriter.knownExtensions` is the four still spellings",
          answer.get("frameKnown") == ["heic", "jpeg", "jpg", "png"], f'{answer.get("frameKnown")}')
    ext = answer.get("frameExtensions", {})
    check("JPEG's `fileExtension` really is `jpg` (the table below assumes it)",
          ext == {"png": "png", "jpeg": "jpg", "heic": "heic"}, f"{ext}")
    check_table("still", FRAME_ROWS, answer.get("frame", []),
                ("name", "format", "fallback"), "renamed")

    print("\n  1c. `ProjectDocument.displayStem(of:)` — the title-bar stem")
    check("the package extension the helper strips is `reelcut`",
          answer.get("projectExtension") == "reelcut", f'{answer.get("projectExtension")}')
    check("the untitled fallback is `defaultDraftName()`'s own spelling",
          answer.get("untitled") == "Untitled Project", f'{answer.get("untitled")}')
    check_table("stem", STEM_ROWS, answer.get("stems", []), ("name",), "stem")

    print("\n  1d. the instance accessor, over live documents")
    fresh_name = answer.get("freshDisplayName")
    fresh_expected = "Untitled Project" if fresh_name is None else fresh_name
    print(f"       (a fresh `ProjectDocument()` outside a controller is titled {fresh_name!r})")
    check("a fresh document's `displayStem` is the function over its title, or over the "
          "untitled fallback when AppKit has not named it yet",
          answer.get("freshStem") == expected_stem(fresh_expected), f'{answer.get("freshStem")}')
    named_name = answer.get("namedDisplayName")
    print(f"       (a document at `Board v1.2.reelcut` is titled {named_name!r} on this Mac)")
    check("a document whose file is `Board v1.2.reelcut` answers `Board v1.2` — whether "
          "Finder shows it the extension or hides it, which is the whole reason the set "
          "is `{reelcut}`",
          answer.get("namedStem") == "Board v1.2", f'{answer.get("namedStem")}')
    check("and its title really was one of the two spellings the helper is for",
          named_name in ("Board v1.2.reelcut", "Board v1.2"), f"{named_name!r}")

    print("\n  1f. `AgentServer.destinationURL` — `knownExtensions` ⊆ `replaceableExtensions`, "
          "pinned")
    check_table("destination", destinations, answer.get("destinations", []),
                ("path", "extension"), "written")
    stripped = {r["path"].rsplit(".", 1)[1].lower() for r in destinations
                if r["expect"].count(".") == 1}
    check("the rows above strip-and-replace EVERY member of the set the probe read off "
          "`CaptionExporter.knownExtensions` — a third format would fail here by name "
          "until it joined `replaceableExtensions`",
          set(answer.get("captionKnown", [])) <= stripped,
          f"members {answer.get('captionKnown')}, rows strip {sorted(stripped)}")

    section_wiring(sources)


# 1e. The wiring, read from the sources the probe was compiled from. A
# function body here runs from its signature line to the first line holding
# only the closing brace at the signature's own indent — the shape every
# method in `app/Sources` has at four-space indent.
SITES = [
    # (file, signature fragment, what the body must name)
    ("CaptionExporter.swift", "@objc private func formatChanged", "CaptionExporter.renamed("),
    ("CaptionExporter.swift", "func exportCaptionsCommand()", "document.displayStem"),
    ("EditorViewController+SaveFrame.swift", "func saveFrameCommand()", "document.displayStem"),
    ("ExportSheetController.swift", "private func suggestedName(", ".displayStem"),
]

# Where a bare `deletingPathExtension` MAY stand in the four files: the two
# helpers, once each. Comments are stripped before counting, because the
# doc comments name the bare call in order to argue against it.
BARE_ALLOWED = {
    "CaptionExporter.swift": 1,
    "ProjectDocument+DisplayStem.swift": 1,
    "EditorViewController+SaveFrame.swift": 0,
    "ExportSheetController.swift": 0,
}


def code_lines(text):
    """The source with `//` comments removed — a doc line saying
    `deletingPathExtension` is an argument, not a call."""
    out = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        out.append(line.split("//")[0] if "//" in line and '"' not in line else line)
    return out


def function_body(lines, signature):
    start = next((i for i, l in enumerate(lines) if signature in l), None)
    if start is None:
        return None
    indent = len(lines[start]) - len(lines[start].lstrip())
    for j in range(start + 1, len(lines)):
        if lines[j].strip() == "}" and len(lines[j]) - len(lines[j].lstrip()) == indent:
            return lines[start:j + 1]
    return lines[start:]


def section_wiring(sources):
    print("\n  1e. the wiring — a structural read of the four sites (no probe can press a panel)")
    texts = {}
    for name in BARE_ALLOWED:
        path = os.path.join(sources, name)
        texts[name] = code_lines(open(path).read()) if os.path.exists(path) else None
        check(f"`{name}` is in the sources", texts[name] is not None, path)
    for name, signature, helper in SITES:
        lines = texts.get(name)
        body = function_body(lines, signature) if lines else None
        check(f"`{name}`: `{signature.strip()}` is there", body is not None)
        if body is None:
            continue
        joined = "\n".join(body)
        site = f"`{name}`: `{signature.strip()}`"
        check(f"  {site} calls `{helper}`", helper in joined)
        check(f"  {site} carries no `deletingPathExtension` of its own",
              "deletingPathExtension" not in joined,
              next((l.strip() for l in body if "deletingPathExtension" in l), ""))
    for name, allowed in BARE_ALLOWED.items():
        lines = texts.get(name)
        if lines is None:
            continue
        count = sum(l.count("deletingPathExtension") for l in lines)
        check(f"`{name}` holds exactly {allowed} bare `deletingPathExtension` in code "
              f"(comments stripped) — {'the helper' if allowed else 'none'}",
              count == allowed, f"found {count}")


def expected_stem(name):
    """The rule restated in Python for the one check whose input the probe
    chooses (a fresh document's title): strip a trailing `.reelcut`, once,
    case-insensitively, and only that."""
    lower = name.lower()
    if lower.endswith(".reelcut") and len(name) > len(".reelcut"):
        return name[: -len(".reelcut")]
    return name


# --------------------------------------------------------------------------
# Sections 2–4 — §2a: the cache completion marker's three app-side facts.
# The MCP half (`remaining_proof.py`) owns everything a running instance can
# be asked to show — a saved package's markers landing, not moving, and
# moving. What is here is what no tool reaches: the stamp as a function, the
# ledger under three synchronous calls, and the timeline's memo as pixels.

# `A.mov`'s record, as `import_media` reports it: 10 s at 640 × 360, video
# only. The stamp carries the RECORD's fields, so the probe is handed them
# rather than probing the file — that is `MediaImporter.probe`'s job and not
# this section's claim.
A_RECORD = {"duration": 6_000_000, "width": 640, "height": 360,
            "hasVideo": True, "hasAudio": False}


def fixture(name):
    path = os.path.join(MEDIA, name)
    check(f"`media/{name}` is there (tools/proof/README.md says how to make it)",
          os.path.exists(path), path)
    return path if os.path.exists(path) else None


def fresh_dir(*parts):
    path = os.path.join(FILES, *parts)
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path)
    return path


def section_cachestamp(binary, sources):
    print("\n2. The stamp — §2a, `CacheStamp` as pure calls")
    source = fixture("A.mov")
    if source is None:
        return
    here = fresh_dir("stamp")
    original = os.path.join(here, "original.mov")
    copy = os.path.join(here, "copy-elsewhere.mov")
    touched = os.path.join(here, "touched.mov")
    missing = os.path.join(here, "missing.mov")
    shutil.copy2(source, original)
    shutil.copy2(original, copy)
    shutil.copy2(original, touched)
    st = os.stat(original)
    os.utime(touched, ns=(st.st_atime_ns, st.st_mtime_ns + 7_000_000_000))
    request = {
        "mode": "cachestamp", "record": A_RECORD,
        "files": {"original": original, "copy": copy, "touched": touched, "missing": missing},
    }
    answer, error = run_probe(binary, "cachestamp", request)
    check("the probe answers mode `cachestamp`", answer is not None and "error" not in answer,
          error or (answer or {}).get("error", ""))
    if answer is None:
        return
    stamps = answer.get("stamps", {})
    original_stamp = stamps.get("original")
    check("the original's stamp is an object", isinstance(original_stamp, dict), f"{original_stamp}")
    if not isinstance(original_stamp, dict):
        return
    keys = sorted(original_stamp)
    print(f"       (the encoding's keys: {keys})")
    check("the encoding has NO key naming a path — a moved package, a consolidated copy and "
          "a copy on another disk all keep their filmstrips because of this",
          not any("path" in k.lower() for k in keys), f"{keys}")
    check("and no string value at all", not any(isinstance(v, str) for v in original_stamp.values()),
          f"{original_stamp}")
    check("it carries `size`, `modified` and `duration`",
          {"size", "modified", "duration"} <= set(keys), f"{keys}")
    check("`size` is the file's byte size", original_stamp.get("size") == st.st_size,
          f"{original_stamp.get('size')} vs {st.st_size}")
    check("`modified` is the file's modification SECOND, rounded (the reversed cache's "
          "convention)", original_stamp.get("modified") == int(round(st.st_mtime)),
          f"{original_stamp.get('modified')} vs {st.st_mtime}")
    check("`duration`, `width`, `height`, `hasVideo`, `hasAudio` are the record's",
          all(original_stamp.get(k) == v for k, v in A_RECORD.items()),
          f"{ {k: original_stamp.get(k) for k in A_RECORD} }")
    check("the three generator constants ride along (160 px, 600 frames, 100 buckets/s), so "
          "a build that changes one invalidates every old cache",
          (original_stamp.get("thumbnailHeight"), original_stamp.get("maxThumbnails"),
           original_stamp.get("peakBucketsPerSecond")) == (160, 600, 100),
          f"{original_stamp}")
    check("a byte copy at another path with its times preserved stamps EQUAL — the path "
          "is not in it", stamps.get("copy") == original_stamp, f"{stamps.get('copy')}")
    touched_stamp = stamps.get("touched") or {}
    check("the same bytes with a later mtime stamp DIFFERENT",
          touched_stamp != original_stamp, f"{touched_stamp}")
    check("  and differ in `modified` alone, by exactly 7",
          {k: v for k, v in touched_stamp.items() if k != "modified"}
          == {k: v for k, v in original_stamp.items() if k != "modified"}
          and touched_stamp.get("modified") == original_stamp["modified"] + 7,
          f"{touched_stamp.get('modified')} vs {original_stamp['modified']}")
    check("a path that is not there stamps nil — and a nil stamp never skips and never "
          "writes a marker", stamps.get("missing") is None and "missing" in stamps,
          f"{stamps.get('missing')}")
    check("the strip's marker is `thumbs/<id>/complete.json` — inside the strip's own "
          "directory, and not a `.jpg`, which `thumbnailCount` would count as a frame",
          answer.get("thumbsMarker") == "/cache/thumbs/7/complete.json",
          f"{answer.get('thumbsMarker')}")
    check("the peaks marker is `peaks/<id>.complete.json`, a sidecar beside `peaks/<id>.bin`, "
          "which keeps its name",
          answer.get("peaksMarker") == "/cache/peaks/7.complete.json"
          and answer.get("peaksBin") == "/cache/peaks/7.bin",
          f"{answer.get('peaksMarker')} / {answer.get('peaksBin')}")


def section_ledger(binary, sources):
    print("\n3. The ledger — §2a, one pass per media, counted by its posts")
    source = fixture("A.mov")
    if source is None:
        return
    here = fresh_dir("ledger")
    copy = os.path.join(here, "A.mov")
    shutil.copy2(source, copy)
    request = {
        "mode": "cacheledger", "record": A_RECORD, "source": copy,
        "dirOne": fresh_dir("ledger", "one"), "dirThree": fresh_dir("ledger", "three"),
    }
    answer, error = run_probe(binary, "cacheledger", request)
    check("the probe answers mode `cacheledger`", answer is not None and "error" not in answer,
          error or (answer or {}).get("error", ""))
    if answer is None:
        return
    one, three, fourth = answer.get("one"), answer.get("three"), answer.get("fourth")
    print(f"       (thumbs posts — one call: {one}; three rapid calls: {three}; a fourth after "
          f"the quiet: {fourth})")
    check("every wait settled (no post for 1.5 s inside the 60 s cap)",
          all(answer.get(k) for k in ("oneSettled", "threeSettled", "fourthSettled")))
    check("one pass posts at least once and leaves a marker — the measure below is not "
          "vacuous", isinstance(one, int) and one >= 1 and answer.get("oneMarker") is True,
          f"one={one}, marker={answer.get('oneMarker')}")
    check("A's ten frames are on disk after one pass",
          answer.get("oneJPEGs") == 10, f"{answer.get('oneJPEGs')}")
    check("three calls in a row post exactly ONE pass's worth — the second and third queued "
          "behind the first and found its marker (a ledger-less build posts about three times "
          "this)", three == one, f"three={three}, one={one}")
    check("  and leave one complete strip and its marker",
          answer.get("threeJPEGs") == 10 and answer.get("threeMarker") is True,
          f"jpgs={answer.get('threeJPEGs')}, marker={answer.get('threeMarker')}")
    check("  with no post carrying `replaced` — nothing was on disk to replace",
          answer.get("threeReplacedPosts") == 0, f"{answer.get('threeReplacedPosts')}")
    check("a fourth call after the quiet posts NOTHING — the head check",
          fourth == 0, f"{fourth}")
    check("  and `0.jpg`'s inode is what it was", answer.get("fourthInodeBefore")
          == answer.get("fourthInodeAfter") != -1,
          f"{answer.get('fourthInodeBefore')} → {answer.get('fourthInodeAfter')}")


# ---- PNGs, for section 4 ---------------------------------------------------
# `phase9_proof.py`'s decoder: 8-bit non-interlaced, the five filters.


def decode_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        raise RuntimeError(f"{path}: {depth}-bit or interlaced")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


class Picture:
    def __init__(self, path):
        self.width, self.height, self.channels, self.rows = decode_png(path)

    def region(self, x, y, w, h):
        """The bytes of a rectangle, row by row."""
        c = self.channels
        return b"".join(self.rows[j][x * c:(x + w) * c] for j in range(y, y + h))

    def differences(self, other):
        """The bounding box `[x, y, w, h]` of every pixel that differs from
        `other`, or None when none does."""
        c = self.channels
        xs, ys = [], []
        for j in range(min(self.height, other.height)):
            a, b = self.rows[j], other.rows[j]
            if a == b:
                continue
            for i in range(min(self.width, other.width)):
                if a[i * c:(i + 1) * c] != b[i * c:(i + 1) * c]:
                    xs.append(i)
                    ys.append(j)
        if not xs:
            return None
        return [min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1]


def section_staletile(binary, sources):
    print("\n4. The stale tile — §2a, the timeline's memo and the `replaced` flag, as pixels")
    request = {"mode": "staletile", "cacheDir": fresh_dir("tile", "cache"),
               "outDir": fresh_dir("tile", "png")}
    answer, error = run_probe(binary, "staletile", request)
    check("the probe answers mode `staletile`", answer is not None and "error" not in answer,
          error or (answer or {}).get("error", ""))
    if answer is None:
        return
    shots = {}
    for name in ("red", "blue", "memo", "replaced"):
        record = answer.get(name) or {}
        check(f"the `{name}` render settled and was written",
              record.get("settled") is True and "path" in record, f"{record}")
        if "path" in record:
            shots[name] = Picture(record["path"])
    if len(shots) < 4:
        return
    clip = answer.get("clipPx") or [0, 0, 0, 0]
    print(f"       (scale {answer.get('scale')}; the clip's rectangle in pixels {clip})")
    box = shots["red"].differences(shots["blue"])
    print(f"       (red against blue differs inside {box})")
    check("a red `0.jpg` and a blue one render differently — the tile is drawn at all",
          box is not None, "the two renders are byte-identical")
    if box is None:
        return
    x, y, w, h = box
    cx, cy, cw, ch = clip
    check("  and every differing pixel lies inside the clip's rectangle — it is the tile, "
          "not the chrome",
          x >= cx and y >= cy and x + w <= cx + cw and y + h <= cy + ch,
          f"box {box} vs clip {clip}")
    red = shots["red"].region(x, y, w, h)
    blue = shots["blue"].region(x, y, w, h)
    memo = shots["memo"].region(x, y, w, h)
    after = shots["replaced"].region(x, y, w, h)
    check("told `.mediaCacheDidChange` for the media WITHOUT the replaced flag, after the "
          "file turned blue, the view still draws the RED tile it decoded — the memo rule, "
          "pinned: a tile already read is still the same tile while a strip is filling in",
          memo == red, f"the tile at {box} changed")
    check("  (and did not turn blue)", memo != blue, f"the tile at {box} is the blue render's")
    check("told again WITH the flag, the tile is BLUE — the decoded tiles for that media were "
          "dropped, so a replaced strip does not stay on screen until the 800-entry drop",
          after == blue, f"the tile at {box} is not the blue render's")
    check("  (and is no longer red)", after != red, f"the tile at {box} is still the red render's")
    check("the whole `replaced` render equals the whole fresh blue render — nothing else moved",
          shots["replaced"].differences(shots["blue"]) is None,
          f"differs inside {shots['replaced'].differences(shots['blue'])}")


# --------------------------------------------------------------------------
# Section 5 — §2a, the pass itself: when it may write its marker, and what it
# tells. The rules the review put into `thumbnails` and `peaks` after the
# marker landed, each a pass driven straight at a directory here because no
# tool can delete a frame under a running pass, hand the app a text file
# with a movie's record, or count a notification.

# `AV.mov`'s record, as `import_media` reports it: 5 s at 640 × 360, video
# AND audio — the one fixture with a peaks half.
AV_RECORD = {"duration": 3_000_000, "width": 640, "height": 360,
             "hasVideo": True, "hasAudio": True}


def thumbs_posts(record):
    return [p for p in (record or {}).get("posts", []) if p.get("kind") == "thumbs"]


def peaks_posts(record):
    return [p for p in (record or {}).get("posts", []) if p.get("kind") == "peaks"]


def section_pass(binary, sources):
    print("\n5. The pass — §2a, when a pass may certify a strip, and what it tells")
    a = fixture("A.mov")
    av = fixture("AV.mov")
    if a is None or av is None:
        return
    here = fresh_dir("pass")
    a_copy = os.path.join(here, "A.mov")
    av_copy = os.path.join(here, "AV.mov")
    shutil.copy2(a, a_copy)
    shutil.copy2(av, av_copy)
    # A few KB of text under a movie's name and under an image's: a file the
    # record calls a picture and AVFoundation and ImageIO cannot open.
    unreadable = os.path.join(here, "unreadable.mov")
    garbage_image = os.path.join(here, "garbage.png")
    for path in (unreadable, garbage_image):
        with open(path, "w") as handle:
            handle.write("not a movie, not a picture — a few KB of text\n" * 90)
    request = {
        "mode": "cachepass", "record": A_RECORD, "avRecord": AV_RECORD,
        "source": a_copy, "avSource": av_copy,
        "unreadable": unreadable, "garbageImage": garbage_image,
        "dirs": {name: fresh_dir("pass", name)
                 for name in ("hole", "unreadable", "image", "twice", "withdrawn")},
    }
    answer, error = run_probe(binary, "cachepass", request)
    check("the probe answers mode `cachepass`", answer is not None and "error" not in answer,
          error or (answer or {}).get("error", ""))
    if answer is None:
        return
    for name in ("hole", "holeRetry", "unreadable", "image", "twice",
                 "withdrawnBuilt", "withdrawn", "withdrawnBack"):
        check(f"the `{name}` pass settled (no post for 1.5 s inside the 60 s cap)",
              (answer.get(name) or {}).get("settled") is True, f"{answer.get(name)}")

    print("\n  5a. a frame the pass wrote and lost — no marker; the next pass finishes the strip")
    hole = answer.get("hole") or {}
    retry = answer.get("holeRetry") or {}
    check("`0.jpg` appeared while the pass ran and the 1 ms poll removed it (the "
          "precondition: the hole was made before the pass could finish)",
          hole.get("deletedZero") is True, f"deletedZero={hole.get('deletedZero')!r}")
    check("  after the pass, `0.jpg` is still gone and the other nine frames are there",
          hole.get("zeroExists") is False and hole.get("jpgCount") == 9,
          f"zeroExists={hole.get('zeroExists')} jpgs={hole.get('jpgCount')}")
    check("a pass whose written frame is missing at the end writes NO marker — `stripHolds` "
          "lists the directory before the marker, and a frame it wrote that is not there is "
          "a save's swap it cannot otherwise see",
          hole.get("thumbsMarker") is False, f"marker present={hole.get('thumbsMarker')}")
    check("  and it still posted, so the timeline draws what did land",
          len(thumbs_posts(hole)) >= 1, f"{hole.get('posts')}")
    check("the SAME pass run again, untouched, finds no marker and rebuilds: marker written, "
          "all ten frames on disk — the retry the missing marker exists to buy",
          retry.get("thumbsMarker") is True and retry.get("jpgCount") == 10
          and retry.get("zeroExists") is True,
          f"marker={retry.get('thumbsMarker')} jpgs={retry.get('jpgCount')}")
    check("  and its first post carries `replaced` — a partial strip finished is one of the "
          "three cases the notification's doc names",
          bool(thumbs_posts(retry)) and thumbs_posts(retry)[0].get("replaced") is True,
          f"{retry.get('posts')}")

    print("\n  5b. a file AVFoundation cannot open — no frame, no marker, and a post")
    unread = answer.get("unreadable") or {}
    print(f"       (the pass over the text file made {len(thumbs_posts(unread))} thumbs post(s))")
    check("a record with `hasVideo` over a text file lands NO frame",
          unread.get("jpgCount") == 0, f"jpgs={unread.get('jpgCount')}")
    check("and writes NO marker — a pass that wrote nothing is a failed reader to retry, not a "
          "strip with holes; the marker would have stopped every retry until the file's size "
          "or date moved",
          unread.get("thumbsMarker") is False, f"marker present={unread.get('thumbsMarker')}")
    check("and still posts — the after-loop post is unconditional, so a timeline waiting on "
          "the strip is told there is nothing to draw",
          len(thumbs_posts(unread)) >= 1, f"{unread.get('posts')}")

    print("\n  5c. an image whose decode fails, with the old tile on disk — cleared, and "
          "the post says `replaced`")
    image = answer.get("image") or {}
    check("the seeded `0.jpg` is gone and nothing replaced it (the decode failed)",
          image.get("zeroExists") is False and image.get("jpgCount") == 0,
          f"zeroExists={image.get('zeroExists')} jpgs={image.get('jpgCount')}")
    check("no marker — nothing certifies a tile that is not there",
          image.get("thumbsMarker") is False, f"marker present={image.get('thumbsMarker')}")
    check("exactly ONE thumbs post, carrying `replaced` — posted on the decode-failure path "
          "too, or a memo holding the old tile would draw a picture the package no longer has",
          len(thumbs_posts(image)) == 1 and thumbs_posts(image)[0].get("replaced") is True,
          f"{image.get('posts')}")

    print("\n  5d. a replacing pass says `replaced` on its FIRST post and no other")
    twice = answer.get("twice") or {}
    twice_posts = thumbs_posts(twice)
    print(f"       (A.mov under a 20 s record: {len(twice_posts)} thumbs posts, "
          f"{twice.get('jpgCount')} frames)")
    check("the pass posted MORE than once — the 20 s record over the 10 s file asks 20 frames, "
          "so the every-16 post fires before the after-loop one (the precondition: with one "
          "post the claim below could not fail)",
          len(twice_posts) >= 2, f"{len(twice_posts)} posts")
    check("the first post carries `replaced` — the seeded `0.jpg` was on disk and is the old "
          "film to the timeline's memo",
          bool(twice_posts) and twice_posts[0].get("replaced") is True, f"{twice_posts}")
    check("and NO later post does: nothing of the old film is on disk once `clearThumbnails` "
          "returns, so every tile memoised after the first post is this pass's, and a flag on "
          "every post would empty the media's memo every sixteen frames for nothing",
          len(twice_posts) >= 2 and all(p.get("replaced") is not True for p in twice_posts[1:]),
          f"{twice_posts}")
    check("  the marker is written over a strip with holes — a request past the file's end "
          "fails, and complete is not a count (the ten real seconds are on disk, plus the "
          "one at 10 s that the half-second tolerance lets land)",
          twice.get("thumbsMarker") is True and (twice.get("jpgCount") or 0) >= 10,
          f"marker={twice.get('thumbsMarker')} jpgs={twice.get('jpgCount')}")

    print("\n  5e. a peaks rebuild withdraws the old `.bin` at its head and says so — the "
          "timeline is TOLD, which no tool can see")
    built = answer.get("withdrawnBuilt") or {}
    gone = answer.get("withdrawn") or {}
    back = answer.get("withdrawnBack") or {}
    check("AV's first pass lands the `.bin` and its marker with exactly one peaks post — "
          "the landing; nothing was there to withdraw",
          built.get("binExists") is True and built.get("peaksMarker") is True
          and len(peaks_posts(built)) == 1,
          f"bin={built.get('binExists')} marker={built.get('peaksMarker')} "
          f"posts={built.get('posts')}")
    check("the same record over a VIDEO-ONLY file (a relink to a file with no audio track; "
          "`hasAudio` still true, since a relink never re-probes): the `.bin` is GONE — "
          "`clearPeaks` removed it at the head, before the track load that returns early",
          gone.get("binExists") is False, f"binExists={gone.get('binExists')}")
    check("  and its marker with it, so nothing vouches for a file that is not there",
          gone.get("peaksMarker") is False, f"marker present={gone.get('peaksMarker')}")
    check("  and exactly ONE peaks post — the withdrawal — so every memo drops the old "
          "floats and the detector reports the media as pending rather than measuring them",
          len(peaks_posts(gone)) == 1, f"{gone.get('posts')}")
    check("  (the thumbs half rebuilt for the new file and certified it: marker present)",
          gone.get("thumbsMarker") is True, f"marker present={gone.get('thumbsMarker')}")
    check("relinked back to AV: the `.bin` returns byte-for-byte the first pass's size, its "
          "marker with it, with one peaks post — the landing, since there was nothing to "
          "withdraw",
          back.get("binExists") is True and back.get("binBytes") == built.get("binBytes")
          and back.get("peaksMarker") is True and len(peaks_posts(back)) == 1,
          f"bin={back.get('binExists')} bytes={back.get('binBytes')} vs "
          f"{built.get('binBytes')} marker={back.get('peaksMarker')} posts={back.get('posts')}")


SECTIONS = [section_naming, section_cachestamp, section_ledger, section_staletile, section_pass]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--sources", default=os.environ.get("RC_APP_SOURCES", TREE_SOURCES),
                        help="an app/Sources directory to compile the probe against — a "
                             "mutant copy under work/ for the gate (default: the tree's, "
                             "or $RC_APP_SOURCES, the spelling phase9_chrome.py shares)")
    args = parser.parse_args()
    sources = os.path.abspath(args.sources)

    print("remaining — the app arithmetic designs/reelcut-remaining.md fixes\n")
    if sources != os.path.realpath(TREE_SOURCES):
        print(f"  (compiling against {sources}, not the tree)\n")
    binary, error = build_probe(sources)
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is not None:
        for section in SECTIONS:
            section(binary, sources)

    print(f"\n{passed}/{passed + failed} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
