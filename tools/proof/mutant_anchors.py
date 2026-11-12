#!/usr/bin/env python3
"""#554 — every proof's mutant anchors, counted in the tree. `tools/proof/README.md`'s
"Mutant anchors (mutant_anchors.py)" is the long form.

    python3 tools/proof/mutant_anchors.py              # the check (make test)
    python3 tools/proof/mutant_anchors.py --list       # every table and what was read from it
    python3 tools/proof/mutant_anchors.py --selftest   # the reader over synthetic proofs (make test)
    python3 tools/proof/mutant_anchors.py --mutant count-any|skip-unreadable|pins-one-way|\\
        missing-file-zero|no-entry-check|loose-file-passes|copies-counted|pin-per-anchor

A proof's mutant is an anchor (a piece of source text) and its replacement; its applier demands
that the anchor occurs exactly once in a file of the tree. When the source moves, the anchor rots,
and nothing said so until someone ran the mutant. This reads every `tools/proof/**/*.py` (not
`work/`), finds each mutant table, and counts each anchor in the file it names: exactly once, or
the run fails naming the proof, the table, the mutant, the count and the file.

A proof is READ, never imported: its file is parsed, and a table's expression is evaluated in a
namespace that runs only the top-level statements that bind or add to a name the table needs (a
constant, a helper `def`, a later `T[k] = …` or `T.update(…)`), each at most once, on demand. An
import of a sibling proof is a proxy read the same way; a statement that merely sits at top level
(`proof_app.binary()`, `sys.exit`) never runs. So a table's expression must be pure.

What is a table: a top-level name ending `MUTANTS`, `MUTANT_EDITS`, the pair `MUTANT_FILE` with
`MUTANT_ANCHOR` or `MUTANT_EDITS`, and `MUTANT` bound to a tuple. A name bound by an import is the
other proof's table, and is checked there. An entry's edits are read by three rules: a file
followed by an anchor and a replacement (R1); a file followed by a list of (anchor, replacement)
pairs (R2); and, for a table whose file is implicit in its applier, a row in HINTS (R3). A dict
entry with its own `file` and `anchor` keys is read by those. An edit that is in two tables
(`CLOUD_MUTANTS[name] = …MUTANTS[name]`, `MUTANTS.update(DEEP_MUTANTS)`) is counted once, under
the first table in path and source order: a copy is the same mutant name with the same anchor in
the same file.

Nothing is passed over silently. Each of these fails by name:
- a table that cannot be evaluated (UNREADABLE, with the exception);
- a table no anchor was read from, unless SWITCHES holds it with its exact mutant count;
- a mutant no anchor was read from in a table that has some, unless UNANCHORED names it;
- a source file named in an entry that no rule took as an edit's file (a half-read entry);
- an edit's file that is nowhere, or a bare name found under two folders;
- an anchor that occurs 0 or 2+ times, unless ROTTED holds its mutant with where it is filed
  (a table in EVERY has an applier that replaces every occurrence, so its anchors need one or
  more). ROTTED is decided per MUTANT: a pinned mutant's anchors that still count are counted,
  and only its dead ones are held, so a mutant with one dead edit of two can be pinned;
- another top-level name containing `MUTANT`, unless NOT_TABLES names it (`MUTANT = None`,
  an instrument's own switch, needs no row);
- a proof with the literal `--mutant` and no table, unless NO_TABLE names it;
- a pin that no longer applies, in either direction (a row for a table that now has anchors, a
  count that is off, a ROTTED mutant with no dead anchor counted under that table, a name that
  is gone).

A `--mutant` runs the selftest alone under one of the reader's own switches and must fail exactly
its rows (EXPECTED).
"""

import argparse
import ast
import builtins
import collections
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROOF = "tools/proof"
SELF = "mutant_anchors.py"
SCRATCH = ROOT / PROOF / "work/mutant-anchors-selftest"
TABLE = re.compile(r"^(?:[A-Z0-9]+_)*MUTANTS$|^MUTANT_EDITS$")
SOURCE = re.compile(r"^[\w+./-]+\.(?:swift|rs|metal|ts|js|mjs|h|m|c|py|toml|yml|json|sh|plist"
                    r"|entitlements)$|^(?:[\w+.-]+/)*Makefile$")
# Where a bare file name may live. A name found under two of them is ambiguous, never guessed.
BASES = ("", "app/Sources", "app/Resources/Shaders", "app/Bridging", "app", "core/src",
         "core/include", "core", "graphic/src", "graphic", "mcp-proxy/src", "mcp-proxy",
         "agent/src", "agent", "tools/proof")
MUTATORS = {"update", "append", "extend", "add", "insert", "setdefault", "pop", "remove",
            "discard", "clear"}
EXPECTED = {
    "count-any": {"A3"},
    "skip-unreadable": {"U1", "U3"},
    "pins-one-way": {"P2", "P3", "P4", "P6", "P8", "P10", "P11"},
    "missing-file-zero": {"F1"},
    "no-entry-check": {"E1", "E3"},
    "loose-file-passes": {"E2"},
    "copies-counted": {"C2", "P11"},
    "pin-per-anchor": {"P9", "P10", "P11"},
}
MUTANT = None

# ---------------------------------------------------------------------------
# The pins. Every row is exact: a row that no longer applies fails the run.

# R3: a table whose file is implicit in its applier. proof → table → (file, shape), where shape
# says what an entry is: "pair" (anchor, replacement, …), "anchor" (anchor, …), or "pairs"
# ([(anchor, replacement) or (anchor, replacement, file), …], …). Each row was read off the
# applier named beside it.
HINTS = {
    # `fake_mutant`: FAKE read, `text.count(before) != 1` refused.
    "cloud_captions_probe.py": {"FAKE_MUTANTS": ("tools/proof/assemblyai_fake.py", "pair")},
    # `build_mutant`: `target = copy / "app/Sources/GraphicPrefetch.swift"`.
    "graphics_prefetch_proof.py": {"MUTANTS": ("app/Sources/GraphicPrefetch.swift", "pairs")},
    # `build`: MAIN is `harness/main.swift`, the anchor one whole line of it.
    "harness_playhead_proof.py": {"MUTANTS": ("tools/proof/harness/main.swift", "anchor")},
    # `run_probe`: `shader_text = SHADER.read_text()`, the count refused unless 1.
    "matte_probe.py": {"MUTANTS": ("app/Resources/Shaders/Compositor.metal", "pair")},
    # `mutant_helper`: the scratch agent's `src/main.ts`.
    "spend_proof.py": {"HELPER_MUTANTS": ("agent/src/main.ts", "pair")},
    # `mutant_sources`: `os.path.join(sources, "AssistantSpendMonth.swift")`.
    "spend_ui_proof.py": {"MUTANTS": ("app/Sources/AssistantSpendMonth.swift", "pair")},
    # `build_mutant`: `edit[2] if len(edit) > 2 else RENDERER`, under app/Sources.
    "word_looks_proof.py": {"MUTANTS": ("app/Sources/LayerRenderersWords.swift", "pairs")},
}

