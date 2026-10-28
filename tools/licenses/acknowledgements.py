#!/usr/bin/env python3
"""The acknowledgements (#376, spec §11 PUB-10): every third-party notice the bundle owes,
written each build into `Contents/Resources/Acknowledgements.txt` by project.yml's "Write
Acknowledgements" step; byte-identical for identical inputs, written atomically.

    python3 tools/licenses/acknowledgements.py --out PATH [--strict-bun] [--sparkle-license PATH]
    python3 tools/licenses/acknowledgements.py --print-bun-version
    python3 tools/licenses/acknowledgements.py --selftest | --mutant dev-edges|nested-unchecked|bun-unchecked

Crates over every non-dev edge of `cargo metadata` (not FIRST_PARTY), npm from `agent/bun.lock`
(no dev dependency or optional peer), each with its root licence files, else `spdx/<id>.txt`
under its authors, NESTED deciding every nested licence file; then Bun (BUN_LICENSE_VERSION,
`--strict-bun` refusing another), Sparkle, the encoders, the model and the fonts. D42/D43
(dist_check.py) read the file with their own readers. The selftest is
`acknowledgements_selftest.py`; a `--mutant` fails exactly its rows: `dev-edges` G1,
`nested-unchecked` L3, `bun-unchecked` B1. Stdlib only, Python 3.9.
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple, Optional

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "licenses"
sys.path.insert(0, str(ROOT / "tools" / "codecs"))
import build_codecs  # noqa: E402  (PINS: the encoders, in order)

FIRST_PARTY = ("framejob-core", "graphic", "framejob-mcp")
CARGO_ROOTS = ("core", "mcp-proxy")
TARGET = "aarch64-apple-darwin"
BUN_LICENSE_VERSION = "1.3.6"
LICENCE_PREFIXES = ("LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE")
NESTED = {("rquickjs-sys", "quickjs/LICENSE"): True, ("rquickjs-sys", "vendor/wasi-libc/NOTICE.md"):
          False, ("fontdb", "tests/fonts/LICENSE.txt"): False,
          ("@anthropic-ai/sdk", "src/internal/qs/LICENSE.md"): True}
PATCHED = {"tiny-skia": "spec §11 PR-13"}
LIBRARY_LICENCES = {"svt-av1": "BSD-3-Clause-Clear (parts BSD-2-Clause), with the Alliance for "
                               "Open Media Patent License 1.0",
                    "libvpx": "BSD-3-Clause, with the WebM Project's patent grant"}
SPARKLE_LICENSE = Path("SourcePackages/artifacts/sparkle/Sparkle/LICENSE")
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"
EXPECTED = {"dev-edges": {"G1"}, "nested-unchecked": {"L3"}, "bun-unchecked": {"B1"}}
MUTANT = None
PREAMBLE = ("Frame Job is licensed under the Apache License, Version 2.0. It includes the "
            "third-party software below, each under the licence its entry names, followed by "
            "that licence's full text (or, where the same text appeared above, a pointer to it).")


class Entry(NamedTuple):
    kind: str
    name: str
    version: str
    licence: str
    source: str
    texts: tuple  # ((label, text), ...)


class Failed(RuntimeError):
    pass


def read(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def cargo_packages(metadata: dict) -> list:
    """Package dicts reachable from resolve.root over non-dev edges, FIRST_PARTY removed."""
    packages = {p["id"]: p for p in metadata["packages"]}
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    seen, stack = set(), [metadata["resolve"]["root"]]
    while stack:
        current = stack.pop()
        if current not in seen:
            seen.add(current)
            stack += [d["pkg"] for d in nodes[current].get("deps", []) if MUTANT == "dev-edges"
                      or any(k.get("kind") != "dev" for k in d.get("dep_kinds", []))]
    return [packages[i] for i in sorted(seen) if packages[i]["name"] not in FIRST_PARTY]


def npm_packages(lock_text: str) -> list:
    """[(name, version, folder)] from workspaces[""].dependencies through each package's
    "dependencies"; not devDependencies, not optionalPeers. A dependency resolves as Node does:
    bun's nested key under the dependent's own chain (`a/b/c`), else under each shorter chain
    (`a/c`), else the hoisted `c`; `folder` is its folder under agent/
    (`node_modules/a/node_modules/c`)."""
    lock = json.loads(re.sub(r",(\s*[}\]])", r"\1", lock_text))
    entries, found = lock.get("packages", {}), {}
    stack = [((), name) for name in sorted(lock["workspaces"][""].get("dependencies", {}))]
    while stack:
        chain, name = stack.pop()
        paths = [chain[:level] + (name,) for level in range(len(chain), -1, -1)]
        path = next((p for p in paths if "/".join(p) in entries), None)
        if path is None:
            raise Failed(f"acknowledgements: {name} is not in agent/bun.lock's packages")
        key = "/".join(path)
        if key in found:
            continue
        entry = entries[key]
        folder = "/".join(f"node_modules/{part}" for part in path)
        found[key] = (name, entry[0].rsplit("@", 1)[1], folder)
        meta = entry[2] if len(entry) > 2 and isinstance(entry[2], dict) else {}
        stack += [(path, dep) for dep in sorted(meta.get("dependencies", {}))]
    return sorted(set(found.values()))


def licence_texts(directory: Path, owner: str, licence: str, authors: list) -> tuple:
    """((label, text), ...): the root licence files, else the canonical SPDX texts under the
    authors; then each nested licence file NESTED includes."""
    directory = Path(directory)
    texts = [(p.name, read(p)) for p in sorted(directory.iterdir())
             if p.is_file() and p.name.upper().startswith(LICENCE_PREFIXES)]
    if not texts:
        if not licence:
            raise Failed(f"acknowledgements: {owner} ships no licence file and declares none")
        holders = ", ".join(authors) if authors else f"the {owner} authors"
        ids = [t for t in re.findall(r"[A-Za-z0-9.+-]+", licence) if t not in ("AND", "OR", "WITH")]
        if " AND " not in licence and "(" not in licence:  # alternatives: the first with a text
            ids = [i for i in ids if (HERE / "spdx" / f"{i}.txt").is_file()][:1] or ids
        for spdx in ids:
            canonical = HERE / "spdx" / f"{spdx}.txt"
            if not canonical.is_file():
                raise Failed(f"acknowledgements: {owner} ships no licence file and there is no "
                             f"canonical text for {spdx} (tools/licenses/spdx/{spdx}.txt)")
            texts.append((f"{spdx} (the SPDX text; {owner} ships no licence file)",
                          f"Copyright (c) {holders}\n\n{read(canonical)}"))
    for folder, dirs, files in os.walk(directory):
        here = Path(folder)
        dirs[:] = sorted(d for d in dirs if d not in ("target", "node_modules")
                         and not (here / d / "Cargo.toml").exists()
                         and not (here / d / "package.json").exists())
        for name in sorted(files) if here != directory else ():
            relative = (here / name).relative_to(directory).as_posix()
            listed = NESTED.get((owner, relative))
            licence_file = name.upper().startswith(LICENCE_PREFIXES)
            if licence_file and listed is None and MUTANT != "nested-unchecked":
                raise Failed(f"acknowledgements: {owner}'s nested licence file {relative} is "
                             "not in NESTED (tools/licenses/acknowledgements.py); list it")
            if licence_file and listed:
                texts.append((relative, read(here / name)))
    return tuple(texts)


def font_revision(path: Path) -> str:
    """The `head` table's fontRevision (16.16 fixed), to three decimals."""
    data = Path(path).read_bytes()
    count = struct.unpack(">H", data[4:6])[0] if len(data) >= 12 else 0
    for index in range(count):
        tag, _, offset, _ = struct.unpack(">4sIII", data[12 + 16 * index:28 + 16 * index])
        if tag == b"head":
            return f"{struct.unpack('>i', data[offset + 4:offset + 8])[0] / 65536:.3f}"
    raise Failed(f"acknowledgements: {path} has no sfnt head table")


