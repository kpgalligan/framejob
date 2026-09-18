#!/usr/bin/env python3
"""The op table, read back through the APP — `rc_op_schemas` from Swift.

Road map 7's D3·2 publishes every op's ARGUMENTS as JSON Schema and
`ReelOp.coreSchemas()` is the app's one reader of it. Nothing in the app
CALLS that reader yet — the catalog is migrated in a later ticket, and until
then `tools/list` returns exactly the schemas it always did — so there is no
MCP surface to measure and the instrument is the shape `CLAUDE.md` names for
app STRUCTURE no script can reach: a probe compiled out of `app/Sources`
over `harness/build.sh`'s own swiftc line, not a photograph.

What it measures, all of it through the wrapper the catalog will use:

  * **Every op has a schema and no other name does.** `coreSchemas()`'s keys
    against `coreNames()`'s names, in both directions. The two are separate
    reads of two separate exports, and nothing on the Swift side derives one
    from the other, so a schema map that had dropped an op — or invented one
    — is named here.
  * **Each schema declares exactly the arguments the DECODER has.** For each
    of the 57 ops the probe sends an envelope carrying one key no op has;
    serde refuses it with the list of fields it DID expect, and that list is
    compared to the published properties. **No argument name is written in
    this file** — the oracle is the core's own decoder, answering the built
    binary's staticlib, which is the instrument spec kpgalligan/reelcut#14
    asks for in place of the Python literals the older proofs use.
  * **`required` is a subset of the properties**, so a schema cannot demand
    an argument it does not declare — and it is the DECODER's required-ness:
    the same op sent with no arguments at all makes serde name the first
    field it could not do without, which must be one the schema calls
    required, and an op whose schema requires nothing must produce no such
    complaint.
  * **The envelope's `scope` is in no schema.** It is not an argument of any
    op; the catalog injects it, and it is the fourth part of the startup
    parity check's business, not the table's. `project` likewise.
  * **The kinds arrive as kinds.** One representative argument per kind,
    with the JSON Schema the mapping says it must be. These twelve rows are
    literals on purpose: they are the one claim a probe reading the core's
    own answer cannot make about itself, and they are about the MAPPING, not
    about which arguments exist.

A probe that will not build is a scored FAILURE, never an exit.

    python3 tools/proof/op_schema_probe.py
"""

import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "op-schema-probe")

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


# --------------------------------------------------------------------------
# The probe. It reads both exports through their Swift wrappers, asks the
# decoder what each op's arguments are, and prints one JSON object.

PROBE_SOURCE = r'''
import Foundation

func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

var answer: [String: Any] = [:]
func fail(_ why: String) -> Never {
    answer["error"] = why
    write(answer)
    exit(0)
}

// The two halves of the op table, read back through the only file in the
// app that may name an `rc_*` symbol.
let names = ReelOp.coreNames()
answer["names"] = names

var schemas: [String: Any] = [:]
for (name, schema) in ReelOp.coreSchemas() {
    schemas[name] = ["properties": schema.properties, "required": schema.required]
}
answer["schemas"] = schemas

// What the DECODER says, asked of the same staticlib: one envelope per op
// carrying a key no op has. serde refuses it with the fields it wanted, and
// the scorer reads the names out of that sentence rather than typing any.
guard let project = ReelProject.new(width: 1920, height: 1080, fps: .thirty) else {
    fail("ReelProject.new answered nil")
}
func answered(_ name: String, _ args: [String: Any]) -> String {
    do {
        _ = try project.applying(ReelOp(name: name, args: args))
        return ""
    } catch let error as ReelCoreError {
        return error.message
    } catch {
        return "\(error)"
    }
}

var decoder: [String: String] = [:]
var bare: [String: String] = [:]
for name in names {
    decoder[name] = answered(name, ["zz_not_an_argument": 1])
    // The same op with NO arguments at all: serde names the FIRST field it
    // could not do without, which is the decoder's own word on required-ness.
    bare[name] = answered(name, [:])
}
answer["decoder"] = decoder
answer["bare"] = bare

write(answer)
'''


