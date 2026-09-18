#!/usr/bin/env python3
"""A misspelt argument, put to all fifty-seven ops (road map 7's D3·5).

The startup parity check gained a FIFTH part with this ticket: every op tool's
declared arguments must be the core's own, every argument must carry a
description, and a description whose key is not an argument is a complaint
rather than a sentence dropped in silence. This script is the other half of
that, and the reason it exists is the series rule D3·3 and D3·4 both paid for:

> **A generated artefact is checked by asking the thing that generated it a
> question it did not write the answer to.**

The fifth part reads the same published table the catalog prints, so a
constraint the app still ENFORCES that the table stops DECLARING moves both
sides of its comparison together and passes. Twice in this series that
happened. So the weight here is on the sections that call the RUNNING TOOL and
read its answer: **for every op tool, every argument the tool calls required is
one the app refuses to do without, BY NAME** — which is a sentence written by
hand in fifty-eight handlers, against a required list that is now printed from
the core.

The sections, in order:

0. **The fifth part, made to complain.** A probe compiled from `app/Sources`
   builds the catalog this binary registers and puts it to
   `AgentServer.argumentFailure` — clean — and then puts four broken catalogs
   to it: an op tool with an argument the core has not got, one missing an
   argument the core has, one whose argument lost its description, and one
   whose prose names nothing. Each must be named with its op, its argument and
   the side that has it. An app-state tool broken the same way must draw
   NOTHING, which is the fourth part's skip rule.
1. **The catalog's size**, EXACTLY 77 — this script owns the exact count now
   and every older script keeps the floor the proof README's handover rule
   gives it — and the shipped binary's own parity log, which must be empty.
2. **Every difference between a tool's schema and the core's table is one the
   declarations list NAMES.** Not a second computation of the merge (that is
   `op_catalog_proof.py`'s) but an attribution: each key that differs — a
   type, an enum, a minimum, an items, a required list — must have a row that
   says so, and each row must be visible somewhere, so a row that does nothing
   is a failure too.
3. **A misspelt argument, for all fifty-seven ops.** For each op tool: one
   CONTROL call with every required argument spelled right, which must not be
   refused for a missing argument — that is the tool's required list proved
   SUFFICIENT against the running app — and then one call per required
   argument with that argument misspelt, which must be refused naming it. The
   values are derived from the core's published kinds; the only names written
   here are the five entity ids, and each is checked against the core's table
   first.
4. **A misspelt key INSIDE an opaque object is named by the CORE**, which is
   where the dotted path lives. An op ARGUMENT never reaches the core's
   decoder — the handlers read arguments one at a time and build the op
   (spec kpgalligan/reelcut#14's twelfth decision) — so the sentence that
   names a misspelt ARGUMENT is the app's, and the sentence that names a
   misspelt KEY is the core's, which deepening D1 made the one validator of a
   patch.

A probe that will not build is a scored FAILURE, never an exit. The probe is
built BEFORE the first MCP call, so no swiftc runs while the proof is driving
the app.

    make app
    (RC_AGENT_PORT=4903 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \\
       -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4903.log 2>&1 &)
    grep "Reelcut: " /tmp/reelcut-4903.log     # must print nothing
    python3 tools/proof/op_argument_proof.py 4903
"""

import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "op-argument-probe")
# AV.mov rather than A.mov: section 4 needs a clip with AUDIO properties
# as well as video, and section 3 needs one clip id and does not care
# which kind it is.
MEDIA = os.path.join(ROOT, "tools", "proof", "media", "AV.mov")

# This script owns the EXACT tool count (`tools/proof/README.md`'s handover
# rule): 57 ops plus the twenty app-state tools. D3 adds no tool and renames
# none, so it is road map 3's 75 plus phase 9's set_scope and… no: it is the
# number the catalog has had since road map 5's E1, taken exactly here for the
# first time. Every older script keeps its floor.
TOOLS = 77
OPS = 57
PARITY = "Reelcut: "

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
# The probe: the core's table, the declarations, and the fifth part of the
# startup parity check put to catalogs it did not build.

