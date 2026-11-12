#!/usr/bin/env python3
"""The acknowledgements (#376, spec §11 PUB-10, SA-10): every third-party notice the bundle
owes, written each build into `Contents/Resources/Acknowledgements.txt` by project.yml's "Write
Acknowledgements" step; byte-identical for identical inputs, written atomically.

    python3 tools/licenses/acknowledgements.py --out PATH [--agent-scratch PATH] [--sparkle-license PATH]
    python3 tools/licenses/acknowledgements.py --selftest | --mutant dev-edges|nested-unchecked|slaude-missing-ok

Crates over every non-dev edge of `cargo metadata` (not FIRST_PARTY), each with its root licence
files, else `spdx/<id>.txt` under its authors, NESTED deciding every nested licence file; then
Slaude, the assistant helper's one dependency (spec §11 SA-10), from the helper's SwiftPM scratch
path (`--agent-scratch`, which project.yml passes as `$PROJECT_DIR/build/agent-swift`, else the
tree's): its revision from `workspace-state.json`, its texts from the resolved checkout; then
Sparkle, the encoders, the model and the fonts. D42/D43 (dist_check.py) read the file with their
own readers. The selftest is `acknowledgements_selftest.py`; a `--mutant` fails exactly its rows:
`dev-edges` G1, `nested-unchecked` L3, `slaude-missing-ok` S2. Stdlib only, Python 3.9.
"""

import argparse
import json
import os
import re
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
LICENCE_PREFIXES = ("LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE")
# Slaude's sources are transformed from Anthropic's Python SDK, vendored under `upstream/`, which
# keeps its own licences (Slaude's README): both are listed. `httpx_aiohttp` is a Python transport
# that SDK vendors; nothing of it ships in the helper (spec §11 SA-10).
SLAUDE_SDK = "upstream/anthropic-sdk-python"
NESTED = {("rquickjs-sys", "quickjs/LICENSE"): True, ("rquickjs-sys", "vendor/wasi-libc/NOTICE.md"):
          False, ("fontdb", "tests/fonts/LICENSE.txt"): False,
          ("slaude", f"{SLAUDE_SDK}/LICENSE"): True, ("slaude", f"{SLAUDE_SDK}/LICENSE-MIT"): True,
          ("slaude", f"{SLAUDE_SDK}/src/anthropic/_vendor/httpx_aiohttp/LICENSE"): False,
          ("slaude", f"{SLAUDE_SDK}/src/anthropic/_vendor/httpx_aiohttp/NOTICE.md"): False}
PATCHED = {"tiny-skia": "spec §11 PR-13"}
LIBRARY_LICENCES = {"svt-av1": "BSD-3-Clause-Clear (parts BSD-2-Clause), with the Alliance for "
                               "Open Media Patent License 1.0",
                    "libvpx": "BSD-3-Clause, with the WebM Project's patent grant"}
SPARKLE_LICENSE = Path("SourcePackages/artifacts/sparkle/Sparkle/LICENSE")
AGENT_SCRATCH = Path("build/agent-swift")
SLAUDE = ("slaude", "https://github.com/kpgalligan/Slaude",
          "Apache-2.0 (the Anthropic Python SDK it is transformed from: Apache-2.0, and MIT for "
          "that SDK's versions and contributions before its 2.0.0)")
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"
EXPECTED = {"dev-edges": {"G1"}, "nested-unchecked": {"L3"}, "slaude-missing-ok": {"S2"}}
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
        dirs[:] = sorted(d for d in dirs if d not in ("target", "node_modules", ".git")
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


def _slaude(scratch):
    """Slaude's entry: its revision and checkout from the helper's SwiftPM scratch path."""
    name, source, licence = SLAUDE
    state_path = Path(scratch) / "workspace-state.json"
    try:
        found = [d for d in json.loads(read(state_path))["object"]["dependencies"]
                 if d["packageRef"]["identity"] == name][0]
        revision = found["state"]["checkoutState"]["revision"]
        checkout = Path(scratch) / "checkouts" / found["subpath"]
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        raise Failed(f"acknowledgements: no resolved {name} revision in {state_path} (the "
                     f"assistant helper's SwiftPM scratch path; Build Agent Helper makes it): "
                     f"{error!r}")
    if not checkout.is_dir():
        if MUTANT == "slaude-missing-ok":
            return None
        raise Failed(f"acknowledgements: {name}'s checkout {checkout} is missing")
    texts = licence_texts(checkout, name, "Apache-2.0", [])
    return Entry("package", name, revision, licence, source, texts)


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


def collect(root: Path, build_dir: Optional[str], agent_scratch: Optional[Path],
            sparkle_license: Optional[Path]) -> list:
    root = Path(root)
    entries = _crates(root)
    slaude = _slaude(agent_scratch if agent_scratch is not None else root / AGENT_SCRATCH)
    if slaude is not None:
        entries.append(slaude)
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
    parser.add_argument("--agent-scratch",
                        help="the assistant helper's SwiftPM scratch path, Slaude's checkout's "
                             "(project.yml: $PROJECT_DIR/build/agent-swift; else the tree's)")
    parser.add_argument("--sparkle-license", help="Sparkle's LICENSE, else found from $BUILD_DIR")
    parser.add_argument("--selftest", action="store_true", help="D0 T1 G1 G2 L1–L4 F1 S1 S2")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    args = parser.parse_args(argv)
    if args.selftest or args.mutant:
        import acknowledgements_selftest  # beside this file, so on sys.path[0]
        return acknowledgements_selftest.selftest(args.mutant)
    if not args.out:
        parser.error("--out is required")
    try:
        sparkle = Path(args.sparkle_license) if args.sparkle_license else None
        scratch = Path(args.agent_scratch) if args.agent_scratch else None
        entries = collect(ROOT, os.environ.get("BUILD_DIR"), scratch, sparkle)
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
