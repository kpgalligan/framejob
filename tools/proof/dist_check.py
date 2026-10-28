#!/usr/bin/env python3
"""Road map 11 V0, road map 12 A4, #145, road map 14 MC3, build velocity, Sparkle, codec export and the acknowledgements — the binary check `make dist` runs.

The Distribution configuration is Release without the Swift condition
`FRAMEJOB_DEV_TOOLS` (spec §11 V-1), so its binary must hold none of the dev
tools' code. This reads each app's `Contents/MacOS/Frame Job` in process, as
bytes, and looks for ONE needle: the `devToolsMarker` literal declared in
`app/Sources/AgentServer+DevTools.swift`, read out of that file at every run.

    python3 tools/proof/dist_check.py [--release APP] [--dist APP]

**Why a marker and not the tool names.** Swift string literals of 15 UTF-8
bytes or fewer are stored inline in the code of an `-O` binary, not as
contiguous bytes (road map 11 measured a Release binary that still held two
names road map 14's MC4 has since deleted: `RC_AGENT_PORT`, 13 bytes, found 0
times, and `AgentServerEnabled`, 18, once; `unsaved_changes`, 15, 0 times), so
a short tool name could never be found in either build and an absence check
on it would pass for nothing. The marker is at least 16 bytes, and the flag-on
`devTools()` logs it, which keeps the literal live in the optimised binary.

**The helper (road map 12 A4).** Both bundles carry the assistant helper,
`Contents/Helpers/framejob-agent`, which `agent/build.sh helper` copies in and
signs `--options runtime` with `agent/entitlements.plist` before Xcode signs
the app. Without `com.apple.security.cs.allow-jit` under the hardened runtime
the helper dies at launch; with more, it holds a right it does not need. The
rows check `runtime` in the CodeDirectory flags, not `adhoc`, so a Developer
ID signature passes too. `codesign -dv` writes its display to stderr, so the
flags are read there; the entitlements are read from stdout.

**The app's entitlements (#145).** Distribution is the build that ships
(spec §11 V-1), and notarization refuses `get-task-allow`, which Xcode
injects unless `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` is off (`project.yml`
turns it off for Distribution alone). D14 reads the Distribution app's
signature through its executable, `realpath`ed so a skeleton's symlink reads
the real app, and wants exactly `com.apple.security.device.audio-input` and
`com.apple.security.device.camera` (the camera's since camera-recording CR1a,
spec §11 CAM-3).

**Release's signature and both seals (issue batch B88).** A no-op build once
left the Release app signed ad hoc by Write Agent Catalog alone: no
entitlements (no microphone) and a seal broken by the catalog written after
it, which nothing here read, because D14 reads Distribution's alone. D25
reads the Release app's entitlements the same way and wants exactly what
Xcode's own CodeSign gives it, the Distribution set plus the
`com.apple.security.get-task-allow` Xcode injects outside Distribution (the
processed `Frame Job.app.xcent` of a Release build holds those three): an
exact set, so a build signed with anything but Xcode's processed entitlements —
a missing `get-task-allow` as much as a missing microphone or camera — fails,
and a
no-op build cannot ship a different signature from a linking one. D26 / D27
run `codesign --verify --deep --strict` over each app, the bundle being the
one its executable `realpath`s into (so a skeleton reads the real app, as
D14 does).

**The MCP proxy and its snapshot (road map 14 MC3).** Both bundles carry
`Contents/Helpers/framejob-mcp`, which `project.yml`'s "Build MCP Proxy"
phase copies in and signs `--options runtime` with NO entitlements (a plain
Rust binary needs none), and `Contents/Resources/agent-catalog.json`, which
the "Write Agent Catalog" phase writes by running the just-built app with
`-RCWriteCatalog`: `{version, tools}`, the version the bundle's own
`CFBundleShortVersionString`. Release's snapshot is the positive control for
Distribution's: it must name every key of the seam's flag-on `devHandlers`
table, read out of `AgentServer+DevTools.swift` at every run, and
Distribution's must name none.

**The updater (spec §11 PUB-6..PUB-9).** Sparkle.framework is embedded in
every configuration (xcodegen links a package per target) and loaded only in
Distribution: only Distribution compiles `AppDelegate+Updates.swift`
(`FRAMEJOB_UPDATER`) and holds a feed and an EdDSA public key, and Release
links with `-dead_strip_dylibs`, so its binary has no Sparkle load command
(loaded, dyld refuses the ad-hoc framework under library validation and the
app does not launch, PUB-7). D28 wants the Distribution
framework present and its binary signed by the app binary's team (library
validation under the hardened runtime refuses a framework of another team;
an ad-hoc build reads `not set` on both); D29 wants every other Mach-O under
it — Autoupdate, Updater.app, the two XPC services, found by magic — signed
with the hardened runtime and verifying strictly. D30 wants Distribution's
`SUFeedURL` to be the `RC_SPARKLE_FEED_URL` its configuration sets in
`project.yml` (an `https://` URL), D31 its `SUPublicEDKey` to be strict
base64 of exactly 32 bytes (an Ed25519 public key): until the owner's key
lands it is empty and D31 fails, by the owner's choice (PUB-8). D32 wants
both keys empty in Release, D34 the Release binary without the updater's
class name, and D33 is that row's positive control: the Distribution binary
holds `SPUStandardUpdaterController`. D35 wants no `Sparkle.framework`
path among the Release binary's load commands (`otool -L`).

**The bundled encoders (road map "codec-export" C0, spec §11 CX-4, CX-5).** SVT-AV1
and libvpx are linked statically into every configuration from `build/codecs/`
(`tools/codecs/build_codecs.py`), and their licence and patent texts are copied
into `Contents/Resources/Licenses/<library>/` (project.yml's "Copy Codec
Licences"). D36 / D37 read each executable's symbol table (`nm -j`) for one
entry point of each encoder; D38 / D39 want every load command (`otool -L`)
under `/usr/lib/` or `/System/Library/`, or an `@rpath/Sparkle.framework/` path
(whose presence in Release stays D35's), so no codec dylib, nor any other
non-system library, is ever loaded; D40 / D41 want every licence text the pins
name (`build_codecs.PINS`) in each bundle, byte-identical to
`build/codecs/licenses/`. `codec_strings()` is published_check's P22 (spec §11 PUB-11),
not a row here: each encoder's own string literal (CODEC_STRINGS) in the binary's bytes,
which survive the `strip` an `xcodebuild archive` applies and D37's symbol table does
not. Both literals were confirmed with `grep -c -a -F` in the built Release binary and
in `build/codecs/lib/`'s archives (`SVT-AV1 Encoder Lib %s`, the library's version
banner; `WebM Project VP9 Encoder v1.17.0`, libvpx's interface name).

**The acknowledgements (#376, spec §11 PUB-10).** Every configuration carries
`Contents/Resources/Acknowledgements.txt`, written by `tools/licenses/acknowledgements.py`.
D42 / D43 read it with readers of their own — this script never imports the generator,
so the check is not the generator agreeing with itself: `shipped_crates()` runs `cargo
metadata --format-version 1 --locked --offline --filter-platform aarch64-apple-darwin` in
`core/` and `mcp-proxy/` and walks every non-dev edge from the root, Frame Job's own
crates left out; `shipped_npm()` reads `agent/bun.lock` from the workspace's
`dependencies` through each package's own. The file must hold an `== <kind> <name>
<version> ==` header for each of those, `library <name> <version>` for each pin,
`framework sparkle <project.yml's exactVersion>`, `runtime bun`, `model silero-vad` and
`font <stem>` for each `*.ttf` in the bundle's `Contents/Resources/Fonts/` (any version
for those four).

The forty-three rows, none ever skipped:

* D1 — the needle is read from the seam file: exactly one bare declaration
  line, ASCII, at least 16 UTF-8 bytes;
* D2 — the Release binary exists;
* D3 — the Distribution binary exists;
* D4 — the Release binary holds the needle: the POSITIVE CONTROL, without
  which an absence check passes against a build that never had it;
* D5 — the Distribution binary does not hold the needle;
* D6 / D7 — the Release / Distribution helper exists;
* D8 / D9 — it is signed with the hardened runtime (`runtime` in the
  CodeDirectory flags) and `codesign --verify --strict` accepts it;
* D10 / D11 — its entitlements are exactly `com.apple.security.cs.allow-jit`;
* D12 / D13 — it does not hold the needle;
* D14 — the Distribution app's entitlements are exactly
  `com.apple.security.device.audio-input` and
  `com.apple.security.device.camera`;
* D15 / D16 — the Release / Distribution MCP proxy exists;
* D17 / D18 — it is signed with the hardened runtime and `codesign --verify
  --strict` accepts it;
* D19 / D20 — it holds no entitlements (an empty `codesign -d
  --entitlements - --xml`, or an empty dict);
* D21 / D22 — the snapshot parses as `{version, tools}`, its `version` is
  the bundle's `CFBundleShortVersionString` (`Contents/Info.plist`), and
  `tools` is a non-empty array of objects each with a string `name`;
* D23 — Release's snapshot names every `devHandlers` key (at least one: the
  positive control);
* D24 — Distribution's snapshot names none of them;
* D25 — the Release app's entitlements are exactly
  `com.apple.security.device.audio-input`,
  `com.apple.security.device.camera` and
  `com.apple.security.get-task-allow`;
* D26 / D27 — the Release / Distribution app passes `codesign --verify
  --deep --strict`;
* D28 — the Distribution app holds `Contents/Frameworks/Sparkle.framework`,
  its binary signed with the app binary's TeamIdentifier;
* D29 — every other Mach-O under that framework (at least one) is signed
  with the hardened runtime and `codesign --verify --strict` accepts it;
* D30 — the Distribution app's `SUFeedURL` is Distribution's
  `RC_SPARKLE_FEED_URL` in `project.yml`, an `https://` URL;
* D31 — the Distribution app's `SUPublicEDKey` is strict base64 of exactly
  32 bytes;
* D32 — the Release app's `SUFeedURL` and `SUPublicEDKey` are both empty;
* D33 — the Distribution binary holds `SPUStandardUpdaterController` (the
  positive control for D34);
* D34 — the Release binary does not hold it;
* D35 — `otool -L` lists the Release binary's load commands (at least one)
  and none is a `Sparkle.framework` path;
* D36 / D37 — the Release / Distribution binary's symbol table (`nm -j`)
  names `_svt_av1_enc_init_handle` and `_vpx_codec_vp9_cx`;
* D38 / D39 — every load command of the Release / Distribution binary
  (at least one) is under `/usr/lib/` or `/System/Library/`, or is an
  `@rpath/Sparkle.framework/` path;
* D40 / D41 — the Release / Distribution bundle holds
  `Contents/Resources/Licenses/<library>/<file>` for every licence text of
  every pin, byte-identical to `build/codecs/licenses/<library>/<file>`;
* D42 / D43 — the Release / Distribution bundle's
  `Contents/Resources/Acknowledgements.txt` has a header for every shipped crate
  and npm package (name and version), each pin, Sparkle at `project.yml`'s
  version, Bun, the model and each bundled font.

If D1 fails, D4, D5, D12 and D13 FAIL too, and so does each when its binary
or helper is missing; D14 FAILs when the Distribution binary is, D25 and
D26 when the Release binary is, and D27 when the Distribution binary is; D33
and D34 FAIL when their binary is missing, and D35 when the Release binary
is, or `otool` is missing or fails; D36–D39 FAIL when their binary is missing
or `nm`/`otool` is missing or fails, and D40 / D41 when `build/codecs/` has no
licences to compare; D42 / D43 FAIL when the file, `cargo`, its metadata or
`agent/bun.lock` is missing or unreadable, naming which. D17–D20
FAIL when their proxy is missing; D23 and D24 when their snapshot has no
readable `tools` or the dev names cannot be read. A missing `codesign`, a
timeout or output that does not parse FAILs the row with the reason.
`tools/proof/dist_check_mutants.py` makes each helper row, D14 and each of
D15–D32, D35, D36, D38 and D40–D43 fail on purpose. The last line is
`dist_check: <passed>/43`; the exit is 0 only at 43/43.
"""

