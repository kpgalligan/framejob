#!/usr/bin/env python3
"""Issue batch B83 (#238) — the proofs and the owner's `UserDefaults`: what a
session moved, by key NAME, and the removal of the proofs' own domains.

    python3 tools/proof/proof_defaults.py              # --selftest, then --sweep
    python3 tools/proof/proof_defaults.py --selftest
    python3 tools/proof/proof_defaults.py --list       # removes nothing
    python3 tools/proof/proof_defaults.py --sweep
    python3 tools/proof/proof_defaults.py --ran NAME   # with --list or a sweep; repeatable
    python3 tools/proof/proof_defaults.py --mutant no-unlink|no-refusal|no-busy

No environment moves `UserDefaults` (the proof README's B83 section has the
measurements): a probe compiled from app/Sources writes a domain named for
its executable into the owner's real `~/Library/Preferences/`, and the app
writes `com.kgalligan.Reelcut`. This file is the two halves of what is done
about it, and it imports nothing from `tools/proof`.

**What a session moved.** `snapshot(domain)` runs `defaults export <domain>
-` and nothing else, and answers each key's name against a digest salted per
process, so a value is never held, printed or written. `moved` names the
keys added, removed or changed between two snapshots, `owner_visible` drops
AppKit's own (`NS*`, `Apple*`), and `sharing_pids` lists the running
`…/Contents/MacOS/Reelcut` that share a domain. `mcp.py`'s guard is built
from these; `defaults_proof.py` is its proof. `APP_DOMAIN` is only ever read.
Every `defaults` this file runs — these reads, the removal recipe's delete
and the selftest's write — runs WITHOUT `CFFIXED_USER_HOME` (`read_env`):
under that variable `defaults export` answers the same domain while the
folder it names exists and NO key while it does not (measured, the proof
README's B84 section), so a read that followed it would compare a scratch
home not made yet, or already removed, against the owner's whole domain, and
a delete that followed an absent one would do nothing while its read-back
looked elsewhere.

**The removal recipe.** `remove_domain(name)`: `defaults delete <name>` (0
and 1 are both answers), THEN unlinking `<Preferences>/<name>.plist`. It
works only after the process that wrote the domain has exited; either half
alone leaves a file or brings it back. `refusal(name)` is asked first and
names every class that is never acted on: the empty name, a name `defaults`
reads as an option or a path (`-g`, `a/b`, a leading `.`), the global
domain, the product's own names (`reelcut`, `reelcut-agent`, `reelcut-mcp`,
`com.kgalligan.Reelcut` in any case, its capital-R namespace, and a name
that extends it without a dot, `com.kgalligan.Reelcut-Dev`), Apple's, and
any name containing `rasterize`. A call that reaches the real
Preferences folder asks `refusal`'s rule a second time under no mutant, and
a scratch folder with no stand-in runner raises, so a scratch call cannot
reach the real daemon.

**Ownership.** A plist in Preferences with no `refusal` is a proof's own by
the first rule that holds: `executable` (a Mach-O of that name with an exec
bit under `tools/proof/work`; the walk skips `*.app`, `*.dSYM`,
`node_modules`, `.git`, `Intermediates.noindex`, `target` and symlinks),
`source` (the stem of a `*_probe.swift` under `tools/proof`), `prefix` (the
name starts `com.kgalligan.reelcut.` or `reelcut.`, case-sensitive), `keys`
(at least one key, every one starting `Reelcut`). `unattributed` is what no
rule owns and still looks like a proof's: a name matching
`probe|harness|refute|spike`, or a `Reelcut*` key. No script removes those.

**The sweep.** Per owned name, `busy` is read immediately before acting
(the plist is under `BUSY_MINUTES` old, a process of that basename is
running, or one's bundle identifier is the name): it is left and reported.
Else, when every key is in `FAMILIES` (or there is none), `remove_domain`.
Else the domain is `shared` with something else's keys: `defaults delete
<name> <key>` for its `Reelcut*` keys only, and the file is never unlinked.
A returned reason is reported under `denied` and never worked around. The
busy gate cannot see a write `cfprefsd` has not flushed from a process that
already exited into a plist older than `BUSY_MINUTES`. `make test` names the
two probes it runs (`--ran assistant_lane_probe --ran
assistant_prompt_probe`): for a named probe whose plist holds only
`NS*`/`Apple*` keys the sweep does not ask the plist's age, there being no
key of a probe's own to read back; a running process of that name is still
`busy`. A probe added to `make test` and not named stays `busy` and is
printed. `--list --ran NAME` prints what that sweep would do.

**The selftest.** P1 and P2 are real, on a throwaway domain
`reelcut.proof-defaults-selftest.<pid>` made with `defaults write`: P1 its
plist exists (the control), P2 `remove_domain` answers None and the file and
the domain are absent at once and 6 s later. P3–P9 run over scratch
`preferences`, `work` and `sources` folders under `$TMPDIR` with a RECORDING
runner, so no `defaults` is executed (a Mach-O is a copy of
`/usr/bin/true`). Each refused name a file can bear has a plist and a Mach-O
in a folder of its own beside the row's control, and "untouched" is:
`refusal` answers, `remove_domain` leaves the recorder empty and the plist's
bytes the same, and `owned_domains`, `unattributed` and `sweep` never name
it, while the control IS removed.

- **P3** the app's: `com.kgalligan.Reelcut`, `com.kgalligan.reelcut`,
  `COM.KGALLIGAN.REELCUT`, `com.kgalligan.Reelcut.helper`,
  `com.kgalligan.Reelcut-Dev`, `com.kgalligan.ReelcutHelper`; control
  `com.kgalligan.reelcut.x` (`prefix`).
- **P4** global: `-g`, `-globalDomain`, `-app`, `NSGlobalDomain`, `Apple
  Global Domain`, `.GlobalPreferences`, the empty name, `a/b`; control `g`
  (`executable`).
- **P5** Rasterize: `com.kgalligan.rasterize.jobs-probe`,
  `com.kgalligan.Rasterize`, `rasterize-probe`; control `raster-probe`.
- **P5s** shared: an `executable`-owned plist holding `ReelcutA` and
  `toolOptions.x` is `shared`, the recorder holds only `defaults delete
  <name> ReelcutA` and the file is kept; the same name holding `ReelcutA`
  and `NSB` is removed whole.
- **P6** helpers: `reelcut-agent`, `reelcut-mcp`, `Reelcut`; control
  `reelcut-agent-probe`.
- **P7** one name per rule (the `prefix` one
  `reelcut.proof-defaults-selftest.12345`), and an `NS`-only `x-probe` owned
  by none and in `unattributed`.
- **P8** busy: an owned plist written now, and one (owned by `keys`) named
  for a running `/bin/sleep`, are `busy` with the recorder empty, and so is
  a fresh `NS`-only `ran-probe`; with all three named in `ran`, `ran-probe`
  alone is removed (the first holds `ReelcutA`, the second is running); the
  first with its mtime two hours back is removed. The sleeper is `/bin/sleep`
  started through a symlink of that name, whose path is what `ps` prints: a
  COPY of `/bin/sleep` is killed at exec on macOS 26 (exit 137, measured).
- **P9** a scratch `preferences` with no runner raises `ValueError`.

`--mutant NAME` runs the selftest alone (never the sweep) and prints `MUTANT
PASS` when exactly its rows fail: `no-unlink` P2 (the unlink is skipped in
the real Preferences folder; over a scratch folder the unlink is the whole
removal, there being no daemon, so the mutant stays out of those rows),
`no-refusal` P3–P6 and not P5s (`refusal` answers None; the real folder
still asks the rule itself), `no-busy` P8 (`busy` answers None). Exit 1 on
a failed row only: a `busy` or `denied` name is reported, not failed.
"""

