#!/usr/bin/env python3
"""The package's `graphics/` store and its watcher: road map 10's G3a (§10.6).

Builds `graphics_store_probe.swift` over `app/Sources` with
`tools/proof/swift_build.py`'s line (a probe that will not build is a
scored FAILURE of every row, never an exit), runs it under
`graphics_spike/bounded.py`'s `run` with `TMPDIR=<work>/tmp`, and scores what
it measured against oracles of its own — hashlib for every revision, this
file's literals for every sentence:

W1  an untitled store makes its root under `NSTemporaryDirectory()/FrameJob/`
    at start(), scans empty, never calls back and never posts (TMPDIR does not
    move that directory on this host, measured; the probe reports it and
    removes every root it made);
W2  a PACKAGE store on a package without graphics/ creates nothing; a
    `mkdir graphics` + `mv x.js` from outside posts ["x"] within 1 s and calls
    back ONCE, and an in-place edit after it posts ["x"];
W3  `a.js.tmp` renamed over `a.js` is ONE post ["a"], revision = hashlib's;
W4  an in-place O_TRUNC rewrite (same inode) is ONE post ["a"], new revision;
W5  `rm a.js` is ONE post ["a"], and the module is gone;
W6  `b.js` and `c.js` back to back are ONE post ["b","c"] within 1 s;
W7  `Bad.js` and `d.js.partial` post nothing in 0.5 s, and the scan warns
    about `Bad.js` in the core's words;
W8  `fonts/` + a bundled face: ONE post, library true, names = every module,
    the version moved, makeLibrary() succeeds; `assets/` + a PNG + a 0-byte
    PNG: ONE post, the version moved, exactly the empty file's warning, one
    asset;
W9  write(name: "d") on a package without graphics/ creates it, calls back
    ONCE, leaves no .partial, the bytes equal, ONE post ["d"]; write(name:
    "Bad") throws the core's sentence and creates nothing;
W10 the folder swapped as a save swaps it posts nothing, and an in-place
    edit after it posts ["x"] (the sources were re-armed by path);
W11 packageDidMove(to:) posts the location once; an edit in the new folder
    posts, one in the old does not;
W12 an edit then stop() in the same turn, and an edit after: nothing posts;
W13 write(name: "e") then rescan() at once is exactly ONE post ["e"];
W14 (issue batch B8, #75) a new untitled store with `fonts/<bundled face>`
    and `assets/logo.png`, settled: `logo.png` rewritten IN PLACE (O_TRUNC,
    same inode) with other PNG bytes is ONE post, library true, within 1 s,
    and `libraryVersion` moved; the font rewritten in place with another
    bundled face's bytes is ONE post, library true (each font and asset file
    has its own source, spec §11 G-19 (c));
W15 `write(name: "q")` over a `q.js` flagged `.immutable` throws, leaves no
    `q.js.partial` and leaves q.js's bytes as they were (`land`'s cleanup);
W16 `holdsContent` is false for a folder holding only `API.md` and
    `x.js.partial`, and true once `x.js` is added;
W17 (issue batch B19, #172) an untitled store holding `a.js`, settled:
    RLIMIT_NOFILE's soft limit set to the lowest free descriptor (found by
    opening `/dev/null`), `rescan()`, the limit restored — `scan.warnings`
    holds `graphics/ is not watched: open failed (Too many open files)`
    (spec §11 G-20 (b)); CONTROL: a second `rescan()` has no "is not
    watched" warning and lists `a`;
W18 (issue batch B67, #105, spec §11 G-23 (f)) an untitled store with
    `fonts/f.ttf` = a bundled face, its mtime pinned to a whole second,
    settled; `stop()`, f.ttf overwritten IN PLACE (same inode) with as many
    zero bytes, its mtime set back; `start()`: `scan.fonts` is ["f.ttf"]
    holding the face's bytes and no `graphics/fonts/f.ttf:` warning (the
    verdict was reused, the file not read); CONTROL: mtime +2 s, `rescan()`:
    no fonts and one `graphics/fonts/f.ttf: ` warning;
W19 (B67, G-23 (a)-(d)) `GraphicAssetName.legalized` over this file's table,
    with `isLegal(x) == (legalized(x) == x)` and `isLegal(legalized(x))` on
    each; `importAsset(as: "#logo&mark.png")` files `logo-mark.png`
    (renamedFrom set, replaced false, listed); again files `logo-mark-2.png`
    and leaves `logo-mark.png`'s bytes; `as: "logo-mark.png"` replaces with
    no renamedFrom; a 300-byte name lands as 243 a's + `.png` (247 bytes),
    then as 241 a's + `-2.png`; `renameNotice` is this file's literal;
W20 (B67, G-23 (e)) `assets/#bad.png` and `assets/.dot.png` written to disk,
    `rescan()`: neither is listed, the warnings are exactly `#bad.png`'s
    sentence; CONTROL: `ok.png` beside them is listed;
C1  a saved document's save carries graphics/x.js (the whitelist line);
C2  an untitled document restored from autosave seeds its temporary root and
    its save carries graphics/x.js;
C3  a fresh untitled document's save has NO graphics/ (an empty root is not
    carried, G-14);
C4  a document is freed after close(), and after being dropped unclosed;
C5  an untitled document holding a module: its graphics root exists, and after
    close() it is gone; a second one, its wrapper written to a package and then
    its `fileURL` set: its old root is gone, `folderURL` is `<package>/graphics`
    and holds the module; CONTROL: that saved document's close() leaves
    `<package>/graphics` (G-19 (d));
C6  an untitled document's `cacheDirectory` holding `transcripts/9.json`: after
    close() that root is gone; a second one, its wrapper written to a package
    and `fileURL` set: `<package>/cache/transcripts/9.json` equals the original
    and its temporary root still exists; after close() the root is gone and
    the package's copy unchanged; CONTROL: a document opened from the package
    has `temporaryCacheDirectory` nil and its close() leaves `<package>/cache`.

Issue batch B84 (#103; spec §11 G-27, G-28, G-29) — kept revisions, delete,
rename and restore, through `GraphicStore` and the three bodies in
`ProjectDocument+GraphicFiles.swift`:

H1  an untitled store: `write(h, a)` + `rescan()` keeps nothing; `write(h, b)`
    + `rescan()` keeps [a]; an in-place outside rewrite with c is ONE post
    [h] and keeps [b, a], newest first, their revisions hashlib's;
H2  `restoreGraphic(r)` after writes a, b returns sha(a), leaves r.js
    byte-equal to a and keeps [b]; again returns sha(b), r.js is b, kept [a];
    a name with nothing kept and an unknown revision throw their sentences;
    the document is not edited; then, with a third text written and the newest
    kept FILE rewritten by hand, a default restore throws the sentence naming
    that file and the other kept revision, and writes nothing (G-29 (d));
H3  thirteen texts written keep exactly the 10 newest of the 12 replaced
    (the two oldest gone); `keep` of a text already kept lists it once, first;
H4  `deleteGraphic(used)` while a clip draws it throws the used sentence
    with the file intact; an absent name throws the folder's sentence; with
    the clip deleted (and the change count cleared) it returns sha(text),
    removes the file, keeps [text], lists the name under `keptNames()`,
    leaves `fonts/` and `assets/` and does not edit the document;
H5  a timeline clip and a nest clip drawn by `old` (kept [a]):
    `graphicClips` groups them; a taken name, a bad name and an open nest
    throw their sentences and move nothing; `renameGraphic(old → new)`
    answers both ids as ONE step "Rename Graphic", both clips name `new`,
    new.js holds the text, kept(new) is [a], `history/old/` is gone and the
    journal holds [old, new]; `undo()` puts the old name back on the clips,
    the file and the history; `redo()` the new;
H6  a saved package whose project names `old`, with `graphics/new.js` and a
    journal pair [old, new], is healed by `startGraphicStore()` (old.js back,
    not edited); CONTROL: the same package without the journal is not;
H7  rename `title` → `title-v1`, write a new `title`, repoint the clip at
    `title`, delete `title-v1`, `undo()`: title.js keeps its bytes, there is
    no title-v1.js, and the clip names `title-v1` (G-27 (f));
H8  a clip naming a file-less `ghost` (its clip deleted, `deleteGraphic`,
    `undo()`): `renameGraphic(other → ghost)` throws the drawn sentence and
    moves nothing (G-28 (c));
H9  40 `recordRename` calls of distinct pairs, then one of them reversed:
    `renamePairs()` answers 32, newest first, the repeated pair once and
    first (G-28 (e));
H10 rename `a` → `b` (a clip follows), `b.js` removed OUTSIDE the app and
    rescanned (nothing kept), a new undrawn `a` written, then a committed
    change: a.js keeps its bytes, there is no b.js, the clip names `b` — the
    repair goes from a pair's second name back to its first, never the other
    way (G-28 (e), (f));
H11 rename `a` → `b` (a clip follows), a new `a` written and deleted,
    `undo()` of Rename Graphic: b.js keeps its bytes, there is no a.js, the
    clip names `a` and kept(a) is the deleted text — the row where the
    repair's kept-revision test is the ONLY guard (G-27 (f));
H12 a package built by hand whose `graphics/m.js` is also the NEWEST of two
    kept texts (a text put back while the project was closed; a crash between
    `removeModule`'s keep and its removal): `startGraphicStore()` drops it,
    kept is [the older], and a default restore writes the older text and
    keeps the current (G-29 (b));
H13 with `history/renames.json` a directory, so the journal cannot be
    written: `renameGraphic(old → new)` throws the could-not-be-renamed
    sentence and old.js, its kept text, the clip's name and the undo stack
    are where they were (G-28 (e));
H14 with a FILE at `history/new`, so `old`'s history cannot be folded under
    it: `renameGraphic(old → new)` throws the could-not-be-renamed sentence,
    old.js, its kept text and the clip's name are where they were, and the
    journal is as it was — no pair and no `renames.json`: a refused rename
    journals nothing (G-28 (d));
H15 the state a crash INSIDE `moveModule` leaves when the old name had kept
    texts, built by hand (H6's control package plus a kept text under
    `history/old/` and the pair [old, new]): `startGraphicStore()` moves
    nothing — the clip names `old`, there is no old.js, new.js keeps its
    bytes, kept(old) is the kept text and the pair is still [old, new]. The
    repair reads `old` as DELETED; this is G-28 (f)'s limit, MEASURED, not a
    behaviour wanted (H6 is the same crash with nothing kept, which heals,
    and H6's CONTROL the crash before the pair was written). Then, in that
    package, a default `restoreGraphic(old)` returns the kept revision and
    writes that OLDER text to old.js while new.js keeps the current text,
    undrawn; the clip names `old` and the document is not edited;
H16 rename `a` → `b` (a clip follows, kept [a's first text]), then with a
    FILE at `history/a` a rename `b` → `a` is refused at the fold:
    `renames.json` is byte-for-byte what it was ([a, b] — the EARLIER pair),
    b.js and its kept text are where they were; with that file removed,
    `undo()` of the first rename puts a.js back with its kept text and the
    clip names `a` (G-28 (d));
H17 a chain: rename `a` → `b` → `c` with one kept text, `undo()` twice and
    `redo()` twice — after each of the six steps the clip's name, the one
    module file and the kept text are under the same name, and nothing is
    under the other two (G-28 (e));
H18 a rename refused at the CLIPS — the probe's own `apply`, which throws,
    or returns having applied nothing ("its clips did not take the new
    name") — in both journal states: with no `renames.json` (`a` → `b`),
    and after a real `a` → `b` (`b` → `c`, the journal [a, b]). After each
    of the four the module file, its kept text, the clip's name, the undo
    stack and `renames.json` (no file; byte-for-byte [a, b]) are where they
    were, and `apply` was handed one op; `undo()` of the real rename then
    puts a.js back (G-28 (d)). LIMIT, measured: a rename onto a DELETED
    module's name refused at the clips has already folded the two
    histories, so the move back leaves the deleted text kept under the
    renamed module and nothing kept under the deleted name. And a move
    back that FAILS (`apply` puts a FILE at `history/a` before it throws,
    so the history cannot be folded back): b.js and its kept text stay,
    the clip names `a`, and the pair [a, b] is still journalled; with that
    file removed, a committed change repairs — a.js back with its kept
    text;
C7  an untitled document's save carries `graphics/history/m/000001-<sha>.js`
    holding the replaced text; every history row's untitled root is removed.

    python3 tools/proof/graphics_store_probe.py
    python3 tools/proof/graphics_store_probe.py --mutant whitelist-removed
    python3 tools/proof/graphics_store_probe.py --mutant no-file-sources
    python3 tools/proof/graphics_store_probe.py --mutant strong-callback
    python3 tools/proof/graphics_store_probe.py --mutant partial-left
    python3 tools/proof/graphics_store_probe.py --mutant scratch-kept
    python3 tools/proof/graphics_store_probe.py --mutant cache-kept
    python3 tools/proof/graphics_store_probe.py --mutant no-library-file-sources
    python3 tools/proof/graphics_store_probe.py --mutant silent-open
    python3 tools/proof/graphics_store_probe.py --mutant font-uncached
    python3 tools/proof/graphics_store_probe.py --mutant asset-name-kept
    python3 tools/proof/graphics_store_probe.py --mutant asset-name-unchecked
    python3 tools/proof/graphics_store_probe.py --mutant history-unkept
    python3 tools/proof/graphics_store_probe.py --mutant history-uncapped
    python3 tools/proof/graphics_store_probe.py --mutant delete-used
    python3 tools/proof/graphics_store_probe.py --mutant rename-unreconciled
    python3 tools/proof/graphics_store_probe.py --mutant history-left-behind
    python3 tools/proof/graphics_store_probe.py --mutant reconcile-over-delete
    python3 tools/proof/graphics_store_probe.py --mutant rename-onto-drawn
    python3 tools/proof/graphics_store_probe.py --mutant journal-uncapped
    python3 tools/proof/graphics_store_probe.py --mutant reconcile-both-directions
    python3 tools/proof/graphics_store_probe.py --mutant rename-unjournalled
    python3 tools/proof/graphics_store_probe.py --mutant start-undropped
    python3 tools/proof/graphics_store_probe.py --mutant restore-unhashed
    python3 tools/proof/graphics_store_probe.py --mutant rollback-unjournalled
    python3 tools/proof/graphics_store_probe.py --mutant moveback-unjournalled
    python3 tools/proof/graphics_store_probe.py --mutant moveback-unconditional

A mutant is built from a COPY of `app/Sources` with one anchor, asserted to
occur exactly once, replaced. Rule R: exit 0 means the row it names — EVERY
row, for the two mutants that name two — FAILED in
the copy (C1's file ABSENT, W4, C4, W15, C5, C6, W14, W17, W18, W19, W20, H1, H2, H3, H4,
H5, H8, H9, H10, H11, H12, H13, H14, H18 — and with them H16 for
`rollback-unjournalled`, H17 for `rename-unreconciled`) — caught; exit 1
means it passed — survived; exit 2 means the control was not performed (the
copy, the anchor or the build failed, or the probe gave no answer).
`no-file-sources` drops the one file-arm loop (modules, fonts and assets,
spec §11 G-20 (a)); `no-library-file-sources` drops the fonts and assets from
it; `silent-open` makes `arm`'s failure branch answer nil; `partial-left`
drops the cleanup in `land`'s catch, `scratch-kept` empties
`removeScratchRoot`, and `cache-kept` drops `stopGraphicStore`'s
`removeTemporaryCacheDirectory()`. `font-uncached` makes a cached font
verdict's identity comparison `false`; `asset-name-kept` replaces
`importAsset`'s `legalized(name)` with `name`; `asset-name-unchecked` makes
the scan's `isLegal` guard `true`. B84's fifteen: `history-unkept` drops the
pass's `keepReplaced` call (H1); `history-uncapped` drops `tidy`'s prune (H3);
`delete-used` empties `deleteGraphic`'s clip groups (H4);
`rename-unreconciled` empties the `.projectDocumentDidChange` observer (H5,
and H17's chain, which it must also fail);
`history-left-behind` drops `moveModule`'s `moveHistory` (H5);
`reconcile-over-delete` drops the repair's kept-revision test (H11; H7 no
longer needs that test — the repair's one direction holds it);
`rename-onto-drawn` makes `renameGraphic`'s drawn check `true` (H8);
`journal-uncapped` drops `recordRename`'s cut to `renameJournalLimit` (H9);
`reconcile-both-directions` makes the repair try each pair both ways (H10);
`rename-unjournalled` drops `moveModule`'s read-back of the pair it wrote
(H13); `start-undropped` drops `start()`'s drop of each current revision
(H12); `restore-unhashed` makes `restoreGraphic`'s hash check `true` (H2);
`rollback-unjournalled` drops `moveModule`'s put-back of the journal when the
history could not be folded (H14, and H16, which it must also fail);
`moveback-unjournalled` drops `renameGraphic`'s put-back of the journal after
a rename refused at the clips is moved back (H18); `moveback-unconditional`
makes that put-back run whether or not the move back succeeded, which takes
the pair away from a file left at the new name (H18).
"""

