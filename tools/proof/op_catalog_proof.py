#!/usr/bin/env python3
"""ALL FIFTY-NINE op tools, against the core's own op table (road map 7's D3·4).

`clip_catalog_proof.py` measured the forty-three clip and action tools when
they stopped describing their own arguments. This measures the whole catalog:
the nine track, marker and canvas rows, the three raw media ops and the two
transitions migrated last, and the forty-three beside them, from the same two
independent sides:

  * **the CATALOG**, read over MCP off `tools/list` from the running binary;
  * **the TABLE**, read out of the staticlib by a probe compiled from
    `app/Sources` over `swift_build.py`'s line — `rc_op_schemas`
    through `ReelOp.coreSchemas()`, which is the same export the app reads,
    and `AgentServer.declarations`, the list of places a tool deliberately
    takes more or less than its op does.

**No argument name and no op name is written in this file's structural half.**
The group is the core's own op list, and the expectation is COMPUTED from the
table and the declarations by an oracle written here rather than imported, so
a bug in the Swift merge is a failure and not a shared opinion. The behavioural
half names the ops it drives, and checks each against the core's list first.

The sections, in order:

1. **The catalog is the core's op list plus the app's own tools.** Every op
   has a tool, every op tool carries the injected `project` and `scope`, and
   no tool the core calls no op carries a `scope`.
2. **Every op tool is the core's table plus what is declared** — argument,
   JSON kind, `enum`, `minimum`, `maximum` and the required list. Prose is
   compared only for EXISTING where the tool had it, because what an argument
   is FOR is the app's and this script must not hold a copy of it.
3. **The vocabularies the handlers still parse by hand are still the core's**
   — including `add_transition`'s `align`, whose tie to `TransitionAlign` was
   structural until D3·4 made the schema the core's.
4. **Every declaration still names something the core has**, the staleness
   check `opsWithoutTools` has.
5. **Every claim the last fourteen tools make is true of the RUNNING APP.**
   This is the half a generated schema cannot do without: the oracle above is
   built from the same declarations list the catalog is, so a row dropped from
   the list moves both sides together and the comparison stays green (the
   `ripple_delete_ranges.ranges` regression D3·3 recorded as a fix). A marker
   takes the playhead, a boolean takes `"true"`, a negative id is refused by
   name, the canvas bound is refused outside, a transition kind is NOT
   nullable, and a descriptor must be an object.

A probe that will not build is a scored FAILURE, never an exit. The probe is
built BEFORE the first MCP call, so no swiftc runs while the proof is driving
the app.

    make app-debug
    python3 tools/proof/proof_app.py launch   # prints folder, socket, log, pid
    grep "Reelcut: " <dir>/reelcut.log     # must print nothing
    python3 tools/proof/op_catalog_proof.py <dir>/agent.sock
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp import MCP, ToolError, target  # noqa: E402
import swift_build  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "op-catalog-probe")

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

// The vocabularies a HANDLER still parses by name, which the schema used to
// be built from and now is not. `align` is D3·4's: `add_transition` built its
// own `enum` from `TransitionAlign.allCases` until the migration.
answer["vocabularies"] = [
    "transition": TransitionKind.allCases.map { $0.rawValue },
    "align": TransitionAlign.allCases.map { $0.rawValue },
    "curve": Curve.allCases.map { $0.rawValue },
    "fit": ZoomFit.allCases.map { $0.rawValue },
    "groups": AgentServer.attributeGroups,
]

write(answer)
'''


def build_probe():
    """`swift_build.build` over `app/Sources` plus this
    probe's `main.swift`, which makes it the entry point."""
    os.makedirs(WORK, exist_ok=True)
    binary = os.path.join(WORK, "opcatalogprobe")
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
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n      " + "\n      ".join(errors[:6] or ["(no error lines)"])
    if built.reused:
        print(f"op-catalog probe: {binary} (up to date)")
    else:
        print(f"op-catalog probe: {binary} (built in {built.seconds:.1f} s)")
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
        # A row the app fills is not published at all (G3b's `schema`).
        if any(d["requirement"] == "filledByTheApp" for d in rows(argument)):
            continue
        property = fragment
        for declaration in rows(argument):
            property = widened(declaration, property)
        properties[argument] = property
    required = [
        argument for argument in table[op]["required"]
        if not any(d["requirement"] in ("optional", "filledByTheApp")
                   for d in rows(argument))
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
    socket_path = target(sys.argv)
    print("every op tool, against the core's op table\n")
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

    mcp = MCP(socket_path)
    tools = mcp.schemas()

    print("\n1 — the catalog is the core's op list plus the app's own tools")
    check(f"the core declares {len(ops)} ops and every one of them is a tool",
          len(ops) == 59 and ops <= set(tools),
          f"{len(ops)} ops, missing tools: {sorted(ops - set(tools))}")
    group = sorted(ops)
    envelope = {
        name: [key for key in ("project", "scope")
               if key not in tools[name]["inputSchema"]["properties"]]
        for name in group
        if any(key not in tools[name]["inputSchema"]["properties"]
               for key in ("project", "scope"))}
    check("…and every one carries the injected project and scope", not envelope,
          json.dumps(envelope))
    stray = sorted(
        name for name, tool in tools.items()
        if name not in ops and "scope" in tool["inputSchema"].get("properties", {}))
    check(f"no tool the core calls no op has a scope — {len(tools) - len(ops)} app-state "
          "tools, and the injection is still op-only", not stray, json.dumps(stray))

    print("\n2 — every op tool is the core's table plus what is declared")
    drift = {}
    for name in group:
        properties, required = expected_input(name, table, declarations)
        schema = tools[name]["inputSchema"]
        declared = schema.get("properties", {})
        got = {key: structure(value) for key, value in declared.items()
               if key not in ("project", "scope")}
        if got != properties or schema.get("required", []) != required:
            drift[name] = {
                "declared": got, "expected": properties,
                "required": schema.get("required", []), "expected required": required,
            }
    check(f"all {len(group)} of them declare exactly the core's arguments, kinds, enums, "
          "minimums, maximums and required list", not drift,
          json.dumps(drift, indent=2)[:1200])
    hollow = sorted(
        name for name in group
        if not any(key not in ("project", "scope")
                   for key in tools[name]["inputSchema"]["properties"]))
    check("exactly one op tool declares nothing but the envelope's two keys — the one op "
          "the table gives no arguments at all", len(hollow) == 1
          and not table[hollow[0]]["properties"], f"hollow: {hollow}")
    total = sum(
        1 for name in group
        for key, value in tools[name]["inputSchema"]["properties"].items()
        if key not in ("project", "scope") and value.get("description"))
    arguments = sum(len(table[name]["properties"]) for name in group)
    hushed = sorted(
        name for name in group
        if not tools[name]["description"].strip()
        or (table[name]["properties"] and not any(
            value.get("description")
            for key, value in tools[name]["inputSchema"]["properties"].items()
            if key not in ("project", "scope"))))
    check("every op tool carries its own description and, where it takes arguments at all, "
          "prose on at least one of them — the half the core cannot write",
          not hushed, json.dumps(hushed))
    def describes(fragment):
        """Whether a published fragment carries prose at any depth. The KEYS
        are walked rather than the serialized text: a vocabulary member
        spelling the word would make a substring test say yes."""
        if isinstance(fragment, dict):
            return "description" in fragment or any(map(describes, fragment.values()))
        if isinstance(fragment, list):
            return any(map(describes, fragment))
        return False

    core_prose = sorted(
        f"{name}.{argument}" for name in group
        for argument, fragment in table[name]["properties"].items()
        if describes(fragment))
    check(f"…and the core's table carries none of it: {total} of the {arguments} published "
          "arguments are described by the CATALOG and not one by the table",
          not core_prose and 0 < total <= arguments,
          json.dumps(core_prose) or f"{total} described of {arguments}")

    print("\n3 — the vocabularies a handler still parses by name are still the core's")
    for label, op, argument, key, is_list in [
        ("set_transition's kinds", "set_transition", "kind", "transition", False),
        ("add_transition's align", "add_transition", "align", "align", False),
        ("add_zoom_action's fit", "add_zoom_action", "fit", "fit", False),
        ("the easing curves", "set_action", "curve", "curve", False),
        ("paste_attributes's groups", "paste_attributes", "groups", "groups", True),
    ]:
        fragment = table.get(op, {}).get("properties", {}).get(argument, {})
        if is_list:
            fragment = fragment.get("items", {})
        published = [member for member in fragment.get("enum", []) if member is not None]
        check(f"{label} — {op}.{argument}",
              op in ops and bool(published)
              and published == answer["vocabularies"][key],
              f"core {published} vs swift {answer['vocabularies'][key]}")

    print("\n4 — every declaration still names something the core has")
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
          "core has — the staleness check `opsWithoutTools` has", not stale,
          json.dumps(stale))

    print("\n5 — every claim the last fourteen tools make is true of the running app")
    for name in ["add_marker", "set_track", "remove_track", "remove_media", "set_canvas",
                 "add_transition", "add_media"]:
        if name not in ops:
            check(f"{name} is an op the core declares", False, "renamed?")

    def declared(op, argument, key="type"):
        """One key of what the tool declares for `argument`; a lone `type` is
        answered as a one-element list, so a widening reads the same way."""
        value = tools[op]["inputSchema"]["properties"][argument].get(key)
        if key == "type" and not isinstance(value, list):
            return [value]
        return value

    def refusal(op, arguments):
        try:
            mcp.call_with(op, arguments)
        except ToolError as error:
            return str(error)
        return ""

    mcp.call("new_project")
    project = mcp.call("get_project")["project"]
    track = project["tracks"][0]["id"]

    # The playhead, the fourth time: a marker with no `at` is the M key's own
    # default, and the core REQUIRES the tick. Only the running app can say
    # whether the declaration that drops it from `required` is true.
    mcp.call("set_playhead", t=1200000)
    mcp.call("add_marker")
    markers = mcp.call("get_project")["project"].get("markers", [])
    check("add_marker takes the playhead when `at` is left out, although the core requires "
          "it — the row that says a default is app state",
          [m["time"] for m in markers] == [1200000]
          and "at" not in tools["add_marker"]["inputSchema"].get("required", []),
          f"markers {markers}, required {tools['add_marker']['inputSchema'].get('required')}")

    # A boolean's string spellings, in a group that did not have them declared
    # until now. `boolArg` is the whole kind's reader, so the row names a kind
    # and the claim is checked where the kind is used.
    mcp.call_with("set_track", {"track": track, "hidden": "true"})
    hidden = mcp.call("get_project")["project"]["tracks"][0].get("hidden")
    check("a track switch takes a boolean's string spelling, and every boolean argument of "
          "every op tool says a string is allowed",
          hidden is True
          and all("string" in declared(op, argument)
                  for op in group
                  for argument, fragment in table[op]["properties"].items()
                  if fragment.get("type") == "boolean"),
          f"hidden {hidden!r}")

    # A negative id: the `minimum: 0` the migration published is a rule the
    # app enforces, not a key that was added because the core's kind carried
    # one.
    for op, argument in [("remove_track", "track"), ("remove_media", "media")]:
        refused = refusal(op, {argument: -1})
        check(f"{op} refuses a negative {argument} by name, which is what its minimum says",
              f"{argument} is not an id" in refused and declared(op, argument, "minimum") == 0,
              f"refusal {refused[:120]!r}, minimum {declared(op, argument, 'minimum')}")

    # The one published BOUND outside the clip group: 16–16384, sourced from
    # the constants `edit_canvas.rs` refuses by.
    refused = refusal("set_canvas", {"width": 15})
    check("set_canvas refuses a width one step under the bound it publishes, naming both "
          "ends", "16" in refused and "16384" in refused
          and declared("set_canvas", "width", "minimum") == 16
          and declared("set_canvas", "width", "maximum") == 16384,
          f"refusal {refused[:120]!r}, bound "
          f"{declared('set_canvas', 'width', 'minimum')}–"
          f"{declared('set_canvas', 'width', 'maximum')}")

    # …and the one bound the APP refuses outside where the core's kind is
    # looser. A schema wider than what is accepted is the direction that
    # costs a caller a call it cannot make, so the row narrows the items and
    # this asks the app whether the narrowing is true.
    refused = refusal("set_canvas", {"fps": [0, 1]})
    check("set_canvas refuses a frame rate with a zero term by name, and the tool narrows "
          "the core's whole numbers to say so",
          "fps[0] must be" in refused
          and (declared("set_canvas", "fps", "items") or {}).get("minimum") == 1,
          f"refusal {refused[:120]!r}, items {declared('set_canvas', 'fps', 'items')}")

    # The opposite direction of `set_transition`'s null, and the reason the
    # two ops cannot share a row: an explicit null here is a mistake, the
    # tool refuses it, and the schema does NOT offer it.
    mcp.call("add_text_clip", track=track, at=0)
    clip = mcp.call("get_project")["project"]["clips"][-1]["id"]
    refused = refusal("add_transition", {"clip": clip, "kind": None, "duration": 300000})
    check("add_transition's kind is NOT nullable — an explicit null is refused by name and "
          "the tool never offered one, where set_transition's null clears",
          "kind must be one of" in refused and "null" not in declared("add_transition", "kind"),
          f"refusal {refused[:120]!r}, declared {declared('add_transition', 'kind')}")

    # A patch is opaque and the op's door is what refuses a non-object — the
    # one thing `Kind::Object` claims, put to the running app.
    refused = refusal("add_media", {"descriptor": "~/Movies/x.mov"})
    check("add_media's descriptor is declared an object with no properties, and a string is "
          "refused by name", "descriptor must be a JSON object" in refused
          and declared("add_media", "descriptor") == ["object"]
          and "properties" not in tools["add_media"]["inputSchema"]["properties"]["descriptor"],
          f"refusal {refused[:120]!r}, declared "
          f"{json.dumps(tools['add_media']['inputSchema']['properties']['descriptor'])}")

    print(f"\n{passed}/{passed + failed} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