def bun_check(found, strict):
    """None when `found` is BUN_LICENSE_VERSION; else Failed under `strict`, or the note."""
    if found == BUN_LICENSE_VERSION:
        return None
    message = (f"bun --version is {found or '(no bun found)'}, but the vendored licence is Bun "
               f"{BUN_LICENSE_VERSION}'s; re-vendor it (tools/licenses/PROVENANCE.md)")
    if strict and MUTANT != "bun-unchecked":
        raise Failed(f"acknowledgements: {message}")
    return message


def _crates(root):
    found = {}
    for folder in CARGO_ROOTS:
        argv = ["cargo", "metadata", "--format-version", "1", "--locked", "--offline",
                "--filter-platform", TARGET]
        done = subprocess.run(argv, cwd=str(root / folder), capture_output=True, text=True)
        if done.returncode != 0:
            raise Failed(f"acknowledgements: {' '.join(argv)} in {folder}/ exited "
                         f"{done.returncode}: {done.stderr.strip()[-300:]}")
        found.update((p["id"], p) for p in cargo_packages(json.loads(done.stdout)))
    entries = []
    for p in sorted(found.values(), key=lambda p: (p["name"], p["version"])):
        directory = Path(p["manifest_path"]).parent
        source = "crates.io" if p.get("source") == CRATES_IO else p.get("source")
        if source is None:
            patched = f" (patched, {PATCHED[p['name']]})" if p["name"] in PATCHED else ""
            source = f"vendored at {os.path.relpath(directory, root)}{patched}"
        licence = p.get("license") or ""
        texts = licence_texts(directory, p["name"], licence, p.get("authors") or [])
        entries.append(Entry("crate", p["name"], p["version"], licence or "(none declared)",
                             source, texts))
    return entries