# Tables no anchor is read from: switches inside the instrument itself, or mutants with no tree
# text. proof → table → the number of mutants, so one added there fails until the row says so.
SWITCHES = {
    # A launch argument: the app started with clearing off.
    "assistant_clearing_proof.py": {"MUTANTS": 1},
    "bt709_fixture.py": {"MUTANTS": 4},
    # `main` rebinds `budget.BUDGETS` or `budget.anthropic_worst_row` in memory.
    "budget_proof.py": {"MUTANTS": 2},
    # `run` imports one fixture in the other's place.
    "codec_import_proof.py": {"MUTANTS": 2},
    "container_import_proof.py": {"MUTANTS": 1},
    "camera_spike/camera_spike.py": {"MUTANTS": 5},
    "constant_render_spike.py": {"MUTANTS": 3},
    "cursor_spike/cursor_spike.py": {"MUTANTS": 15},
    # `child` rebinds a function of `proof_defaults` or `mcp` in the child process.
    "defaults_proof.py": {"MUTANTS": 4},
    # `MUTANT ==` in the spike's own token strip, classifier and o2 verdict.
    "filler_spike/filler_spike.py": {"MUTANTS": 3},
    # `MUTANT` in the gate's own input classes, fingerprint, stamp rule and warning baseline.
    "gate.py": {"MUTANTS": 4},
    # MUTANT_EDITS edits the spike's own patch text, never a file of the tree.
    "grading_spike/grading_spike.py": {"TREE_MUTANTS": 1, "MUTANTS": 6, "MUTANT_EDITS": 5},
    "grading_verdict.py": {"SIZES_MUTANTS": 1, "MEASURE_MUTANTS": 3},
    "matte_spike/matte_spike.py": {"MUTANTS": 2},
    # `MUTANT` in its own scan: the pin comparison, the untracked walk, the exempt prefixes.
    "name_residue.py": {"MUTANTS": 3},
    # `MUTANT` in `verdict` (a hang decided by the timeout alone) and in `memory_fell` (O5
    # passed by any fall).
    "open_documents_proof.py": {"MUTANTS": 2},
    # `MUTANT` in its own decoder's filter distance (#566).
    "png_read.py": {"MUTANTS": 1},
    # `main` changes the loaded table or the fetched page in memory, after its one network GET.
    "prices_crosscheck.py": {"MUTANTS": 2},
    # `MUTANT` in its own launch-argument read, input filter and two stale markers.
    "proof_app.py": {"MUTANTS": 4},
    "proof_defaults.py": {"MUTANTS": 3},
    "ramp_proof.py": {"MUTANTS": 2},
    "ramp_spike/ramp_spike.py": {"MUTANTS": 5},
    "ramp_spike/render_spike.py": {"MUTANTS": 14},
    "retimed_audio_proof.py": {"MUTANTS": 2},
    # `MUTANT` in its own entry reader, `pin` and the spikes' call scan.
    "spec_rule.py": {"MUTANTS": 7},
}

# Single mutants with no anchor, in a table that has anchors. proof → table → [names].
UNANCHORED = {
    # A switch in P4's `configure`: the three fields left out.
    "assistant_helper_proof.py": {"MUTANTS": ["no-fields"]},
    # Builds nothing: launch A of the built app, K1 last.
    "assistant_session_proof.py": {"MUTANTS": ["key-echo"]},
    # In memory: every cache_read rate doubled; one expected number of the reducer's case.
    "prices_proof.py": {"MUTANTS": ["py-disagrees", "reduce-disagrees"]},
    # Copies `core/` without the vendored tiny-skia patch: a file swap, no text edit.
    "raster_dither_proof.py": {"MUTANTS": ["core-unpatched"]},
}

# A mutant with a known-dead anchor, left for a filed issue. (proof, table, mutant) → where it
# is filed and why it was not re-aimed. The pin is the MUTANT's: its anchors that still count
# once are counted, its dead ones are held, and the row fails ("drop the row") once none of its
# anchors counted under that table is dead. A copy's rot is pinned under the first table, where
# it is counted. A row is for a rot found and not re-aimed in the same change, because a re-aim
# counts only once its mutant has been run and seen caught. Empty since 2026-11-11: the twelve
# rows this check's first run (#554) left were re-aimed and run, or dropped with the decision
# they mutated (#572–#580).
ROTTED = {}

# Tables whose applier replaces EVERY occurrence of an anchor (`anchor in text`, then
# `replace`), so an anchor there must occur at least once. proof → [tables].
EVERY = {
    # `mutant`: `if anchor not in text` refused, then `text.replace(anchor, replacement)`.
    "clip_inspector2_proof.py": ["MUTANT_FILE"],
}

# Other top-level names containing MUTANT: rows, folders, names, flags. proof → [names].
NOT_TABLES = {
    "camera_recording_probe.py": ["MUTANT_SECTION"],
    "clip_inspector3_proof.py": ["MUTANT_GROUPS"],
    "clip_inspector4_proof.py": ["MUTANT_EXPECTED"],
    "clip_inspector5_proof.py": ["MUTANT_EXPECTED"],
    "clip_inspector_proof.py": ["RECLICK_MUTANT"],
    "export_cancel_proof.py": ["MUTANT_WORK"],
    "export_offset_proof.py": ["MUTANT_FIXTURES"],
    "graphic_prop_action_proof.py": ["MUTANT_ROWS"],
    "raster_dither_proof.py": ["MUTANT_DIR"],
    "spend_proof.py": ["MUTANT_ROWS"],
    "transcript_proof.py": ["APP_MUTANT"],
}