PROBE_SOURCE = r'''
import Foundation

func write(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

var answer: [String: Any] = [:]

// The op table, through the app's one reader of `rc_op_schemas`.
var schemas: [String: Any] = [:]
for (name, schema) in ReelOp.coreSchemas() {
    schemas[name] = ["properties": schema.properties, "required": schema.required]
}
answer["schemas"] = schemas
answer["names"] = ReelOp.coreNames()

// The declarations list — the widening list the catalog and the fifth part
// both read — one object per row.
func subject(_ subject: AgentDeclaration.Subject) -> [String: Any] {
    switch subject {
    case let .argument(name, of: op): return ["kind": "argument", "name": name, "op": op]
    case let .everyArgumentTyped(type): return ["kind": "everyTyped", "type": type]
    case let .everyArgumentNamed(name): return ["kind": "everyNamed", "name": name]
    }
}
func requirement(_ requirement: AgentDeclaration.Requirement) -> String {
    switch requirement {
    case .theCores: return "theCores"
    case .required: return "required"
    case .optional: return "optional"
    }
}
answer["declarations"] = AgentServer.declarations.map { declaration in
    [
        "subject": subject(declaration.subject),
        "alsoTypes": declaration.alsoTypes,
        "requirement": requirement(declaration.requirement),
        "alsoKeys": declaration.alsoKeys,
        "why": declaration.why,
    ] as [String: Any]
}

// The fifth part of the startup parity check, put to the catalog this build
// registers and then to four broken ones. `probe` is the op every mutation
// is made to, and `spare` an app-state tool, which the part must skip.
let ops = Set(ReelOp.coreNames())
let probeOp = "trim_start"
let appStateTool = "set_playhead"
var verdicts: [String: Any] = [:]
if let catalog = try? AgentServer.shared.catalogJSON(),
    let tools = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8)))
        as? [[String: Any]]
{
    func mutated(_ name: String, _ change: (inout [String: Any]) -> Void) -> [[String: Any]] {
        tools.map { tool in
            guard tool["name"] as? String == name else { return tool }
            var copy = tool
            var schema = copy["inputSchema"] as? [String: Any] ?? [:]
            var properties = schema["properties"] as? [String: Any] ?? [:]
            change(&properties)
            schema["properties"] = properties
            copy["inputSchema"] = schema
            return copy
        }
    }
    verdicts["clean"] = AgentServer.argumentFailure(tools, ops) ?? ""
    verdicts["extra"] = AgentServer.argumentFailure(
        mutated(probeOp) { $0["clipx"] = ["type": "integer", "description": "not an argument"] },
        ops) ?? ""
    verdicts["absent"] = AgentServer.argumentFailure(
        mutated(probeOp) { $0.removeValue(forKey: "to") }, ops) ?? ""
    verdicts["undescribed"] = AgentServer.argumentFailure(
        mutated(probeOp) { properties in
            var fragment = properties["clip"] as? [String: Any] ?? [:]
            fragment.removeValue(forKey: "description")
            properties["clip"] = fragment
        }, ops) ?? ""
    verdicts["appState"] = AgentServer.argumentFailure(
        mutated(appStateTool) { $0["clipx"] = ["type": "integer", "description": "stray"] },
        ops) ?? ""
    // The prose half cannot be made by editing a built catalog: a sentence
    // whose key is not an argument reaches nothing, so the merge is what has
    // to be told. `noteProse` is what `opTool` calls, with the same
    // arguments.
    let published = AgentServer.opSchemas[probeOp] ?? ReelOpSchema(properties: [:], required: [])
    AgentServer.noteProse(["clipx": "a description for an argument no op has"],
                          of: probeOp, against: published)
    verdicts["orphan"] = AgentServer.argumentFailure(tools, ops) ?? ""
    AgentServer.noteProse([:], of: probeOp, against: published)
    verdicts["cleanAgain"] = AgentServer.argumentFailure(tools, ops) ?? ""
    verdicts["op"] = probeOp
    verdicts["appStateTool"] = appStateTool
}
answer["verdicts"] = verdicts

write(answer)
'''


def build_probe():
    """`harness/build.sh`'s own swiftc line over `app/Sources` plus this
    probe's `main.swift`, which makes it the entry point."""
    os.makedirs(WORK, exist_ok=True)
    binary = os.path.join(WORK, "opargumentprobe")
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
        print(f"op-argument probe: {binary} (up to date)")
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
    print(f"op-argument probe: {binary} (built in {time.time() - start:.1f} s)")
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