import argparse
import hashlib
import os
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

APP_DOMAIN = "com.kgalligan.Reelcut"
HARMLESS = ("NS", "Apple")                       # AppKit's key-name families
FAMILIES = ("Reelcut", "RC", "NS", "Apple")      # what a probe compiled from app/Sources writes
BUSY_MINUTES = 60

HERE = os.path.dirname(os.path.abspath(__file__))
# The account's own home, not `$HOME`: `cfprefsd` does not follow the variable.
REAL_PREFERENCES = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, "Library", "Preferences")
WORK = os.path.join(HERE, "work")
SOURCES = HERE
SELFTEST_PREFIX = "reelcut.proof-defaults-selftest."
PREFIXES = ("com.kgalligan.reelcut.", "reelcut.")
UNATTRIBUTED_NAME = re.compile(r"probe|harness|refute|spike")
SKIP_DIRS = ("node_modules", ".git", "Intermediates.noindex", "target")
SKIP_SUFFIXES = (".app", ".dSYM")
MACHO_MAGICS = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe",
                b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
MUTANTS = ("no-unlink", "no-refusal", "no-busy")
EXPECTED = {"no-unlink": {"P2"}, "no-refusal": {"P3", "P4", "P5", "P6"}, "no-busy": {"P8"}}
MUTANT = None

_SALT = os.urandom(16)


# ---- what a session moved --------------------------------------------------------

def read_env():
    """The environment every `defaults` of this file runs in (a read, the
    recipe's delete, the selftest's write): this process's without
    `CFFIXED_USER_HOME`, so two reads of one domain answer the same thing
    whether or not the folder that variable names exists at either, and a
    delete acts on the domain its read-back reads. What the guard answers
    for is the owner's domain, the one read without the variable: an
    instance under a scratch home that exists writes it (#238), and a write
    that lands anywhere else moves nothing of the owner's."""
    env = dict(os.environ)
    env.pop("CFFIXED_USER_HOME", None)
    return env