# Proofs that take `--mutant` and hold their edits or switches inline in functions, with no
# table to read. Empty since 2026-11-11 (#581): the nineteen proofs it named each hold a
# top-level table now, read above. A row goes here again only for a proof whose mutant cannot
# run without money or a real key, with the issue it is filed under.
NO_TABLE = set()

PINS = {"HINTS": HINTS, "SWITCHES": SWITCHES, "UNANCHORED": UNANCHORED, "ROTTED": ROTTED,
        "EVERY": EVERY, "NOT_TABLES": NOT_TABLES, "NO_TABLE": NO_TABLE}


# ---------------------------------------------------------------------------
# Reading a proof without importing it.


class Unreadable(Exception):
    pass


def touched(statement):
    """The top-level names a statement binds or adds to (nothing inside a def, class, lambda or
    comprehension body counts)."""
    names = []

    def visit(node):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.append(node.name)
            return
        if isinstance(node, (ast.Lambda, ast.ListComp, ast.SetComp, ast.DictComp,
                             ast.GeneratorExp)):
            return
        if isinstance(node, ast.Import):
            names.extend(a.asname or a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom):
            names.extend(a.asname or a.name for a in node.names)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            names.append(node.id)
        elif (isinstance(node, (ast.Subscript, ast.Attribute))
              and isinstance(node.ctx, (ast.Store, ast.Del)) and isinstance(node.value, ast.Name)):
            names.append(node.value.id)
        elif (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
              and isinstance(node.func.value, ast.Name) and node.func.attr in MUTATORS):
            names.append(node.func.value.id)
        for child in ast.iter_child_nodes(node):
            visit(child)

    visit(statement)
    return names


def read_names(statement):
    """The names a top-level statement reads as it runs (a def's or a class's body runs later)."""
    names = []

    def visit(node):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            return
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            names.append(node.id)
        for child in ast.iter_child_nodes(node):
            visit(child)

    visit(statement)
    return list(dict.fromkeys(names))


class Namespace(dict):
    """A proof's globals: a missing name runs the statements that bind it, then answers."""

    def __init__(self, module):
        super().__init__()
        self.module = module

    def __missing__(self, key):
        self.module.ensure(key)
        if not dict.__contains__(self, key):
            raise KeyError(key)
        return dict.__getitem__(self, key)


class Proxy:
    """A sibling proof as an imported module: an attribute is read lazily from its file."""

    def __init__(self, module):
        object.__setattr__(self, "_module", module)

    def __getattr__(self, name):
        try:
            self._module.ensure(name)
            return self._module.env[name]
        except KeyError:
            raise AttributeError(f"{self._module.path.name} binds no top-level {name}") from None


class Module:
    def __init__(self, path, loader):
        self.path, self.loader = path, loader
        self.tree = ast.parse(path.read_text(), str(path))
        self.concern = collections.defaultdict(list)
        for index, statement in enumerate(self.tree.body):
            if isinstance(statement, (ast.Import, ast.ImportFrom)):
                for alias in statement.names:
                    name = alias.asname or (alias.name.split(".")[0]
                                            if isinstance(statement, ast.Import) else alias.name)
                    self.concern[name].append((index, alias))
            else:
                for name in dict.fromkeys(touched(statement)):
                    self.concern[name].append((index, None))
        self.reads = {index: read_names(statement)
                      for index, statement in enumerate(self.tree.body)}
        self.done, self.resolving = set(), set()
        scope = dict(vars(builtins))
        scope["__import__"] = self.imported
        self.env = Namespace(self)
        self.env.update({"__file__": str(path), "__name__": path.stem, "__builtins__": scope})

    def imported(self, name, globals=None, locals=None, fromlist=(), level=0):
        """`__import__` for the proof's code: a sibling proof is a Proxy, never run."""
        sibling = self.loader.sibling(name, self.path) if level == 0 else None
        if sibling is None:
            return builtins.__import__(name, globals, locals, fromlist, level)
        if "." in name and not fromlist:
            raise ImportError(f"import {name}: a dotted sibling import is not read")
        return Proxy(self.loader.module(sibling))

    def ensure(self, name, before=None):
        """Run, in source order and each at most once, the top-level statements that bind or add
        to `name`: all of them, or those above statement `before`. A statement first has the names
        it reads brought up to its own line, so a table holds what its constants were where it is
        written, whatever rebinds them further down."""
        if name not in self.concern or name in self.resolving:
            return
        self.resolving.add(name)
        try:
            for index, alias in self.concern[name]:
                key = (index, alias.name if alias else None)
                if key in self.done or (before is not None and index >= before):
                    continue
                self.done.add(key)
                statement = self.tree.body[index]
                if alias is None:
                    for read in self.reads[index]:
                        self.ensure(read, index)
                    code = compile(ast.Module([statement], type_ignores=[]), str(self.path), "exec")
                    exec(code, self.env)
                elif isinstance(statement, ast.Import):
                    value = self.imported(alias.name, level=0)
                    if alias.asname:
                        for part in alias.name.split(".")[1:]:
                            value = getattr(value, part)
                    self.env[name] = value
                else:
                    module = self.imported(statement.module or "", fromlist=(alias.name,),
                                           level=statement.level)
                    self.env[name] = getattr(module, alias.name)
        finally:
            self.resolving.discard(name)

    def value(self, name):
        try:
            self.ensure(name)
            return self.env[name]
        except KeyboardInterrupt:
            raise
        except BaseException as error:  # noqa: BLE001 — a SystemExit is a reason, too
            raise Unreadable(f"{type(error).__name__}: {error}") from None


class Loader:
    def __init__(self, root):
        self.root, self.proof = root, root / PROOF
        self.modules = {}
        self.files = sorted(
            path for path in self.proof.rglob("*.py")
            if not {"work", "__pycache__"} & set(path.relative_to(self.proof).parts[:-1])
            and path.relative_to(self.proof).as_posix() != SELF)

    def module(self, path):
        if path not in self.modules:
            self.modules[path] = Module(path, self)
        return self.modules[path]

    def sibling(self, name, origin):
        """The proof file an import names: beside the importer, in tools/proof, or the one file
        of that name anywhere under it (a folder a proof adds to `sys.path`)."""
        relative = name.replace(".", "/") + ".py"
        for folder in (origin.parent, self.proof):
            if (folder / relative).is_file():
                return folder / relative
        if name.split(".")[0] in sys.stdlib_module_names:
            return None
        found = [path for path in self.files if path.as_posix().endswith("/" + relative)]
        if len(found) > 1:
            raise ImportError(f"import {name}: {len(found)} files under {PROOF} have that name")
        return found[0] if found else None