import hashlib
import json
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
from bounded import child_env, run as bounded_run  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-store-probe"
FONTS = ROOT / "app/Resources/Fonts"
PNG = ROOT / "app/Assets.xcassets/AppIcon.appiconset/icon_16.png"
DEADLINE = 600
RULE = ("is not a module name (lowercase letters, digits and -, starting with a letter "
        "or a digit, at most 63 characters)")
ROWS = ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11", "W12", "W13",
        "W14", "W15", "W16", "W17", "W18", "W19", "W20", "C1", "C2", "C3", "C4", "C5", "C6",
        "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10", "H11", "H12", "H13",
        "H14", "H15", "H16", "H17", "H18", "C7"]
ADVICE = "; delete those clips or point them at another module (set_graphic {name}) first"
UNWATCHED = "graphics/ is not watched: open failed (Too many open files)"
ASSET_RULE = ("is not an asset name (no leading . or #; no / : \" ' < > & or control "
              "character; at most 247 bytes)")
NAME_TABLE = {
    "#logo&mark.png": "logo-mark.png",
    ".hidden.png": "hidden.png",
    "My Photo (1).png": "My Photo (1).png",
    "a\"b'c<d>e.png": "a-b-c-d-e.png",
    "a&&b.png": "a-b.png",
    "#&.png": "image.png",
    "x\u0007y.PNG": "x-y.PNG",
    "10:30.jpg": "10-30.jpg",
    "é" * 200 + ".png": "é" * 121 + ".png",
    "a" * 247 + ".png": "a" * 243 + ".png",
    "logo.svg": "logo.svg",
}
NOTICE = '"#logo&mark.png" was added as "logo-mark.png": asset(name) cannot use the name it had.'