def _export(domain, run=None):
    """`defaults export <domain> -` as a dict ({} for no such domain), or
    None when it could not be run or read. Runs in `read_env()`."""
    if not domain or domain.startswith("-"):
        return None
    try:
        done = (run or subprocess.run)(["defaults", "export", domain, "-"],
                                       capture_output=True, timeout=30, env=read_env())
        if done.returncode != 0:
            return None
        loaded = plistlib.loads(done.stdout)
    except Exception:  # an unreadable answer is None, never a raise
        return None
    return loaded if isinstance(loaded, dict) else None


def snapshot(domain=APP_DOMAIN):
    """key -> sha256(per-process salt + the value's plist bytes); {} for no
    such domain; None on failure. `defaults export <domain> -` ONLY."""
    loaded = _export(domain)
    if loaded is None:
        return None
    digests = {}
    try:
        for key, value in loaded.items():
            body = plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=True)
            digests[str(key)] = hashlib.sha256(_SALT + body).hexdigest()
    except Exception:
        return None
    return digests


def moved(before, after):
    """Sorted names added, removed or changed; [] if either is None."""
    if before is None or after is None:
        return []
    return sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key))


def owner_visible(names):
    """The names starting with no `HARMLESS` prefix."""
    return [name for name in names if not name.startswith(HARMLESS)]


def bundle_domain(binary):
    """`CFBundleIdentifier` of `<binary>/../../Info.plist`, else None."""
    try:
        contents = os.path.dirname(os.path.dirname(os.path.abspath(str(binary))))
        with open(os.path.join(contents, "Info.plist"), "rb") as handle:
            identifier = plistlib.load(handle).get("CFBundleIdentifier")
    except Exception:
        return None
    return identifier if isinstance(identifier, str) and identifier else None


def _processes():
    """[(pid, executable path)] of `ps -axo pid=,comm=`; None when it could
    not be run or read."""
    try:
        listed = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True,
                                timeout=30)
    except Exception:
        return None
    if listed.returncode != 0:
        return None
    found = []
    for line in listed.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            found.append((int(parts[0]), parts[1]))
    return found


def sharing_pids(domain):
    """The running `*/Contents/MacOS/Reelcut` whose `bundle_domain` is
    `domain` or None, sorted."""
    found = []
    for pid, path in _processes() or []:
        if path.endswith("/Contents/MacOS/Reelcut"):
            identifier = bundle_domain(path)
            if identifier is None or identifier == domain:
                found.append(pid)
    return sorted(found)


# ---- the removal recipe ----------------------------------------------------------

def _refusal(name):
    if not isinstance(name, str) or not name:
        return "the empty name is no domain"
    if "/" in name:
        return f"{name!r} holds a /: `defaults` reads it as a path"
    if name.startswith("."):
        return f"{name!r} starts with a dot: a hidden or global preferences file"
    if name.startswith("-"):
        return f"{name!r} starts with -: `defaults` reads it as an option"
    lower = name.lower()
    if lower in ("nsglobaldomain", "apple global domain"):
        return f"{name!r} is the global domain"
    if lower in ("reelcut", "reelcut-agent", "reelcut-mcp"):
        return f"{name!r} is one of the product's own executables"
    if lower.startswith("com.apple."):
        return f"{name!r} is Apple's"
    if "rasterize" in lower:
        return f"{name!r} is Rasterize's"
    if lower.startswith("com.kgalligan.reelcut") and not name.startswith(
            "com.kgalligan.reelcut."):
        return f"{name!r} is the app's own domain or in its namespace"
    return None


def refusal(name):
    """Why `name` is never acted on, or None."""
    if MUTANT == "no-refusal":
        return None
    return _refusal(name)


def _is_real(preferences):
    return os.path.realpath(preferences) == os.path.realpath(REAL_PREFERENCES)


def _gate(name, preferences, run):
    """(the folder, whether it is the real one, the reason nothing may run)."""
    preferences = REAL_PREFERENCES if preferences is None else os.fspath(preferences)
    real = _is_real(preferences)
    if not real and run is None:
        raise ValueError(f"{preferences} is not the real Preferences folder and no runner was "
                         "given: a scratch call may not reach the real daemon")
    reason = refusal(name)
    if reason is None and real:
        reason = _refusal(name)      # the real folder never takes a mutant's word
    return preferences, real, reason


def _plist_path(preferences, name):
    return os.path.join(preferences, name + ".plist")