# ---------------------------------------------------------------------------
# From a table's value to its edits.


def is_file(value):
    if isinstance(value, Path):
        return True
    return isinstance(value, str) and "\n" not in value and bool(SOURCE.match(value))


def is_pairs(value):
    return (isinstance(value, (list, tuple)) and bool(value)
            and all(isinstance(pair, (list, tuple)) and len(pair) == 2 and isinstance(pair[0], str)
                    and isinstance(pair[1], (str, type(None))) for pair in value))


def edits_of(value, edits, loose):
    """R1 and R2 over an entry: `edits` takes (file, anchor), `loose` a file no rule consumed."""
    if isinstance(value, dict):
        if is_file(value.get("file")) and isinstance(value.get("anchor"), str):
            edits.append((value["file"], value["anchor"]))
            value = {key: item for key, item in value.items()
                     if key not in ("file", "anchor", "replacement")}
        for key, item in value.items():
            edits_of([key, item] if is_file(key) else item, edits, loose)
        return
    if not isinstance(value, (list, tuple)):
        return
    items, index = list(value), 0
    while index < len(items):
        item = items[index]
        after = items[index + 1:index + 3]
        if is_file(item):
            if (len(after) == 2 and isinstance(after[0], str)
                    and isinstance(after[1], (str, type(None)))):
                edits.append((item, after[0]))
                index += 3
                continue
            if after and is_pairs(after[0]):
                edits.extend((item, anchor) for anchor, _ in after[0])
                index += 2
                continue
            loose.append(item)
        elif isinstance(item, (list, tuple, dict)):
            edits_of(item, edits, loose)
        index += 1


def hinted(value, file, shape):
    """R3: an entry of a table whose file is implicit. Answers [(file, anchor)], or None when
    the entry is not the hinted shape."""
    items = list(value) if isinstance(value, (list, tuple)) else [value]
    if shape == "anchor":
        return [(file, items[0])] if items and isinstance(items[0], str) else None
    if shape == "pair":
        if len(items) >= 2 and isinstance(items[0], str) and isinstance(items[1], (str, type(None))):
            return [(file, items[0])]
        return None
    if shape == "pairs":
        rows = items[0] if items else None
        if not isinstance(rows, (list, tuple)) or not rows:
            return None
        out = []
        for row in rows:
            if not (isinstance(row, (list, tuple)) and len(row) in (2, 3)
                    and isinstance(row[0], str) and isinstance(row[1], (str, type(None)))):
                return None
            if len(row) == 3 and not is_file(row[2]):
                return None
            out.append((row[2] if len(row) == 3 else file, row[0]))
        return out
    raise ValueError(f"HINTS: no shape {shape!r}")


def entries(table):
    """[(mutant name, entry value)] of a dict or a sequence."""
    if isinstance(table, dict):
        return [(str(key), value) for key, value in table.items()]
    out = []
    for entry in table:
        if isinstance(entry, str):
            out.append((entry, None))
        elif isinstance(entry, (list, tuple)) and entry and isinstance(entry[0], str):
            out.append((entry[0], entry[1:]))
        elif isinstance(entry, dict) and isinstance(entry.get("name"), str):
            out.append((entry["name"], entry))
        else:
            out.append((repr(entry)[:40], entry))
    return out


def located(root, file):
    """The tree's files a table's file string can mean."""
    text = str(file)
    if Path(text).is_absolute():
        return [Path(text)] if Path(text).is_file() else []
    found = {}
    for base in BASES:
        path = root / base / text
        if path.is_file():
            found[path.resolve()] = path
    return list(found.values())


def first_line(anchor):
    lines = [line.strip() for line in anchor.splitlines() if line.strip()]
    text = lines[0] if lines else anchor.strip()
    return text if len(text) <= 90 else text[:87] + "…"


# ---------------------------------------------------------------------------
# The check.


class Report:
    def __init__(self):
        self.fails, self.rows, self.counts = [], [], collections.Counter()

    def fail(self, kind, where, text):
        self.fails.append((kind, where, text))

    def kinds(self):
        return sorted(kind for kind, _, _ in self.fails)


def tables_of(module):
    """A proof's tables and its other MUTANT names: ([(table name, value thunk)], [other names],
    whether a table name is bound by an import)."""
    assigned, borrowed = {}, False
    for statement in module.tree.body:
        if isinstance(statement, (ast.Import, ast.ImportFrom)):
            borrowed |= any(TABLE.match(alias.asname or alias.name) for alias in statement.names)
            continue
        targets = (statement.targets if isinstance(statement, ast.Assign)
                   else [statement.target] if isinstance(statement, ast.AnnAssign) else [])
        for target in targets:
            for node in ([target] if isinstance(target, ast.Name)
                         else target.elts if isinstance(target, (ast.Tuple, ast.List)) else []):
                if isinstance(node, ast.Name) and "MUTANT" in node.id:
                    assigned.setdefault(node.id, getattr(statement, "value", None))
    tables, others = [], []
    for name, node in assigned.items():
        if TABLE.match(name) and not (name == "MUTANT_EDITS" and "MUTANT_FILE" in assigned):
            tables.append((name, lambda name=name: module.value(name)))
        elif name == "MUTANT_FILE":
            partner = next((p for p in ("MUTANT_EDITS", "MUTANT_ANCHOR") if p in assigned), None)

            def single(partner=partner):
                if partner is None:
                    raise Unreadable("MUTANT_FILE without MUTANT_ANCHOR or MUTANT_EDITS")
                file, other = module.value("MUTANT_FILE"), module.value(partner)
                return {"MUTANT": (file, other, "") if partner == "MUTANT_ANCHOR" else (file, other)}
            tables.append((name, single))
        elif name in ("MUTANT_ANCHOR", "MUTANT_EDITS") and "MUTANT_FILE" in assigned:
            continue
        elif (name == "MUTANT" and isinstance(node, ast.Constant)
              and (node.value is None or node.value is False)):
            continue
        elif name == "MUTANT" and isinstance(node, (ast.Tuple, ast.List, ast.Dict)):
            tables.append((name, lambda: {"MUTANT": module.value("MUTANT")}))
        else:
            others.append(name)
    return tables, others, borrowed