import argparse
import base64
import binascii
import json
import os
import plistlib
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import proof_app  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "codecs"))
import build_codecs  # noqa: E402
SEAM = os.path.join(ROOT, "app", "Sources", "AgentServer+DevTools.swift")
DEFAULT_RELEASE = os.path.join(ROOT, "build", "Build", "Products", "Release", "Frame Job.app")
DEFAULT_DIST = os.path.join(ROOT, "build", "Build", "Products", "Distribution", "Frame Job.app")

# The declaration line, bare: nothing after the closing quote.
DECLARATION = re.compile(r'^\s*static let devToolsMarker = "([^"\\\n]+)"\s*$', re.M)
# Below this, the literal is stored inline in code and never found as bytes.
MIN_BYTES = 16
# The assistant helper, inside each bundle; its one entitlement (agent/entitlements.plist).
HELPER = os.path.join("Contents", "Helpers", "framejob-agent")
ENTITLEMENTS = {"com.apple.security.cs.allow-jit": True}
# The Distribution app's entitlements (#145, spec §11 CAM-3): the microphone and the camera,
# never get-task-allow.
APP_ENTITLEMENTS = {"com.apple.security.device.audio-input": True,
                    "com.apple.security.device.camera": True}
# The Release app's (B88): Distribution's plus the get-task-allow Xcode injects outside it.
RELEASE_ENTITLEMENTS = {**APP_ENTITLEMENTS, "com.apple.security.get-task-allow": True}
# The MCP proxy and its catalog snapshot, inside each bundle (road map 14 MC3).
PROXY = os.path.join("Contents", "Helpers", "framejob-mcp")
SNAPSHOT = os.path.join("Contents", "Resources", "agent-catalog.json")
INFO_PLIST = os.path.join("Contents", "Info.plist")
# The flag-on devHandlers table, inside the seam's `#if FRAMEJOB_DEV_TOOLS` block.
DEV_BLOCK = re.compile(r"^\s*#if FRAMEJOB_DEV_TOOLS\s*$(.*?)^\s*#else\s*$", re.M | re.S)
DEV_TABLE = re.compile(r"private static let devHandlers: \[String: ToolHandler\] = \[(.*?)\n\s*\]",
                       re.S)
