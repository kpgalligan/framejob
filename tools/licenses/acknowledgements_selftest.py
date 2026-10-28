"""The acknowledgements generator's selftest (#376, spec §11 PUB-10): no cargo, no network,
scratch only. Run through the generator, never alone:

    python3 tools/licenses/acknowledgements.py --selftest | --mutant dev-edges|nested-unchecked|bun-unchecked

Rows: D0 T1 the render; G1 G2 the crate walk; N1 N2 the npm walk; L1–L4 the licence texts;
F1 the font revision; B1 the Bun pin. A `--mutant` (acknowledgements.EXPECTED) must fail
exactly its rows.
"""

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

        lock = """{ "workspaces": { "": { "dependencies": { "a": "^1", }, "devDependencies": {
    "dev": "^1", }, }, }, "packages": { "a": ["a@1.2.0", "", { "dependencies": { "b": "^2", },
    "peerDependencies": { "p": "^1" }, "optionalPeers": ["p"], }, "sha512-x"], "b": ["b@2.0.1",
    "", {}, "y"], "dev": ["dev@1.0.0", "", {}, "z"], "p": ["p@1.0.0", "", {}, "w"], } }"""
        got = ack.npm_packages(lock)
        row("N1", got == [("a", "1.2.0", "node_modules/a"), ("b", "2.0.1", "node_modules/b")],
            f"a trailing-comma lock skips dev deps and optional peers: {got}")
        nested = """{ "workspaces": { "": { "dependencies": { "@s/a": "^1", "c": "^1" } } },
    "packages": { "@s/a": ["@s/a@1.0.0", "", { "dependencies": { "b": "^1" } }, "x"],
    "@s/a/b": ["b@1.0.0", "", { "dependencies": { "d": "^1", "e": "^1" } }, "x"],
    "@s/a/e": ["e@3.0.0", "", {}, "x"], "b": ["b@2.0.1", "", {}, "x"],
    "c": ["c@1.0.0", "", { "dependencies": { "b": "^2" } }, "x"],
    "d": ["d@1.0.0", "", {}, "x"], "e": ["e@1.0.0", "", {}, "x"] } }"""
        got = ack.npm_packages(nested)
        want = [("@s/a", "1.0.0", "node_modules/@s/a"),
                ("b", "1.0.0", "node_modules/@s/a/node_modules/b"),
                ("b", "2.0.1", "node_modules/b"), ("c", "1.0.0", "node_modules/c"),
                ("d", "1.0.0", "node_modules/d"),
                ("e", "3.0.0", "node_modules/@s/a/node_modules/e")]
        row("N2", got == want, f"nested keys resolve to the nearest chain and its folder: {got}")

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

        pinned = ack.BUN_LICENSE_VERSION
        other = "0.0.1" if pinned != "0.0.1" else "0.0.2"
        why, note = failure(lambda: ack.bun_check(other, True)), ack.bun_check(other, False)
        row("B1", why is not None and other in why and note is not None
            and pinned in note and ack.bun_check(pinned, True) is None,
            f"a Bun mismatch fails under --strict-bun ({why}) and is noted without it")
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