def takes_mutant(module):
    return any(isinstance(node, ast.Constant) and isinstance(node.value, str)
               and re.fullmatch(r"--mutants?(?:[-=]\S*)?", node.value)
               for node in ast.walk(module.tree))


def scan(root, pins):
    """Read every proof under `root` and count every anchor. Answers a Report."""
    report, loader = Report(), Loader(root)
    one_way = MUTANT == "pins-one-way"
    read = []                  # (proof, table, [(mutant, entry)]) in path and source order
    seen_tables, seen_others, no_table = set(), set(), set()
    for path in loader.files:
        proof = path.relative_to(loader.proof).as_posix()
        if "MUTANT" not in path.read_text() and "--mutant" not in path.read_text():
            continue
        try:
            module = loader.module(path)
        except SyntaxError as error:
            report.fail("unreadable", proof, f"{proof}: UNREADABLE, {error}")
            continue
        tables, others, borrowed = tables_of(module)
        for name in others:
            seen_others.add((proof, name))
            if name not in pins["NOT_TABLES"].get(proof, ()):
                report.fail("nottable", proof, f"{proof} {name}: a top-level name containing "
                            "MUTANT that is no table: read it as one, or name it in NOT_TABLES")
        if not tables and not borrowed and takes_mutant(module):
            no_table.add(proof)
            if proof not in pins["NO_TABLE"]:
                report.fail("notable", proof, f"{proof}: takes --mutant and has no mutant table: "
                            "give it one, or name it in NO_TABLE")
        for name, thunk in tables:
            seen_tables.add((proof, name))
            report.counts["tables"] += 1
            try:
                table = thunk()
                if not isinstance(table, (dict, list, tuple)):
                    raise Unreadable(f"a {type(table).__name__}, not a dict or a sequence")
                read.append((proof, name, entries(table)))
            except Unreadable as error:
                if MUTANT != "skip-unreadable":
                    report.fail("unreadable", proof, f"{proof} {name}: UNREADABLE, {error}")
        if tables:
            report.counts["proofs"] += 1

    owners = {}                # (mutant, file, anchor) → the first table that holds it
    for proof, name, rows in read:
        hint = pins["HINTS"].get(proof, {}).get(name)
        switch = pins["SWITCHES"].get(proof, {}).get(name)
        unanchored = set(pins["UNANCHORED"].get(proof, {}).get(name, ()))
        every = name in pins["EVERY"].get(proof, ())
        where = f"{proof} {name}"
        report.counts["mutants"] += len(rows)
        counted, without, copies = 0, [], 0
        for mutant, entry in rows:
            edits, loose = [], []
            if hint:
                found = hinted(entry, *hint)
                if found is None:
                    report.fail("hint", where, f"{where} {mutant}: not the shape HINTS says "
                                f"({hint[1]} in {hint[0]})")
                else:
                    edits = found
            elif entry is not None:
                edits_of(entry if isinstance(entry, (list, tuple, dict)) else [entry], edits, loose)
            if MUTANT != "loose-file-passes":
                for file in loose:
                    if located(root, file):
                        report.fail("loose", where, f"{where} {mutant}: names {file} and no "
                                    "rule read an anchor for it: a half-read entry")
            if not edits:
                without.append(mutant)
            pin = pins["ROTTED"].get((proof, name, mutant))
            per_anchor = MUTANT == "pin-per-anchor"
            sound, dead, unplaced = [], 0, 0
            for file, anchor in edits:
                paths = located(root, file)
                key = (mutant, str(paths[0].resolve()) if len(paths) == 1 else str(file), anchor)
                if owners.setdefault(key, where) != where and MUTANT != "copies-counted":
                    copies += 1
                    continue
                counted += 1
                if not paths:
                    unplaced += 1
                    if MUTANT != "missing-file-zero":
                        report.fail("nofile", where, f"{where} {mutant}: no file {file}")
                    continue
                if len(paths) > 1:
                    unplaced += 1
                    report.fail("ambiguous", where, f"{where} {mutant}: {file} is ambiguous, "
                                + " and ".join(str(p.relative_to(root)) for p in paths))
                    continue
                times = paths[0].read_text(errors="replace").count(anchor) if anchor else 0
                shown = paths[0].relative_to(root) if paths[0].is_relative_to(root) else paths[0]
                good = times >= 1 if MUTANT == "count-any" or every else times == 1
                if good and pin and per_anchor and not one_way:
                    report.fail("pin", where, f"{where} {mutant}: ROTTED names it ({pin}) and "
                                f"its anchor occurs once in {shown}: drop the row")
                elif good:
                    report.counts["anchors"] += 1
                    sound.append(str(shown))
                elif pin:
                    report.counts["rotted"] += 1
                    dead += 1
                else:
                    report.fail("count", where, f"{where} {mutant}: anchor occurs {times} times "
                                f"in {shown}: {first_line(anchor)!r}")
            # The pin is the mutant's: it stands while one anchor counted here is dead. (An edit
            # whose file could not be placed has failed above, and says nothing about the pin.)
            if pin and not dead and not unplaced and not one_way and not per_anchor:
                what = (f"its anchor occurs once in {sound[0]}" if len(sound) == 1
                        else f"its {len(sound)} anchors each occur once" if sound
                        else "no anchor of it is counted under this table")
                report.fail("pin", where, f"{where} {mutant}: ROTTED names it ({pin}) and "
                            f"{what}: drop the row")
        report.rows.append((proof, name, len(rows), counted + copies, len(without), copies))
        report.counts["copies"] += copies
        if switch is not None:
            report.counts["switch tables"] += 1
            report.counts["switch mutants"] += len(rows)
            if counted and not one_way:
                report.fail("pin", where, f"{where}: SWITCHES names it and {counted} anchors "
                            "were read from it: drop the row")
            elif switch != len(rows) and not one_way:
                report.fail("pin", where, f"{where}: SWITCHES says {switch} mutants and it has "
                            f"{len(rows)}: a mutant with tree text needs its file and anchor in "
                            "the table; otherwise correct the count")
            continue
        if rows and len(without) == len(rows):
            if MUTANT != "no-entry-check":
                report.fail("noedit", where, f"{where}: no anchor read from any of its "
                            f"{len(rows)} mutants: teach the reader its shape (HINTS), or pin it "
                            "in SWITCHES with its count")
            continue
        for mutant in without:
            if mutant in unanchored:
                report.counts["unanchored"] += 1
            elif MUTANT != "no-entry-check":
                report.fail("noedit", where, f"{where} {mutant}: no anchor read: give the entry "
                            "its file and anchor, or name it in UNANCHORED")
        if not one_way:
            for mutant in sorted(unanchored - set(without)):
                report.fail("pin", where, f"{where} {mutant}: UNANCHORED names it and it is "
                            "not a mutant without an anchor there: drop the row")

    report.counts["no-table proofs"] = len(no_table)
    if not one_way:
        stale = [(pin, f"{p} {t}") for pin in ("HINTS", "EVERY")
                 for p, ts in pins[pin].items() for t in ts if (p, t) not in seen_tables]
        stale += [("SWITCHES", f"{p} {t}") for p, ts in pins["SWITCHES"].items() for t in ts
                  if (p, t) not in seen_tables]
        stale += [("UNANCHORED", f"{p} {t}") for p, ts in pins["UNANCHORED"].items() for t in ts
                  if (p, t) not in seen_tables]
        stale += [("NOT_TABLES", f"{p} {n}") for p, ns in pins["NOT_TABLES"].items() for n in ns
                  if (p, n) not in seen_others]
        stale += [("NO_TABLE", p) for p in sorted(pins["NO_TABLE"] - no_table)]
        known = {(p, t, m) for p, t, rows in read for m, _ in rows}
        stale += [("ROTTED", " ".join(key)) for key in pins["ROTTED"] if key not in known]
        for pin, what in stale:
            report.fail("pin", what, f"{what}: {pin} names it and it is not there: drop the row")
    return report


