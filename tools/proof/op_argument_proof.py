#!/usr/bin/env python3
"""A stranger argument, put to all eighty-two tools (road map 7's D3·5, and
the gate of kpgalligan/framejob#21).

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
1. **The catalog's size**, EXACTLY 90 PRODUCT tools — this script owns the
   exact count now and every older script keeps the floor the proof README's
   handover rule gives it — and the shipped binary's own parity log, which
   must be empty. The dev tools (road map 11, `dev_tools.py`) are counted
   apart: all present with the log's marker count equal to their number
   (Debug or Release), or all absent with no marker line (Distribution), and when
   present they sit together immediately before `import_media`, where
   `devTools()` splices them (V0's owed count and order probes).
2. **Every difference between a tool's schema and the core's table is one the
   declarations list NAMES.** Not a second computation of the merge (that is
   `op_catalog_proof.py`'s) but an attribution: each key that differs — a
   type, an enum, a minimum, an items, a required list — must have a row that
   says so, and each row must be visible somewhere, so a row that does nothing
   is a failure too.
3. **A stranger argument, for every op tool.** For each of the sixty-one:
   one CONTROL call with every required argument spelled
   right, which must not be refused for a missing argument — that is the
   tool's required list proved SUFFICIENT against the running app; one call
   per required argument with that argument LEFT OUT, which must be refused
   naming it — the handler reads it; and one call per argument the core
   publishes, required or not, with that argument MISSPELT beside the
   control, plus one carrying two names no op has, each of which must draw
   the GATE's sentence (kpgalligan/framejob#21, `AgentServer+Gate.swift`):
   the tool, the stranger, and exactly what the tool takes, read back out of
   the sentence and compared to the core's row, the declarations' rows and
   the envelope's two keys. The values are derived from the core's published
   kinds; the only names written here are the six that name the five
   ENTITIES an id can point at, and each is checked against the core's table
   first.

   **Six op tools require nothing**, so no left-out row can reach them. The
   gate reads a NAME against the schema and never whether anything reads the
   value, so a declared argument no handler reads would pass it in silence:
   for these six, what is read instead is what the op DID — the same call
   twice, once with the argument and once without it, answering two
   different projects. One argument of one op cannot be separated that way
   with this fixture, and it is named in the script with its reason and
   asserted to be the whole of the exceptions.

   And **a fraction where a whole number belongs** — #21's sibling, `3.7`
   read as the id 3 — is refused rather than truncated, through the scalar
   reader and the clip-list one.

   And **a TERM of a frame rate**, the last two readers still on `intValue`
   after the gate (`archive/remaining.md` §5's residue, closed
   2026-09-20): `set_canvas`'s pair and `add_media`'s descriptor pair both go
   through `rateTerm` now, so a fraction, a zero, a negative, `Int64.max`,
   one past u32, a string and a JSON `true` are each refused BY THEIR PATH —
   `fps[0]`, `fps[1]`, `descriptor.fps[0]` — a pair of the wrong length is
   refused as a pair, a bare `1e30` no longer TRAPS on `Int(number)`, and
   `[30000, 1001]` and `[30000.0, 1001.0]` still apply and read back.
4. **A misspelt key INSIDE an opaque object is named by the CORE**, which is
   where the dotted path lives. An op ARGUMENT never reaches the core's
   decoder — the handlers read arguments one at a time and build the op
   (spec kpgalligan/framejob#14's twelfth decision) — so the sentence that
   names a misspelt ARGUMENT is the app's, and the sentence that names a
   misspelt KEY is the core's, which deepening D1 made the one validator of a
   patch.
5. **The twenty tools the core calls no op**, which the gate covers the same
   way: the same two strangers, sent alone, and the list the gate speaks
   compared to the catalog's — the one spelling a hand-written schema has.
   Last on purpose: on a broken gate every one of these calls reaches its
   handler, and `new_project` opens a document over the fixture.

A probe that will not build is a scored FAILURE, never an exit. The probe is
built BEFORE the first MCP call, so no swiftc runs while the proof is driving
the app.

    make app-debug
    python3 tools/proof/proof_app.py launch   # prints folder, socket, log, pid
    grep "Frame Job: " <dir>/framejob.log     # must print nothing
    python3 tools/proof/op_argument_proof.py <dir>/agent.sock
"""