DEV_KEY = re.compile(r'^\s*"([a-z_]+)":', re.M)
# Sparkle (spec §11 PUB-6..PUB-9): the embedded framework, and the class name the
# updater's code references, held by the Distribution binary alone.
SPARKLE = os.path.join("Contents", "Frameworks", "Sparkle.framework")
UPDATER_NEEDLE = b"SPUStandardUpdaterController"
PROJECT_YML = os.path.join(ROOT, "project.yml")
# Distribution's settings block in project.yml (the bare `Distribution:` line; the top-level
# `configs:` map writes `Distribution: release` on one line) and its feed setting.
DIST_BLOCK = re.compile(r"^( +)Distribution:[ \t]*$")
FEED_SETTING = re.compile(r"^\s*RC_SPARKLE_FEED_URL:\s*(\S+)\s*$")
TEAM = re.compile(r"^TeamIdentifier=(.*)$", re.M)
# A load command naming the framework (`@rpath/Sparkle.framework/Versions/B/Sparkle`).
SPARKLE_LOAD = "/Sparkle.framework/"
# The first four bytes of a Mach-O, thin or universal, either byte order.
MACHO_MAGIC = {bytes.fromhex(m) for m in
               ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca")}
# The bundled encoders (codec-export C0, spec §11 CX-4, CX-5): one entry point of each,
# the load commands a binary may hold, and where each bundle's licence texts are.
CODEC_SYMBOLS = ("_svt_av1_enc_init_handle", "_vpx_codec_vp9_cx")
SYSTEM_LOADS = ("/usr/lib/", "/System/Library/")
SPARKLE_RPATH = "@rpath/Sparkle.framework/"
LICENSES = os.path.join("Contents", "Resources", "Licenses")
CODEC_LICENSES = os.path.join(ROOT, "build", "codecs", "licenses")
# Each encoder's own string literal (spec §11 PUB-11): bytes `strip` keeps, unlike D37's symbols.
CODEC_STRINGS = (b"SVT-AV1 Encoder Lib", b"WebM Project VP9 Encoder")
# The acknowledgements (spec §11 PUB-10): the file, its entry headers, Frame Job's own crates,
# the cargo roots the shipped crates are read from, and the bundle's fonts.
ACKNOWLEDGEMENTS = os.path.join("Contents", "Resources", "Acknowledgements.txt")
ACK_HEADER = re.compile(r"^== (crate|npm|runtime|framework|library|model|font) (\S+) (\S+) ==$",
                        re.M)
FIRST_PARTY = ("framejob-core", "graphic", "framejob-mcp")
CARGO_ROOTS = ("core", "mcp-proxy")
BUN_LOCK = os.path.join(ROOT, "agent", "bun.lock")
FONTS = os.path.join("Contents", "Resources", "Fonts")
SPARKLE_VERSION = re.compile(r"^  Sparkle:\s*\n(?:    .*\n)*?    exactVersion:\s*\"?([^\"\s]+)\"?\s*$",
                             re.M)
TOTAL = 43
# The CodeDirectory line's flags; `Executable Segment flags=0x1` has no parentheses.
FLAGS = re.compile(r"flags=0x[0-9a-fA-F]+\(([^)]*)\)")
TIMEOUT = 120

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


def read_needle():
    """The marker's bytes, or None with the reason."""
    try:
        with open(SEAM, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        return None, f"cannot read {SEAM}: {error}"
    matches = DECLARATION.findall(text)
    if len(matches) != 1:
        return None, f"{len(matches)} bare `static let devToolsMarker = \"…\"` lines in {SEAM}"
    marker = matches[0]
    if not marker.isascii():
        return None, f"the marker {marker!r} is not ASCII"
    needle = marker.encode("utf-8")
    if len(needle) < MIN_BYTES:
        return None, f"the marker {marker!r} is {len(needle)} bytes, under {MIN_BYTES}"
    return needle, ""


def read_binary(app):
    """The app's executable's bytes, or None with the reason."""
    path = str(proof_app.executable(app))
    try:
        with open(path, "rb") as handle:
            return handle.read(), path
    except OSError as error:
        return None, f"{path}: {error}"


def read_helper(app):
    """The app's helper's bytes, or None with the reason."""
    path = os.path.join(app, HELPER)
    try:
        with open(path, "rb") as handle:
            return handle.read(), path
    except OSError as error:
        return None, f"{path}: {error}"


def child_env():
    """This process's environment without either product key, for every child."""
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    return env


def run_codesign(arguments):
    """`codesign` with the arguments: (completed process, None) or (None, the reason)."""
    try:
        return subprocess.run(["codesign"] + arguments, capture_output=True,
                              timeout=TIMEOUT, env=child_env()), None
    except FileNotFoundError:
        return None, "codesign is not on PATH"
    except subprocess.TimeoutExpired:
        return None, f"codesign {' '.join(arguments[:-1])} timed out after {TIMEOUT} s"
    except OSError as error:
        return None, f"codesign: {error}"


def helper_runtime(path):
    """Whether the helper is signed with the hardened runtime and verifies strictly."""
    shown, reason = run_codesign(["-dv", "--verbose=4", path])
    if shown is None:
        return False, reason
    stderr = shown.stderr.decode("utf-8", "replace")
    if shown.returncode != 0:
        return False, f"codesign -dv exit {shown.returncode}: {stderr.strip()[:300]}"
    match = FLAGS.search(stderr)
    if match is None:
        return False, "no `flags=0x…(…)` in codesign -dv's display"
    flags = [flag.strip() for flag in match.group(1).split(",")]
    if "runtime" not in flags:
        return False, f"CodeDirectory flags ({match.group(1)}) lack runtime in {path}"
    verified, reason = run_codesign(["--verify", "--strict", path])
    if verified is None:
        return False, reason
    if verified.returncode != 0:
        return False, (f"codesign --verify --strict exit {verified.returncode}: "
                       f"{verified.stderr.decode('utf-8', 'replace').strip()[:300]}")
    return True, f"flags ({match.group(1)})"


def entitlements(path, want):
    """Whether the code at `path` is signed with exactly the entitlements `want`."""
    shown, reason = run_codesign(["-d", "--entitlements", "-", "--xml", path])
    if shown is None:
        return False, reason
    if shown.returncode != 0:
        return False, (f"codesign -d --entitlements exit {shown.returncode}: "
                       f"{shown.stderr.decode('utf-8', 'replace').strip()[:300]}")
    try:
        held = plistlib.loads(shown.stdout)
    except Exception as error:  # plistlib raises several kinds on bad input
        return False, f"the entitlements do not parse ({type(error).__name__}: {error}) in {path}"
    if held != want:
        return False, f"entitlements {held!r} in {path}"
    return True, ""


def helper_entitlements(path):
    """Whether the helper's entitlements are exactly ENTITLEMENTS."""
    return entitlements(path, ENTITLEMENTS)


def proxy_entitlements(path):
    """Whether the proxy holds no entitlements: empty output, or an empty dict."""
    shown, reason = run_codesign(["-d", "--entitlements", "-", "--xml", path])
    if shown is None:
        return False, reason
    if shown.returncode != 0:
        return False, (f"codesign -d --entitlements exit {shown.returncode}: "
                       f"{shown.stderr.decode('utf-8', 'replace').strip()[:300]}")
    if not shown.stdout.strip():
        return True, ""
    try:
        held = plistlib.loads(shown.stdout)
    except Exception as error:  # plistlib raises several kinds on bad input
        return False, f"the entitlements do not parse ({type(error).__name__}: {error}) in {path}"
    if held != {}:
        return False, f"entitlements {held!r} in {path}"
    return True, ""


def sealed(binary_where):
    """Whether the bundle the executable `realpath`s into passes `codesign
    --verify --deep --strict`."""
    app = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(binary_where))))
    verified, reason = run_codesign(["--verify", "--deep", "--strict", app])
    if verified is None:
        return False, reason
    if verified.returncode != 0:
        return False, (f"codesign --verify --deep --strict exit {verified.returncode}: "
                       f"{verified.stderr.decode('utf-8', 'replace').strip()[:300]}")
    return True, app