def summary(report):
    c = report.counts
    return (f"{c['proofs']} proofs, {c['tables']} tables, {c['mutants']} mutants: "
            f"{c['anchors']} anchors occur exactly once; {c['switch tables']} switch tables "
            f"({c['switch mutants']} mutants), {c['unanchored']} mutants without an anchor, "
            f"{c['copies']} copies counted under their first table, {c['rotted']} anchors pinned "
            f"as rotted, {c['no-table proofs']} proofs with --mutant and no table")


def check(listing=False):
    report = scan(ROOT, PINS)
    if listing:
        for proof, name, mutants, anchors, without, copies in report.rows:
            print(f"  {proof} {name}: {mutants} mutants, {anchors} anchors read, "
                  f"{without} without, {copies} copies")
    print(f"mutant anchors: {summary(report)}")
    for _, _, text in report.fails:
        print(f"FAIL {text}")
    print("PASS" if not report.fails else f"{len(report.fails)} failures")
    return 1 if report.fails else 0


# ---------------------------------------------------------------------------
# The selftest: the reader over synthetic proofs and sources in scratch trees.

SOURCE_A = ("let a = 1\nlet b = 1\nlet c = 1\nlet d = 1\nlet e = 1\nlet f = 1\nlet g = 1\n"
            "let h = 1\nlet i = 1\nlet j = 1\nlet k = 1\nabab\nfrom the sibling\nshared text\n"
            "twice\ntwice\nwhole line\n")
SHAPES = '''
import sys
from pathlib import Path
import helper_lib as hl
from helper_lib import SHARED
ROOT = Path(__file__).resolve().parents[2]
FILE = "A.swift"
BINARY = open(ROOT / "ran.marker", "w")
open(ROOT / "ran.marker", "w")
sys.exit("a statement that merely sits at top level")


def twice(text):
    return text + text


MUTANTS = {
    "r1": ("A.swift", "let a = 1\\n", "let a = 2\\n", ["R1"]),
    "r1-nested": (["R1"], [(FILE, "let b = 1\\n", None)]),
    "r1-path": (ROOT / "app/Sources/A.swift", "let c = 1\\n", ""),
    "r2": ("A.swift", [("let d = 1\\n", ""), ("let e = 1\\n", None)], {"R2"}),
    "keys": {"file": "core/src/lib.rs", "anchor": "fn one()", "replacement": "", "rows": ["K"]},
    "helper": ("A.swift", twice("ab") + "\\n", ""),
    "sibling": ("A.swift", hl.ANCHOR, ""),
    "shared": ("A.swift", SHARED, ""),
    "no-text": (None, None, "K1"),
    "rotted": ("A.swift", "this line left the tree\\n", ""),
}
FILE = {"rebound": "further down"}
MUTANTS["later"] = ("A.swift", "let f = 1\\n", "")
MUTANTS.update({"updated": ("A.swift", "let g = 1\\n", "")})
for _name in ("looped",):
    MUTANTS[_name] = ("A.swift", "let h = 1\\n", "")
MUTANT = None
MUTANT_ROWS = ["R1", "R2"]
'''
HELPER_LIB = '''
ANCHOR = "from the sibling\\n"
SHARED = "shared text\\n"
raise SystemExit("the sibling was run, not read")
'''
OTHERS = {
    "pair_proof.py": 'MUTANTS = {"p": ("let i = 1\\n", "let i = 2\\n", ["P1"])}\n',
    "anchor_proof.py": 'MUTANTS: dict = {"a": ("whole line", {"P1"})}\n',
    "pairs_proof.py": ('MUTANTS = {"q": ([("let j = 1\\n", ""), ("fn two()", "", "lib.rs")], "Q1")}\n'),
    "single_proof.py": 'MUTANT_FILE = "A.swift"\nMUTANT_ANCHOR = "let k = 1\\n"\n',
    "every_proof.py": 'MUTANT_FILE = "A.swift"\nMUTANT_EDITS = [("twice\\n", "")]\n',
    "tuple_proof.py": 'MUTANT = ("core/src/lib.rs", "fn three()", "", "T1")\n',
    "switch_proof.py": 'MUTANTS = ("guard-dropped", "tags-unchecked")\nMUTANT = None\n',
    "inline_proof.py": 'import argparse\nP = argparse.ArgumentParser()\nP.add_argument("--mutant")\n',
    "borrower_proof.py": ('import argparse\nfrom shapes_proof import MUTANTS\n'
                          'P = argparse.ArgumentParser()\nP.add_argument("--mutant")\n'),
    "copy_proof.py": ('from shapes_proof import MUTANTS as BASE\n'
                      'APP_MUTANTS = {"r1": ("app/Sources/A.swift",) + BASE["r1"][1:]}\n'),
}
CONTROL_PINS = {
    "HINTS": {"pair_proof.py": {"MUTANTS": ("app/Sources/A.swift", "pair")},
              "anchor_proof.py": {"MUTANTS": ("app/Sources/A.swift", "anchor")},
              "pairs_proof.py": {"MUTANTS": ("app/Sources/A.swift", "pairs")}},
    "SWITCHES": {"switch_proof.py": {"MUTANTS": 2}},
    "UNANCHORED": {"shapes_proof.py": {"MUTANTS": ["no-text"]}},
    "ROTTED": {("shapes_proof.py", "MUTANTS", "rotted"): "#0"},
    "EVERY": {"every_proof.py": ["MUTANT_FILE"]},
    "NOT_TABLES": {"shapes_proof.py": ["MUTANT_ROWS"]},
    "NO_TABLE": {"inline_proof.py"},
}


