#!/usr/bin/env python3
"""The clip tools, checked against the core's own op table (road map 7's D3·3).

The forty-three clip and action tools stopped describing their own arguments
and started printing the core's. What this measures is the identity that
makes that safe, from two independent sides:

  * **the CATALOG**, read over MCP off `tools/list` from the running binary;
  * **the TABLE**, read out of the staticlib by a probe compiled from
    `app/Sources` over `harness/build.sh`'s own swiftc line — `rc_op_schemas`
    through `ReelOp.coreSchemas()`, which is the same export the app reads,
    and `AgentServer.declarations`, the list of places a tool deliberately
    takes more or less than its op does.

**No argument name is written in this file.** The expectation is COMPUTED
from the table and the declarations, by an oracle written here rather than
imported, so a bug in the Swift merge is a failure and not a shared opinion.
The only names typed are the two ends of the clip group in catalog order
(`add_clip` … `remove_action`) and the ops the behavioural section drives,
and both are checked against the core's op list before they are used.

Three things it asserts, in this order:

1. **The migrated tools are the core's table plus what is declared.** Every
   argument, its JSON kind, its `enum`, its `minimum`, and the required list
   — against the oracle, with the injected `project` and `scope` beside
   them. Descriptions are compared only for EXISTING, because what an
   argument is FOR is the app's and this script must not hold a copy of it.
2. **Every declaration is true of the running app.** A shorthand that is
   declared works; a shorthand that WORKS is declared (which is the row a
   widening deleted from the list falls to, while the catalog and the oracle
   would still agree with each other); a null that means something is taken;
   a list the tool will not take empty is refused by name; an argument the
   app defaults from its own state may be left out.
3. **The vocabularies the handlers still parse by hand are still the
   core's.** `set_transition`'s kinds, `add_zoom_action`'s fit, the curves
   and `paste_attributes`'s groups are enumerated from the core in the
   schema now, and a Swift enum is what a refusal names — so the two are
   compared, which is the one tie the migration would otherwise have cut.

What it does NOT claim: that `set_speed` clamps a rate rather than refusing
it. That needs a media clip, this script makes none, and the claim is the
core's own (`core/tests/op_table.rs`'s bound test says the range is not one
the table may publish, which is why it is a declared row here).

A probe that will not build is a scored FAILURE, never an exit. The probe is
built BEFORE the first MCP call, so no swiftc runs while the proof is
driving the app.

    make app
    (RC_AGENT_PORT=4853 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \\
       -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4853.log 2>&1 &)
    grep "Reelcut: " /tmp/reelcut-4853.log     # must print nothing
    python3 tools/proof/clip_catalog_proof.py 4853
"""

import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "clip-catalog-probe")

# The clip group is a contiguous run of the catalog, spliced in at the place
# it was cut from, and these are its two ends. They are OP names, not
# argument names, and both are checked against the core's op list below.
FIRST, LAST = "add_clip", "remove_action"
# The two rows inside that run which are composites rather than ops
# (`detect_silence`, `normalize_clip`) are found by asking the core which
# names it calls ops, never by being listed here.

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
# The probe: the core's table and the app's declarations, as data.

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

// The declarations list, one object per row.
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

// The vocabularies a HANDLER still parses by name, which the schema used to
// be built from and now is not.
answer["vocabularies"] = [
    "transition": TransitionKind.allCases.map { $0.rawValue },
    "curve": Curve.allCases.map { $0.rawValue },
    "fit": ZoomFit.allCases.map { $0.rawValue },
    "groups": AgentServer.attributeGroups,
]