def build_probe():
    """`harness/build.sh`'s own swiftc line over `app/Sources` plus this
    probe's `main.swift`, which makes it the entry point."""
    os.makedirs(WORK, exist_ok=True)
    binary = os.path.join(WORK, "opschemaprobe")
    entry = os.path.join(WORK, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(
        os.path.join(ROOT, "app", "Sources", name)
        for name in os.listdir(os.path.join(ROOT, "app", "Sources"))
        if name.endswith(".swift") and name != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
        os.path.getmtime(f) < os.path.getmtime(binary) for f in sources + [entry, lib]
    ):
        print(f"op-schema probe: {binary} (up to date)")
        return binary, None
    sdk = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True
    ).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + sources + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    print(f"op-schema probe: {binary} (built in {time.time() - start:.1f} s)")
    return binary, None


def run_probe(binary):
    out = os.path.join(WORK, "answer.json")
    if os.path.exists(out):
        os.remove(out)
    try:
        result = subprocess.run([binary, out], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None, "the probe never returned"
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stderr.strip().splitlines() or ["(no output)"])[-1]
    with open(out) as f:
        return json.load(f), None


def listed(message, name):
    """The field names serde put after the offender it names first — the
    same grammar `core/tests/op_table.rs` reads, ported here: `unknown field
    `x`, expected one of `a`, `b`` for three or more, `expected `a` or `b``
    for two, `expected `a`` for one, `there are no fields` for none.

    Returns None when the message is not a decode refusal at all, which is
    itself a failure: every op is supposed to refuse an unknown field."""
    prefix = f'op "{name}" is not valid: '
    if not message.startswith(prefix):
        return None
    tail = message[len(prefix):].split("`, ", 1)
    if len(tail) != 2:
        return None
    rest = tail[1]
    if rest.startswith("there are no fields"):
        return []
    return rest.split("`")[1::2]


# One representative argument per kind, and the schema the mapping owes it.
# `Index` shares `Id`'s JSON — both are whole non-negative numbers — and is
# listed separately because the table keeps them apart (serde names `usize`
# and `u32` differently, which is the rule that fixes the kind count).
WHOLE = {"type": "integer", "minimum": 0}
KINDS = [
    ("ticks", "slip", "delta", {"type": "integer"}),
    ("an id", "add_clip", "track", WHOLE),
    ("an index", "move_track", "index", WHOLE),
    ("a list of ids", "delete", "clips", {"type": "array", "items": WHOLE}),
    ("a list of ranges", "ripple_delete_ranges", "ranges",
     {"type": "array",
      "items": {"type": "array", "items": {"type": "integer"},
                "minItems": 2, "maxItems": 2}}),
    ("a number", "set_speed", "rate", {"type": "number"}),
    ("a boolean", "set_reversed", "reversed", {"type": "boolean"}),
    ("a string", "nest", "name", {"type": "string"}),
    ("an opaque patch", "set_video", "patch", {"type": "object"}),
    ("a colour", "add_background", "color",
     {"type": "array", "items": {"type": "number"}, "minItems": 4, "maxItems": 4}),
    ("a frame rate", "set_canvas", "fps",
     {"type": "array", "items": WHOLE, "minItems": 2, "maxItems": 2}),
    ("a declared region", "add_zoom_action", "region",
     {"type": "object",
      "properties": {"x": {"type": "number"}, "y": {"type": "number"},
                     "width": {"type": "number"}, "height": {"type": "number"}},
      "required": ["x", "y", "width", "height"],
      "additionalProperties": False}),
]

# The five closed vocabularies, by an op that takes each. The MEMBERS are not
# written here: what is claimed is that a vocabulary arrives as a string (or
# a list of them) with a non-empty `enum`, which is what an agent picks a
# legal value out of. Which members it has is `core/tests/op_table.rs`'s
# claim, against the decoder.
VOCABULARIES = [
    ("a transition kind", "add_transition", "kind", False),
    ("an alignment", "add_transition", "align", False),
    ("a curve", "set_transition_style", "curve", False),
    ("a zoom fit", "add_zoom_action", "fit", False),
    ("a group list", "paste_attributes", "groups", True),
]