def remove_domain(name, preferences=None, run=None):
    """`defaults delete <name>`, then the plist unlinked. None when no file
    and no domain remain, else the reason."""
    preferences, real, reason = _gate(name, preferences, run)
    if reason:
        return reason
    runner = run or subprocess.run
    try:
        done = runner(["defaults", "delete", name], capture_output=True, timeout=30,
                      env=read_env())
    except subprocess.TimeoutExpired:
        return f"`defaults delete {name}` ran past 30 s"
    except OSError as error:
        return f"`defaults delete {name}` could not run: {error}"
    if done.returncode not in (0, 1):
        return f"`defaults delete {name}` exited {done.returncode}"
    path = _plist_path(preferences, name)
    if not (MUTANT == "no-unlink" and real):
        try:
            if os.path.lexists(path):
                os.unlink(path)
        except OSError as error:
            return f"{path} could not be unlinked: {error}"
    if os.path.lexists(path):
        return f"{path} is still there"
    left = _export(name, run)
    if left is None:
        return f"`defaults export {name} -` did not answer"
    if left:
        return f"the domain {name} still holds {len(left)} keys"
    return None


def _delete_key(name, key, preferences, run):
    """`defaults delete <name> <key>`: None, or the reason."""
    preferences, _real, reason = _gate(name, preferences, run)
    if reason:
        return reason
    try:
        done = (run or subprocess.run)(["defaults", "delete", name, key], capture_output=True,
                                       timeout=30, env=read_env())
    except subprocess.TimeoutExpired:
        return f"`defaults delete {name} {key}` ran past 30 s"
    except OSError as error:
        return f"`defaults delete {name} {key}` could not run: {error}"
    if done.returncode != 0:
        return f"`defaults delete {name} {key}` exited {done.returncode}"
    return None


def busy(name, preferences=None, now=None, ran=()):
    """Why `name` may be in use right now, or None. `ran` names the probes
    the caller itself ran and saw exit: for one of those whose plist holds
    only `HARMLESS` keys (or none) the plist's age is not asked, there being
    no key of a probe's own for anyone to read back. A running process is
    asked either way."""
    if MUTANT == "no-busy":
        return None
    preferences = REAL_PREFERENCES if preferences is None else os.fspath(preferences)
    now = time.time() if now is None else now
    held = _keys(preferences, name) if name in ran else None
    waived = held is not None and all(key.startswith(HARMLESS) for key in held)
    try:
        age = now - os.path.getmtime(_plist_path(preferences, name))
    except OSError:
        age = None
    if not waived and age is not None and age < BUSY_MINUTES * 60:
        return f"its plist changed {max(0, int(age // 60))} min ago (under {BUSY_MINUTES})"
    running = _processes()
    if running is None:
        return "`ps` did not answer, so a running process of that name cannot be ruled out"
    for pid, path in running:
        if os.path.basename(path) == name:
            return f"a process named {name} is running (pid {pid})"
        if "/Contents/MacOS/" in path and bundle_domain(path) == name:
            return f"pid {pid}'s bundle identifier is {name}"
    return None


# ---- ownership -------------------------------------------------------------------

def _plists(preferences):
    """The names of the regular `*.plist` files in `preferences`, sorted."""
    try:
        entries = sorted(os.listdir(preferences))
    except OSError:
        return []
    names = []
    for entry in entries:
        path = os.path.join(preferences, entry)
        if entry.endswith(".plist") and os.path.isfile(path) and not os.path.islink(path):
            names.append(entry[:-len(".plist")])
    return names


def _keys(preferences, name):
    """The plist's key names, or None when it cannot be read as a dict."""
    try:
        with open(_plist_path(preferences, name), "rb") as handle:
            loaded = plistlib.load(handle)
    except Exception:
        return None
    return sorted(str(key) for key in loaded) if isinstance(loaded, dict) else None


def _walk(top, skip=()):
    """Every regular file under `top` as (name, path), skipping `SKIP_DIRS`,
    `SKIP_SUFFIXES`, symlinks and the directories in `skip`."""
    skip = {os.path.realpath(one) for one in skip}
    stack = [top]
    while stack:
        here = stack.pop()
        try:
            entries = list(os.scandir(here))
        except OSError:
            continue
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir(follow_symlinks=False):
                    if entry.name in SKIP_DIRS or entry.name.endswith(SKIP_SUFFIXES):
                        continue
                    if skip and os.path.realpath(entry.path) in skip:
                        continue
                    stack.append(entry.path)
                elif entry.is_file(follow_symlinks=False):
                    yield entry.name, entry.path
            except OSError:
                continue


def _is_macho(path):
    try:
        if not os.stat(path).st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            return False
        with open(path, "rb") as handle:
            return handle.read(4) in MACHO_MAGICS
    except OSError:
        return False


def executables(work=None, wanted=None):
    """The names of the Mach-O files with an exec bit under `work`; only
    those in `wanted` when it is given."""
    work = WORK if work is None else os.fspath(work)
    found = set()
    for name, path in _walk(work):
        if name in found or (wanted is not None and name not in wanted):
            continue
        if _is_macho(path):
            found.add(name)
    return found