rows = {}
answer_seen = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""))


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def one(settled, names, within=None):
    """Exactly one post, naming `names`, inside `within` seconds if given."""
    posts = (settled or {}).get("posts", [])
    latency = (settled or {}).get("latency")
    return (len(posts) == 1 and posts[0].get("names") == names
            and (within is None or (isinstance(latency, (int, float)) and latency <= within)))


def build(sources, out, seconds):
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/graphics_store_probe.swift", entry)
    binary = out / "graphics-store-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [entry], output=binary, timeout=seconds)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, f"the build did not finish within {seconds} s"
        return None, "; ".join(error.diagnostics[:8])
    return binary, ""


def score(a, work):
    # NSTemporaryDirectory() ignores TMPDIR on this host, so the root is
    # scored against the directory the probe itself reports.
    tmp = str((Path(a.get("tmp", "/nonexistent")) / "FrameJob").resolve()) + "/"

    def under_tmp(path):
        return isinstance(path, str) and str(Path(path).resolve()).startswith(tmp)

    w1 = a.get("w1", {})
    check("W1 the untitled root is made in the temporary directory at start(), empty, silent",
          w1.get("exists") is True and under_tmp(w1.get("folder"))
          and str(w1.get("folder", "")).endswith("-graphics")
          and Path(w1.get("folder", "")).parent.name == "FrameJob"
          and w1.get("empty") is True and w1.get("callbacks") == 0 and w1.get("posts") == 0,
          f"{w1}")

    w2 = a.get("w2", {})
    check("W2 no graphics/ at start; an outside mkdir + mv posts [x] within 1 s, calls back "
          "ONCE; an in-place edit then posts [x]",
          w2.get("absent_after_start") is True and w2.get("callbacks_after_start") == 0
          and one(w2.get("appear"), ["x"], 1.0) and w2.get("callbacks") == 1
          and one(w2.get("edit"), ["x"]), f"{w2}")

    w3 = a.get("w3", {})
    check("W3 a.js.tmp renamed over a.js is ONE post [a], revision = hashlib's",
          w3.get("renamed") is True and one(w3, ["a"])
          and w3.get("revision") == sha(w3.get("content", "")), f"{w3}")

    w4 = a.get("w4", {})
    check("W4 an in-place O_TRUNC rewrite is ONE post [a] with the new revision",
          w4.get("same_inode") is True and one(w4, ["a"])
          and w4.get("revision") == sha(w4.get("content", ""))
          and w4.get("revision") != w3.get("revision"), f"{w4}")

    w5 = a.get("w5", {})
    check("W5 rm a.js is ONE post [a], and the module is gone",
          one(w5, ["a"]) and w5.get("gone") is True, f"{w5}")

    w6 = a.get("w6", {})
    check("W6 b.js and c.js back to back are ONE post [b, c] within 1 s",
          one(w6, ["b", "c"], 1.0), f"{w6}")

    w7 = a.get("w7", {})
    check("W7 Bad.js and d.js.partial post nothing in 0.5 s; Bad.js is warned in the core's words",
          w7.get("posts") == [] and f"graphics/Bad.js {RULE}" in w7.get("warnings", [])
          and w7.get("modules") == ["b", "c"], f"{w7}")

    w8 = a.get("w8", {})
    fonts_post = (w8.get("posts") or [{}])[0]
    assets = w8.get("assets", {})
    assets_post = (assets.get("posts") or [{}])[0]
    face = sorted(p.name for p in FONTS.iterdir() if p.suffix == ".ttf")[0]
    check("W8 fonts/: ONE post, library true, names = every module, version moved, "
          "makeLibrary() ok; assets/: ONE post, version moved, one warning, one asset",
          len(w8.get("posts", [])) == 1 and fonts_post.get("library") is True
          and fonts_post.get("names") == w8.get("modules") == ["b", "c"]
          and w8.get("version_before") != w8.get("version_after")
          and w8.get("library") == "ok" and w8.get("fonts") == [face]
          and len(assets.get("posts", [])) == 1 and assets_post.get("library") is True
          and assets.get("version_before") != assets.get("version_after")
          and assets.get("warnings") == ["graphics/assets/empty.png is empty and was skipped"]
          and assets.get("assets") == ["logo.png"], f"{w8}")

    w9 = a.get("w9", {})
    check("W9 write(d) creates graphics/, calls back ONCE, ONE post [d], bytes equal, no "
          ".partial; write(Bad) throws the core's sentence and creates nothing",
          w9.get("thrown") is None and w9.get("callbacks") == 1 and one(w9, ["d"])
          and w9.get("bytes_equal") is True and w9.get("partials") == []
          and w9.get("bad_message") == f'graphic name "Bad" {RULE}'
          and w9.get("bad_files") == [], f"{w9}")

    w10 = a.get("w10", {})
    check("W10 the folder swapped as a save swaps it posts nothing; an in-place edit after "
          "posts [x]",
          w10.get("swap_posts") == [] and one(w10.get("edit"), ["x"]), f"{w10}")

    w11 = a.get("w11", {})
    check("W11 packageDidMove posts the location once; the new folder's edit posts, the "
          "old one's does not",
          w11.get("locations") == 1 and w11.get("folder") == w11.get("expected")
          and one(w11.get("new_edit"), ["x"]) and w11.get("old_edit_posts") == [], f"{w11}")

    w12 = a.get("w12", {})
    check("W12 an edit then stop() in the same turn, and an edit after: nothing posts",
          w12.get("posts") == [], f"{w12}")

    w13 = a.get("w13", {})
    check("W13 write(e) then rescan() at once is exactly ONE post [e]",
          len(w13.get("posts", [])) == 1 and w13["posts"][0].get("names") == ["e"], f"{w13}")

    w14 = a.get("w14", {})
    logo, font = w14.get("logo") or {}, w14.get("font") or {}

    def library_post(settled):
        posts = (settled or {}).get("posts", [])
        return len(posts) == 1 and posts[0].get("library") is True

    check("W14 an asset rewritten IN PLACE is ONE post, library true, within 1 s, the version "
          "moved; a font rewritten in place is ONE post, library true",
          w14.get("png_differs") is True and w14.get("faces", 0) >= 2
          and logo.get("same_inode") is True and library_post(logo)
          and isinstance(logo.get("latency"), (int, float)) and logo["latency"] <= 1.0
          and logo.get("version_moved") is True
          and font.get("same_inode") is True and library_post(font), f"{w14}")

    w15 = a.get("w15", {})
    check("W15 write(q) over an immutable q.js throws, leaves no q.js.partial and q.js unchanged",
          w15.get("thrown") is not None and w15.get("partial") is False
          and w15.get("bytes_unchanged") is True, f"{w15}")

    w16 = a.get("w16", {})
    check("W16 holdsContent is false for API.md and x.js.partial alone, true once x.js is added",
          w16.get("partial_only") is False and w16.get("with_module") is True, f"{w16}")

    w17 = a.get("w17", {})
    control = w17.get("control_warnings")
    check("W17 a failed open is the scan warning \"graphics/ is not watched: open failed (Too many "
          "open files)\"; CONTROL: the next rescan has no such warning and lists a",
          w17.get("modules_before") == ["a"] and w17.get("limited") is True
          and w17.get("restored") is True and UNWATCHED in w17.get("warnings", [])
          and isinstance(control, list)
          and not any("is not watched" in w for w in control)
          and w17.get("control_modules") == ["a"], f"{w17}")

    w18 = a.get("w18", {})
    control = w18.get("control_warnings")
    check("W18 a font overwritten in place with its size, mtime and inode kept is not read "
          "again: start() lists f.ttf with the face's bytes, no warning; CONTROL: mtime +2 s "
          "and rescan() list no font and warn graphics/fonts/f.ttf",
          w18.get("setup_fonts") == ["f.ttf"] and w18.get("face_bytes", 0) > 0
          and w18.get("same_inode") is True and w18.get("same_mtime") is True
          and w18.get("zeroed") is True and w18.get("fonts") == ["f.ttf"]
          and w18.get("bytes_equal") is True
          and not any(w.startswith("graphics/fonts/f.ttf:") for w in w18.get("warnings", []))
          and w18.get("control_fonts") == [] and isinstance(control, list)
          and len([w for w in control if w.startswith("graphics/fonts/f.ttf: ")]) == 1,
          f"{w18}")

    w19 = a.get("w19", {})
    table = {r.get("name"): r for r in w19.get("table", [])}
    long1, long2 = "a" * 243 + ".png", "a" * 241 + "-2.png"

    def landed(r, name, renamed_from, replaced):
        return (isinstance(r, dict) and r.get("name") == name
                and r.get("renamed_from") == renamed_from and r.get("replaced") is replaced
                and r.get("listed") is True and r.get("on_disk") is True)

    check("W19 legalized matches the table and the invariant holds; #logo&mark.png is filed as "
          "logo-mark.png then logo-mark-2.png (the first unchanged); a legal name replaces; a "
          "300-byte name lands at 247 bytes, twice; the notice is the literal",
          set(table) == set(NAME_TABLE)
          and all(table[k].get("legalized") == v and table[k].get("invariant") is True
                  for k, v in NAME_TABLE.items())
          and table.get("é" * 200 + ".png", {}).get("bytes") == 246
          and landed(w19.get("first"), "logo-mark.png", "#logo&mark.png", False)
          and landed(w19.get("second"), "logo-mark-2.png", "#logo&mark.png", False)
          and w19.get("first_bytes_unchanged") is True
          and landed(w19.get("legal"), "logo-mark.png", None, True)
          and landed(w19.get("long"), long1, "a" * 300 + ".png", False)
          and w19["long"].get("bytes") == 247
          and landed(w19.get("long_again"), long2, "a" * 300 + ".png", False)
          and w19["long_again"].get("bytes") == 247
          and w19.get("notice") == NOTICE,
          f"{w19}")

    w20 = a.get("w20", {})
    check("W20 assets/#bad.png and .dot.png are not listed; the warnings are exactly #bad.png's "
          "sentence; CONTROL: ok.png is listed",
          w20.get("assets") == ["ok.png"]
          and w20.get("warnings") == [f"graphics/assets/#bad.png {ASSET_RULE} and was skipped"]
          and w20.get("on_disk") == ["#bad.png", ".dot.png", "ok.png"], f"{w20}")

    c1 = a.get("c1", {})
    check("C1 a saved document's save carries graphics/x.js",
          c1.get("child") is True and c1.get("present") is True
          and c1.get("bytes_equal") is True, f"{c1}")

    c2 = a.get("c2", {})
    check("C2 an untitled document restored from autosave seeds its temporary root; its "
          "save carries graphics/x.js",
          a.get("roots_removed") is True and c2.get("file_url_nil") is True and under_tmp(c2.get("folder"))
          and c2.get("copied") is True and c2.get("child") is True
          and c2.get("present") is True and c2.get("bytes_equal") is True, f"{c2}")

    c3 = a.get("c3", {})
    check("C3 a fresh untitled document's save has NO graphics/",
          c3.get("child") is False and c3.get("graphics_dir") is False
          and c3.get("root_exists") is True, f"{c3}")

    c4 = a.get("c4", {})
    check("C4 a document is freed after close(), and after being dropped unclosed",
          c4.get("closed_freed") is True and c4.get("dropped_freed") is True, f"{c4}")

    c5 = a.get("c5", {})
    check("C5 an untitled graphics root is gone after close() and after the first save "
          "re-points the store to <package>/graphics, which holds the module; CONTROL: the "
          "saved document's close() leaves <package>/graphics",
          c5.get("closed_root_before") is True and c5.get("closed_root_after") is False
          and "save_error" not in c5 and c5.get("saved_root_after") is False
          and c5.get("folder") == c5.get("expected") and c5.get("module_in_package") is True
          and c5.get("control_package_graphics") is True, f"{c5}")

    c6 = a.get("c6", {})
    check("C6 an untitled cache root is gone after close(); after a first save it is KEPT and "
          "the package holds the transcript, and close() then removes it leaving the copy; "
          "CONTROL: an opened package's close() leaves <package>/cache",
          c6.get("closed_root_before") is True and c6.get("closed_root_is_temporary") is True
          and c6.get("closed_root_after") is False and "save_error" not in c6
          and c6.get("copy_equal") is True and c6.get("saved_root_kept") is True
          and c6.get("saved_root_after") is False and c6.get("copy_after_close") is True
          and c6.get("control_temporary_nil") is True
          and c6.get("control_package_cache") is True, f"{c6}")

    h1 = a.get("h1", {})
    ta, tb, tc = (h1.get("texts") or ["", "", ""])[:3]
    check("H1 a first write keeps nothing; a replacing write keeps [a]; an in-place outside "
          "rewrite is ONE post [h] and keeps [b, a], revisions = hashlib's",
          h1.get("kept_fresh") == [] and h1.get("kept_after_write") == [ta]
          and one(h1.get("outside"), ["h"]) and h1.get("kept_after_outside") == [tb, ta]
          and h1.get("revisions") == [sha(tb), sha(ta)] and len({ta, tb, tc}) == 3, f"{h1}")

    h2 = a.get("h2", {})
    ta, tb = (h2.get("texts") or ["", ""])[:2]
    tampered = h2.get("tampered_file") or ""
    check("H2 restore writes the newest kept text byte-for-byte and keeps what it replaced; "
          "twice returns to the first bytes; nothing kept and an unknown revision are "
          "refused in their sentences; the document is not edited; a kept file changed by "
          "hand is refused naming it and the other kept revision, nothing written",
          h2.get("first") == sha(ta) and h2.get("file_after_first") == ta
          and h2.get("bytes_equal") is True and h2.get("kept_after_first") == [tb]
          and h2.get("second") == sha(tb) and h2.get("file_after_second") == tb
          and h2.get("kept_after_second") == [ta]
          and h2.get("none") == ('No kept revision of "never" — one is kept when a write '
                                 "replaces a module's text or delete_graphic removes it")
          and h2.get("unknown") == f'"r" has no kept revision feed — kept: {sha(ta)}'
          and h2.get("kept_revisions") == [sha(ta)] and h2.get("edited") is False
          and re.fullmatch(rf"\d{{6}}-{sha(tb)}\.js", tampered) is not None
          and h2.get("tampered") == (
              f"graphics/history/r/{tampered} was changed outside Frame Job and no longer "
              "holds the revision in its name; it is not restored — other kept revisions: "
              f"{sha(ta)}")
          and h2.get("third") not in (None, ta, tb)
          and h2.get("file_after_tampered") == h2.get("third")
          and h2.get("kept_revisions_after_tampered") == [sha(tb), sha(ta)], f"{h2}")

    h3 = a.get("h3", {})
    texts = h3.get("texts") or []
    newest = list(reversed(texts[2:12]))
    check("H3 thirteen texts keep exactly the 10 newest replaced, the two oldest gone; a text "
          "kept twice is listed once, first",
          len(texts) == 13 and h3.get("kept") == newest and len(newest) == 10
          and h3.get("kept_again") == [texts[7]] + [x for x in newest if x != texts[7]],
          f"kept {len(h3.get('kept', []))}, again {len(h3.get('kept_again', []))}")

    h4 = a.get("h4", {})
    check("H4 delete is refused naming the clip, the file intact; an absent name is refused; "
          "with the clip deleted it removes the file, keeps its bytes, leaves fonts/ and "
          "assets/ and does not edit the document",
          h4.get("clip", 0) > 0
          and h4.get("refused") == (f'The graphic "used" is still drawn by clip {h4.get("clip")} '
                                    f"on the timeline{ADVICE}")
          and h4.get("file_after_refusal") is True
          and h4.get("absent") == 'No module named "nope" in graphics/ — the folder holds: used'
          and h4.get("deleted") == sha(h4.get("text", "")) and h4.get("file_after_delete") is False
          and h4.get("listed_after_delete") is False and h4.get("kept") == [h4.get("text")]
          and h4.get("kept_names") == ["used"] and h4.get("font_kept") is True
          and h4.get("asset_kept") is True and h4.get("edited_by_clip_delete") is True
          and h4.get("edited_by_delete") is False, f"{h4}")

    h5 = a.get("h5", {})
    ta, tb = (h5.get("texts") or ["", ""])[:2]
    timeline, nested, nest = h5.get("timeline", 0), h5.get("nested", 0), h5.get("nest", 0)
    groups = h5.get("groups") or []
    inside = (groups[1].get("clips") if len(groups) == 2 else None) or []
    ids = sorted([timeline] + inside)

    def state(name, other):
        mine, theirs = ("old", "new") if name == "old" else ("new", "old")
        return {"names": {str(i): name for i in ids}, f"{mine}_file": tb, f"{theirs}_file": None,
                f"kept_{mine}": [ta], f"kept_{theirs}": [], f"history_{mine}": True,
                f"history_{theirs}": False, "modules": sorted([name, other])}

    check("H5 a timeline clip and a nest clip follow the rename as ONE step, the kept texts "
          "move and history/old/ is gone; a taken name, a bad name and an open nest are "
          "refused and move nothing; undo() puts the old name back on the clips, the file and "
          "the history, redo() the new",
          timeline > 0 and nest > 0 and len(inside) == 1
          and groups == [{"nest": None, "clips": [timeline]}, {"nest": nest, "clips": inside}]
          and h5.get("before") == state("old", "other")
          and h5.get("taken") == "graphics/other.js already exists"
          and h5.get("bad") == f'graphic name "Bad Name" {RULE}'
          and h5.get("scope_inside") == nest
          and h5.get("nest_open") == (
              f"rename_graphic has no meaning inside nest {nest}: it renames the module for "
              "every clip in the project, the timeline's included. set_scope with no arguments "
              "comes back out; then rename.")
          and h5.get("after_refusals") == state("old", "other")
          and h5.get("renamed") == ids and h5.get("undo_name") == "Rename Graphic"
          and h5.get("after_rename") == state("new", "other")
          and h5.get("pairs") == [["old", "new"]]
          and h5.get("after_undo") == state("old", "other")
          and h5.get("after_redo") == state("new", "other"), f"{h5}")

    h6 = a.get("h6", {})
    healed, control = h6.get("healed") or {}, h6.get("control") or {}
    check("H6 a package whose project names old beside new.js and the journal pair is healed "
          "by startGraphicStore(), not edited; CONTROL: without the journal it is not",
          "save_error" not in h6 and healed.get("names") == ["old"]
          and healed.get("old_file") == h6.get("text") and healed.get("new_file") is False
          and healed.get("listed") == ["old"] and healed.get("edited") is False
          and control.get("names") == ["old"] and control.get("old_file") is None
          and control.get("new_file") is True and control.get("listed") == ["new"], f"{h6}")

    h7 = a.get("h7", {})
    clip = str(h7.get("clip", 0))
    told, tnew = (h7.get("texts") or ["", ""])[:2]
    check("H7 rename title → title-v1, a new title, the clip repointed, title-v1 deleted, "
          "undo(): title.js keeps its bytes, no title-v1.js, the clip names title-v1",
          h7.get("renamed") == [h7.get("clip")] and h7.get("repointed") == {clip: "title"}
          and h7.get("deleted") is None and h7.get("names_after_undo") == {clip: "title-v1"}
          and h7.get("title_file") == tnew and h7.get("v1_file") is False
          and h7.get("kept_v1") == [told] and h7.get("modules") == ["title"], f"{h7}")

    h8 = a.get("h8", {})
    clip = h8.get("clip", 0)
    check("H8 a rename onto a name a clip draws with no file behind it throws the drawn "
          "sentence and moves nothing",
          clip > 0 and h8.get("deleted") is None
          and h8.get("names_after_undo") == {str(clip): "ghost"}
          and h8.get("ghost_file_after_undo") is False
          and h8.get("drawn") == (f'The name "ghost" is already drawn by clip {clip} on the '
                                  f"timeline{ADVICE}")
          and h8.get("other_file") == h8.get("other_text") and h8.get("ghost_file") is False
          and h8.get("kept_ghost") == 1 and h8.get("kept_other") == 0, f"{h8}")

    h9 = a.get("h9", {})
    want = [["m20", "n20"]] + [[f"n{i}", f"m{i}"] for i in reversed(range(8, 40)) if i != 20]
    check("H9 the rename journal holds the 32 newest pairs, newest first, a repeated pair "
          "once and first",
          h9.get("limit") == 32 and len(want) == 32 and h9.get("pairs") == want,
          f"{len(h9.get('pairs', []))} pairs, first {(h9.get('pairs') or [None])[0]}")

    h10 = a.get("h10", {})
    clip = h10.get("clip", 0)
    check("H10 rename a → b, b.js removed outside the app, a new undrawn a written, a "
          "committed change: a.js keeps its bytes, no b.js, the clip names b",
          clip > 0 and h10.get("renamed") == [clip] and h10.get("kept_b") == 0
          and h10.get("pairs") == [["a", "b"]] and h10.get("tracks_added") == 1
          and h10.get("names") == {str(clip): "b"} and h10.get("text")
          and h10.get("a_file") == h10.get("text") and h10.get("b_file") is False
          and h10.get("modules") == ["a"], f"{h10}")

    h11 = a.get("h11", {})
    clip = h11.get("clip", 0)
    ttext, tnew = (h11.get("texts") or ["", ""])[:2]
    check("H11 rename a → b, a new a written and deleted, undo(): b.js keeps its bytes, no "
          "a.js, the clip names a, kept(a) is the deleted text",
          clip > 0 and h11.get("renamed") == [clip] and h11.get("deleted") is None
          and h11.get("undo_name") == "Rename Graphic"
          and h11.get("names_after_undo") == {str(clip): "a"} and h11.get("a_file") is False
          and ttext and h11.get("b_file") == ttext and h11.get("kept_a") == [tnew]
          and h11.get("modules") == ["b"], f"{h11}")

    h12 = a.get("h12", {})
    told, tcurrent = (h12.get("texts") or ["", ""])[:2]
    check("H12 a package whose m.js is also the newest of two kept texts: "
          "startGraphicStore() drops it, kept is [the older], a default restore writes the "
          "older text and keeps the current; not edited",
          "error" not in h12 and told and tcurrent
          and h12.get("built") == [f"000001-{sha(told)}.js", f"000002-{sha(tcurrent)}.js"]
          and h12.get("kept_at_start") == [told]
          and h12.get("entries_at_start") == [f"000001-{sha(told)}.js"]
          and h12.get("restored") == sha(told) and h12.get("file") == told
          and h12.get("kept_after") == [tcurrent] and h12.get("edited") is False, f"{h12}")

    h13 = a.get("h13", {})
    clip = h13.get("clip", 0)
    ta, tb = (h13.get("texts") or ["", ""])[:2]
    check("H13 a rename whose journal cannot be written is refused in the renamed sentence; "
          "the file, its kept text, the clip's name and the undo stack are where they were",
          clip > 0 and h13.get("journal_is_directory") is True
          and h13.get("refused") == ("graphics/old.js could not be renamed: its rename could "
                                     "not be journalled in graphics/history/renames.json")
          and h13.get("names") == {str(clip): "old"} and tb and h13.get("old_file") == tb
          and h13.get("new_file") is False and h13.get("kept_old") == [ta]
          and h13.get("history_new") is False and h13.get("modules") == ["old"]
          and h13.get("undo_name") == "Add Graphic", f"{h13}")

    h14 = a.get("h14", {})
    clip = h14.get("clip", 0)
    ta, tb = (h14.get("texts") or ["", ""])[:2]
    refused = h14.get("refused") or ""
    check("H14 a rename whose history cannot be folded is refused in the renamed sentence; "
          "the file, its kept text and the clip's name are where they were and the journal "
          "is as it was: no pair, no renames.json",
          clip > 0 and h14.get("in_the_way") is True
          and refused.startswith("graphics/old.js could not be renamed: ")
          and "journalled" not in refused
          and h14.get("names") == {str(clip): "old"} and tb and h14.get("old_file") == tb
          and h14.get("new_file") is False and h14.get("kept_old") == [ta]
          and h14.get("pairs") == [] and h14.get("journal_file") is False
          and h14.get("modules") == ["old"]
          and h14.get("undo_name") == "Add Graphic", f"{h14}")

    h15 = a.get("h15", {})
    crashed = h15.get("opened") or {}
    restored = h15.get("restored") or {}
    check("H15 LIMIT (G-28 (f)): new.js, the pair [old, new] and a kept text under "
          "history/old/, the project naming old — startGraphicStore() moves nothing: the "
          "clip names old, no old.js, new.js keeps its bytes, kept(old) is the kept text; a "
          "default restoreGraphic(old) then writes that OLDER text to old.js while new.js "
          "keeps the current text, undrawn, the clip names old, not edited",
          h15.get("text") and h15.get("kept") and h15.get("kept") != h15.get("text")
          and "error" not in crashed and crashed.get("names") == ["old"]
          and crashed.get("old_file") is None and crashed.get("new_file") is True
          and crashed.get("new_text") == h15.get("text")
          and crashed.get("kept_old") == [h15.get("kept")]
          and crashed.get("pairs") == [["old", "new"]] and crashed.get("listed") == ["new"]
          and crashed.get("edited") is False
          and "restore_error" not in h15 and "error" not in restored
          and restored.get("revision") == sha(h15.get("kept"))
          and restored.get("old_file") == h15.get("kept")
          and restored.get("new_text") == h15.get("text")
          and restored.get("names") == ["old"] and restored.get("drawn_new") == 0
          and restored.get("kept_old") == [] and restored.get("pairs") == [["old", "new"]]
          and restored.get("listed") == ["new", "old"]
          and restored.get("edited") is False, f"{h15}")

    h16 = a.get("h16", {})
    clip = h16.get("clip", 0)
    ta, tb = (h16.get("texts") or ["", ""])[:2]
    refused = h16.get("refused") or ""
    check("H16 rename a → b, then b → a refused at the fold (a FILE at history/a): "
          "renames.json is byte-for-byte what it was, [a, b]; with the file removed, undo() "
          "puts a.js back with its kept text and the clip names a",
          clip > 0 and h16.get("renamed") == [clip] and h16.get("in_the_way") is True
          and h16.get("pairs_before") == [["a", "b"]]
          and isinstance(h16.get("journal_before"), str)
          and refused.startswith("graphics/b.js could not be renamed: ")
          and "journalled" not in refused
          and h16.get("journal_after") == h16.get("journal_before")
          and h16.get("pairs_after") == [["a", "b"]]
          and h16.get("names_after_refusal") == {str(clip): "b"}
          and h16.get("a_file_after_refusal") is False and tb
          and h16.get("b_file_after_refusal") == tb
          and h16.get("kept_b_after_refusal") == [ta]
          and h16.get("undo_name") == "Rename Graphic"
          and h16.get("names_after_undo") == {str(clip): "a"} and h16.get("a_file") == tb
          and h16.get("b_file") is False and h16.get("kept_a") == [ta]
          and h16.get("kept_b") == [] and h16.get("modules") == ["a"], f"{h16}")

    h17 = a.get("h17", {})
    clip = h17.get("clip", 0)
    ta, tb = (h17.get("texts") or ["", ""])[:2]

    def chain(name):
        state = {"names": {str(clip): name}, "modules": [name]}
        for other in ("a", "b", "c"):
            state[f"file_{other}"] = tb if other == name else None
            state[f"kept_{other}"] = [ta] if other == name else []
            state[f"history_{other}"] = other == name
        return state

    check("H17 a chain a → b → c with a kept text: undo() twice and redo() twice, and after "
          "each step the clip's name, the one file and the kept text are under one name "
          "(a, b, c, b, a, b, c)",
          clip > 0 and ta and tb and ta != tb
          and h17.get("renamed_b") == [clip] and h17.get("renamed_c") == [clip]
          and h17.get("pairs") == [["b", "c"], ["a", "b"]]
          and [h17.get(k) for k in ("before", "after_b", "after_c", "undo_1", "undo_2",
                                     "redo_1", "redo_2")]
          == [chain(n) for n in ("a", "b", "c", "b", "a", "b", "c")], f"{h17}")

    h18 = a.get("h18", {})
    clip = h18.get("clip", 0)
    ta, tb = (h18.get("texts") or ["", ""])[:2]
    journal = (h18.get("after_rename") or {}).get("journal")
    thrown = "h18: the clips refused"

    def held(name, journal_text, pairs, undo_name):
        state = {"names": {str(clip): name}, "modules": [name], "journal": journal_text,
                 "pairs": pairs, "undo_name": undo_name}
        for other in ("a", "b", "c"):
            state[f"file_{other}"] = tb if other == name else None
            state[f"kept_{other}"] = [ta] if other == name else []
            state[f"history_{other}"] = other == name
        return state

    def left(name):
        return f"graphics/{name}.js could not be renamed: its clips did not take the new name"

    nothing = held("a", None, [], "Add Graphic")
    paired = held("b", journal, [["a", "b"]], "Rename Graphic")
    gone = h18.get("deleted_name") or {}
    gclip = gone.get("clip", 0)
    tgone, tlive1, tlive2 = (gone.get("texts") or ["", "", ""])[:3]
    try:
        journalled = json.loads(journal) if isinstance(journal, str) else None
    except json.JSONDecodeError:
        journalled = None
    failed = h18.get("failed_move_back") or {}
    fclip = failed.get("clip", 0)
    tf1, tf2 = (failed.get("texts") or ["", ""])[:2]
    check("H18 a rename refused at the clips (apply throws; apply applies nothing) with no "
          "journal and with an earlier pair [a, b]: the file, its kept text, the clip's name, "
          "the undo stack and renames.json (no file; byte-for-byte [a, b]) are where they "
          "were, and undo() of the real rename still puts a.js back; LIMIT: onto a deleted "
          "module's name the move back leaves the deleted text kept under the renamed "
          "module; a move back that fails leaves the pair [a, b], and a committed change "
          "then repairs",
          clip > 0 and ta and tb and ta != tb and h18.get("before") == nothing
          and h18.get("thrown_no_journal") == dict(nothing, refused=thrown, asked=1)
          and h18.get("left_no_journal") == dict(nothing, refused=left("a"), asked=1)
          and h18.get("renamed") == [clip] and journalled == [["a", "b"]]
          and h18.get("after_rename") == paired
          and h18.get("thrown_with_pair") == dict(paired, refused=thrown, asked=1)
          and h18.get("left_with_pair") == dict(paired, refused=left("b"), asked=1)
          and h18.get("after_undo") == held("a", (h18.get("after_undo") or {}).get("journal"),
                                            [["b", "a"]], "Add Graphic")
          and gclip > 0 and tgone and tlive1 and tlive2 and gone.get("deleted") is None
          and gone.get("kept_before") == {"gone": [tgone], "live": [tlive1]}
          and gone.get("refused") == thrown and gone.get("names") == {str(gclip): "live"}
          and gone.get("live_file") == tlive2 and gone.get("gone_file") is False
          and gone.get("kept_after") == {"gone": [], "live": [tlive1, tgone]}
          and gone.get("history_gone") is False and gone.get("kept_names") == ["live"]
          and gone.get("journal") is None and gone.get("modules") == ["live"]
          and fclip > 0 and tf1 and tf2 and tf1 != tf2 and failed.get("refused") == thrown
          and failed.get("in_the_way") is True
          and failed.get("stranded") == {
              "names": {str(fclip): "a"}, "modules": ["b"], "a_file": None, "b_file": tf2,
              "kept_a": [], "kept_b": [tf1], "pairs": [["a", "b"]]}
          and failed.get("tracks_added") == 1
          and failed.get("repaired") == {
              "names": {str(fclip): "a"}, "modules": ["a"], "a_file": tf2, "b_file": None,
              "kept_a": [tf1], "kept_b": [], "pairs": [["b", "a"]]}, f"{h18}")

    c7 = a.get("c7", {})
    ta, tb = (c7.get("texts") or ["", ""])[:2]
    check("C7 an untitled document's save carries graphics/history/ with the replaced text; "
          "the history rows' untitled roots are removed",
          "save_error" not in c7 and c7.get("entries") == [f"000001-{sha(ta)}.js"]
          and c7.get("kept_text") == ta and c7.get("module") == tb
          and a.get("history_roots_removed") is True, f"{c7}")


