#!/usr/bin/env python3
"""Road map 10, G5a — the Graphic sub-tab in the clip inspector (§5j; spec
§11 G-15), against the built app, a probe and the offscreen harness.

    python3 tools/proof/graphics_inspector_proof.py [--app PATH]
    python3 tools/proof/graphics_inspector_proof.py --mutant NAME

**The fixture, over MCP** (one owned instance on a scratch socket, launched and
stopped by PID, under the scratch home `CFFIXED_USER_HOME=work/graphics-inspector/home`
since issue batch B87 phase 3 — H0, a CONTROL, says the home took: `<home>/Library/
Application Support` is a directory — its log at `work/graphics-inspector/framejob.log`):
`new_project {path: GI}`, `write_graphic six` — a module with one entry of
every schema type: `title` a string whose default holds `{"}:`, `size` a
number 12–200 step 1, `offset` an unbounded number, `showBox` a boolean,
`color` a colour defaulting to "#FF5A36" (uppercase on purpose), `align` an
enum, `logo` an asset defaulting to null; its `render` sizes the `<svg>` from
ctx (`svg(ctx, …)`) and draws text in `'Nope Sans'` — `import_graphic_asset
graphic/tests/assets/red.png`, `add_graphic_clip`, `set_graphic {props:
{size: 90}}`, `save_project`; the instance is stopped, and `"old": 1` and
`"zzz": 2` are injected into the clip's props in `project.json` (the tool
path refuses a stranger key; this is the external edit G-4 tolerates). The same
instance, before it stops, makes GIA (B87 phase 3): `new_project`, `write_graphic
six`, `add_graphic_clip` at 0, `add_action {at: 600000, duration: 1200000}` (CLIP and
PROJECT 1–3 s), `set_action_end {size: 150, color: "#2d7ff9", showBox: false, align:
"center", title: "Hello"}` and `save_project`.

**The probe**, `graphics_inspector_probe.swift`, compiled AS `main.swift` over
every file in `app/Sources` but the app's own through `swift_build.py`
(a probe that will not build is a scored FAILURE), with the app's Fonts
beside it, over a COPY of the fixture:
I1  `orderedKeys` over six's `describeJSON()` is the module's order;
I2  one row per type, with its control classes; the asset popup lists None
    and red.png;
I3  size 90 vs default 64: the gutter's default differs and its ops are
    `set_graphic {props: {size: null}}`; no stored size → no difference; the
    colour row, unstored, differs not and resets to `{color: null}`;
I4  `patchValue`'s null rule (a number, "#ff5a36" vs "#FF5A36"), the four hex
    forms round-tripped and `css([1, 0.353, 0.212, 1]) == "#ff5a36"` (issue
    batch B69 dropped its two rows that read "white" as unparsed: I21 now
    reads it as the colour it is);
I5  `staleKeys` sorted; the stale rows old then zzz; a syntax error makes every
    stored key stale and the Source section's compile row names line 2; each
    ⌫ removes its key;
I6  one more schema key changes `structureSignature`; so does each of a
    default 64 → 65, `max` 200 → 250 (after which the rebuilt Size slider's
    reflected `upper` is 250) and `align`'s options gaining "justify" — the
    entries are spelled whole (issue batch B8, #106); a stored value alone
    does not;
I7  the tabs [graphic, picture, clip]; the four section ids; two modules →
    [graphic.source, graphic.size]; `keyedCount` of a video-only end patch 0;
I8  the report names Nope Sans and the set's families, with no size warning;
    a fixed 100×100 `<svg>` gets exactly one naming 1920×1080; a throw at
    frame 0 is an error with `frame == 0`;
I9  the TOOL's size 90 shows in the Size field; the checkbox's write lands
    under the module's spelling (`showBox`);
I10 `fitToCanvasOps`; I11 `sourceSize(of:)`; I12 after `trim_start` by 2 s
    the In readout shows the graphic's own in point;
I13 (B8) `decimals(for:)`: no step with default 0.5 → 2, step 0.1 → 2, step 1
    with default 0.5 → 0, no step with default 3 → 0, no step with max 1.5 →
    2; with six's `offset` default rewritten to 0.5 the Offset field reads
    "0.50";
I14 (B8) the Title `InspectorNameField`'s height constraint is
    `DS.controlHeight`, and the Title row's `fittingSize.height` equals the
    Offset row's;
I16 (B8) after two signature reads `schemaMemo.key` is "six|<registry
    revision>" and `layerMemo[clip]` is set with `layerProject ===
    document.editedProject`; after a rewrite of six the key names the new
    revision;
I17 (B8) a `DocumentPane(inspector:)` over the fixture with one marker added
    through `ReelOp.addMarker`: its marker `InspectorNameField` (placeholder
    "Marker") has exactly one height constraint of its own, `DS.controlHeight`;
I18 (issue batch B68, #105, spec §11 G-24 (a)) six rewritten with `const logo
    = asset("x");` first: the Source section has exactly one warning
    `GraphicDiagnosticRow` whose label starts `asset("x") is not in
    graphics/assets/`; six restored: none (CONTROL);
I19 (B68, G-24 (b)) `Bad.js` written into the fixture's `graphics/` and
    `store.rescan()`: the Source section holds the note "In the graphics
    folder" and after it a row labelled `graphics/Bad.js is not a module
    name…` whose button is "Reveal", and `structureSignature` changed; removed
    and rescanned: neither, and the signature is back (CONTROL);
I20 (issue batch B69, #221) the Source section's notes, in view order, each
    group under a heading true of it (hidden notes skipped): a) six rewritten
    with `const logo = asset("x");` first and its `font-family="'Nope
    Sans'"` made `font-family="sans-serif"` (the anchor asserted to occur
    once; a text with NO family warns that the default is not in the set,
    so the family is swapped, not stripped): ["Compiling the module", "No
    errors or warnings at the clip's first frame"], the asset row between
    them; b) six rewritten to a syntax error: ["Compiling the module"]; c)
    `Bad.js` in `graphics/` and six clean (sans-serif): ["No errors or
    warnings at the clip's first frame", "In the graphics folder"]; six
    restored, and Bad.js removed, after each; `old` and `zzz` are nulled first,
    so the rows do not lean on I5's removals;
I21 (B69, #219, spec §11 G-25) a colour default through the core's G-12
    (`rc_normalise_color`): a) `defaultColor` of "white", "steelblue" and
    "hsl(120, 50%, 50%)" is `rgba(css:)` of "#ffffff", "#4682b4" and
    "#40bf40"; b) `patchValue` of each hex against its default is NSNull, and
    "#000000" against "steelblue" is the string itself (CONTROL); c)
    `defaultColor("bluish")` is `unparsedColor`;
K1–K18 (issue batch B87 phase 3, #239, spec §11 G-34 (l); after I21, before I15)
    the Graphic tab under a selected action: six's clip (PROJECT 2–5 s after I12)
    gets an action at CLIP 1–3 s, linear, selected; every write goes through the
    control's own `write` (read from its stored closure through a one-field struct,
    because `Mirror` hands a closure back at the wrong abstraction), and `recorded`
    is every op the inspector sent. K1 (CONTROL) no action selected: Size's write is
    one `set_graphic`; K2 selected: one `set_action_end` naming `graphic.props.size`
    with the module's schema, the end's `kinds.size` "number", the base 90; K3a/K3b
    the mark ◆, the field reads the END, and the section's, tab's and strip's counts
    are 1; K4 the slider's start 90, now 120 at mid-span, keyed; K5 a checkbox and a
    pop-up are ◆ "at end"; K6a/K6b the string row too, and laid out at
    `DS.panelWidth` its field narrows below 170 for a whole tag only while keyed
    (CONTROL: exactly 170 with nothing selected); K7 the colour well ◆, no tag; K8
    the asset is ⊘ and its write stays `set_graphic`; K9 "Set end value to default"
    writes 64 into the end; K10 × removes one key; K11 Clear removes all, counts 0;
    K12 a key the module no longer declares gets the action's own stale row, ◆, ⌫
    "… remove it from action 1", counted (O2, O4); K13 with no action selected ◇1 and
    `set_graphic`; K14 Width, Height and Follow Clip are ⊘ (O6; CONTROL blank); K15a/
    K15b the band's label keys and the zoom test (O3); K16 the Text tab's keyed
    Content row reads "at end" (O5); K17 Properties' Reset writes the end, the
    asset's null to the base (O7); K18a the text clip's action keys the font, and laid
    out at `DS.panelWidth` Font ▸ Family's popup narrows below 150 so its "at end" is
    whole and inside the panel's inset — the CONTROL gives way, never the tag (O8;
    CONTROL: the font not keyed, no tag and exactly 150); K18b the same action keys a
    filter and an obscure region, and in each row only the widest popup gives way;
    K18c (issue batch B87 phase 4) six's `showBox` relabelled "Show the long
    descriptive label for this toggle" and keyed: in a row with no popup the
    checkbox narrows below its own width so its "at end" is whole and inside the
    inset, its compression resistance below the tag's (a tie at 750 is what the
    solver happens to break the right way here), and the row's cached drawing
    has no ink between the checkbox and the tag and none over the tag beyond
    the tag's own (its title cut at its edge) while the checkbox's frame has
    some (CONTROL: not keyed, no tag and the checkbox exactly its own width).
I15 (B8, last) a second `six` clip; the two hold logo "a.png" and "b.png" and
    both are selected: the Logo popup is `["None", "red.png", "a.png",
    "b.png"]`, and the signature holds "red.png,a.png,b.png".

**The harness** (`harness/build.sh`, 1440 × 1500, the clip selected, subTab
graphic, the four sections expanded):
H1  light, rendered twice: byte-identical;
H2  dark, rendered twice: byte-identical, and light ≠ dark. Both kept under
    `work/graphics-inspector/` to be LOOKED AT.
H3  (B87 phase 3) GIA light, its action (index 0) selected, the playhead at 2 s,
    track size L so the band's label shows (`0 2 2 clip - SECTIONS - 0 graphic`),
    rendered twice: byte-identical; H4 dark the same, and light ≠ dark. Kept as
    `work/graphics-inspector/gia-*.png`.
Z1  `grep "Frame Job: "` over the log prints nothing.

`--mutant NAME` builds the probe over a COPY of `app/Sources` with one
anchor of `MUTANTS[NAME]`, asserted to occur exactly once, replaced, over a
fresh fixture. Exit 0 means exactly that mutant's expected rows failed and
nothing else did:
  stale              `GraphicSchemaRows.staleKeys` answers `[]` — the five I5 rows;
  entry-signature    the signature spells an entry "key:type" again — I6's
                     default, max and options rows;
  step-decimals      `decimals(for:)` is the old `(step ?? 1) < 1 ? 2 : 0` — I13;
  name-height        `InspectorNameField` pins no height of its own — I14 and
                     I17 (issue batch B23, #171: the field pins its own
                     `DS.controlHeight` since `stringRow` and
                     `DocumentPane.markerRow` stopped re-pinning a
                     `DSField.style` height; supersedes B8's `title-height`
                     and `marker-height`);
  merged-asset-names the signature's asset names built from `storedProps()`,
                     the first clip's value winning, as before — I15's
                     signature row;
  no-schema-memo     `schema(_:)` never stores `schemaMemo` — I16;
  compile-warnings-dropped  the Source report's `compile: module.compileWarnings`
                     is `compile: []` — I18 (B68) and I20 a (B69: its "Compiling
                     the module" heading goes with the warning);
  folder-warnings-dropped   `folderWarnings()` answers `[]` — I19 (B68) and I20 c
                     (B69: its "In the graphics folder" heading goes too);
  default-color-hex-only    `defaultColor` reads the default as hex only,
                     skipping `ReelColor.normalise` — I21 a and I21 b (B69);
  compile-heading-dropped   the "Compiling the module" note is not appended —
                     I20 a and I20 b (B69);
  first-frame-note-unconditional  the first-frame note is shown whatever
                     `report.frame` is — I20 b (B69).
Issue batch B87 phase 3 adds K12 to `stale` and sixteen more (a bare K id in
`MUTANTS` names that one row):
  row-writes-base    the graphic split sends every value to the base — K2 K3a K4 K5
                     K6a K6b K7 K9 K11 K17;
  count-zero         `keyedCount` of graphic is 0 again — K3b K12;
  null-default-in-end  the end takes G-15 (b)'s nulls — K9 K17;
  stored-read        `graphicProps` reads the stored props — K3a K4;
  paths-flat         an end's `graphic` group is one path — K3a K10 K11 K13;
  string-continuous  the string row is not discrete — K6a K6b;
  title-fixed-width  the Title field's 170 is required — K6b;
  asset-to-end       an asset goes to the end — K8 K17;
  schema-dropped     the typed `setActionEnd` drops `schema` — K2 K5 K9 K17;
  end-stale-dropped  `endProps()` answers nothing — K12;
  layer-keys-unnamed `set_graphic`'s width/height/length name no path — K14;
  band-label-graphic-dropped  the band's label omits graphic keys — K15a;
  zoom-graphic-nil   the zoom test asks for no `graphic` at all — K15b;
  content-continuous the Text tab's Content row is not discrete — K16;
  reset-to-base      Properties' Reset ignores the selected action — K17;
  popup-fixed-width  a row's widest popup holds its width against the tag (its
                     compression resistance required, not 749) — K18a K18b (O8);
                     since phase 4 the same 749 is a popup-less row's widest
                     checkbox's, so K18c too.
Issue batch B87 phase 4 adds two more:
  checkbox-fixed-width  a row with no popup gives no checkbox the 749 — K18c (O8);
  checkbox-title-unclipped  the narrowing checkbox is not clipped to its
                     bounds, so its title draws on under the tag — K18c.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_proof as gp  # noqa: E402  (attempt, complaints)
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics-inspector"
HOME = WORK / "home"
CALL_BOUND = 300
APP = proof_app.binary()
PROBE_SWIFT = ROOT / "tools/proof/graphics_inspector_probe.swift"
HARNESS_BUILD = ROOT / "tools/proof/harness/build.sh"
RED_PNG = ROOT / "graphic/tests/assets/red.png"
SECTIONS = "graphic.source,graphic.properties,graphic.size,graphic.timeline"
WIDTH, HEIGHT = 1440, 1500

SIX_JS = r'''export const meta = { name: "Six", durationInFrames: 150 };
export const schema = {
  title: { type: "string", default: "Hi {\"}: there", label: "Title", help: "The words drawn" },
  size: { type: "number", default: 64, min: 12, max: 200, step: 1, label: "Size" },
  offset: { type: "number", default: 0, label: "Offset" },
  showBox: { type: "boolean", default: true, label: "Show box" },
  color: { type: "color", default: "#FF5A36", label: "Color" },
  align: { type: "enum", default: "left", options: ["left", "center", "right"], label: "Align" },
  logo: { type: "asset", default: null, label: "Logo" },
};
export function render(frame, props, ctx) {
  return svg(ctx, `<text x="100" y="300" font-family="'Nope Sans'" font-size="${props.size}" fill="${props.color}">${escapeXml(props.title)}</text>`);
}
'''

# name: (file, anchor, replacement, the rows that must fail and no others)
MUTANTS = {
    "stale": (
        "GraphicSchemaRows.swift",
        "        return stored.keys.filter { !declared.contains($0) }.sorted()\n",
        "        _ = declared\n        return []  // mutant: nothing is stale\n",
        ["I5 staleKeys is [old, zzz] from a dictionary built in the reverse order",
         "I5 the Properties section lists the stale rows old then zzz, under the schema's",
         "I5 six rewritten to a syntax error: every stored key is a stale row, sorted",
         "I5 old's ⌫ nulls it: the key leaves the stored props",
         "I5 zzz's ⌫ nulls it: the key leaves the stored props",
         "K12"]),
    "entry-signature": (
        "GraphicPane.swift",
        "parsed?.schema.entries.map { String(describing: $0) }",
        "parsed?.schema.entries.map { \"\\($0.key):\\($0.type)\" }",
        ["I6 a default 64 → 65 changes it",
         "I6 max 200 → 250 changes it, and the rebuilt Size slider's upper is 250",
         "I6 align's options gaining \"justify\" changes it"]),
    "step-decimals": (
        "GraphicSchemaRows.swift",
        "        if let step = entry.step { return step < 1 ? 2 : 0 }\n",
        "        return (entry.step ?? 1) < 1 ? 2 : 0\n",
        ["I13 decimals(for:): no step default 0.5 → 2, step 0.1 → 2, step 1 default 0.5 → 0, "
         "no step default 3 → 0, no step max 1.5 → 2",
         "I13 six's offset default rewritten to 0.5 (no step): the Offset field reads \"0.50\""]),
    "name-height": (
        "InspectorNameField.swift",
        "        heightAnchor.constraint(equalToConstant: DS.controlHeight).isActive = true\n", "",
        ["I14 the Title InspectorNameField's height constraint is DS.controlHeight, and the "
         "Title row's fittingSize.height equals the Offset row's",
         "I17 the Document tab's marker InspectorNameField has exactly one height constraint "
         "of its own, DS.controlHeight"]),
    "merged-asset-names": (
        "GraphicPane.swift",
        "GraphicSchemaRows.assetNames(for: $0, files: files, clips: clips)",
        "{ entry -> [String] in _ = clips; let held = [storedProps()[entry.key]].compactMap "
        "{ value -> String? in if case .string(let text)? = value { return text }; return nil }; "
        "return files + Set(held).subtracting(files).sorted() }($0)",
        ["I15 … and the signature holds red.png,a.png,b.png"]),
    "no-schema-memo": (
        "GraphicPane.swift", "        schemaMemo = (key, parsed)\n", "",
        ["I16 after two signature reads schemaMemo.key is \"six|<registry revision>\" and "
         "layerMemo holds the clip under document.editedProject; after a rewrite of six the "
         "key names the new revision"]),
    "compile-warnings-dropped": (
        "GraphicPane+Source.swift", "compile: module.compileWarnings", "compile: []",
        ["I18 six rewritten with const logo = asset(\"x\") first: the Source section has a "
         "warning row naming the asset; restored, none (CONTROL)",
         "I20 a six with const logo = asset(\"x\") first and its font sans-serif: the Source "
         "section's notes are [Compiling the module, No errors or warnings at the clip's first "
         "frame], with the asset row between them"]),
    "folder-warnings-dropped": (
        "GraphicPane.swift", "        binding.document?.graphicStore?.scan.warnings ?? []\n",
        "        []\n",
        ["I19 Bad.js in graphics/ and store.rescan(): the Source section holds \"In the "
         "graphics folder\" then a row naming graphics/Bad.js whose button is Reveal, and the "
         "signature changed; removed and rescanned, neither, and the signature is back "
         "(CONTROL)",
         "I20 c Bad.js in graphics/ and six clean (sans-serif): the Source section's notes are "
         "[No errors or warnings at the clip's first frame, In the graphics folder]"]),
    "default-color-hex-only": (
        "GraphicSchemaRows.swift", "let hex = ReelColor.normalise(text)",
        "let hex = Optional(text)",
        ["I21 a defaultColor of \"white\", \"steelblue\" and \"hsl(120, 50%, 50%)\" is "
         "rgba(css:) of #ffffff, #4682b4 and #40bf40",
         "I21 b patchValue of #ffffff, #4682b4 and #40bf40 against those defaults is NSNull; "
         "#000000 against steelblue is the string itself (CONTROL)"]),
    "compile-heading-dropped": (
        "GraphicPane+Source.swift",
        "            rows.append(InspectorNoteLabel { \"Compiling the module\" })\n", "",
        ["I20 a six with const logo = asset(\"x\") first and its font sans-serif: the Source "
         "section's notes are [Compiling the module, No errors or warnings at the clip's first "
         "frame], with the asset row between them",
         "I20 b six rewritten to a syntax error: the Source section's notes are [Compiling the "
         "module]"]),
    "first-frame-note-unconditional": (
        "GraphicPane+Source.swift", "        if report.frame != nil {\n",
        "        if report.frame != nil || true {\n",
        ["I20 b six rewritten to a syntax error: the Source section's notes are [Compiling the "
         "module]"]),
    # Issue batch B87 phase 3 (#239, G-34 (l)). A bare K id names that one row.
    "row-writes-base": (
        "InspectorBinding+Writes.swift",
        "return (base.isEmpty ? nil : base, animated.isEmpty ? nil : animated)",
        "return (values, nil)",
        ["K2", "K3a", "K4", "K5", "K6a", "K6b", "K7", "K9", "K11", "K17"]),
    "count-zero": (
        "ClipPinnedBlock.swift", "case .graphic: return end.graphic?.props.count ?? 0",
        "case .graphic: return 0", ["K3b", "K12"]),
    "null-default-in-end": (
        "InspectorBinding+Writes.swift", "ActionGraphicPatch(props: $0)",
        "ActionGraphicPatch(props: GraphicSchemaRows.patchProps($0, entries: entries)"
        ".mapValues { GraphicSchemaRows.value($0) })",
        ["K9", "K17"]),
    "stored-read": (
        "InspectorPane.swift", "evaluated(clip).graphic ?? ", "", ["K3a", "K4"]),
    "paths-flat": (
        "InspectorMarks.swift", "            if group == \"graphic\" { return graphicPaths(value) }\n",
        "", ["K3a", "K10", "K11", "K13"]),
    "string-continuous": (
        "GraphicSchemaRows.swift", "discrete: true", "discrete: false", ["K6a", "K6b"]),
    "title-fixed-width": (
        "GraphicSchemaRows.swift",
        "            width.priority = NSLayoutConstraint.Priority(249)\n", "", ["K6b"]),
    "asset-to-end": (
        "InspectorBinding+Writes.swift",
        "let assets = Set(entries.filter { $0.type == \"asset\" }.map(\\.key))",
        "let assets = Set<String>()", ["K8", "K17"]),
    "schema-dropped": (
        "ReelOps.swift", "off: off.sorted(), schema: schema)", "off: off.sorted())",
        ["K2", "K5", "K9", "K17"]),
    "end-stale-dropped": (
        "GraphicPane.swift", "binding.selectedAction?.end.graphic?.props ?? [:]", "[:]",
        ["K12"]),
    "layer-keys-unnamed": (
        "InspectorMarks.swift", "paths.append(\"graphic.\" + key)", "_ = key", ["K14"]),
    "band-label-graphic-dropped": (
        "ActionBands.swift",
        "        if let graphic = patch.graphic { keys.append(contentsOf: graphic.props.keys) }\n",
        "", ["K15a"]),
    "zoom-graphic-nil": (
        "ActionBands.swift", "end.graphic?.props.isEmpty ?? true", "end.graphic == nil",
        ["K15b"]),
    "content-continuous": (
        "TextPane.swift", "discrete: true", "discrete: false", ["K16"]),
    "reset-to-base": (
        "GraphicPane.swift", "if binding.selectedAction != nil {", "if false {", ["K17"]),
    "popup-fixed-width": (
        "InspectorRows.swift", "NSLayoutConstraint.Priority(749), for: .horizontal)",
        ".required, for: .horizontal)", ["K18a", "K18b", "K18c"]),
    "checkbox-fixed-width": (
        "InspectorRows.swift", "(popups.isEmpty ? checks : popups)", "popups", ["K18c"]),
    "checkbox-title-unclipped": (
        "InspectorRows.swift",
        "        if narrowing is OptionCheckboxControl { narrowing.clipsToBounds = true }\n",
        "", ["K18c"]),
}


def expected_names(expected, names):
    """`expected` with each bare K id (no space) replaced by the one row whose name starts
    with it; an id no row starts with stays as it is, so it is reported missing."""
    out = []
    for item in expected:
        if " " in item:
            out.append(item)
        else:
            out += [n for n in names if n.startswith(item + " ")] or [item]
    return out

K_IDS = ["K1", "K2", "K3a", "K3b", "K4", "K5", "K6a", "K6b", "K7", "K8", "K9", "K10", "K11",
         "K12", "K13", "K14", "K15a", "K15b", "K16", "K17", "K18a", "K18b", "K18c"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}", flush=True)
    if detail and not ok:
        print("       " + detail, flush=True)
    elif detail:
        print("       " + detail.splitlines()[0][:300], flush=True)


# ---------------------------------------------------------------------------
# The fixture.


HOME_TOOK = []  # H0's fact, from the last fixture's instance
GIA_MADE = []   # the GIA package, when the last fixture made it


def gia_fixture(step, package):
    """GIA (issue batch B87 phase 3): six on a clip at 0 with one action at CLIP and PROJECT
    1–3 s whose end keys a number, a colour, a boolean, an enum and a string. The package,
    or None."""
    p = {"project": str(package)}
    step("new_project", {"path": str(package)})
    step("write_graphic", dict(p, name="six", source=SIX_JS))
    project = (step("get_project", p).get("reply") or {}).get("project") or {}
    track = (project.get("tracks") or [{}])[0].get("id")
    step("add_graphic_clip", dict(p, name="six", track=track, at=0))
    project = (step("get_project", p).get("reply") or {}).get("project") or {}
    clips = [c for c in project.get("clips", [])
             if (c.get("graphic") or {}).get("name") == "six"]
    if not clips:
        return None
    added = step("add_action", dict(p, clip=clips[0]["id"], at=600000, duration=1200000))
    actions = (added.get("reply") or {}).get("new_actions") or []
    if not actions:
        return None
    step("set_action_end", dict(p, clip=clips[0]["id"], action=actions[0], patch={"graphic": {
        "props": {"size": 150, "color": "#2d7ff9", "showBox": False, "align": "center",
                  "title": "Hello"}}}))
    step("save_project", p)
    return package


def fixture(app, work, gia=False):
    """The package over MCP, then the two stale keys injected on disk. The
    package's path, or None and why; the log. The instance runs under the
    scratch home (`CFFIXED_USER_HOME`), launched and stopped by PID."""
    work.mkdir(parents=True, exist_ok=True)
    HOME.mkdir(parents=True, exist_ok=True)
    package = work / "GI.framejob"
    shutil.rmtree(package, ignore_errors=True)
    shutil.rmtree(work / "GIA.framejob", ignore_errors=True)
    GIA_MADE.clear()
    log = work / "framejob.log"
    if log.exists():
        log.unlink()
    launched = mcp.launch(str(app), env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    client = launched.client
    HOME_TOOK.clear()
    try:
        if client is None:
            return None, "the instance did not start", log
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        HOME_TOOK.append((HOME / "Library/Application Support").is_dir())
        if not HOME_TOOK[0]:
            return None, f"the scratch home did not take: no {HOME}/Library/Application Support", log
        steps = []

        def step(tool, arguments):
            got = gp.attempt(client, tool, arguments)
            steps.append(f"{tool} {'ok' if got['ok'] else got['error']}")
            return got

        p = {"project": str(package)}
        step("new_project", {"path": str(package)})
        wrote = step("write_graphic", dict(p, name="six", source=SIX_JS))
        step("import_graphic_asset", dict(p, path=str(RED_PNG)))
        project = (step("get_project", p).get("reply") or {}).get("project") or {}
        track = (project.get("tracks") or [{}])[0].get("id")
        step("add_graphic_clip", dict(p, name="six", track=track, at=0))
        project = (step("get_project", p).get("reply") or {}).get("project") or {}
        clips = [c for c in project.get("clips", [])
                 if (c.get("graphic") or {}).get("name") == "six"]
        if not clips:
            return None, "no clip drawn by six: " + "; ".join(steps), log
        step("set_graphic", dict(p, clips=[clips[0]["id"]], patch={"props": {"size": 90}}))
        step("save_project", p)
        if gia:
            made = gia_fixture(step, work / "GIA.framejob")
            if made is not None:
                GIA_MADE.append(made)
        ok = (wrote.get("reply") or {}).get("ok") is True
        if not ok or any(not s.endswith(" ok") for s in steps):
            return None, "; ".join(steps) + f"; write_graphic reply {wrote}", log
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    path = package / "project.json"
    data = json.loads(path.read_text())
    for clip in data.get("clips", []):
        if (clip.get("graphic") or {}).get("name") == "six":
            clip["graphic"]["props"]["old"] = 1
            clip["graphic"]["props"]["zzz"] = 2
    path.write_text(json.dumps(data, indent=2))
    return package, None, log


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`swift_build.build` over `sources` with the probe as `main.swift`; the
    app's Fonts beside the binary. The binary, or None and the error lines."""
    lib = ROOT / "core/target/release/libframejob_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    binary = out / "graphics-inspector-probe"
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, timeout=900)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or [f"(no error lines; expired {error.expired})"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s", flush=True)
    shutil.rmtree(out / "Fonts", ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Fonts", out / "Fonts")
    return binary, None


def probe_checks(sources, out, package):
    print("\n1 — the probe: I1–I21, K1–K18", flush=True)
    binary, error = build_probe(Path(sources), out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
    copy = out / "GI-probe.framejob"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(package, copy)
    request, answer = out / "request.json", out / "answer.json"
    if answer.exists():
        answer.unlink()
    request.write_text(json.dumps({"package": str(copy)}))
    ran = bounded.run([str(binary), str(request), str(answer)], 300)
    if ran["rc"] != 0 or not answer.exists():
        check("the probe runs", False, (ran["stdout"] + ran["stderr"]).strip()[-600:])
        return
    probe_rows = json.loads(answer.read_text())["rows"]
    ids = [f"I{n}" for n in range(1, 22)] + K_IDS
    missing = [i for i in ids if not any(r["name"].startswith(i + " ") for r in probe_rows)]
    check("the probe answers every row (I1–I21 and K1–K18 present)", not missing,
          f"{len(probe_rows)} rows, missing {missing}")
    for row in probe_rows:
        check(row["name"], row["ok"], row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def harness_checks(package, gia):
    print("\n2 — the harness: the Graphic sub-tab, light and dark, 1440 × 1500", flush=True)
    built = bounded.run([str(HARNESS_BUILD)], 900)
    binary = built["stdout"].strip().splitlines()[-1] if built["rc"] == 0 else None
    renders, error = {}, None if binary else f"build.sh failed: {built['stderr'][-400:]}"
    for tag, look in (("light-a", "light"), ("light-b", "light"), ("dark-a", "dark"),
                      ("dark-b", "dark")):
        if error:
            break
        out = WORK / f"gi-{tag}.png"
        if out.exists():
            out.unlink()
        ran = bounded.run(
            [binary, str(package), str(out), look, str(WIDTH), str(HEIGHT), "0", "0", "1",
             "clip", "-", SECTIONS, "-", "-", "graphic"], 120)
        if ran["rc"] != 0 or not out.exists():
            error = (ran["stdout"] + ran["stderr"]).strip()[-400:] or f"rc {ran['rc']}"
        renders[tag] = out
    if error:
        check("H1 light, rendered twice: byte-identical PNGs", False, error)
        check("H2 dark, rendered twice: byte-identical PNGs, and light ≠ dark", False, error)
        return

    def data(tag):
        return renders[tag].read_bytes()
    check("H1 light, rendered twice: byte-identical PNGs", data("light-a") == data("light-b"),
          str(renders["light-a"].relative_to(ROOT)))
    check("H2 dark, rendered twice: byte-identical PNGs, and light ≠ dark",
          data("dark-a") == data("dark-b") and data("dark-a") != data("light-a"),
          str(renders["dark-a"].relative_to(ROOT)))
    gia_checks(binary, gia)


def gia_checks(binary, gia):
    """H3/H4 (issue batch B87 phase 3): GIA with its action selected, the playhead at 2 s
    inside the span, track size L (the band's label), the Graphic sub-tab."""
    renders, error = {}, None if gia is not None else "the GIA fixture was not made"
    for tag, look in (("light-a", "light"), ("light-b", "light"), ("dark-a", "dark"),
                      ("dark-b", "dark")):
        if error:
            break
        out = WORK / f"gia-{tag}.png"
        if out.exists():
            out.unlink()
        ran = bounded.run(
            [binary, str(gia), str(out), look, str(WIDTH), str(HEIGHT), "0", "2", "2",
             "clip", "-", SECTIONS, "-", "0", "graphic"], 120)
        if ran["rc"] != 0 or not out.exists():
            error = (ran["stdout"] + ran["stderr"]).strip()[-400:] or f"rc {ran['rc']}"
        renders[tag] = out
    if error:
        check("H3 GIA light, its action selected, rendered twice: byte-identical PNGs", False,
              error)
        check("H4 GIA dark, rendered twice: byte-identical PNGs, and light ≠ dark", False, error)
        return

    def data(tag):
        return renders[tag].read_bytes()
    check("H3 GIA light, its action selected, rendered twice: byte-identical PNGs",
          data("light-a") == data("light-b"), str(renders["light-a"].relative_to(ROOT)))
    check("H4 GIA dark, rendered twice: byte-identical PNGs, and light ≠ dark",
          data("dark-a") == data("dark-b") and data("dark-a") != data("light-a"),
          str(renders["dark-a"].relative_to(ROOT)))


# ---------------------------------------------------------------------------


def mutant(app, name):
    began = time.time()
    file, anchor, replacement, expected = MUTANTS[name]
    with tempfile.TemporaryDirectory(prefix=f"framejob-graphics-inspector-{name}-") as temp:
        temp = Path(temp)
        sources = temp / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        path = sources / file
        text = path.read_text()
        if text.count(anchor) != 1:
            print(f"MUTANT FAILURE: {name}'s anchor occurs {text.count(anchor)} times in {file}")
            return 2
        path.write_text(text.replace(anchor, replacement, 1))
        print(f"MUTANT {name}: {file}, anchor replaced once, in {sources}", flush=True)
        package, why, _ = fixture(app, temp / "fixture")
        if package is None:
            print(f"MUTANT FAILURE: the fixture was not made: {why}")
            return 1
        probe_checks(sources, temp / "probe", package)
    failed = [n for n, ok in RESULTS if not ok]
    expected = expected_names(expected, [n for n, _ in RESULTS])
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(expected):
        print(f"MUTANT PASS: {name} — exactly the {len(expected)} expected row(s) "
              f"FAILED in the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {name} — built {built}; missing failures "
          f"{[n for n in expected if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in expected]}, {elapsed:.0f} s")
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    app = Path(args.app)
    if args.mutant:
        return mutant(app, args.mutant)
    print("Road map 10, G5a — the Graphic sub-tab", flush=True)
    print("\n0 — the fixture over MCP", flush=True)
    package, why, log = fixture(app, WORK, gia=True)
    check("H0 the scratch home took: <home>/Library/Application Support is a directory "
          "(CONTROL)", HOME_TOOK == [True], str(HOME / "Library/Application Support"))
    check("the fixture is made over MCP (new_project, write_graphic, import_graphic_asset, "
          "add_graphic_clip, set_graphic, save_project; GIA: add_action, set_action_end)",
          package is not None and bool(GIA_MADE), why or ("" if GIA_MADE else "no GIA"))
    if package is not None:
        probe_checks(ROOT / "app/Sources", WORK / "probe", package)
        harness_checks(package, GIA_MADE[0] if GIA_MADE else None)
    lines = gp.complaints(log)
    check("Z1 grep \"Frame Job: \" over the log prints nothing", not lines,
          "; ".join(lines[:4]))
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