import glob
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError, log_beside, target  # noqa: E402
from dev_tools import DEV_TOOLS, dev_marker_count  # noqa: E402
import swift_build  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "op-argument-probe")
# AV.mov rather than A.mov: section 4 needs a clip with AUDIO properties
# as well as video, and section 3 needs one clip id and does not care
# which kind it is.
MEDIA = os.path.join(ROOT, "tools", "proof", "media", "AV.mov")

# This script owns the EXACT tool count (`tools/proof/README.md`'s handover
# rule): 61 ops plus the thirty-six app-state tools (G3b added the two graphic ops'
# tools, G4a the three app-state graphics tools, G4b three more, B44 close_project,
# B84 delete_graphic, rename_graphic and restore_graphic; grading GR4a's op tool
# add_adjustment_clip is the sixtieth op, grading-3 T3-2's set_media_color the
# sixty-first; audio-sync AS-1's app-state sync_audio the ninety-second; #326's export_status
# and cancel_export the ninety-third and ninety-fourth; cut-by-transcript CT-2's
# detect_fillers the ninety-fifth; CT-3's transcribe_for_fillers the ninety-sixth; CT-4's
# get_transcript the ninety-seventh). D3 adds no tool and renames
# none, so it is road map 3's 75 plus phase 9's set_scope and… no: it is the
# number the catalog has had since road map 5's E1, taken exactly here for the
# first time. Every older script keeps its floor. It counts PRODUCT tools:
# road map 11's dev tools (`dev_tools.py`) are in a Release catalog and not a
# Distribution one, so section 1 counts them apart.
PRODUCT_TOOLS = 97
OPS = 61
PARITY = "Frame Job: "

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
    case .filledByTheApp: return "filledByTheApp"
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
    """`swift_build.build` over `app/Sources` plus this
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
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"op-argument probe: {binary} (up to date)")
    else:
        print(f"op-argument probe: {binary} (built in {built.seconds:.1f} s)")
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

# The five ENTITIES an id can name, under six argument names (`clips` is a
# list of the same id space `clip` draws from). These are the only argument
# names this script types, because a valid clip id is not a valid track id —
# one id space, so the published kind alone cannot say which entity an integer
# names. Each is checked against the core's table before it is used, so a
# rename fails here loudly rather than leaving a row asserting the old
# spelling.
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


def temp_roots():
    """The untitled graphics roots in `getconf DARWIN_USER_TEMP_DIR`, where
    the app's NSTemporaryDirectory() is whatever TMPDIR says (road map 10
    §10.6 G3a)."""
    base = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True,
                          text=True, timeout=30).stdout.strip()
    return set(glob.glob(os.path.join(base, "FrameJob", "*-graphics")))


def mv_in(folder, name, text):
    """Writes OUTSIDE the folder, then `mv`s it in — how another process
    lands a file; the `mv`'s exit status."""
    os.makedirs(WORK, exist_ok=True)
    outside = os.path.join(WORK, f"outside-{name}")
    with open(outside, "w") as handle:
        handle.write(text)
    return subprocess.run(["mv", outside, os.path.join(folder, name)],
                          timeout=30).returncode


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
    socket_path = target(sys.argv)
    log = log_beside(socket_path)
    print("a stranger argument, put to all eighty-two tools\n")

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
    # Read against the CLEAN verdict rather than against the empty string: on
    # a build that already has a complaint, "draws nothing" would fail for the
    # other complaint's sake and name the wrong thing. What the skip claims is
    # that breaking an app-state tool changes the answer not at all.
    check("…and an APP-STATE tool broken the same way changes the answer not at all — the "
          "fifth part skips a tool the core calls no op, as the fourth does "
          f"({verdicts.get('appStateTool')})",
          verdicts.get("appState") == verdicts.get("clean"),
          f"{verdicts.get('appState')!r}")

    mcp = MCP(socket_path)
    tools = mcp.schemas()

    print("\n1 — the catalog's size, and the shipped binary's own parity log")
    product = [name for name in tools if name not in DEV_TOOLS]
    check(f"the catalog holds EXACTLY {PRODUCT_TOOLS} product tools — this script owns the "
          "exact count now, and every older script keeps a floor (tools/proof/README.md)",
          len(product) == PRODUCT_TOOLS, f"{len(product)} product tools of {len(tools)}")
    present = [name for name in DEV_TOOLS if name in tools]
    marker = dev_marker_count(log)
    check(f"the dev tools {DEV_TOOLS} are all present with the log's marker count equal to "
          "their number, or all absent with no marker line",
          (present == DEV_TOOLS and marker == len(DEV_TOOLS))
          or (present == [] and marker is None),
          f"present {present}, marker count {marker}")
    if present:
        names = list(tools)
        at = names.index(DEV_TOOLS[0]) if DEV_TOOLS[0] in names else len(names)
        block = names[at:at + len(DEV_TOOLS) + 1]
        check("…and they sit together, in dev_tools.py's order, immediately before "
              "import_media, where devTools() splices them",
              block == DEV_TOOLS + ["import_media"], f"{block}")
    check(f"the core declares {OPS} ops and every one of them is a tool",
          len(ops) == OPS and ops <= set(tools),
          f"{len(ops)} ops, missing tools: {sorted(ops - set(tools))}")
    complaints = parity_lines(log)
    check("the startup parity check logged nothing — all five parts, in the binary on the "
          f"socket ({log})", complaints == [],
          "no such log" if complaints is None else json.dumps(complaints)[:300])

    print("\n2 — every difference from the core's table is one the declarations list names")
    group = sorted(ops)
    # The arguments a `filledByTheApp` row takes out of a tool (road map 10
    # G3b: the two graphic ops' `schema`, which the app reads from the
    # module): the core publishes them and the tool deliberately does not.
    filled = {(d["subject"]["op"], d["subject"]["name"]): n
              for n, d in enumerate(declarations)
              if d["requirement"] == "filledByTheApp" and d["subject"]["kind"] == "argument"}

    def published_of(name):
        """The core's row for `name` less what the app fills."""
        return {argument: fragment for argument, fragment in table[name]["properties"].items()
                if (name, argument) not in filled}

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
            if (name, argument) in filled:
                # The row's whole effect is the omission, so it is used when
                # the tool does not declare the argument and named when it does.
                if argument in declared:
                    unnamed[f"{name}.{argument}"] = ["filled by the app", "declared"]
                else:
                    used[filled[(name, argument)]] = True
                continue
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
    check(f"all {len(group)} op tools declare exactly the core's argument NAMES, less the "
          f"{len(filled)} the app fills", not any(
        set(k for k in tools[name]["inputSchema"]["properties"] if k not in ("project", "scope"))
        != set(published_of(name)) for name in group),
        json.dumps({name: sorted(
            set(k for k in tools[name]["inputSchema"]["properties"]
                if k not in ("project", "scope")) ^ set(published_of(name)))
            for name in group
            if set(k for k in tools[name]["inputSchema"]["properties"]
                   if k not in ("project", "scope")) != set(published_of(name))}))
    check("every difference in kind, enum, minimum, maximum, items or required-ness is one "
          "AgentServer.declarations names", not unnamed, json.dumps(unnamed, indent=2)[:1000])
    idle = sorted(
        f"{d['subject'].get('op', '*')}.{d['subject'].get('name', d['subject'].get('type'))}"
        for n, d in enumerate(declarations) if not used[n])
    check(f"…and every one of the {len(declarations)} rows accounts for at least one of them "
          "— a row that changes nothing is a row that does nothing", not idle,
          json.dumps(idle))

    print("\n3 — a stranger argument, for every op tool")
    roots_before = temp_roots()
    mcp.call("new_project")
    new_roots = sorted(temp_roots() - roots_before)
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
    check("the six names for the five entities this script types are all arguments the "
          "core still has — a "
          "rename fails here rather than leaving the rows below asserting the old spelling",
          all(any(name in table[op]["properties"] for op in group) for name in ID_ARGUMENTS)
          and set(ids) == set(ID_ARGUMENTS),
          f"{sorted(name for name in ID_ARGUMENTS if not any(name in table[op]['properties'] for op in group))}")

    def refusal(name, arguments):
        try:
            return "", mcp.call_with(name, arguments)
        except ToolError as error:
            return str(error), None

    def gated(text, name, strangers, takes):
        """Whether `text` is the gate's own sentence for `name` — the tool,
        every stranger, and after "It takes" EXACTLY `takes`. The list is
        read back out of the sentence rather than searched for, so a list
        that has lost a name or gained one fails here; the sentence's shape
        is the app's contract, as `noSuchId`'s is. `mcp.ToolError` puts the
        tool's name and a colon in front of what the app said, and that
        prefix is taken off first."""
        text = text[len(name) + 2:] if text.startswith(name + ": ") else text
        found = re.fullmatch(r"(\S+) does not take (.+?)\. It takes (.+)\.", text)
        if not found or found.group(1) != name:
            return False
        return (set(re.split(r", | and ", found.group(2))) == set(strangers)
                and set(re.split(r", | and ", found.group(3))) == set(takes))

    def rows_for(name):
        """Arguments the declarations list adds to `name` beyond the core's
        row — none today, and read anyway: the fifth part says a tool
        declares the core's row PLUS its rows, and this section must not be
        narrower than the check it exists to second."""
        return {d["subject"]["name"] for d in declarations
                if d["subject"]["kind"] == "argument" and d["subject"]["op"] == name
                and d["requirement"] != "filledByTheApp"}

    # Two names no op has, sent together so the sentence's plural is read too.
    STRANGERS = {"nosuchargument": 1, "nor_this_one": True}
    nothing_required = []
    for name in group:
        published = published_of(name)
        required = tools[name]["inputSchema"].get("required", [])
        takes = set(published) | rows_for(name) | {"project", "scope"}
        arguments = arguments_for(required, published, ids)
        # The control: with every required argument spelled right, nothing may
        # be refused for a MISSING one. That is the tool's required list proved
        # sufficient against the running app — and it is what says the values
        # above are good enough for the rows that follow to mean anything.
        text, applied = refusal(name, arguments)
        if applied is not None:
            mcp.call("undo")
        wrong = [a for a in required if names_as_missing(text, a)]
        # LEFT OUT: each required argument in turn, which must be refused as
        # missing BY NAME — that is the handler reading it. Before the gate
        # this row was a misspelling, which no longer reaches a handler.
        unread = {}
        for argument in required:
            text, applied = refusal(name, {a: v for a, v in arguments.items() if a != argument})
            if applied is not None:
                mcp.call("undo")
            if not names_as_missing(text, argument):
                unread[argument] = text[:160] or "applied"
        # MISSPELT: every argument the core publishes, required or not, beside
        # the control — and then the two names no op has. Each must draw the
        # gate's sentence: the tool, the stranger, and exactly what it takes.
        ungated = {}
        for stranger in sorted(published) + [None]:
            probe = dict(arguments)
            if stranger is None:
                added = dict(STRANGERS)
            else:
                probe.pop(stranger, None)
                added = {stranger + "x": value_for(stranger, published[stranger], ids, 600000)}
            probe.update(added)
            text, applied = refusal(name, probe)
            if applied is not None:
                mcp.call("undo")
            if not gated(text, name, added, takes):
                ungated[", ".join(sorted(added))] = text[:160] or "applied"
        check(f"{name} — every one of {required} is refused as MISSING when left out; every "
              f"one of {sorted(published)} and two names no op has are refused by the GATE "
              "when misspelt, naming the tool and exactly what it takes",
              not wrong and not unread and not ungated,
              f"named as missing although present: {wrong}; not named when left out: "
              f"{json.dumps(unread)}; not gated: {json.dumps(ungated)}")
        if not required:
            nothing_required.append(name)
    # The six that require nothing, named rather than counted — four of them
    # for the declarations list's own playhead rows, which make `at` optional.
    check(f"…and the {len(nothing_required)} op tools that require nothing are NAMED rather "
          "than counted: no call of theirs can be refused for a missing argument, so the "
          "left-out rows above cannot reach them, and four of these are the playhead rows",
          nothing_required == ["add_background", "add_marker", "add_track",
                               "remove_empty_tracks", "set_canvas", "split"],
          json.dumps(nothing_required))

    # …and the hole that leaves, closed the only way it can be. The gate
    # reads a NAME against the schema and never whether anything reads the
    # value, so a declared argument no handler reads passes it in silence —
    # and for these six no left-out row can say otherwise. What is read
    # instead is what the op DID. Every argument of all six, so an argument
    # no handler reads is named here whether its op requires anything or not.
    def applied_project(name, arguments):
        """The whole project after `name` ran, undone again — or None if the
        call was refused, with the sentence."""
        text, answer = refusal(name, arguments)
        if answer is None:
            return None, text
        after = json.dumps(mcp.call("get_project")["project"], sort_keys=True)
        mcp.call("undo")
        return after, ""

    def candidates(argument, fragment):
        """Values to try for one optional argument, in order. The first is
        `value_for`'s; the rest exist because an argument whose value is what
        the project ALREADY says changes nothing when it is read and nothing
        when it is not — a boolean already set, `[30, 1]` on a 30 fps
        project, black on a black canvas, `sdr` on an SDR canvas (hdr H-2's
        `set_canvas.output`: a closed vocabulary tries every member) — and
        that is a fact about the value, not about the handler."""
        first = value_for(argument, fragment, ids, 600000)
        if fragment.get("enum") and not isinstance(first, list):
            return [m for m in fragment["enum"] if m is not None]
        if isinstance(first, bool):
            return [first, not first]
        if first == [0, 0, 0, 1]:
            return [first, [1, 0, 0, 1]]
        if first == [30, 1]:
            return [first, [24, 1]]
        return [first]

    def reads(name, argument, value, whole):
        """Whether the app reads `argument`: the same call twice, once with
        it and once without it, answering two different projects.

        TWO shapes, because one is not enough for six ops at once. ALONE —
        the argument by itself against the op by itself — is the only shape
        `add_background` can take, since it refuses a media and a colour
        together. WHOLE — every argument right against this one misspelt —
        is the only shape `set_canvas`'s `rescale_clips` can take, since it
        scales a clip's placement WITH a size and does nothing without
        one."""
        arguments = dict(whole) if whole else {}
        arguments[argument] = value
        right, text = applied_project(name, arguments)
        if right is None:
            return False, f"refused: {text[:120]}"
        del arguments[argument]
        blind, text = applied_project(name, arguments)
        if blind == right:
            return False, "the project came out as if the argument were not there"
        return True, ""

    # The one argument this fixture cannot separate, named with its reason
    # and asserted as the WHOLE of the exceptions, so a second one is a
    # failure rather than a quiet addition.
    UNSEPARABLE = {
        "split.clips": "the playhead sits inside the only clip at that time, so naming that "
                       "clip and letting the app choose it are the same edit — a limit of the "
                       "fixture, not of the tool",
    }
    # A free tick: the fixture's own marker is at 0 and two markers may not
    # share a time, so `add_marker` would be refused at the playhead it was
    # left at rather than measured.
    mcp.call("set_playhead", t=300000)
    unread, unexpected = [], []
    for name in nothing_required:
        published = table[name]["properties"]
        declared = sorted(published)
        if not declared:
            check(f"{name} takes no argument at all — the one row of the core's table with no "
                  "arguments in it, so there is nothing of its to misspell", True)
            continue
        whole = arguments_for(declared, published, ids)
        blind = {}
        for argument in declared:
            why = ""
            for value in candidates(argument, published[argument]):
                for shape in (None, whole):
                    seen, why = reads(name, argument, value, shape)
                    if seen:
                        break
                if seen:
                    break
            if not seen:
                blind[argument] = why
                key = f"{name}.{argument}"
                (unread if key in UNSEPARABLE else unexpected).append(key)
        check(f"{name} — every one of {declared} CHANGES what the op did, so leaving it out "
              "is a different project: the only way to see an optional argument no handler "
              "reads", all(f"{name}.{a}" in UNSEPARABLE for a in blind), json.dumps(blind)[:400])
    check(f"…and the {len(UNSEPARABLE)} argument this fixture cannot separate is the one named "
          f"in the script, with its reason: {sorted(UNSEPARABLE)}",
          sorted(unread) == sorted(UNSEPARABLE) and not unexpected,
          f"unseparable {sorted(unread)}, unexpected {sorted(unexpected)}")

    print("\n…and a fraction where a whole number belongs")
    # The sibling defect #21 names: `intArg` read `NSNumber.intValue`, so a
    # clip id of 3.7 was clip 3 and the edit landed on a clip nobody named.
    text, applied = refusal("trim_start", {"clip": clip + 0.5, "to": 600000})
    if applied is not None:
        mcp.call("undo")
    check("trim_start {clip: <id>.5} is refused as 'clip must be a whole number' rather than "
          "truncated to the clip below it", "clip must be a whole number" in text,
          text[:160] or "applied")
    text, applied = refusal("delete", {"clips": [clip + 0.5]})
    if applied is not None:
        mcp.call("undo")
    check("…and delete {clips: [<id>.5]} the same, through the list reader",
          "clips must contain clip ids" in text, text[:160] or "applied")
    text, applied = refusal("trim_start", {"clip": float(clip), "to": 600000})
    if applied is not None:
        mcp.call("undo")
    check("…while {clip: <id>.0} is still the id — a whole number spelled as a float is a "
          "typing slip, not a fraction",
          "clip must be" not in text and not names_as_missing(text, "clip"), text[:160])

    print("\n…and a TERM of a frame rate, which two readers still truncated")
    # `archive/remaining.md` §5's residue, closed 2026-09-20: the two
    # `[numerator, denominator]` readers took each half through
    # `NSNumber.intValue` AFTER the gate, so `[29.97, 1]` was 29 fps in
    # silence and a whole double past Int.max TRAPPED. Both now go through
    # `rateTerm` (`AgentServer+Arguments.swift`) and every term is refused by
    # its own path, the way `rangePair` names an end of a range. Each row's
    # extreme is the one road map 4's reader review paid for.
    TERM = "must be a whole number from 1 to 4294967295"
    canvas_before = mcp.call("get_project")["project"]["canvas"]["fps"]
    terms = [
        ([29.97, 1], "fps[0]", "a fraction where the numerator goes — 29 fps until today"),
        ([30000, 1001.5], "fps[1]", "a fraction where the denominator goes"),
        ([0, 1], "fps[0]", "a zero term, which the app now refuses before the core does"),
        ([30, 0], "fps[1]", "a zero denominator"),
        ([30, -1], "fps[1]", "a negative term, which the core takes only as invalid input"),
        ([9223372036854775807, 1], "fps[0]", "Int64.max, the extreme road map 4 paid for"),
        ([4294967296, 1], "fps[0]", "one past u32 — core/src/time.rs is what a term must fit"),
        (["30", 1], "fps[0]", "a term that is a STRING, where intArg would take it"),
        ([True, 1], "fps[0]", "a term that is JSON true, which arrives as an NSNumber"),
    ]
    for value, path, why in terms:
        text, applied = refusal("set_canvas", {"fps": value})
        if applied is not None:
            mcp.call("undo")
        check(f"set_canvas {{fps: {json.dumps(value)}}} — {why}: refused as '{path} {TERM}'",
              f"{path} {TERM}" in text, text[:160] or "applied")
    for value in ([30], [30, 1, 1]):
        text, applied = refusal("set_canvas", {"fps": value})
        if applied is not None:
            mcp.call("undo")
        check(f"set_canvas {{fps: {json.dumps(value)}}} — a list of the wrong length is refused "
              "as a PAIR, naming fps rather than a term",
              "fps must be [numerator, denominator]" in text, text[:160] or "applied")
    text, applied = refusal("set_canvas", {"fps": 1e30})
    if applied is not None:
        mcp.call("undo")
    check("set_canvas {fps: 1e30} — a bare whole double past Int.max is refused naming fps, "
          f"where Int(number) TRAPPED: a live crash until today ('fps {TERM}')",
          f"fps {TERM}" in text, text[:160] or "applied")
    canvas_after = mcp.call("get_project")["project"]["canvas"]["fps"]
    check(f"…and after every one of them the app still answers, with canvas.fps still "
          f"{canvas_before} — nothing truncated in, nothing trapped",
          canvas_after == canvas_before, f"{canvas_before} → {canvas_after}")
    for value in ([30000, 1001], [30000.0, 1001.0]):
        text, applied = refusal("set_canvas", {"fps": value})
        read_back = None
        if applied is not None:
            read_back = mcp.call("get_project")["project"]["canvas"]["fps"]
            mcp.call("undo")
        check(f"…while set_canvas {{fps: {json.dumps(value)}}} APPLIES and reads back as "
              "[30000, 1001] — a whole number spelled as a float is still the term it is",
              read_back == [30000, 1001], text[:160] or json.dumps(read_back))
    # A descriptor the CORE accepts once the app is through with it: a media
    # with pixels must carry a positive width and height, and a path the
    # project has not got already (the same path is the core's IDENTITY arm,
    # not an edit) — both the core's own rules and neither this reader's.
    descriptor = {
        "path": os.path.join(os.path.dirname(MEDIA), "B.mov"), "width": 1920, "height": 1080}
    media_before = len(mcp.call("get_project")["project"]["media"])
    text, applied = refusal("add_media", {"descriptor": dict(descriptor, fps=[29.97, 1])})
    # Counted BEFORE the undo: counted after it, a media the call wrongly added
    # is already gone and "no media added" could not fail.
    media_after = len(mcp.call("get_project")["project"]["media"])
    if applied is not None:
        mcp.call("undo")
    check("add_media's DESCRIPTOR is the second reader, and its term is named by the same "
          f"path with the object in front of it: 'descriptor.fps[0] {TERM}', no media added",
          f"descriptor.fps[0] {TERM}" in text and media_after == media_before,
          f"{text[:160] or 'applied'}; media {media_before} → {media_after}")
    text, applied = refusal("add_media", {"descriptor": dict(descriptor, fps=[30000, 1001])})
    added = None
    if applied is not None:
        added = mcp.call("get_project")["project"]["media"][-1].get("fps")
        mcp.call("undo")
    check("…while the same descriptor with [30000, 1001] applies and the new media row carries "
          "that exact rate", added == [30000, 1001], text[:160] or json.dumps(added))

    print("\n4 — a misspelt key inside an opaque object is named by the CORE")
    doors = sorted(
        (name, argument) for name in group
        for argument, fragment in published_of(name).items()
        if fragment.get("type") == "object" and "properties" not in fragment)
    check(f"the core publishes {len(doors)} arguments as an opaque object a tool takes — a "
          "caller's own patch, which deepening D1 made the core the one validator of",
          len(doors) == 14, json.dumps(doors))
    # The two graphic doors reach the core only through a module the
    # untitled project's graphics/ holds (road map 10 G3b: the app reads the
    # schema from it and refuses a module it cannot find). `value_for` names
    # the module "proof", so `proof.js` is moved in from outside, and the
    # clip `add_graphic_clip` lands once the store has seen it is the one
    # `set_graphic` is pointed at.
    module = ("export const schema = { title: { type: 'string', default: 'A' } };\n"
              "export function render() { return '<svg/>'; }\n")
    moved = mv_in(new_roots[0], "proof.js", module) if len(new_roots) == 1 else None
    graphic_clip = None
    deadline = time.monotonic() + 5
    while moved == 0 and time.monotonic() < deadline:
        text, applied = refusal("add_graphic_clip", {"track": track, "at": 24000000,
                                                      "name": "proof"})
        if applied is not None:
            graphic_clip = max(c["id"] for c in mcp.call("get_project")["project"]["clips"])
            break
        time.sleep(0.2)
    check("the untitled project's graphics/ takes proof.js and add_graphic_clip lands a clip "
          "drawn by it within 5 s", graphic_clip is not None,
          f"new roots {new_roots}, mv {moved}")
    # A property group belongs to a KIND of clip, and an op whose rule is
    # "this clip has no text properties" answers that before the patch is
    # read. So three ops are pointed at the clip their group lives on; every
    # other door takes the fixture's AV clip, which has both video and audio.
    subject_clip = {"set_text": text_clip, "set_shape": shape_clip, "set_graphic": graphic_clip}
    for name, argument in doors:
        if argument == "payload":
            continue
        required = tools[name]["inputSchema"].get("required", [])
        published = published_of(name)
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

    print("\n5 — the twenty tools the core calls no op, which the gate covers the same way")
    others = sorted(set(tools) - ops)
    dev = [name for name in DEV_TOOLS if name in tools]
    want = PRODUCT_TOOLS - OPS + len(dev)
    check(f"there are {want} of them ({PRODUCT_TOOLS - OPS} product and {len(dev)} dev)",
          len(others) == want, json.dumps(others))
    for name in others:
        # A hand-written schema is the only spelling these have, so the list
        # the gate speaks is compared to the catalog's — what a caller reads
        # over tools/list, which here is the contract itself rather than a
        # second copy of it. The strangers go ALONE, and this section is LAST
        # on purpose: on the working gate no handler runs, and on a broken
        # one every handler does — `new_project` opens a document over the
        # fixture — so these rows sit after every row that needs it.
        takes = set(tools[name]["inputSchema"]["properties"])
        text, applied = refusal(name, dict(STRANGERS))
        check(f"{name} — two names it never published are refused by the gate, naming the tool "
              f"and exactly {sorted(takes)}", gated(text, name, STRANGERS, takes),
              text[:160] or f"applied: {json.dumps(applied)[:80]}")


    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