def probe(sources, work):
    if work.exists():
        shutil.rmtree(work)
    (work / "tmp").mkdir(parents=True)
    began = time.monotonic()
    binary, problem = build(sources, work / "build", DEADLINE)
    if binary is None:
        print(f"  FAIL the probe builds over app/Sources\n       {problem}")
        for name in ROWS:
            rows[name] = False
        return
    left = max(DEADLINE - (time.monotonic() - began), 60)
    result = bounded_run([str(binary), str(FONTS), str(PNG), str(work)], left,
                         env=child_env({"TMPDIR": str(work / "tmp") + "/"}))
    try:
        answer = json.loads(result["stdout"])
    except json.JSONDecodeError:
        answer = {}
    answer_seen.update(answer)
    if answer.get("ok") is not True:
        print(f"  FAIL the probe answers: expired {result['expired']}, rc {result['rc']}: "
              f"{result['stdout'][-300:]} {result['stderr'][-600:]}")
        for name in ROWS:
            rows[name] = False
        return
    (work / "answer.json").write_text(json.dumps(answer, indent=1, sort_keys=True))
    score(answer, work)


def replace_once(path, before, after):
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"mutation anchor {path.name}: expected once, found {count}: "
                           f"{before!r}")
    path.write_text(text.replace(before, after), encoding="utf-8")


