#!/usr/bin/env python3
"""The package's `graphics/` store and its watcher: road map 10's G3a (§10.6).

Builds `graphics_store_probe.swift` over `app/Sources` with
`tools/proof/harness/build.sh`'s swiftc line (a probe that will not build is a
scored FAILURE of every row, never an exit), runs it under
`graphics_spike/bounded.py`'s `run` with `TMPDIR=<work>/tmp`, and scores what
it measured against oracles of its own — hashlib for every revision, this
file's literals for every sentence:

W1  an untitled store makes its root under `NSTemporaryDirectory()/Reelcut/`
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

A mutant is built from a COPY of `app/Sources` with one anchor, asserted to
occur exactly once, replaced. Rule R: exit 0 means the row it names FAILED in
the copy (C1's file ABSENT, W4, C4, W15, C5, C6, W14, W17, W18, W19, W20) — caught; exit 1
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
the scan's `isLegal` guard `true`.
"""

import hashlib
import json
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
from bounded import child_env, run as bounded_run  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-store-probe"
FONTS = ROOT / "app/Resources/Fonts"
PNG = ROOT / "app/Assets.xcassets/AppIcon.appiconset/icon_16.png"
DEADLINE = 600
RULE = ("is not a module name (lowercase letters, digits and -, starting with a letter "
        "or a digit, at most 63 characters)")
ROWS = ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11", "W12", "W13",
        "W14", "W15", "W16", "W17", "W18", "W19", "W20", "C1", "C2", "C3", "C4", "C5", "C6"]
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
    sdk = bounded_run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = bounded_run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry), "-o", str(binary)],
        seconds)
    if result["expired"]:
        return None, f"the build did not finish within {seconds} s"
    if result["rc"]:
        errors = [line for line in result["stderr"].splitlines() if ": error:" in line]
        return None, "; ".join(errors[:8]) or result["stderr"][-600:]
    return binary, ""


def score(a, work):
    # NSTemporaryDirectory() ignores TMPDIR on this host, so the root is
    # scored against the directory the probe itself reports.
    tmp = str((Path(a.get("tmp", "/nonexistent")) / "Reelcut").resolve()) + "/"

    def under_tmp(path):
        return isinstance(path, str) and str(Path(path).resolve()).startswith(tmp)

    w1 = a.get("w1", {})
    check("W1 the untitled root is made in the temporary directory at start(), empty, silent",
          w1.get("exists") is True and under_tmp(w1.get("folder"))
          and str(w1.get("folder", "")).endswith("-graphics")
          and Path(w1.get("folder", "")).parent.name == "Reelcut"
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
    "strong-callback": (
        "ProjectDocument+Graphics.swift",
        "{ [weak self] in self?.packageContentsDidChangeOnDisk() }",
        "{ self.packageContentsDidChangeOnDisk() }", "C4"),
}


def mutant(name):
    """Rule R: 0 caught, 1 survived, 2 the control was not performed."""
    file, before, after, anchor = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"reelcut-graphics-store-{name}-") as temp:
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
    if anchor == "C1":
        killed = answered and answer_seen.get("c1", {}).get("present") is False
    else:
        killed = answered and rows.get(anchor) is False
    if killed:
        failed = [k for k, v in rows.items() if not v]
        print(f"MUTANT PASS: {name} — {anchor} FAILED in the copy (failed: {', '.join(failed)})")
        return 0
    print(f"MUTANT FAILURE: {name} — answered {answered}, {anchor} {rows.get(anchor)}")
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
