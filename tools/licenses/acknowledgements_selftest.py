"""The acknowledgements generator's selftest (#376, spec §11 PUB-10, SA-10): no cargo, no
network, no SwiftPM, scratch only. Run through the generator, never alone:

    python3 tools/licenses/acknowledgements.py --selftest | --mutant dev-edges|nested-unchecked|slaude-missing-ok

Rows: D0 T1 the render; G1 G2 the crate walk; L1–L4 the licence texts; F1 the font revision;
S1 S2 Slaude's entry from a synthetic SwiftPM scratch path. A `--mutant`
(acknowledgements.EXPECTED) must fail exactly its rows.
"""

import json
import shutil
import struct
import tempfile
from pathlib import Path

import acknowledgements as ack
from acknowledgements import Entry, Failed


def node(identifier, *deps):
    return {"id": identifier,
            "deps": [{"pkg": d, "dep_kinds": [{"kind": k}]} for d, k in deps]}


def failure(call):
    try:
        call()
    except Failed as error:
        return str(error)
    return None


def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def selftest(mutant=None):
    ack.MUTANT = mutant
    results = []

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    scratch = Path(tempfile.mkdtemp(prefix="acknowledgements-selftest-"))
    try:
        entries = [Entry("crate", "a", "1.0", "MIT", "crates.io", (("LICENSE", "text a\n"),)),
                   Entry("crate", "b", "2.0", "MIT", "crates.io", (("LICENSE", "text a\n"),)),
                   Entry("font", "F-Bold", "1.500", "OFL-1.1", "x", (("OFL-F.txt", "ofl\n"),))]
        one, two = ack.render(entries), ack.render(list(entries))
        row("D0", one.encode() == two.encode(),
            f"CONTROL: two renders are byte-identical ({len(one)} characters)")
        row("T1", "(identical to crate a 1.0's LICENSE, above)" in one
            and one.count("\ntext a\n") == 1, "a repeated text becomes the 'identical to' line")

        ids = ("framejob-core", "graphic", "lib", "devonly", "buildonly", "devdeep")
        metadata = {"packages": [{"id": i, "name": i, "version": "1"} for i in ids],
                    "resolve": {"root": "framejob-core", "nodes": [
                        node("framejob-core", ("graphic", None), ("devonly", "dev"),
                             ("buildonly", "build")),
                        node("graphic", ("lib", None)), node("lib"),
                        node("devonly", ("devdeep", None)), node("buildonly"), node("devdeep")]}}
        names = {p["name"] for p in ack.cargo_packages(metadata)}
        row("G1", not names & {"devonly", "devdeep", *ack.FIRST_PARTY} and "lib" in names,
            f"dev edges and first-party are excluded: {sorted(names)}")
        row("G2", "buildonly" in names, f"build edges are included: {sorted(names)}")

        (scratch / "bare").mkdir()
        texts = ack.licence_texts(scratch / "bare", "bare", "MIT", ["Ann <ann@example.com>"])
        row("L1", len(texts) == 1 and texts[0][1].startswith("Copyright (c) Ann <ann@example")
            and "Permission is hereby granted" in texts[0][1],
            f"no licence file gives the SPDX text under the authors: {[t[0] for t in texts]}")
        why = failure(lambda: ack.licence_texts(scratch / "bare", "bare", "Foo-1.0", []))
        row("L2", why is not None and "bare" in why and "Foo-1.0" in why,
            f"no canonical text fails naming the package and id: {why}")
        for path in ("nested/LICENSE", "nested/sub/COPYING"):
            put(scratch / path, f"{path}\n")
        why = failure(lambda: ack.licence_texts(scratch / "nested", "nested", "MIT", []))
        row("L3", why is not None and "sub/COPYING" in why,
            f"an unlisted nested licence fails, naming it: {why}")
        listed = scratch / "rquickjs-sys"
        for path in ("quickjs/LICENSE", "vendor/wasi-libc/NOTICE.md", "crate/Cargo.toml",
                     "crate/LICENSE"):
            put(listed / path, f"{path}\n")
        labels = [label for label, _ in ack.licence_texts(listed, "rquickjs-sys", "MIT", [])]
        row("L4", "quickjs/LICENSE" in labels and "vendor/wasi-libc/NOTICE.md" not in labels
            and "crate/LICENSE" not in labels,
            f"a listed include is written, an exclude is not: {labels}")

        head = struct.pack(">IIiI", 0x00010000, 0x00018000, 0, 0x5F0F3CF5)
        sfnt = struct.pack(">IHHHH4sIII", 0x00010000, 1, 16, 0, 0, b"head", 0, 28, len(head))
        (scratch / "font.ttf").write_bytes(sfnt + head)
        got = ack.font_revision(scratch / "font.ttf")
        row("F1", got == "1.500", f"the font revision is read from a synthetic sfnt: {got}")

        revision = "4c6c2ca435350741796c3d461720a61e7149b378"
        state = {"object": {"dependencies": [{
            "packageRef": {"identity": "slaude", "kind": "remoteSourceControl",
                           "location": "https://github.com/kpgalligan/Slaude", "name": "Slaude"},
            "state": {"checkoutState": {"revision": revision}, "name": "sourceControlCheckout"},
            "subpath": "Slaude"}]}, "version": 7}
        swiftpm = scratch / "agent-swift"
        put(swiftpm / "workspace-state.json", json.dumps(state))
        sdk = "upstream/anthropic-sdk-python"
        vendored = f"{sdk}/src/anthropic/_vendor/httpx_aiohttp"
        for name in ("LICENSE", f"{sdk}/LICENSE", f"{sdk}/LICENSE-MIT", f"{vendored}/LICENSE",
                     f"{vendored}/NOTICE.md", ".git/NOTICE", "Sources/Anthropic/Client.swift"):
            put(swiftpm / "checkouts" / "Slaude" / name, f"{name}\n")
        why = failure(lambda: ack._slaude(swiftpm))
        entry = ack._slaude(swiftpm) if why is None else None
        labels = [label for label, _ in entry.texts] if entry else why
        row("S1", entry is not None and (entry.kind, entry.name, entry.version)
            == ("package", "slaude", revision)
            and labels == ["LICENSE", f"{sdk}/LICENSE", f"{sdk}/LICENSE-MIT"]
            and "== package slaude " + revision + " ==" in ack.render([entry]),
            f"a synthetic scratch path gives the entry and its three texts: "
            f"{(entry.kind, entry.name, entry.version) if entry else None}, {labels}")
        shutil.rmtree(swiftpm / "checkouts")
        missing = None
        try:
            entry = ack._slaude(swiftpm)
        except Failed as error:
            missing, entry = str(error), None
        row("S2", missing is not None and str(swiftpm / "checkouts" / "Slaude") in missing,
            f"a missing checkout fails, naming it: {missing or f'answered {entry!r}'}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    if mutant:
        ok = failed == ack.EXPECTED[mutant]
        print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
              f"{sorted(ack.EXPECTED[mutant])}")
    else:
        ok = not failed
        print("PASS" if ok else "FAIL")
    return 0 if ok else 1