MUTANTS = {
    "whitelist-removed": (
        "ProjectDocument.swift",
        "        if let graphics = graphicsWrapper() "
        "{ children[Self.graphicsDirectoryName] = graphics }\n",
        "", "C1"),
    "no-file-sources": (
        "GraphicStore.swift",
        "        for url in (moduleURLs + fontURLs + assetURLs).prefix(Self.fileSourceLimit) {\n"
        "            if let unwatched = arm(url, folder: false, g) { warnings.append(unwatched) }\n"
        "        }\n",
        "", "W4"),
    "no-library-file-sources": (
        "GraphicStore.swift",
        "        for url in (moduleURLs + fontURLs + assetURLs).prefix(Self.fileSourceLimit) {\n",
        "        for url in moduleURLs.prefix(Self.fileSourceLimit) {\n", "W14"),
    "silent-open": (
        "GraphicStore.swift",
        "            return \"\\(watchSubject(url, folder: folder)) is not watched: open failed "
        "(\\(why))\"\n",
        "            return nil\n", "W17"),
    "partial-left": (
        "GraphicStore+Files.swift",
        "            try? files.removeItem(at: partial)\n            throw error\n",
        "            throw error\n", "W15"),
    "scratch-kept": (
        "GraphicStore+Files.swift",
        "        guard package == nil else { return }\n"
        "        try? FileManager.default.removeItem(at: folderURL)\n",
        "", "C5"),
    "cache-kept": (
        "ProjectDocument+Graphics.swift",
        "        graphicStore = nil\n        removeTemporaryCacheDirectory()\n",
        "        graphicStore = nil\n", "C6"),
    "font-uncached": (
        "GraphicStore+Fonts.swift",
        "                cached.identity == identity\n",
        "                false\n", "W18"),
    "asset-name-kept": (
        "GraphicStore+Import.swift",
        "let legal = GraphicAssetName.legalized(name)",
        "let legal = name", "W19"),
    "asset-name-unchecked": (
        "GraphicStore.swift",
        "guard GraphicAssetName.isLegal(url.lastPathComponent) else",
        "guard true else", "W20"),
    "history-unkept": (
        "GraphicStore.swift",
        "        Self.keepReplaced(from: lastScan, to: found, in: watchedFolder)\n",
        "", "H1"),
    "history-uncapped": (
        "GraphicStore+History.swift",
        "        for entry in newestFirst.dropFirst(historyLimit) "
        "{ try? files.removeItem(at: entry.url) }\n",
        "", "H3"),
    "delete-used": (
        "ProjectDocument+GraphicFiles.swift",
        "        let groups = graphicClips(named: name)\n        guard groups.isEmpty else {\n",
        "        let groups: [(nest: UInt32?, clips: [UInt32])] = []\n"
        "        guard groups.isEmpty else {\n", "H4"),
    "rename-unreconciled": (
        "ProjectDocument+GraphicFiles.swift",
        "        guard note.userInfo?[\"isLive\"] as? Bool != true else { return }\n"
        "        reconcileGraphicNames()\n",
        "", ("H5", "H17")),
    "history-left-behind": (
        "GraphicStore+Files.swift",
        "            do {\n"
        "                try Self.moveHistory(from: from, to: to, in: folderURL)\n"
        "            } catch {\n"
        "                try? files.moveItem(at: target, to: source)\n"
        "                Self.putBackRenameJournal(journalled, in: folderURL)\n"
        "                throw error\n"
        "            }\n",
        "", "H5"),
    "reconcile-over-delete": (
        "ProjectDocument+GraphicFiles.swift",
        "                store.kept(named: x).isEmpty,\n",
        "", "H11"),
    "reconcile-both-directions": (
        "ProjectDocument+GraphicFiles.swift",
        "        for (x, y) in store.renamePairs() {\n",
        "        for (x, y) in store.renamePairs().flatMap({ [($0.0, $0.1), ($0.1, $0.0)] }) {\n",
        "H10"),
    "rename-unjournalled": (
        "GraphicStore+Files.swift",
        "            guard let newest = renamePairs().first, newest == (from, to) else {\n"
        "                try? files.moveItem(at: target, to: source)\n"
        "                throw ReelCoreError(\n"
        "                    message: \"its rename could not be journalled in graphics/\"\n"
        "                        + \"\\(Self.historyFolderName)/\\(Self.renameJournalName)\")\n"
        "            }\n",
        "", "H13"),
    "start-undropped": (
        "GraphicStore.swift",
        "            for (name, module) in found.modules {\n"
        "                Self.dropKept(revision: module.revision, named: name, in: folder)\n"
        "            }\n",
        "", "H12"),
    "restore-unhashed": (
        "ProjectDocument+GraphicFiles.swift",
        "            guard GraphicStore.hex(SHA256.hash(data: bytes)) == entry.revision else {\n",
        "            guard true else {\n", "H2"),
    "rollback-unjournalled": (
        "GraphicStore+Files.swift",
        "                Self.putBackRenameJournal(journalled, in: folderURL)\n",
        "", ("H14", "H16")),
    "moveback-unjournalled": (
        "ProjectDocument+GraphicFiles.swift",
        "                GraphicStore.putBackRenameJournal(journalled, in: store.folderURL)\n",
        "", "H18"),
    "moveback-unconditional": (
        "ProjectDocument+GraphicFiles.swift",
        "            if (try? store.moveModule(from: to, to: name)) != nil {\n",
        "            try? store.moveModule(from: to, to: name)\n            do {\n", "H18"),
    "journal-uncapped": (
        "GraphicStore+History.swift",
        "        pairs = Array(pairs.suffix(renameJournalLimit))\n",
        "", "H9"),
    "rename-onto-drawn": (
        "ProjectDocument+GraphicFiles.swift",
        "        guard drawn.isEmpty else {\n",
        "        guard true else {\n", "H8"),
    "strong-callback": (
        "ProjectDocument+Graphics.swift",
        "{ [weak self] in self?.packageContentsDidChangeOnDisk() }",
        "{ self.packageContentsDidChangeOnDisk() }", "C4"),
}