def parity_lines(path):
    """The startup parity check's complaints in one log, if any."""
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as f:
        return [line for line in f.read().splitlines() if PARITY in line]


# --------------------------------------------------------------------------
# The declarations, read the way the catalog reads them.


def covers(declaration, op, argument, published_type):
    subject = declaration["subject"]
    if subject["kind"] == "argument":
        return subject["op"] == op and subject["name"] == argument
    if subject["kind"] == "everyTyped":
        return published_type == subject["type"]
    return subject["name"] == argument


def explains(declaration, key):
    """Whether this row is what makes `key` differ from the core's fragment.

    A row widens the `type` (and, when the widening is a `null`, the `enum`
    that goes with it) or writes a key of its own; nothing else about a
    fragment is the app's to change."""
    if key == "type":
        return bool(declaration["alsoTypes"])
    if key == "enum":
        return "null" in declaration["alsoTypes"]
    return key in declaration["alsoKeys"]


# --------------------------------------------------------------------------
# Section 3's values, derived from the core's published kinds.

# The five entity ids. These are the only argument NAMES this script types,
# because a valid clip id is not a valid track id — one id space, so the kind
# alone cannot say which entity an integer names. Each is checked against the
# core's table before it is used, so a rename fails here loudly rather than
# leaving a row asserting the old spelling.
ID_ARGUMENTS = ("clip", "clips", "track", "media", "action", "marker")


def value_for(argument, fragment, ids, tick):
    """A value the handler will READ without complaint, from what the core
    publishes about the argument — an entity id by name, everything else by
    kind. `tick` is the time this argument gets if it is one.

    Nothing here has to make the op APPLY. What it does have to do is not be
    refused by NAME for a reason of its own, which is what the control row
    below measures: a `duration` of 0 and a range whose two ends are equal are
    both answered "<name> must be …", and that is the sentence this section
    reads."""
    if argument in ids:
        return ids[argument]
    kinds = fragment.get("type")
    kinds = kinds if isinstance(kinds, list) else [kinds]
    kind = next((k for k in kinds if k != "null"), None)
    if kind == "array":
        items = fragment.get("items") or {}
        if items.get("type") == "array":            # a list of [from, to] pairs
            return [[0, 600000]]
        if items.get("enum"):                       # a closed vocabulary as a list
            return [items["enum"][0]]
        if fragment.get("minItems") == 2 and fragment.get("maxItems") == 2:
            return [30, 1]                          # a frame rate
        if fragment.get("minItems") == 4:
            return [0, 0, 0, 1]                     # a colour
        return [0]
    if kind == "object":
        properties = fragment.get("properties")
        if properties:                              # a region: the core names its members
            return {name: 100 for name in properties}
        return {}
    if kind == "integer":
        # An id, an index and a canvas dimension publish a `minimum` and the
        # smallest legal one is always readable; a TIME publishes none, and
        # 0 is a duration no op accepts, so a time gets a second of its own.
        return int(fragment["minimum"]) if "minimum" in fragment else tick
    if kind == "number":
        return 2.0
    if kind == "boolean":
        return True
    if fragment.get("enum"):
        return next(member for member in fragment["enum"] if member is not None)
    return "proof"


def arguments_for(required, published, ids):
    """One plausible call: every argument in `required`, in the core's own
    table order, so a pair of times comes out increasing (`from` before `to`,
    `at` before `length`) rather than equal."""
    values, tick = {}, 0
    for argument in required:
        fragment = published.get(argument, {})
        kinds = fragment.get("type")
        kinds = kinds if isinstance(kinds, list) else [kinds]
        if "integer" in kinds and "minimum" not in fragment and argument not in ids:
            tick += 600000
        values[argument] = value_for(argument, fragment, ids, tick)
    return values