def main():
    print("the op table, read back through the app\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    check("…and it got as far as reading the core", "error" not in answer,
          answer.get("error", ""))
    if "error" in answer:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1

    names = answer["names"]
    schemas = answer["schemas"]
    decoder = answer["decoder"]

    print("\n1 — the map: every op, and no other name")
    check("the core reports its op names at all", len(names) > 0, json.dumps(names[:3]))
    check(f"every op name has a schema ({len(names)} of them)",
          sorted(schemas.keys()) == sorted(names),
          f"only in names: {sorted(set(names) - set(schemas))}; "
          f"only in schemas: {sorted(set(schemas) - set(names))}")
    check("no schema is empty of structure — each has a properties map and a required list",
          all(isinstance(s.get("properties"), dict) and isinstance(s.get("required"), list)
              for s in schemas.values()),
          json.dumps([n for n, s in schemas.items()
                      if not isinstance(s.get("properties"), dict)
                      or not isinstance(s.get("required"), list)]))

    print("\n2 — the identity: the published properties are what the DECODER lists")
    unread = [name for name in names if listed(decoder.get(name, ""), name) is None]
    check("every op refuses an argument it has not got, naming the ones it has",
          not unread,
          json.dumps({name: decoder.get(name, "") for name in unread[:3]}))
    drift = {}
    for name in names:
        expected = listed(decoder.get(name, ""), name)
        if expected is None:
            continue
        published = sorted(schemas.get(name, {}).get("properties", {}))
        if published != sorted(expected):
            drift[name] = {"published": published, "decoder": sorted(expected)}
    check(f"…and for all {len(names)} ops those names are exactly the published properties",
          not drift, json.dumps(drift, indent=2)[:900])
    unbacked = {name: sorted(set(s["required"]) - set(s["properties"]))
                for name, s in schemas.items()
                if set(s["required"]) - set(s["properties"])}
    check("no schema requires an argument it does not declare", not unbacked,
          json.dumps(unbacked))

    # The decoder's own word on required-ness: an envelope with NO arguments
    # makes serde name the FIRST field it could not do without. An op the
    # schema says requires nothing must not produce one of those at all.
    missed = {}
    for name in names:
        message = answer["bare"].get(name, "")
        required = schemas.get(name, {}).get("required", [])
        prefix = f'op "{name}" is not valid: missing field `'
        if message.startswith(prefix):
            field = message[len(prefix):].split("`")[0]
            if field not in required:
                missed[name] = {"decoder wants": field, "published required": required}
        elif required:
            missed[name] = {"decoder wants": None, "published required": required}
    check("…and every op the decoder will not read without an argument publishes that "
          "argument as required", not missed, json.dumps(missed, indent=2)[:900])

    print("\n3 — the envelope's keys are not arguments")
    intruders = {name: [key for key in ("scope", "project")
                        if key in s["properties"] or key in s["required"]]
                 for name, s in schemas.items()
                 if any(key in s["properties"] or key in s["required"]
                        for key in ("scope", "project"))}
    check("no published schema carries `scope` or `project` — the catalog injects both",
          not intruders, json.dumps(intruders))

    print("\n4 — one representative argument per kind, against the mapping")
    for label, op, argument, expected in KINDS:
        got = schemas.get(op, {}).get("properties", {}).get(argument)
        check(f"{label} — {op}.{argument}", got == expected,
              f"got {json.dumps(got)}, wanted {json.dumps(expected)}")

    print("\n5 — a closed vocabulary arrives with its members enumerated")
    for label, op, argument, is_list in VOCABULARIES:
        got = schemas.get(op, {}).get("properties", {}).get(argument) or {}
        inner = (got.get("items") or {}) if is_list else got
        members = inner.get("enum")
        check(f"{label} — {op}.{argument} is a string with a non-empty enum",
              got.get("type") == ("array" if is_list else "string")
              and inner.get("type") == "string"
              and isinstance(members, list) and len(members) > 0
              and all(isinstance(member, str) for member in members),
              json.dumps(got))

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