write(answer)
'''


def build_probe():
    """`harness/build.sh`'s own swiftc line over `app/Sources` plus this
    probe's `main.swift`, which makes it the entry point."""
    os.makedirs(WORK, exist_ok=True)
    binary = os.path.join(WORK, "clipcatalogprobe")
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
        print(f"clip-catalog probe: {binary} (up to date)")
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
    print(f"clip-catalog probe: {binary} (built in {time.time() - start:.1f} s)")
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


# --------------------------------------------------------------------------
# The oracle: the table, the declarations, and the envelope's two keys — the
# same three sources `AgentServer.declaredInput` reads, put together here
# independently of it.


def covers(declaration, op, argument, published_type):
    subject = declaration["subject"]
    if subject["kind"] == "argument":
        return subject["op"] == op and subject["name"] == argument
    if subject["kind"] == "everyTyped":
        return published_type == subject["type"]
    return subject["name"] == argument


def widened(declaration, fragment):
    property = dict(fragment)
    also = declaration["alsoTypes"]
    if also and isinstance(property.get("type"), str):
        property["type"] = [property["type"]] + also
        if "null" in also and isinstance(property.get("enum"), list):
            property["enum"] = property["enum"] + [None]
    property.update(declaration["alsoKeys"])
    return property


def expected_input(op, table, declarations):
    """What the tool for `op` must declare, structure only.

    One predicate answers "which rows are about this argument", asked with
    the CORE's own published type — a row may name a kind, and the answer
    must not depend on which row was applied first."""
    def rows(argument):
        published = table[op]["properties"].get(argument, {})
        return [d for d in declarations
                if covers(d, op, argument, published.get("type"))]

    properties = {}
    for argument, fragment in table[op]["properties"].items():
        property = fragment
        for declaration in rows(argument):
            property = widened(declaration, property)
        properties[argument] = property
    required = [
        argument for argument in table[op]["required"]
        if not any(d["requirement"] == "optional" for d in rows(argument))
    ]
    for argument in sorted(properties):
        if argument in required:
            continue
        if any(d["requirement"] == "required" for d in rows(argument)):
            required.append(argument)
    return properties, required


def structure(property):
    """A declared property with its prose removed — what the core owns."""
    return {key: value for key, value in property.items() if key != "description"}


# --------------------------------------------------------------------------


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4853
    print("the clip tools, against the core's op table\n")
    binary, error = build_probe()
    check("the probe builds — an instrument that will not compile is a FAILURE here, "
          "not an exit", binary is not None, error or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    answer, error = run_probe(binary)
    check("the probe answers with the core's table and the app's declarations",
          answer is not None, error or "")
    if answer is None:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    table = answer["schemas"]
    ops = set(answer["names"])
    declarations = answer["declarations"]

    mcp = MCP(port)
    # One read of the catalog, kept both ways round: the ORDER is what finds
    # the clip group, and the map is what every check below reads. Both come
    # from `mcp.schemas()`, the shared accessor road map 7's D3·5 added, and
    # a dict keeps the catalog's own order.
    tools = mcp.schemas()
    order = list(tools)

    print("\n1 — the group: a contiguous run of the catalog, and the core says which of "
          "it is ops")
    check("both ends of the clip group are ops the core declares",
          FIRST in ops and LAST in ops, f"{FIRST} in core: {FIRST in ops}; "
          f"{LAST} in core: {LAST in ops}")
    check(f"…and both are tools, with {FIRST} before {LAST}",
          FIRST in order and LAST in order and order.index(FIRST) < order.index(LAST),
          f"order: {order.index(FIRST) if FIRST in order else None} .. "
          f"{order.index(LAST) if LAST in order else None}")
    if FIRST not in order or LAST not in order:
        print(f"\n{passed}/{passed + failed} checks passed")
        return 1
    run = order[order.index(FIRST):order.index(LAST) + 1]
    group = [name for name in run if name in ops]
    check(f"the run holds {len(group)} op tools — the clip and action rows — and "
          f"{len(run) - len(group)} composites the core calls no op",
          len(group) == 43 and len(run) - len(group) == 2,
          f"run of {len(run)}: {run}")

    print("\n2 — every migrated tool is the core's table plus what is declared")
    drift = {}
    for name in group:
        properties, required = expected_input(name, table, declarations)
        schema = tools[name]["inputSchema"]
        declared = schema.get("properties", {})
        # The envelope's two keys are the catalog's and are not the table's.
        got = {key: structure(value) for key, value in declared.items()
               if key not in ("project", "scope")}
        if got != properties or schema.get("required", []) != required:
            drift[name] = {
                "declared": got, "expected": properties,
                "required": schema.get("required", []), "expected required": required,
            }
    check(f"all {len(group)} of them declare exactly the core's arguments, kinds, enums, "
          "minimums and required list", not drift,
          json.dumps(drift, indent=2)[:1200])
    missing = {
        name: sorted(key for key, value in tools[name]["inputSchema"]["properties"].items()
                     if key not in ("project", "scope") and not value.get("description"))
        for name in group
        if any(key not in ("project", "scope") and not value.get("description")
               for key, value in tools[name]["inputSchema"]["properties"].items())
    }
    check("…and every argument still carries prose, which is the half the core cannot "
          "write", not missing, json.dumps(missing))
    envelope = {
        name: [key for key in ("project", "scope")
               if key not in tools[name]["inputSchema"]["properties"]]
        for name in group
        if any(key not in tools[name]["inputSchema"]["properties"]
               for key in ("project", "scope"))}
    check("…and every one still carries the injected project and scope",
          not envelope, json.dumps(envelope))
    stray = sorted(
        name for name, tool in tools.items()
        if name not in ops and "scope" in tool["inputSchema"].get("properties", {}))
    check("no tool the core calls no op has a scope — the injection is still op-only",
          not stray, json.dumps(stray))

    print("\n3 — the vocabularies a handler still parses by name are still the core's")
    for label, op, argument, key, is_list in [
        ("set_transition's kinds", "set_transition", "kind", "transition", False),
        ("add_zoom_action's fit", "add_zoom_action", "fit", "fit", False),
        ("the easing curves", "set_action", "curve", "curve", False),
        ("paste_attributes's groups", "paste_attributes", "groups", "groups", True),
    ]:
        fragment = table[op]["properties"][argument]
        if is_list:
            fragment = fragment.get("items", {})
        published = [member for member in fragment.get("enum", []) if member is not None]
        check(f"{label} — {op}.{argument}",
              published == answer["vocabularies"][key],
              f"core {published} vs swift {answer['vocabularies'][key]}")

    print("\n4 — every declaration is true of the running app")
    # `opsWithoutTools` has a staleness check beside it — an entry naming an
    # op the core does not have is a complaint at startup. The declarations
    # list has none until the fifth parity part lands, and a row naming a
    # renamed op or argument would go silently INERT, so the same question
    # is asked here, of the core's own table.
    stale = []
    for declaration in declarations:
        subject = declaration["subject"]
        if subject["kind"] == "argument":
            row = table.get(subject["op"], {}).get("properties", {})
            if subject["name"] not in row:
                stale.append(f"{subject['op']}.{subject['name']}")
        elif subject["kind"] == "everyNamed":
            if not any(subject["name"] in schema["properties"] for schema in table.values()):
                stale.append(f"every argument named {subject['name']}")
        elif not any(fragment.get("type") == subject["type"]
                     for schema in table.values()
                     for fragment in schema["properties"].values()):
            stale.append(f"every argument typed {subject['type']}")
    check(f"every one of the {len(declarations)} declarations still names something the "
          "core has — the staleness check `opsWithoutTools` has and this list has not",
          not stale, json.dumps(stale))

    mcp.call("new_project")
    project = mcp.call("get_project")["project"]
    track = project["tracks"][0]["id"]

    def declared_type(op, argument):
        value = tools[op]["inputSchema"]["properties"][argument].get("type")
        return value if isinstance(value, list) else [value]

    mcp.call("add_text_clip", track=track, at=0, text="A bare string")
    clip = mcp.call("get_project")["project"]["clips"][-1]
    check("a new text clip's body takes a bare string, and the tool SAYS a string is "
          "allowed — the row a widening dropped from the list falls to",
          clip.get("text", {}).get("content") == "A bare string"
          and "string" in declared_type("add_text_clip", "text"),
          f"content {clip.get('text', {}).get('content')!r}, declared "
          f"{declared_type('add_text_clip', 'text')}")
    mcp.call("add_shape_clip", track=track, at=3000000, shape="ellipse")
    shape = mcp.call("get_project")["project"]["clips"][-1]
    check("a new shape clip's body takes a bare kind, and the tool says so",
          shape.get("shape", {}).get("kind") == "ellipse"
          and "string" in declared_type("add_shape_clip", "shape"),
          f"kind {shape.get('shape', {}).get('kind')!r}, declared "
          f"{declared_type('add_shape_clip', 'shape')}")
    mcp.call("set_enabled", clip=clip["id"], video="false")
    flipped = [c for c in mcp.call("get_project")["project"]["clips"]
               if c["id"] == clip["id"]][0]
    check("a boolean takes its string spelling, and every boolean argument says so",
          flipped.get("enabled", {}).get("video") is False
          and all("string" in declared_type(op, argument)
                  for op in group
                  for argument, fragment in table[op]["properties"].items()
                  if fragment.get("type") == "boolean"),
          f"enabled {flipped.get('enabled')}")

    # The two nulls that mean something: declared nullable AND required, so
    # that forgetting the key cannot become the edit the null makes.
    for op, argument, arguments in [
        ("set_transition", "kind", {"clip": clip["id"]}),
        ("add_zoom_action", "region", {"clip": clip["id"], "at": 0}),
    ]:
        refused = ""
        try:
            mcp.call_with(op, arguments)
        except ToolError as error:
            refused = str(error)
        check(f"{op}'s {argument} is refused when it is left out, and the tool asks for "
              "it — a null here MEANS something",
              argument in refused
              and argument in tools[op]["inputSchema"].get("required", [])
              and "null" in declared_type(op, argument),
              f"refusal {refused[:120]!r}, required "
              f"{tools[op]['inputSchema'].get('required')}, declared "
              f"{declared_type(op, argument)}")
    # …and the null itself is taken and MEANS what the prose says. A third
    # clip overlapping the shape one is a transition; the null clears it,
    # which a null merely tolerated could not do.
    mcp.call("add_text_clip", track=track, at=5000000)
    overlapped = mcp.call("get_project")["project"]["clips"][-1]["id"]
    mcp.call("set_transition", clip=overlapped, kind="wipe")

    def transition_of(clip_id):
        found = [c for c in mcp.call("get_project")["project"]["clips"] if c["id"] == clip_id]
        return (found[0].get("transition_in") or {}).get("kind") if found else "<no clip>"

    kind = transition_of(overlapped)
    cleared = ""
    try:
        mcp.call("set_transition", clip=overlapped, kind=None)
    except ToolError as error:
        cleared = str(error)
    check("set_transition takes an explicit null and it CLEARS the transition — the "
          "spelling the core cannot tell from an absent argument",
          kind == "wipe" and cleared == "" and transition_of(overlapped) is None,
          f"set to {kind!r}, then {cleared[:120]!r}, now {transition_of(overlapped)!r}")

    # Each of the three lists a tool will not take empty, asked the same way:
    # the REFUSAL and the schema key have to agree, because the oracle above
    # is built from the same declarations list the catalog is and would move
    # with it. Only a row that asks the running app can see a declaration
    # dropped while the behaviour stays — `ranges` is here because it was
    # dropped exactly that way and no row noticed.
    for op, argument, arguments in [
        ("delete", "clips", {"clips": []}),
        ("split", "clips", {"clips": []}),
        ("ripple_delete_ranges", "ranges", {"ranges": []}),
    ]:
        refused = ""
        try:
            mcp.call_with(op, arguments)
        except ToolError as error:
            refused = str(error)
        check(f"{op} refuses an empty {argument} list by name, which is what its "
              "minItems says",
              f"{argument} is empty" in refused
              and tools[op]["inputSchema"]["properties"][argument].get("minItems") == 1,
              f"refusal {refused[:120]!r}")

    mcp.call("set_playhead", t=1200000)
    mcp.call("split", clips=[clip["id"]])
    cut = sorted(c["start"] for c in mcp.call("get_project")["project"]["clips"])
    check("split takes the playhead when `at` is left out, although the core requires "
          "it — the row that says a default is app state",
          1200000 in cut and "at" not in tools["split"]["inputSchema"].get("required", []),
          f"starts {cut}, required {tools['split']['inputSchema'].get('required')}")

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