def probe_stems(sources=None, work=None):
    """The stems of the `*_probe.swift` under `sources` (not under `work`)."""
    sources = SOURCES if sources is None else os.fspath(sources)
    work = WORK if work is None else os.fspath(work)
    return {name[:-len(".swift")] for name, _path in _walk(sources, skip=(work,))
            if name.endswith("_probe.swift")}


def _survey(preferences=None, work=None, sources=None):
    """(owned [(name, rule)], unattributed [name]) in one pass."""
    preferences = REAL_PREFERENCES if preferences is None else os.fspath(preferences)
    names = [name for name in _plists(preferences) if refusal(name) is None]
    runnable = executables(work, wanted=set(names))
    stems = probe_stems(sources, work)
    owned, loose = [], []
    for name in names:
        keys = _keys(preferences, name)
        if name in runnable:
            owned.append((name, "executable"))
        elif name in stems:
            owned.append((name, "source"))
        elif name.startswith(PREFIXES):
            owned.append((name, "prefix"))
        elif keys and all(key.startswith("Reelcut") for key in keys):
            owned.append((name, "keys"))
        elif UNATTRIBUTED_NAME.search(name) or any(
                key.startswith("Reelcut") for key in keys or []):
            loose.append(name)
    return owned, loose


def owned_domains(preferences=None, work=None, sources=None):
    """[(name, rule)]: the plists a proof wrote, by the first rule that holds."""
    return _survey(preferences, work, sources)[0]


def unattributed(preferences=None, work=None, sources=None):
    """The plists no rule owns that still look like a proof's: never removed."""
    return _survey(preferences, work, sources)[1]


def families(keys):
    """`Reelcut:2,NS:1` for a list of key names."""
    if keys is None:
        return "(unreadable)"
    if not keys:
        return "(no key)"
    counts = {}
    for key in keys:
        family = next((one for one in FAMILIES if key.startswith(one)), "other")
        counts[family] = counts.get(family, 0) + 1
    return ",".join(f"{one}:{counts[one]}" for one in FAMILIES + ("other",) if one in counts)


def plan(name, preferences=None, now=None, ran=()):
    """What the sweep would do with an owned `name` now: (`busy`, reason),
    (`denied`, reason), (`remove`, None) or (`shared`, its `Reelcut*` keys)."""
    preferences = REAL_PREFERENCES if preferences is None else os.fspath(preferences)
    reason = busy(name, preferences, now, ran)
    if reason:
        return "busy", reason
    keys = _keys(preferences, name)
    if keys is None:
        return "denied", "its plist could not be read"
    if all(key.startswith(FAMILIES) for key in keys):
        return "remove", None
    return "shared", [key for key in keys if key.startswith("Reelcut")]


def sweep(preferences=None, work=None, sources=None, run=None, now=None, ran=()):
    """Removes the proofs' own idle domains. {"removed": [name], "shared":
    [(name, [keys])], "busy": [(name, reason)], "denied": [(name, reason)]}
    `ran` is `busy`'s: the probes the caller ran and saw exit."""
    result = {"removed": [], "shared": [], "busy": [], "denied": []}
    for name, _rule in owned_domains(preferences, work, sources):
        action, detail = plan(name, preferences, now, ran)
        if action in ("busy", "denied"):
            result[action].append((name, detail))
        elif action == "remove":
            reason = remove_domain(name, preferences, run)
            if reason:
                result["denied"].append((name, reason))
            else:
                result["removed"].append(name)
        else:
            deleted = []
            for key in detail:
                reason = _delete_key(name, key, preferences, run)
                if reason:
                    result["denied"].append((name, reason))
                else:
                    deleted.append(key)
            result["shared"].append((name, deleted))
    return result


# ---- the selftest ----------------------------------------------------------------

EMPTY_PLIST = plistlib.dumps({})


class Recorder:
    """A stand-in for `subprocess.run` that executes nothing."""

    def __init__(self):
        self.calls = []

    def __call__(self, argv, **_options):
        self.calls.append(list(argv))
        return subprocess.CompletedProcess(argv, 0, stdout=EMPTY_PLIST, stderr=b"")


class Case:
    """One scratch `preferences`, `work` and `sources`."""

    def __init__(self, root, label):
        self.root = os.path.join(root, label)
        self.preferences = os.path.join(self.root, "preferences")
        self.work = os.path.join(self.root, "work")
        self.sources = os.path.join(self.root, "sources")
        for folder in (self.preferences, self.work, self.sources):
            os.makedirs(folder)

    def plist(self, name, keys, hours_old=2):
        path = _plist_path(self.preferences, name)
        with open(path, "wb") as handle:
            plistlib.dump({key: True for key in keys}, handle)
        if hours_old:
            then = time.time() - hours_old * 3600
            os.utime(path, (then, then))
        return path

    def macho(self, name, original="/usr/bin/true"):
        path = os.path.join(self.work, name)
        shutil.copyfile(original, path)
        os.chmod(path, 0o755)
        return path

    def folders(self):
        return self.preferences, self.work, self.sources