def selftest(mutant=None):
    global MUTANT
    MUTANT, results = mutant, []
    shutil.rmtree(SCRATCH, ignore_errors=True)

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    def tree(name, proofs, sources=None):
        root = SCRATCH / name
        files = {f"{PROOF}/{path}": text for path, text in proofs.items()}
        files.update(sources if sources is not None else {"app/Sources/A.swift": SOURCE_A})
        for path, text in files.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text)
        return root

    def pins(**rows):
        return {**{key: type(value)() for key, value in PINS.items()}, **rows}

    def one(name, text, sources=None, **rows):
        """One proof, `p_proof.py`, in a tree of its own. Answers its Report."""
        return scan(tree(name, {"p_proof.py": text}, sources), pins(**rows))

    def said(report, kinds, *words):
        return report.kinds() == sorted(kinds) and all(
            any(word in text for _, _, text in report.fails) for word in words)

    def shown(report):
        return f"{report.kinds()} {[text for _, _, text in report.fails][:2]}"

    control = {"app/Sources/A.swift": SOURCE_A,
               "core/src/lib.rs": "fn one() {}\nfn two() {}\nfn three() {}\n"}
    root = tree("K0", {"shapes_proof.py": SHAPES, "helper_lib.py": HELPER_LIB, **OTHERS}, control)
    report = scan(root, CONTROL_PINS)
    c = report.counts
    row("K0", not report.fails and c["tables"] == 9 and c["mutants"] == 22
        and c["anchors"] + c["copies"] == 20 and c["switch tables"] == 1 and c["unanchored"] == 1
        and c["rotted"] == 1 and c["no-table proofs"] == 1,
        "CONTROL: R1 flat, nested, by Path and with None; R2; a dict's own keys; a constant "
        "rebound further down; a helper def; a sibling's constants; T[k] =, T.update and a "
        "top-level for; the three hinted shapes; MUTANT_FILE with MUTANT_ANCHOR and with "
        f"MUTANT_EDITS (EVERY); a MUTANT tuple; and one row of every pin: {dict(c)} "
        f"{shown(report)}")
    row("U2", not (root / "ran.marker").exists(),
        "CONTROL: `BINARY = open(…)`, a bare `open(…)`, `sys.exit(…)` and the sibling's own "
        "`raise SystemExit` sit at top level and never ran: no marker file")
    row("C1", ("borrower_proof.py", "MUTANTS") not in {(p, t) for p, t, *_ in report.rows}
        and not any("borrower_proof" in text for _, _, text in report.fails),
        "CONTROL: a table name bound by `from shapes_proof import MUTANTS` is no table of the "
        "importer, and the importer, which takes --mutant, is not a proof without a table")

    good = 'MUTANTS = {"m": ("A.swift", "let a = 1\\n", "")}\n'
    report = one("A1", 'MUTANTS = {"m": ("A.swift", "let a = 9\\n", "")}\n')
    row("A1", said(report, ["count"], "p_proof.py MUTANTS m: anchor occurs 0 times in "
                   "app/Sources/A.swift: 'let a = 9'"),
        f"an anchor that is nowhere fails, named: {shown(report)}")
    before = one("A2", good)
    (SCRATCH / "A2/app/Sources/A.swift").write_text(SOURCE_A.replace("let a = 1", "let a = 1 // x"))
    report = scan(SCRATCH / "A2", pins())
    row("A2", not before.fails and said(report, ["count"], "occurs 0 times"),
        f"the same table passes, then fails once its SOURCE line moves: {shown(report)}")
    report = one("A3", 'MUTANTS = {"m": ("A.swift", "twice\\n", "")}\n')
    row("A3", said(report, ["count"], "occurs 2 times"),
        f"an anchor that occurs twice fails: {shown(report)}")
    report = one("F1", 'MUTANTS = {"m": ("Gone.swift", "let a = 1\\n", "")}\n')
    row("F1", said(report, ["nofile"], "no file Gone.swift"),
        f"an edit whose file is nowhere fails: {shown(report)}")
    report = one("F2", 'MUTANTS = {"m": ("lib.rs", "fn one()", "")}\n',
                 {"core/src/lib.rs": "fn one() {}\n", "graphic/src/lib.rs": "fn one() {}\n"})
    row("F2", said(report, ["ambiguous"], "core/src/lib.rs and graphic/src/lib.rs"),
        f"a bare name found under two folders fails, never guessed: {shown(report)}")
    report = one("U1", 'MUTANTS = {"m": ("A.swift", UNDEFINED, "")}\n')
    row("U1", said(report, ["unreadable"], "p_proof.py MUTANTS: UNREADABLE, NameError"),
        f"a table that needs a name nothing binds is UNREADABLE, by name: {shown(report)}")
    report = one("U3", 'MUTANTS = "a, b"\n')
    row("U3", said(report, ["unreadable"], "a str, not a dict or a sequence"),
        f"a table that is no dict or sequence is UNREADABLE: {shown(report)}")
    report = one("E1", 'MUTANTS = {"m": ("A.swift", "let a = 1\\n", ""), "bare": (["R1"], 3)}\n')
    row("E1", said(report, ["noedit"], "p_proof.py MUTANTS bare: no anchor read"),
        f"a mutant with no anchor and no UNANCHORED row fails: {shown(report)}")
    report = one("E3", 'MUTANTS = ["one", "two"]\n')
    row("E3", said(report, ["noedit"], "no anchor read from any of its 2 mutants"),
        f"a table with no anchor and no SWITCHES row fails: {shown(report)}")
    report = one("E2", 'MUTANTS = {"m": ("A.swift", "let a = 1\\n", "", "B.swift", "let z = 1\\n")}\n',
                 {"app/Sources/A.swift": SOURCE_A, "app/Sources/B.swift": "let z = 1\n"})
    row("E2", said(report, ["loose"], "names B.swift and no rule read an anchor for it"),
        f"a half-read entry (one edit taken, a second file left) fails: {shown(report)}")
    report = one("H1", 'MUTANTS = {"m": (["R1"], "let a = 1\\n")}\n',
                 HINTS={"p_proof.py": {"MUTANTS": ("app/Sources/A.swift", "pair")}})
    row("H1", "hint" in report.kinds() and said(report, report.kinds(), "not the shape HINTS says"),
        f"an entry that is not its hinted shape fails: {shown(report)}")
    report = one("P2", 'MUTANTS = ["one", "two", "three"]\n',
                 SWITCHES={"p_proof.py": {"MUTANTS": 2}})
    row("P2", said(report, ["pin"], "SWITCHES says 2 mutants and it has 3"),
        f"a SWITCHES count off by one fails: {shown(report)}")
    report = one("P3", good, ROTTED={("p_proof.py", "MUTANTS", "m"): "#0"})
    row("P3", said(report, ["pin"], "ROTTED names it (#0) and its anchor occurs once"),
        f"a ROTTED row whose anchor is back fails: {shown(report)}")
    report = one("P4", good, UNANCHORED={"p_proof.py": {"MUTANTS": ["m"]}})
    row("P4", said(report, ["pin"], "UNANCHORED names it"),
        f"an UNANCHORED row for a mutant that has an anchor fails: {shown(report)}")
    report = one("P5", good + "MUTANT_NOTES = {}\n")
    row("P5", said(report, ["nottable"], "p_proof.py MUTANT_NOTES"),
        f"a new top-level MUTANT name with no NOT_TABLES row fails: {shown(report)}")
    report = one("P6", good, NO_TABLE={"p_proof.py"})
    row("P6", said(report, ["pin"], "p_proof.py: NO_TABLE names it and it is not there"),
        f"a NO_TABLE row for a proof that has a table fails: {shown(report)}")
    report = one("P7", 'import sys\nif "--mutant" in sys.argv:\n    pass\n')
    row("P7", said(report, ["notable"], "p_proof.py: takes --mutant and has no mutant table"),
        f"a proof with --mutant, no table and no NO_TABLE row fails: {shown(report)}")
    report = one("P8", good, SWITCHES={"p_proof.py": {"MUTANTS": 1}})
    row("P8", said(report, ["pin"], "SWITCHES names it and 1 anchors were read"),
        f"a SWITCHES row for a table that has anchors fails: {shown(report)}")
    half = ('MUTANTS = {"m": (["R1"], [("A.swift", "let a = 1\\n", ""), '
            '("A.swift", "let gone = 1\\n", "")])}\n')
    rotted = {("p_proof.py", "MUTANTS", "m"): "#0"}
    bare, report = one("P9a", half), one("P9", half, ROTTED=rotted)
    row("P9", said(bare, ["count"], "p_proof.py MUTANTS m: anchor occurs 0 times")
        and not report.fails and report.counts["anchors"] == 1 and report.counts["rotted"] == 1,
        "a mutant with two edits, one dead: unpinned it fails for the dead one alone; with its "
        f"ROTTED row the good anchor is counted and the dead one held: {shown(bare)}; pinned "
        f"{shown(report)}, {report.counts['anchors']} counted, {report.counts['rotted']} rotted")
    report = one("P10", 'MUTANTS = {"m": (["R1"], [("A.swift", "let a = 1\\n", ""), '
                 '("A.swift", "let b = 1\\n", "")])}\n', ROTTED=rotted)
    row("P10", said(report, ["pin"], "ROTTED names it (#0) and its 2 anchors each occur once"),
        f"a ROTTED row for a mutant whose two anchors are both back fails, once: {shown(report)}")
    dead = '"m": ("A.swift", "let a = 9\\n", "")'
    root = tree("C2", {"a_probe.py": "MUTANTS = {" + dead + "}\n",
                       "b_proof.py": ("from a_probe import MUTANTS\nAPP_MUTANTS = {}\n"
                                      "for _name in ('m',):\n"
                                      "    _file, _old, _new = MUTANTS[_name]\n"
                                      "    APP_MUTANTS[_name] = ('app/Sources/' + _file, _old, "
                                      "_new)\n")})
    report = scan(root, pins())
    row("C2", said(report, ["count"], "a_probe.py MUTANTS m") and report.counts["copies"] == 1,
        f"a dead anchor copied into a second table is reported once, under the first: "
        f"{shown(report)}, copies {report.counts['copies']}")
    report = scan(root, pins(ROTTED={("a_probe.py", "MUTANTS", "m"): "#0",
                                     ("b_proof.py", "APP_MUTANTS", "m"): "#1"}))
    row("P11", said(report, ["pin"], "b_proof.py APP_MUTANTS m: ROTTED names it (#1) and no "
                    "anchor of it is counted under this table") and report.counts["rotted"] == 1,
        "a copy's rot is pinned under the first table: the first table's row holds it, and a "
        f"row for the copy holds nothing and fails: {shown(report)}, rotted "
        f"{report.counts['rotted']}")

    shutil.rmtree(SCRATCH, ignore_errors=True)
    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    ok = failed == EXPECTED[mutant] if mutant else not failed
    print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
          f"{sorted(EXPECTED[mutant])}" if mutant else "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    args = parser.parse_args()
    sys.exit(selftest(args.mutant) if args.selftest or args.mutant else check(args.list))