def mutant(name):
    """Rule R: 0 caught, 1 survived, 2 the control was not performed."""
    file, before, after, anchor = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"framejob-graphics-store-{name}-") as temp:
        sources = Path(temp) / "Sources"
        try:
            shutil.copytree(ROOT / "app/Sources", sources)
            replace_once(sources / file, before, after)
        except (OSError, RuntimeError) as error:
            print(f"mutant {name}: the control could not be performed — {error}")
            return 2
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}")
        probe(sources, Path(temp) / "work")
    answered = answer_seen.get("ok") is True
    if not answered:
        print(f"mutant {name}: the control could not be performed — the probe did not build "
              "or gave no answer")
        return 2
    must = anchor if isinstance(anchor, tuple) else (anchor,)
    named = " and ".join(must)
    if anchor == "C1":
        killed = answered and answer_seen.get("c1", {}).get("present") is False
    else:
        killed = answered and all(rows.get(row) is False for row in must)
    if killed:
        failed = [k for k, v in rows.items() if not v]
        print(f"MUTANT PASS: {name} — {named} FAILED in the copy (failed: {', '.join(failed)})")
        return 0
    print(f"MUTANT FAILURE: {name} — answered {answered}, "
          + ", ".join(f"{row} {rows.get(row)}" for row in must))
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("G3a — the graphics store and its watcher (probe)")
    probe(ROOT / "app/Sources", WORK)
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