def _read(path):
    with open(path, "rb") as handle:
        return handle.read()


def _named(result):
    names = set(result["removed"])
    for key in ("shared", "busy", "denied"):
        names |= {name for name, _detail in result[key]}
    return names


def _untouched(root, label, name, control, control_rule):
    """The problems with `name` being left alone while `control` is removed."""
    problems = []
    case = Case(root, label)
    bears_plist = "/" not in name
    bears_macho = bool(name) and "/" not in name
    path = case.plist(name, ["ReelcutA"]) if bears_plist else None
    if bears_macho:
        case.macho(name)
    control_path = case.plist(control, ["ReelcutA", "NSB"])
    if control_rule == "executable":
        case.macho(control)
    before = _read(path) if path else None

    if refusal(name) is None:
        problems.append("refusal answers None")
    recorder = Recorder()
    if remove_domain(name, case.preferences, recorder) is None:
        problems.append("remove_domain answers None")
    if recorder.calls:
        problems.append(f"remove_domain ran {recorder.calls}")
    owned = owned_domains(*case.folders())
    if any(one == name for one, _rule in owned):
        problems.append("owned_domains names it")
    if (control, control_rule) not in owned:
        problems.append(f"the control is not owned by {control_rule}: {owned}")
    if name in unattributed(*case.folders()):
        problems.append("unattributed names it")
    recorder = Recorder()
    result = sweep(*case.folders(), run=recorder)
    if name in _named(result):
        problems.append("sweep names it")
    if result["removed"] != [control] or os.path.lexists(control_path):
        problems.append(f"the control was not removed: {result}")
    wanted = [["defaults", "delete", control], ["defaults", "export", control, "-"]]
    if recorder.calls != wanted:
        problems.append(f"sweep ran {recorder.calls}")
    if path and (not os.path.lexists(path) or _read(path) != before):
        problems.append("its plist changed")
    return problems


def _refused_row(root, row, names, control, control_rule):
    failed = []
    for index, name in enumerate(names):
        problems = _untouched(root, f"{row}-{index}", name, control, control_rule)
        if problems:
            failed.append(f"{name!r}: " + ", ".join(problems))
    detail = (f"{len(names)} names untouched ({', '.join(repr(n) for n in names)}); control "
              f"{control!r} ({control_rule}) removed beside each")
    return not failed, detail if not failed else "; ".join(failed)


def _real_cleanup(name):
    """The recipe under no mutant, for the selftest's own domain only."""
    if not name.startswith(SELFTEST_PREFIX) or _refusal(name):
        return
    try:
        subprocess.run(["defaults", "delete", name], capture_output=True, timeout=30,
                       env=read_env())
        path = _plist_path(REAL_PREFERENCES, name)
        if os.path.lexists(path):
            os.unlink(path)
    except (OSError, subprocess.TimeoutExpired):
        pass