def _npm(root):
    entries = []
    for name, version, folder in npm_packages(read(root / "agent" / "bun.lock")):
        directory = root / "agent" / folder
        try:
            manifest = json.loads(read(directory / "package.json"))
        except (OSError, ValueError) as error:
            raise Failed(f"acknowledgements: agent/{folder}/package.json: {error}")
        if manifest.get("version") != version:
            raise Failed(f"acknowledgements: agent/bun.lock pins {name} {version}, but "
                         f"agent/{folder} holds {manifest.get('version')} (run bun install)")
        licence, author = manifest.get("license") or "", manifest.get("author")
        licence = licence.get("type", "") if isinstance(licence, dict) else licence
        author = author.get("name") if isinstance(author, dict) else author
        texts = licence_texts(directory, name, licence, [author] if author else [])
        entries.append(Entry("npm", name, version, licence or "(none declared)", "npm", texts))
    return sorted(entries, key=lambda e: e.name)


def _sparkle(root, build_dir, sparkle_license):
    if sparkle_license is None:
        starts = [Path(build_dir)] if build_dir else []
        tried = [folder / SPARKLE_LICENSE for start in starts for folder in [start, *start.parents]]
        tried.append(root / "build" / SPARKLE_LICENSE)
        sparkle_license = next((path for path in tried if path.is_file()), None)
        if sparkle_license is None:
            raise Failed("acknowledgements: Sparkle's LICENSE is in none of "
                         + ", ".join(map(str, tried)))
    state_path = Path(sparkle_license).parents[3] / "workspace-state.json"
    try:
        version = [d["state"]["checkoutState"]["version"]
                   for d in json.loads(read(state_path))["object"]["dependencies"]
                   if d["packageRef"]["identity"] == "sparkle"][0]
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        raise Failed(f"acknowledgements: no resolved sparkle version in {state_path}: {error!r}")
    return Entry("framework", "sparkle", version, "MIT (with the notices its LICENSE lists)",
                 "https://github.com/sparkle-project/Sparkle", (("LICENSE", read(sparkle_license)),))