def dev_names():
    """The flag-on devHandlers keys read from the seam, or None with the reason."""
    try:
        with open(SEAM, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        return None, f"cannot read {SEAM}: {error}"
    block = DEV_BLOCK.search(text)
    if block is None:
        return None, f"no `#if FRAMEJOB_DEV_TOOLS` … `#else` block in {SEAM}"
    table = DEV_TABLE.search(block.group(1))
    if table is None:
        return None, f"no flag-on devHandlers table in {SEAM}"
    names = DEV_KEY.findall(table.group(1))
    if not names:
        return None, f"no keys in the flag-on devHandlers table in {SEAM}"
    return names, ""


def read_snapshot(app):
    """(the snapshot's tool names or None, its version or None, its path or why not)."""
    path = os.path.join(app, SNAPSHOT)
    try:
        with open(path, "rb") as handle:
            value = json.loads(handle.read())
    except OSError as error:
        return None, None, f"{path}: {error}"
    except ValueError as error:
        return None, None, f"{path} is not JSON: {error}"
    if not isinstance(value, dict):
        return None, None, f"{path} is not an object"
    tools = value.get("tools")
    if not isinstance(tools, list) or not tools:
        return None, None, f"{path}'s `tools` is not a non-empty array"
    names = []
    for tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str):
            return None, None, f"{path} holds a tool that is not an object with a string name"
        names.append(tool["name"])
    version = value.get("version")
    return names, version if isinstance(version, str) else None, path