def selftest():
    """The rows that failed, as a set of ids."""
    results = []

    def row(row_id, ok, detail):
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ") + f"{row_id} {detail}", flush=True)

    def guarded(row_id, body):
        try:
            ok, detail = body()
        except Exception as error:  # an instrument that cannot run is a FAIL
            ok, detail = False, f"raised {type(error).__name__}: {error}"
        row(row_id, ok, detail)

    # P1, P2 — real, on a throwaway domain.
    name = f"{SELFTEST_PREFIX}{os.getpid()}"
    path = _plist_path(REAL_PREFERENCES, name)
    try:
        def p1():
            wrote = subprocess.run(["defaults", "write", name, "ReelcutSelftest", "-bool", "true"],
                                   capture_output=True, timeout=30, env=read_env())
            deadline = time.monotonic() + 10
            while not os.path.exists(path) and time.monotonic() < deadline:
                time.sleep(0.1)
            return wrote.returncode == 0 and os.path.exists(path), (
                f"CONTROL: `defaults write {name}` exited {wrote.returncode}; its plist exists "
                f"{os.path.exists(path)}")

        def p2():
            answer = remove_domain(name)
            at_once = (os.path.lexists(path), _export(name))
            time.sleep(6)
            later = (os.path.lexists(path), _export(name))
            ok = answer is None and at_once == (False, {}) and later == (False, {})
            return ok, (f"remove_domain answered {answer!r}; file there, keys in the domain: at "
                        f"once {_shape(at_once)}, 6 s later {_shape(later)}")

        guarded("P1", p1)
        guarded("P2", p2)
    finally:
        _real_cleanup(name)

    root = tempfile.mkdtemp(prefix="rc-proof-defaults-")
    sleeper = None
    try:
        guarded("P3", lambda: _refused_row(
            root, "P3", ["com.kgalligan.Reelcut", "com.kgalligan.reelcut", "COM.KGALLIGAN.REELCUT",
                         "com.kgalligan.Reelcut.helper", "com.kgalligan.Reelcut-Dev",
                         "com.kgalligan.ReelcutHelper"], "com.kgalligan.reelcut.x", "prefix"))
        guarded("P4", lambda: _refused_row(
            root, "P4", ["-g", "-globalDomain", "-app", "NSGlobalDomain", "Apple Global Domain",
                         ".GlobalPreferences", "", "a/b"], "g", "executable"))
        guarded("P5", lambda: _refused_row(
            root, "P5", ["com.kgalligan.rasterize.jobs-probe", "com.kgalligan.Rasterize",
                         "rasterize-probe"], "raster-probe", "executable"))

        def p5s():
            problems = []
            case = Case(root, "P5s-shared")
            kept = case.plist("shared-probe", ["ReelcutA", "toolOptions.x"])
            case.macho("shared-probe")
            before = _read(kept)
            recorder = Recorder()
            result = sweep(*case.folders(), run=recorder)
            if result != {"removed": [], "shared": [("shared-probe", ["ReelcutA"])], "busy": [],
                          "denied": []}:
                problems.append(f"sweep answered {result}")
            if recorder.calls != [["defaults", "delete", "shared-probe", "ReelcutA"]]:
                problems.append(f"sweep ran {recorder.calls}")
            if not os.path.lexists(kept) or _read(kept) != before:
                problems.append("the shared plist changed")
            case = Case(root, "P5s-whole")
            gone = case.plist("shared-probe", ["ReelcutA", "NSB"])
            case.macho("shared-probe")
            result = sweep(*case.folders(), run=Recorder())
            if result["removed"] != ["shared-probe"] or os.path.lexists(gone):
                problems.append(f"the control (ReelcutA + NSB) was not removed whole: {result}")
            return not problems, ("; ".join(problems) if problems else
                                  "ReelcutA + toolOptions.x: shared, only `defaults delete "
                                  "shared-probe ReelcutA` recorded, the file kept; CONTROL: "
                                  "ReelcutA + NSB removed whole")

        guarded("P5s", p5s)
        guarded("P6", lambda: _refused_row(
            root, "P6", ["reelcut-agent", "reelcut-mcp", "Reelcut"], "reelcut-agent-probe",
            "executable"))

        def p7():
            case = Case(root, "P7")
            case.plist("e-probe", ["NSA"])
            case.macho("e-probe")
            case.plist("s_probe", ["NSA"])
            with open(os.path.join(case.sources, "s_probe.swift"), "w") as handle:
                handle.write("// a probe's source\n")
            case.plist(f"{SELFTEST_PREFIX}12345", ["NSA"])
            case.plist("k", ["ReelcutA", "ReelcutB"])
            case.plist("x-probe", ["NSA"])
            owned = owned_domains(*case.folders())
            loose = unattributed(*case.folders())
            wanted = [("e-probe", "executable"), ("k", "keys"),
                      (f"{SELFTEST_PREFIX}12345", "prefix"), ("s_probe", "source")]
            ok = owned == wanted and loose == ["x-probe"]
            return ok, f"owned {owned}; unattributed {loose}"

        guarded("P7", p7)

        def p8():
            nonlocal sleeper
            problems = []
            case = Case(root, "P8")
            fresh = case.plist("busy-probe", ["ReelcutA"], hours_old=0)
            case.macho("busy-probe")
            taken = case.plist("ran-probe", ["NSA"], hours_old=0)
            case.macho("ran-probe")
            running = f"rc-pd-sleep-{os.getpid()}"
            old = case.plist(running, ["ReelcutA"])
            link = os.path.join(case.root, running)
            os.symlink("/bin/sleep", link)
            sleeper = subprocess.Popen([link, "60"], stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
            if sleeper.poll() is not None:
                problems.append(f"the sleeper exited {sleeper.returncode} at once")
            recorder = Recorder()
            result = sweep(*case.folders(), run=recorder)
            reasons = dict(result["busy"])
            if sorted(reasons) != ["busy-probe", "ran-probe", running] or result["removed"]:
                problems.append(f"sweep answered {result}")
            if recorder.calls:
                problems.append(f"sweep ran {recorder.calls}")
            if not (os.path.lexists(fresh) and os.path.lexists(old) and os.path.lexists(taken)):
                problems.append("a busy plist is gone")
            recorder = Recorder()
            result = sweep(*case.folders(), run=recorder,
                           ran=("busy-probe", "ran-probe", running))
            if (result["removed"] != ["ran-probe"] or os.path.lexists(taken)
                    or sorted(name for name, _why in result["busy"]) != ["busy-probe", running]
                    or recorder.calls != [["defaults", "delete", "ran-probe"],
                                          ["defaults", "export", "ran-probe", "-"]]):
                problems.append(f"with all three named in `ran`, sweep answered {result} and "
                                f"ran {recorder.calls}")
            then = time.time() - 2 * 3600
            if os.path.lexists(fresh):
                os.utime(fresh, (then, then))
            result = sweep(*case.folders(), run=Recorder())
            if result["removed"] != ["busy-probe"] or [n for n, _r in result["busy"]] != [running]:
                problems.append(f"CONTROL: with its mtime two hours back, sweep answered {result}")
            return not problems, ("; ".join(problems) if problems else
                                  f"busy-probe: {reasons.get('busy-probe')}; the running "
                                  f"/bin/sleep of its name: {reasons.get(running)}; nothing "
                                  "recorded; ran-probe (NS only, named in `ran`) is removed "
                                  "while fresh; busy-probe named in `ran` stays busy for its "
                                  "ReelcutA; CONTROL: busy-probe two hours old is removed")

        guarded("P8", p8)

        def p9():
            case = Case(root, "P9")
            kept = case.plist("nine-probe", ["ReelcutA"])
            case.macho("nine-probe")
            before = _read(kept)
            raised = []
            for call in (lambda: remove_domain("nine-probe", case.preferences),
                         lambda: sweep(*case.folders())):
                try:
                    call()
                    raised.append(None)
                except ValueError:
                    raised.append("ValueError")
            ok = raised == ["ValueError", "ValueError"] and _read(kept) == before
            return ok, (f"remove_domain and sweep over a scratch folder with no runner: {raised}; "
                        f"the plist's bytes the same {_read(kept) == before}")

        guarded("P9", p9)
    finally:
        if sleeper is not None:
            sleeper.kill()
            sleeper.wait()
        shutil.rmtree(root, ignore_errors=True)

    failed = {row_id for row_id, ok in results if not ok}
    print(f"passed {len(results) - len(failed)}/{len(results)}")
    return failed


def _shape(pair):
    there, keys = pair
    return f"({there}, {'no answer' if keys is None else len(keys)})"


# ---- the command line ------------------------------------------------------------

def print_list(ran=()):
    owned, loose = _survey()
    print(f"owned: {len(owned)}")
    for name, rule in owned:
        action, detail = plan(name, ran=ran)
        if action == "shared":
            does = "shared: " + (", ".join(detail) if detail else "no Reelcut* key left")
        elif action == "remove":
            does = "remove"
        else:
            does = f"{action}: {detail}"
        print(f"  {name}  [{rule}]  {families(_keys(REAL_PREFERENCES, name))}  -> {does}")
    print(f"unattributed (no script removes these): {len(loose)}")
    for name in loose:
        print(f"  {name}")


def print_sweep(ran=()):
    result = sweep(ran=ran)
    print(f"sweep: removed {len(result['removed'])}, shared {len(result['shared'])}, "
          f"busy {len(result['busy'])}, denied {len(result['denied'])}")
    for name in result["removed"]:
        print(f"  removed {name}")
    for name, keys in result["shared"]:
        print(f"  shared {name}: " + (", ".join(keys) + " deleted" if keys
                                      else "no Reelcut* key to delete"))
    for name, reason in result["busy"]:
        print(f"  busy {name}: {reason}")
    for name, reason in result["denied"]:
        print(f"  denied {name}: {reason}")


def main(argv=None):
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true", help="P1–P9")
    parser.add_argument("--list", action="store_true",
                        help="the owned names and what the sweep would do; removes nothing")
    parser.add_argument("--sweep", action="store_true",
                        help="remove the proofs' own idle domains")
    parser.add_argument("--ran", action="append", default=[], metavar="NAME",
                        help="a probe the caller ran and saw exit: its AppKit-only plist is "
                             "not held back for its age")
    parser.add_argument("--mutant", choices=MUTANTS)
    arguments = parser.parse_args(argv)
    if arguments.mutant:
        MUTANT = arguments.mutant
        failed = selftest()
        expected = EXPECTED[arguments.mutant]
        verdict = "MUTANT PASS" if failed == expected else "MUTANT FAIL"
        print(f"{verdict}: {arguments.mutant} failed {sorted(failed)}, expected "
              f"{sorted(expected)}")
        return 0 if failed == expected else 1
    everything = not (arguments.selftest or arguments.list or arguments.sweep)
    if arguments.selftest or everything:
        if selftest():
            return 1
    if arguments.list:
        print_list(tuple(arguments.ran))
    if arguments.sweep or everything:
        print_sweep(tuple(arguments.ran))
    return 0


if __name__ == "__main__":
    sys.exit(main())