def collect(root: Path, build_dir: Optional[str], strict_bun: bool,
            sparkle_license: Optional[Path]) -> list:
    root = Path(root)
    entries = _crates(root) + _npm(root)
    bun = shutil.which("bun")
    done = bun and subprocess.run([bun, "--version"], capture_output=True, text=True, timeout=60)
    note = bun_check(done.stdout.strip() if done and done.returncode == 0 else None, strict_bun)
    if note:
        print(f"warning: {note}", file=sys.stderr, flush=True)
    entries.append(Entry(
        "runtime", "bun", BUN_LICENSE_VERSION,
        "MIT; it embeds JavaScriptCore and WebKit (LGPL-2) and the libraries its notice lists",
        f"https://github.com/oven-sh/bun/tree/bun-v{BUN_LICENSE_VERSION}",
        ((("note", note),) if note else ()) + (("LICENSE.md", read(HERE / "bun/LICENSE.txt")),)))
    entries.append(_sparkle(root, build_dir, sparkle_license))
    for pin in build_codecs.PINS:
        paths = [root / "build/codecs/licenses" / pin.name / name for _, name in pin.licenses]
        entries.append(Entry("library", pin.name, pin.version, LIBRARY_LICENCES[pin.name],
                             pin.url, tuple((path.name, read(path)) for path in paths)))
    models = root / "app/Resources/Models"
    tag = re.search(r"tag `v([^`]+)`", read(models / "PROVENANCE.md"))
    if tag is None:
        raise Failed("acknowledgements: no tag `vX` in app/Resources/Models/PROVENANCE.md")
    entries.append(Entry("model", "silero-vad", tag.group(1), "MIT",
                         "https://github.com/snakers4/silero-vad",
                         (("LICENSE", read(models / "LICENSE")),)))
    fonts = root / "app/Resources/Fonts"
    for font in sorted(fonts.glob("*.ttf"), key=lambda p: p.stem):
        ofl = fonts / f"OFL-{font.stem.split('-')[0]}.txt"
        if not ofl.is_file():
            raise Failed(f"acknowledgements: {font.name} has no {ofl.name} beside it")
        entries.append(Entry("font", font.stem, font_revision(font), "OFL-1.1",
                             "vendored at app/Resources/Fonts", ((ofl.name, read(ofl)),)))
    return entries


def render(entries: list) -> str:
    out, first = ["Frame Job — third-party software notices", "Generated at build time by "
                  "tools/licenses/acknowledgements.py; do not edit.", PREAMBLE, ""], {}
    for e in entries:
        out += [f"== {e.kind} {e.name} {e.version} ==", f"Licence: {e.licence}",
                f"Source: {e.source}"]
        for label, text in e.texts:
            out.append(f"--- {label} ---")
            if text in first:
                out.append(f"(identical to {first[text]}, above)")
            else:
                first[text] = f"{e.kind} {e.name} {e.version}'s {label}"
                out.append(text.rstrip("\n"))
        out.append("")
    return "\n".join(out)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="the acknowledgements (#376, spec §11 PUB-10)")
    parser.add_argument("--out", help="where to write Acknowledgements.txt")
    parser.add_argument("--strict-bun", action="store_true",
                        help="fail when bun --version is not BUN_LICENSE_VERSION (Distribution)")
    parser.add_argument("--sparkle-license", help="Sparkle's LICENSE, else found from $BUILD_DIR")
    parser.add_argument("--print-bun-version", action="store_true", help="for setup-bun")
    parser.add_argument("--selftest", action="store_true", help="D0 T1 G1 G2 N1 N2 L1–L4 F1 B1")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    args = parser.parse_args(argv)
    if args.selftest or args.mutant:
        import acknowledgements_selftest  # beside this file, so on sys.path[0]
        return acknowledgements_selftest.selftest(args.mutant)
    if args.print_bun_version:
        print(BUN_LICENSE_VERSION)
        return 0
    if not args.out:
        parser.error("--out is required")
    try:
        sparkle = Path(args.sparkle_license) if args.sparkle_license else None
        entries = collect(ROOT, os.environ.get("BUILD_DIR"), args.strict_bun, sparkle)
        out = Path(args.out)  # atomically: a temporary file beside it, then os.replace
        out.parent.mkdir(parents=True, exist_ok=True)
        handle, temporary = tempfile.mkstemp(prefix=".acknowledgements-", dir=str(out.parent))
        try:
            with os.fdopen(handle, "w", encoding="utf-8") as stream:
                stream.write(render(entries))
            os.chmod(temporary, 0o644)
            os.replace(temporary, out)
        finally:
            if os.path.exists(temporary):  # not replaced: never left for the seal
                os.unlink(temporary)
    except (Failed, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr, flush=True)
        return 1
    print(f"acknowledgements: {len(entries)} entries in {args.out}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