def bundle_version(app):
    """The bundle's CFBundleShortVersionString, or None with the reason."""
    path = os.path.join(app, INFO_PLIST)
    try:
        with open(path, "rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # OSError or a plist that does not parse
        return None, f"{path}: {type(error).__name__}: {error}"
    version = info.get("CFBundleShortVersionString") if isinstance(info, dict) else None
    if not isinstance(version, str):
        return None, f"no string CFBundleShortVersionString in {path}"
    return version, ""


def feed_url():
    """Distribution's RC_SPARKLE_FEED_URL in project.yml, or None with the reason."""
    try:
        with open(PROJECT_YML, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        return None, f"cannot read {PROJECT_YML}: {error}"
    starts = [(i, DIST_BLOCK.match(line)) for i, line in enumerate(lines)]
    starts = [(i, match) for i, match in starts if match]
    if len(starts) != 1:
        return None, f"{len(starts)} bare `Distribution:` lines in {PROJECT_YML}"
    first, match = starts[0]
    indent = len(match.group(1))
    values = []
    for line in lines[first + 1:]:
        if line.strip() and len(line) - len(line.lstrip(" ")) <= indent:
            break
        setting = FEED_SETTING.match(line)
        if setting:
            values.append(setting.group(1).strip("\"'"))
    if len(values) != 1:
        return None, f"{len(values)} RC_SPARKLE_FEED_URL lines in Distribution's block"
    if not values[0].startswith("https://"):
        return None, f"Distribution's RC_SPARKLE_FEED_URL {values[0]!r} is not https://"
    return values[0], ""


def updater_keys(app):
    """{"SUFeedURL", "SUPublicEDKey"} from the bundle's Info.plist (a missing key reads
    ""), or None with the reason."""
    path = os.path.join(app, INFO_PLIST)
    try:
        with open(path, "rb") as handle:
            info = plistlib.load(handle)
    except Exception as error:  # OSError or a plist that does not parse
        return None, f"{path}: {type(error).__name__}: {error}"
    if not isinstance(info, dict):
        return None, f"{path} is not a dictionary"
    keys = {key: info.get(key, "") for key in ("SUFeedURL", "SUPublicEDKey")}
    for key, value in keys.items():
        if not isinstance(value, str):
            return None, f"{key} in {path} is not a string: {value!r}"
    return keys, path


def public_key_ok(value):
    """Whether the value is strict base64 of exactly 32 bytes (an Ed25519 public key)."""
    if not value:
        return False, "SUPublicEDKey is empty (the owner's key has not landed, spec §11 PUB-8)"
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        return False, f"SUPublicEDKey {value!r} is not strict base64: {error}"
    if len(raw) != 32:
        return False, f"SUPublicEDKey {value!r} decodes to {len(raw)} bytes, not 32"
    return True, ""


def team_identifier(path):
    """The TeamIdentifier `codesign -dv --verbose=4` shows for the code at `path`
    (`not set` kept as is), or None with the reason."""
    shown, reason = run_codesign(["-dv", "--verbose=4", path])
    if shown is None:
        return None, reason
    stderr = shown.stderr.decode("utf-8", "replace")
    if shown.returncode != 0:
        return None, f"codesign -dv exit {shown.returncode}: {stderr.strip()[:300]}"
    match = TEAM.search(stderr)
    if match is None:
        return None, f"no TeamIdentifier= line in codesign -dv's display of {path}"
    return match.group(1).strip(), ""


def sparkle_framework(app):
    """Whether the bundle holds Sparkle.framework, its binary signed with the app
    binary's team (library validation refuses a framework of another team)."""
    framework = os.path.join(app, SPARKLE)
    binary = os.path.join(framework, "Sparkle")
    if not os.path.isfile(binary):
        return False, f"{binary}: no such file"
    want, reason = team_identifier(os.path.realpath(str(proof_app.executable(app))))
    if want is None:
        return False, f"the app binary: {reason}"
    held, reason = team_identifier(os.path.realpath(binary))
    if held is None:
        return False, f"the framework binary: {reason}"
    if held != want:
        return False, f"the framework's TeamIdentifier is {held!r}, the app's {want!r}"
    return True, f"TeamIdentifier {held}"


def is_macho(path):
    """Whether the file starts with a Mach-O magic."""
    try:
        with open(path, "rb") as handle:
            return handle.read(4) in MACHO_MAGIC
    except OSError:
        return False


def sparkle_helper_paths(framework):
    """Every Mach-O under the framework but its own binary, symlinks not followed, in a
    stable order (folders sorted, a folder's files before its subfolders)."""
    own = os.path.realpath(os.path.join(framework, "Sparkle"))
    helpers = []
    for folder, directories, files in os.walk(framework):
        directories.sort()
        for file in sorted(files):
            path = os.path.join(folder, file)
            if os.path.islink(path) or os.path.realpath(path) == own:
                continue
            if is_macho(path):
                helpers.append(path)
    return helpers


def sparkle_helpers(app):
    """Whether every Mach-O under Sparkle.framework but its own binary (at least one) is
    signed with the hardened runtime and verifies strictly (`helper_runtime`)."""
    framework = os.path.join(app, SPARKLE)
    if not os.path.isdir(framework):
        return False, f"{framework}: no such directory"
    helpers = sparkle_helper_paths(framework)
    if not helpers:
        return False, f"no Mach-O under {framework} but its own binary"
    for path in helpers:
        ok, reason = helper_runtime(path)
        if not ok:
            return False, reason
    return True, f"{len(helpers)} helpers"


def load_commands(binary):
    """The dylib paths `otool -L` lists for the executable (at least one), or None with
    the reason."""
    try:
        shown = subprocess.run(["otool", "-L", binary], capture_output=True, timeout=TIMEOUT,
                               env=child_env())
    except FileNotFoundError:
        return None, "otool is not on PATH"
    except subprocess.TimeoutExpired:
        return None, f"otool -L timed out after {TIMEOUT} s"
    except OSError as error:
        return None, f"otool: {error}"
    if shown.returncode != 0:
        return None, (f"otool -L exit {shown.returncode}: "
                      f"{shown.stderr.decode('utf-8', 'replace').strip()[:300]}")
    lines = shown.stdout.decode("utf-8", "replace").splitlines()[1:]
    paths = [line.strip().rsplit(" (", 1)[0] for line in lines if line.strip()]
    if not paths:
        return None, f"otool -L listed no load command for {binary}"
    return paths, ""


def codec_symbols(binary):
    """Whether the executable's symbol table (`nm -j`) names every CODEC_SYMBOLS entry."""
    try:
        shown = subprocess.run(["nm", "-j", os.path.realpath(binary)], capture_output=True,
                               timeout=TIMEOUT, env=child_env())
    except FileNotFoundError:
        return False, "nm is not on PATH"
    except subprocess.TimeoutExpired:
        return False, f"nm -j timed out after {TIMEOUT} s"
    except OSError as error:
        return False, f"nm: {error}"
    if shown.returncode != 0:
        return False, (f"nm -j exit {shown.returncode}: "
                       f"{shown.stderr.decode('utf-8', 'replace').strip()[:300]}")
    names = set(shown.stdout.decode("utf-8", "replace").split())
    missing = [symbol for symbol in CODEC_SYMBOLS if symbol not in names]
    if missing:
        return False, f"{missing} not in the symbol table of {binary}"
    return True, ""


def system_loads(binary):
    """Whether every load command is a system library or Sparkle (`otool -L`)."""
    paths, reason = load_commands(binary)
    if paths is None:
        return False, reason
    other = [path for path in paths
             if not path.startswith(SYSTEM_LOADS) and not path.startswith(SPARKLE_RPATH)]
    if other:
        return False, f"{other} in {binary}"
    return True, f"{len(paths)} load commands"


def codec_licences(app):
    """Whether the bundle holds every pin's licence texts, byte-identical to
    build/codecs/licenses/."""
    wanted = [(pin.name, installed) for pin in build_codecs.PINS
              for _, installed in pin.licenses]
    problems = []
    for library, name in wanted:
        source = os.path.join(CODEC_LICENSES, library, name)
        held = os.path.join(app, LICENSES, library, name)
        try:
            with open(source, "rb") as handle:
                want = handle.read()
        except OSError as error:
            return False, f"build/codecs has no {library}/{name} to compare: {error}"
        try:
            with open(held, "rb") as handle:
                if handle.read() != want:
                    problems.append(f"{library}/{name} differs")
        except OSError:
            problems.append(f"{library}/{name} is missing")
    if problems:
        return False, f"{problems} in {os.path.join(app, LICENSES)}"
    return True, f"{len(wanted)} texts"


def codec_strings(binary):
    """Whether the executable's bytes hold every CODEC_STRINGS literal (P22; `strip` keeps
    them, unlike the symbols D36/D37 read)."""
    try:
        with open(os.path.realpath(binary), "rb") as handle:
            data = handle.read()
    except OSError as error:
        return False, f"{binary}: {error}"
    missing = [needle.decode("ascii") for needle in CODEC_STRINGS if needle not in data]
    if missing:
        return False, f"{missing} not in the bytes of {binary}"
    return True, ""


def shipped_crates():
    """({(name, version)} of every crate reachable from core/'s and mcp-proxy/'s roots over a
    non-dev edge, Frame Job's own left out) or None, with the reason."""
    shipped = set()
    for folder in CARGO_ROOTS:
        try:
            shown = subprocess.run(["cargo", "metadata", "--format-version", "1", "--locked",
                                    "--offline", "--filter-platform", "aarch64-apple-darwin"],
                                   cwd=os.path.join(ROOT, folder), capture_output=True,
                                   timeout=TIMEOUT, env=child_env())
        except FileNotFoundError:
            return None, "cargo is not on PATH"
        except (OSError, subprocess.TimeoutExpired) as error:
            return None, f"cargo metadata in {folder}/: {error}"
        if shown.returncode != 0:
            return None, (f"cargo metadata in {folder}/ exit {shown.returncode}: "
                          f"{shown.stderr.decode('utf-8', 'replace').strip()[-300:]}")
        try:
            metadata = json.loads(shown.stdout)
            names = {p["id"]: (p["name"], p["version"]) for p in metadata["packages"]}
            edges = {n["id"]: [d["pkg"] for d in n["deps"]
                               if {k["kind"] for k in d["dep_kinds"]} != {"dev"}]
                     for n in metadata["resolve"]["nodes"]}
            reached, frontier = set(), {metadata["resolve"]["root"]}
            while frontier:
                reached |= frontier
                frontier = {c for i in frontier for c in edges[i]} - reached
        except (ValueError, KeyError, TypeError) as error:
            return None, f"cargo metadata in {folder}/ does not parse: {error!r}"
        shipped |= {names[i] for i in reached if names[i][0] not in FIRST_PARTY}
    return shipped, ""


def shipped_npm():
    """({(name, version)} of every npm package agent/bun.lock reaches from the workspace's
    dependencies through each package's own) or None, with the reason. A dependency is bun's
    nested key under its dependent's chain (`a/b/c`), else under a shorter one, else hoisted."""
    try:
        with open(BUN_LOCK, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        return None, f"{BUN_LOCK}: {error}"
    try:
        lock = json.loads(re.sub(r",\s*([}\]])", r"\1", text))
        packages = lock["packages"]
        todo = [((), name) for name in lock["workspaces"][""].get("dependencies", {})]
        shipped, seen = set(), set()
        while todo:
            chain, name = todo.pop()
            level = next((i for i in range(len(chain), -1, -1)
                          if "/".join(chain[:i] + (name,)) in packages), 0)
            path = chain[:level] + (name,)
            key = "/".join(path)
            if key in seen:
                continue
            seen.add(key)
            spec = packages[key]
            shipped.add((name, spec[0][spec[0].rindex("@") + 1:]))
            extra = spec[2] if len(spec) > 2 and isinstance(spec[2], dict) else {}
            todo.extend((path, dep) for dep in extra.get("dependencies", {}))
    except (ValueError, KeyError, TypeError, IndexError) as error:
        return None, f"{BUN_LOCK} does not read as a lock: {error!r}"
    return shipped, ""


def sparkle_version():
    """Sparkle's exactVersion in project.yml, or None with the reason."""
    try:
        with open(PROJECT_YML, encoding="utf-8") as handle:
            found = SPARKLE_VERSION.findall(handle.read())
    except OSError as error:
        return None, f"cannot read {PROJECT_YML}: {error}"
    if len(found) != 1:
        return None, f"{len(found)} Sparkle exactVersion lines in {PROJECT_YML}"
    return found[0], ""


def acknowledgements(app):
    """Whether the bundle's Acknowledgements.txt has a header for every shipped crate and npm
    package, each pin, Sparkle at project.yml's version, Bun, the model and each font."""
    path = os.path.join(app, ACKNOWLEDGEMENTS)
    try:
        with open(path, encoding="utf-8") as handle:
            headers = ACK_HEADER.findall(handle.read())
    except (OSError, UnicodeDecodeError) as error:
        return False, f"{path}: {error}"
    crates, reason = shipped_crates()
    if crates is None:
        return False, reason
    npm, reason = shipped_npm()
    if npm is None:
        return False, reason
    sparkle, reason = sparkle_version()
    if sparkle is None:
        return False, reason
    held = set(headers)
    named = {(kind, name) for kind, name, _ in headers}
    exact = ({("crate",) + c for c in crates} | {("npm",) + n for n in npm}
             | {("library", pin.name, pin.version) for pin in build_codecs.PINS}
             | {("framework", "sparkle", sparkle)})
    fonts = os.path.join(app, FONTS)
    stems = sorted(f[:-4] for f in (os.listdir(fonts) if os.path.isdir(fonts) else [])
                   if f.endswith(".ttf"))
    anyversion = {("runtime", "bun"), ("model", "silero-vad")} | {("font", s) for s in stems}
    missing = sorted(" ".join(e) for e in exact - held)
    missing += sorted(" ".join(e) + " <any>" for e in anyversion - named)
    if missing:
        return False, f"{len(missing)} missing from {path}: {missing[:8]}"
    return True, f"{len(headers)} entries, {len(crates)} crates, {len(npm)} npm, {len(stems)} fonts"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default=DEFAULT_RELEASE, help="the Release Frame Job.app")
    parser.add_argument("--dist", default=DEFAULT_DIST, help="the Distribution Frame Job.app")
    arguments = parser.parse_args()

    needle, needle_reason = read_needle()
    print("road map 11 V0, road map 12 A4, #145, road map 14 MC3, B88, spec §11 PUB-6..PUB-10 "
          "and CX-4, CX-5 — no dev tools in Distribution; the helper signed in both; both apps' "
          "entitlements and seals; the MCP proxy and its snapshot in both; the updater in "
          "Distribution alone; the encoders static in both, with their licences; the "
          "acknowledgements in both\n")
    print(f"  needle:       {needle.decode('ascii') if needle else '(none)'}")
    print(f"  release:      {os.path.abspath(arguments.release)}")
    print(f"  distribution: {os.path.abspath(arguments.dist)}\n")

    check("D1 the needle is one bare devToolsMarker line, ASCII, at least "
          f"{MIN_BYTES} bytes", needle is not None, needle_reason)

    release, release_where = read_binary(arguments.release)
    check("D2 the Release binary exists", release is not None, release_where)
    dist, dist_where = read_binary(arguments.dist)
    check("D3 the Distribution binary exists", dist is not None, dist_where)

    if needle is None:
        check("D4 the Release binary holds the needle (the positive control)", False,
              "no needle (D1)")
        check("D5 the Distribution binary does not hold the needle", False, "no needle (D1)")
    else:
        if release is None:
            check("D4 the Release binary holds the needle (the positive control)", False,
                  "no Release binary (D2)")
        else:
            count = release.count(needle)
            check(f"D4 the Release binary holds the needle (the positive control; {count} "
                  "occurrences)", count > 0, f"0 occurrences in {release_where}")
        if dist is None:
            check("D5 the Distribution binary does not hold the needle", False,
                  "no Distribution binary (D3)")
        else:
            count = dist.count(needle)
            check("D5 the Distribution binary does not hold the needle", count == 0,
                  f"{count} occurrences in {dist_where}")

    sides = (("Release", "D6", "D8", "D10", "D12", arguments.release),
             ("Distribution", "D7", "D9", "D11", "D13", arguments.dist))
    helpers = {}
    for side, exists_id, _, _, _, app in sides:
        helper, helper_where = read_helper(app)
        helpers[side] = (helper, helper_where)
        check(f"{exists_id} the {side} helper exists", helper is not None, helper_where)
    for side, exists_id, runtime_id, _, _, _ in sides:
        helper, helper_where = helpers[side]
        name = f"{runtime_id} the {side} helper is signed with the hardened runtime"
        if helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            ok, detail = helper_runtime(helper_where)
            check(name, ok, "" if ok else detail)
    for side, exists_id, _, entitlements_id, _, _ in sides:
        helper, helper_where = helpers[side]
        name = (f"{entitlements_id} the {side} helper's entitlements are exactly "
                "com.apple.security.cs.allow-jit")
        if helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            ok, detail = helper_entitlements(helper_where)
            check(name, ok, detail)
    for side, exists_id, _, _, needle_id, _ in sides:
        helper, helper_where = helpers[side]
        name = f"{needle_id} the {side} helper does not hold the needle"
        if needle is None:
            check(name, False, "no needle (D1)")
        elif helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            count = helper.count(needle)
            check(name, count == 0, f"{count} occurrences in {helper_where}")

    name = ("D14 the Distribution app's entitlements are exactly "
            "com.apple.security.device.audio-input and com.apple.security.device.camera")
    if dist is None:
        check(name, False, "no Distribution binary (D3)")
    else:
        ok, detail = entitlements(os.path.realpath(dist_where), APP_ENTITLEMENTS)
        check(name, ok, detail)

    proxy_sides = (("Release", "D15", "D17", "D19", "D21", arguments.release),
                   ("Distribution", "D16", "D18", "D20", "D22", arguments.dist))
    proxies = {}
    for side, exists_id, _, _, _, app in proxy_sides:
        path = os.path.join(app, PROXY)
        proxies[side] = path if os.path.isfile(path) else None
        check(f"{exists_id} the {side} MCP proxy exists", proxies[side] is not None,
              f"{path}: no such file")
    for side, exists_id, runtime_id, _, _, _ in proxy_sides:
        name = f"{runtime_id} the {side} MCP proxy is signed with the hardened runtime"
        if proxies[side] is None:
            check(name, False, f"no {side} MCP proxy ({exists_id})")
        else:
            ok, detail = helper_runtime(proxies[side])
            check(name, ok, "" if ok else detail)
    for side, exists_id, _, entitlements_id, _, _ in proxy_sides:
        name = f"{entitlements_id} the {side} MCP proxy holds no entitlements"
        if proxies[side] is None:
            check(name, False, f"no {side} MCP proxy ({exists_id})")
        else:
            ok, detail = proxy_entitlements(proxies[side])
            check(name, ok, detail)
    snapshots = {}
    for side, _, _, _, snapshot_id, app in proxy_sides:
        names, version, where = read_snapshot(app)
        snapshots[side] = (names, where)
        name = (f"{snapshot_id} the {side} snapshot is {{version, tools}} at the bundle's "
                "version, every tool named")
        want, why = bundle_version(app)
        if names is None:
            check(name, False, where)
        elif want is None:
            check(name, False, why)
        else:
            check(f"{name} ({len(names)} tools, {version})", version == want,
                  f"version {version!r} in {where}; the bundle's is {want!r}")
    dev, dev_reason = dev_names()
    names, where = snapshots["Release"]
    name = "D23 the Release snapshot names every dev tool (the positive control)"
    if dev is None:
        check(name, False, dev_reason)
    elif names is None:
        check(name, False, f"no readable Release snapshot (D21): {where}")
    else:
        missing = [tool for tool in dev if tool not in names]
        check(f"{name}: {len(dev)} of {len(dev)}" if not missing else name, not missing,
              f"missing {missing} in {where}")
    names, where = snapshots["Distribution"]
    name = "D24 the Distribution snapshot names no dev tool"
    if dev is None:
        check(name, False, dev_reason)
    elif names is None:
        check(name, False, f"no readable Distribution snapshot (D22): {where}")
    else:
        held = [tool for tool in dev if tool in names]
        check(name, not held, f"holds {held} in {where}")

    name = ("D25 the Release app's entitlements are exactly "
            "com.apple.security.device.audio-input, com.apple.security.device.camera and "
            "com.apple.security.get-task-allow")
    if release is None:
        check(name, False, "no Release binary (D2)")
    else:
        ok, detail = entitlements(os.path.realpath(release_where), RELEASE_ENTITLEMENTS)
        check(name, ok, detail)
    for side, row_id, binary, where, exists_id in (
            ("Release", "D26", release, release_where, "D2"),
            ("Distribution", "D27", dist, dist_where, "D3")):
        name = f"{row_id} the {side} app passes codesign --verify --deep --strict"
        if binary is None:
            check(name, False, f"no {side} binary ({exists_id})")
        else:
            ok, detail = sealed(where)
            check(name, ok, "" if ok else detail)

    ok, detail = sparkle_framework(arguments.dist)
    check("D28 the Distribution app holds Sparkle.framework, signed with the app's team",
          ok, "" if ok else detail)
    ok, detail = sparkle_helpers(arguments.dist)
    check("D29 every helper in the Distribution Sparkle.framework is signed with the "
          "hardened runtime" + (f" ({detail})" if ok else ""), ok, "" if ok else detail)
    want, want_reason = feed_url()
    keys, keys_where = updater_keys(arguments.dist)
    name = "D30 the Distribution app's SUFeedURL is Distribution's RC_SPARKLE_FEED_URL"
    if want is None:
        check(name, False, want_reason)
    elif keys is None:
        check(name, False, keys_where)
    else:
        check(name, keys["SUFeedURL"] == want,
              f"SUFeedURL {keys['SUFeedURL']!r} in {keys_where}; project.yml's is {want!r}")
    name = "D31 the Distribution app's SUPublicEDKey is base64 of exactly 32 bytes"
    if keys is None:
        check(name, False, keys_where)
    else:
        ok, detail = public_key_ok(keys["SUPublicEDKey"])
        check(name, ok, detail)
    keys, keys_where = updater_keys(arguments.release)
    name = "D32 the Release app's SUFeedURL and SUPublicEDKey are both empty"
    if keys is None:
        check(name, False, keys_where)
    else:
        check(name, keys == {"SUFeedURL": "", "SUPublicEDKey": ""},
              f"{keys!r} in {keys_where}")
    name = ("D33 the Distribution binary holds SPUStandardUpdaterController (the positive "
            "control)")
    if dist is None:
        check(name, False, "no Distribution binary (D3)")
    else:
        count = dist.count(UPDATER_NEEDLE)
        check(f"{name}; {count} occurrences" if count else name, count > 0,
              f"0 occurrences in {dist_where}")
    name = "D34 the Release binary does not hold SPUStandardUpdaterController"
    if release is None:
        check(name, False, "no Release binary (D2)")
    else:
        count = release.count(UPDATER_NEEDLE)
        check(name, count == 0, f"{count} occurrences in {release_where}")
    name = "D35 the Release binary has no Sparkle load command"
    if release is None:
        check(name, False, "no Release binary (D2)")
    else:
        paths, reason = load_commands(release_where)
        if paths is None:
            check(name, False, reason)
        else:
            held = [path for path in paths if SPARKLE_LOAD in path]
            check(f"{name} ({len(paths)} load commands)" if not held else name, not held,
                  f"{held} in {release_where}")

    encoder_sides = (("Release", "D36", "D38", "D40", release, release_where, "D2",
                      arguments.release),
                     ("Distribution", "D37", "D39", "D41", dist, dist_where, "D3",
                      arguments.dist))
    for side, symbols_id, _, _, binary, where, exists_id, _ in encoder_sides:
        name = (f"{symbols_id} the {side} binary's symbol table names "
                + " and ".join(CODEC_SYMBOLS))
        if binary is None:
            check(name, False, f"no {side} binary ({exists_id})")
        else:
            ok, detail = codec_symbols(where)
            check(name, ok, detail)
    for side, _, loads_id, _, binary, where, exists_id, _ in encoder_sides:
        name = (f"{loads_id} every {side} load command is a system library or "
                "Sparkle's")
        if binary is None:
            check(name, False, f"no {side} binary ({exists_id})")
        else:
            ok, detail = system_loads(where)
            check(f"{name} ({detail})" if ok else name, ok, "" if ok else detail)
    for side, _, _, licences_id, _, _, _, app in encoder_sides:
        ok, detail = codec_licences(app)
        check(f"{licences_id} the {side} bundle holds the encoders' licence texts"
              + (f" ({detail})" if ok else ""), ok, "" if ok else detail)
    for side, row_id, app in (("Release", "D42", arguments.release),
                              ("Distribution", "D43", arguments.dist)):
        ok, detail = acknowledgements(app)
        check(f"{row_id} the {side} bundle's Acknowledgements.txt names every shipped crate, "
              "npm package, pin, Sparkle, Bun, the model and each font"
              + (f" ({detail})" if ok else ""), ok, "" if ok else detail)

    print(f"\ndist_check: {passed}/{TOTAL}")
    return 0 if passed == TOTAL else 1


if __name__ == "__main__":
    sys.exit(main())