def names_as_missing(text, argument):
    """Whether this refusal says the app could not do without `argument`.

    Three sentences, each anchored to the argument's own name, and all three
    are the APP's: the shared vocabulary's `Missing required argument: <name>`
    (`AgentServer+Arguments.swift`), a handler's own `<op> needs <name>`
    (`set_transition`, which lists the kinds with it), and `<name> must be
    <what>` — what a handler answers when a reader gave it nil and the
    sentence it wants is about the SHAPE (`set_speed`'s rate, `move_track`'s
    index, `add_media`'s descriptor, `paste`'s payload, `set_reversed`'s
    flag). Nothing here matches a bare mention of the name, which matters for
    the short ones: `at`, `to` and `from` are English words as well as
    arguments."""
    return (
        f"Missing required argument: {argument}" in text
        or f"needs {argument}" in text
        or re.search(rf"(?<![a-z_.]){re.escape(argument)} must be", text) is not None
    )


# --------------------------------------------------------------------------


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4903
    log = f"/tmp/reelcut-{port}.log"
    print("a misspelt argument, put to all fifty-seven ops\n")

    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers with the core's table, the declarations and the fifth part's "
          "verdicts", answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    table = answer["schemas"]
    ops = set(answer["names"])
    declarations = answer["declarations"]
    verdicts = answer["verdicts"]

    print("\n0 — the fifth part of the startup parity check, made to complain")
    op = verdicts.get("op", "")
    check("it says NOTHING about the catalog this build registers — the same silence the "
          "log below reports, measured where it can be falsified",
          verdicts.get("clean") == "" and verdicts.get("cleanAgain") == "",
          f"clean {verdicts.get('clean')!r}, again {verdicts.get('cleanAgain')!r}")
    check("an op tool declaring an argument the core has not got is named, with the op, the "
          "argument and the side",
          op in verdicts.get("extra", "") and "clipx" in verdicts.get("extra", "")
          and "declared by the tool" in verdicts.get("extra", ""),
          f"{verdicts.get('extra')!r}")
    check("…and an argument the core HAS that the tool does not declare, the other "
          "direction of the same comparison",
          op in verdicts.get("absent", "") and "\"to\"" in verdicts.get("absent", "").replace(
              "'", "\""),
          f"{verdicts.get('absent')!r}")
    check("an op tool argument with no description at all is named — the core says what an "
          "argument IS and the catalog says what it is FOR",
          op in verdicts.get("undescribed", "") and "clip" in verdicts.get("undescribed", "")
          and "no description" in verdicts.get("undescribed", ""),
          f"{verdicts.get('undescribed')!r}")
    check("a description written for an argument no op has is named — the sentence opTool "
          "drops in silence, which nothing in the built catalog remembers",
          op in verdicts.get("orphan", "") and "clipx" in verdicts.get("orphan", "")
          and "do not take" in verdicts.get("orphan", ""),
          f"{verdicts.get('orphan')!r}")
    check("…and an APP-STATE tool broken the same way draws nothing — the fifth part skips "
          f"a tool the core calls no op, as the fourth does ({verdicts.get('appStateTool')})",
          verdicts.get("appState") == "", f"{verdicts.get('appState')!r}")

    mcp = MCP(port)
    tools = mcp.schemas()

    print("\n1 — the catalog's size, and the shipped binary's own parity log")
    check(f"the catalog holds EXACTLY {TOOLS} tools — this script owns the exact count now, "
          "and every older script keeps a floor (tools/proof/README.md)",
          len(tools) == TOOLS, f"{len(tools)} tools")
    check(f"the core declares {OPS} ops and every one of them is a tool",
          len(ops) == OPS and ops <= set(tools),
          f"{len(ops)} ops, missing tools: {sorted(ops - set(tools))}")
    complaints = parity_lines(log)
    check("the startup parity check logged nothing — all five parts, in the binary on the "
          f"port ({log})", complaints == [],
          "no such log" if complaints is None else json.dumps(complaints)[:300])

    print("\n2 — every difference from the core's table is one the declarations list names")
    group = sorted(ops)
    unnamed = {}
    used = [False] * len(declarations)
    for name in group:
        published = table[name]["properties"]
        declared = {
            key: value
            for key, value in tools[name]["inputSchema"]["properties"].items()
            if key not in ("project", "scope")
        }
        for argument, core in published.items():
            fragment = {k: v for k, v in declared.get(argument, {}).items() if k != "description"}
            rows = [(n, d) for n, d in enumerate(declarations)
                    if covers(d, name, argument, core.get("type"))]
            for key in set(fragment) | set(core):
                if fragment.get(key) == core.get(key):
                    continue
                excuse = [n for n, d in rows if explains(d, key)]
                for n in excuse:
                    used[n] = True
                if not excuse:
                    unnamed[f"{name}.{argument}.{key}"] = [core.get(key), fragment.get(key)]
        # The required list: the core's, less what a row calls optional, plus
        # what a row asks for. Read as a DIFFERENCE, so a row is what has to
        # account for each one.
        declared_required = set(tools[name]["inputSchema"].get("required", []))
        for argument in declared_required - set(table[name]["required"]):
            rows = [(n, d) for n, d in enumerate(declarations)
                    if covers(d, name, argument, published.get(argument, {}).get("type"))
                    and d["requirement"] == "required"]
            for n, _ in rows:
                used[n] = True
            if not rows:
                unnamed[f"{name}.{argument}.required"] = ["the core does not", "the tool does"]
        for argument in set(table[name]["required"]) - declared_required:
            rows = [(n, d) for n, d in enumerate(declarations)
                    if covers(d, name, argument, published.get(argument, {}).get("type"))
                    and d["requirement"] == "optional"]
            for n, _ in rows:
                used[n] = True
            if not rows:
                unnamed[f"{name}.{argument}.required"] = ["the core does", "the tool does not"]
    check(f"all {len(group)} op tools declare exactly the core's argument NAMES", not any(
        set(k for k in tools[name]["inputSchema"]["properties"] if k not in ("project", "scope"))
        != set(table[name]["properties"]) for name in group),
        json.dumps({name: sorted(
            set(k for k in tools[name]["inputSchema"]["properties"]
                if k not in ("project", "scope")) ^ set(table[name]["properties"]))
            for name in group
            if set(k for k in tools[name]["inputSchema"]["properties"]
                   if k not in ("project", "scope")) != set(table[name]["properties"])}))
    check("every difference in kind, enum, minimum, maximum, items or required-ness is one "
          "AgentServer.declarations names", not unnamed, json.dumps(unnamed, indent=2)[:1000])
    idle = sorted(
        f"{d['subject'].get('op', '*')}.{d['subject'].get('name', d['subject'].get('type'))}"
        for n, d in enumerate(declarations) if not used[n])
    check(f"…and every one of the {len(declarations)} rows accounts for at least one of them "
          "— a row that changes nothing is a row that does nothing", not idle,
          json.dumps(idle))

    print("\n3 — a misspelt argument, for every op tool")
    mcp.call("new_project")
    mcp.call("import_media", path=MEDIA)
    project = mcp.call("get_project")["project"]
    track = project["tracks"][0]["id"]
    media = project["media"][0]["id"]
    mcp.call("add_clip", track=track, media=media, at=0)
    mcp.call("add_clip", track=track, media=media, at=6000000)
    mcp.call("add_text_clip", track=track, at=12000000, text="Hi")
    mcp.call_with("add_shape_clip", {"track": track, "at": 18000000, "shape": "rectangle"})
    project = mcp.call("get_project")["project"]
    clip = project["clips"][0]["id"]
    text_clip = project["clips"][2]["id"]
    shape_clip = project["clips"][3]["id"]
    mcp.call("add_action", clip=clip, at=0, duration=600000)
    mcp.call("add_marker", at=0)
    project = mcp.call("get_project")["project"]
    ids = {
        "clip": clip,
        "clips": [clip],
        "track": track,
        "media": media,
        "action": project["clips"][0]["actions"][0]["id"],
        "marker": project["markers"][0]["id"],
    }
    check("the five entity ids this script names are all arguments the core still has — a "
          "rename fails here rather than leaving the rows below asserting the old spelling",
          all(any(name in table[op]["properties"] for op in group) for name in ID_ARGUMENTS)
          and set(ids) == set(ID_ARGUMENTS),
          f"{sorted(name for name in ID_ARGUMENTS if not any(name in table[op]['properties'] for op in group))}")

    def refusal(name, arguments):
        try:
            return "", mcp.call_with(name, arguments)
        except ToolError as error:
            return str(error), None

    nothing_required = []
    for name in group:
        required = tools[name]["inputSchema"].get("required", [])
        if not required:
            nothing_required.append(name)
            continue
        published = table[name]["properties"]
        arguments = arguments_for(required, published, ids)
        # The control: with every required argument spelled right, nothing may
        # be refused for a MISSING one. That is the tool's required list proved
        # sufficient against the running app — and it is what says the values
        # above are good enough for the rows that follow to mean anything.
        text, applied = refusal(name, arguments)
        if applied is not None:
            mcp.call("undo")
        wrong = [a for a in required if names_as_missing(text, a)]
        misspelt = {}
        for argument in required:
            probe = {a: v for a, v in arguments.items() if a != argument}
            probe[argument + "x"] = arguments[argument]
            text, applied = refusal(name, probe)
            if applied is not None:
                mcp.call("undo")
            if not names_as_missing(text, argument):
                misspelt[argument] = text[:160] or "applied"
        check(f"{name} — every one of {required} is refused BY NAME when it is misspelt, and "
              "asked for by none of them when it is not",
              not wrong and not misspelt,
              f"named as missing although present: {wrong}; not named when misspelt: "
              f"{json.dumps(misspelt)}")
    # The other end of the same sentence, and the limit of what this section
    # can claim: a misspelt OPTIONAL argument is silently ignored by every
    # tool, so an op that requires nothing cannot be measured here at all.
    # Named rather than counted, because four of the six are the declarations
    # list's own doing — the playhead rows that make `at` optional.
    check(f"…and the {len(nothing_required)} op tools that require nothing are NAMED rather "
          "than counted: a misspelling of an optional argument is silently ignored, and four "
          "of these are the playhead rows of the declarations list",
          nothing_required == ["add_background", "add_marker", "add_track",
                               "remove_empty_tracks", "set_canvas", "split"],
          json.dumps(nothing_required))

    print("\n4 — a misspelt key inside an opaque object is named by the CORE")
    doors = sorted(
        (name, argument) for name in group
        for argument, fragment in table[name]["properties"].items()
        if fragment.get("type") == "object" and "properties" not in fragment)
    check(f"the core publishes {len(doors)} arguments as an opaque object — a caller's own "
          "patch, which deepening D1 made the core the one validator of",
          len(doors) == 11, json.dumps(doors))
    # A property group belongs to a KIND of clip, and an op whose rule is
    # "this clip has no text properties" answers that before the patch is
    # read. So two ops are pointed at the clip their group lives on; every
    # other door takes the fixture's AV clip, which has both video and audio.
    subject_clip = {"set_text": text_clip, "set_shape": shape_clip}
    for name, argument in doors:
        if argument == "payload":
            continue
        required = tools[name]["inputSchema"].get("required", [])
        published = table[name]["properties"]
        arguments = arguments_for(required, published, ids)
        if name in subject_clip:
            arguments["clips"] = [subject_clip[name]]
        arguments[argument] = {"nosuchkey": 1}
        text, applied = refusal(name, arguments)
        if applied is not None:
            mcp.call("undo")
        check(f"{name}.{argument} — the core names the key it did not know",
              "nosuchkey" in text, f"{text[:200]!r}")
    # The two the core cannot be reached through from here, named rather than
    # skipped: `pastePayloadArg` checks a payload is an object with clips in
    # it before forwarding, and a payload valid enough to reach the core's
    # unknown-key answer is a whole Copy payload this fixture does not make.
    # What IS true of both is checked instead — the app names the key it
    # wanted, in one sentence for the two tools, which is the reason the two
    # share one reader.
    for name in ["paste", "paste_attributes"]:
        required = tools[name]["inputSchema"].get("required", [])
        published = table[name]["properties"]
        arguments = arguments_for(required, published, ids)
        arguments["payload"] = {"nosuchkey": 1}
        text, applied = refusal(name, arguments)
        if applied is not None:
            mcp.call("undo")
        check(f"{name}.payload — the APP names payload.clips first, so the core is not "
              "reached: one reader for the two tools, and a Copy payload is not something "
              "this fixture can make", "payload.clips must be" in text, f"{text[:200]!r}")

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
