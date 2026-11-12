#!/bin/bash
# Builds the assistant's helper, framejob-agent (agent/, a SwiftPM package on Slaude; road map
# "swift-helper", spec §11 SA-8), then strips it at DESTINATION and signs it there:
#
#   PROJECT_DIR=<tree> tools/agent/build_helper.sh DESTINATION
#
# project.yml's "Build Agent Helper" step passes the bundle's Contents/Helpers/framejob-agent;
# tools/proof/agent_helper_build.py passes a proof's own path, for the tree's helper and for a
# helper mutant (built on the persistent tree build/agent-swift-mutant/, SA-8).
#
# The tree is the CALLER's: $PROJECT_DIR, which Xcode sets to the project's folder. A tree
# copy's tools/ is a link to the tree's (tools/proof/tree_copy.py), so this script's own path
# would name the tree, and the copy would bundle the tree's helper. An unset PROJECT_DIR is
# refused.
#
# SwiftPM builds the release configuration, file by file in batches
# (-no-whole-module-optimization -enable-batch-mode): whole-module optimization of Slaude's
# ~2,400 files peaks at 10.6 GB in one compiler process, past the publish runner (Doctored's
# measurement, road map §10). There is no configuration knob (the owner's answer 5 (a)). The
# scratch path is <tree>/build/agent-swift; the suite's own (spec §11 SA-12) is never touched.
#
# SwiftPM runs under `env -i`: an Xcode script phase exports the app target's build settings
# (SDKROOT, SWIFT_*, ARCHS and hundreds more), which would steer SwiftPM's compiler, and a
# caller's shell may hold a key or FJ_AGENT_STRICT. Only HOME (git's and SwiftPM's caches),
# TMPDIR, a fixed PATH and DEVELOPER_DIR (the Xcode that runs the app build, when set) reach it.
#
# The stamp. SwiftPM is skipped when nothing it reads changed: the stamp inside the scratch path
# holds a key and the product's size and time, and all three must match. The key digests this
# script, the toolchain, agent/Package.swift, agent/Package.resolved and every file under
# agent/Sources read THROUGH links (find -L): the kit's anthropic.json is a link to
# agent/prices/anthropic.json, so the price table's content is in the key (spec §11 SA-3), and a
# tree copy, whose agent/ holds the table's bytes as a regular file, has the same key.
#
# The scratch path's own path. SwiftPM cannot build on a scratch path made at another path: the
# cloned module cache's precompiled headers name the path they were built at, and every compile
# fails (road map §13, SA0 items 3 and 9). A tree copy gets the tree's scratch path as a clone,
# so the scratch path records its own physical path in .framejob-helper-path, BESIDE the stamp
# and never in its key, and the record is read only on a miss: a clone is served at any path
# while its key matches, and a miss on a scratch path whose record is missing or names another
# path empties it first, so Slaude builds cold there.
#
# A dependency whose source the key cannot see always runs SwiftPM, with no stamp kept: one
# edited in place (`swift package edit`, under agent/Packages) or a local `.package(path:)` one,
# which the scratch path's workspace-state.json records.
#
# The destination is removed before anything else, so a failed build leaves no helper there and
# no stamp. The product is copied out, its linker signature removed (strip would invalidate it
# and say so on a `warning:` line Xcode counts), `strip -x`ed and signed with the hardened runtime
# and NO entitlements (spec §11 SA-8, Doctored's AH-6): Xcode's EXPANDED_CODE_SIGN_IDENTITY, else
# ad hoc, and --timestamp for a real identity. tools/proof/agent_build_proof.py holds these rules
# over toy packages. Prints one line saying whether SwiftPM was skipped or ran, and why.
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "usage: PROJECT_DIR=<tree> tools/agent/build_helper.sh DESTINATION" >&2
    exit 2
fi
DESTINATION="$1"
if [ -z "${PROJECT_DIR:-}" ]; then
    echo "error: build_helper.sh takes its tree from PROJECT_DIR, which is not set (spec §11 SA-8)" >&2
    exit 2
fi
TREE="$(cd "$PROJECT_DIR" && pwd -P)"
SELF_DIGEST="$(shasum -a 256 < "${BASH_SOURCE[0]}" | cut -d' ' -f1)"
SCRATCH="$TREE/build/agent-swift"
PRODUCT="$SCRATCH/release/framejob-agent"
STAMP="$SCRATCH/.framejob-helper-stamp"
RECORD="$SCRATCH/.framejob-helper-path"

SCRUBBED=(env -i "HOME=$HOME" "PATH=/usr/bin:/bin:/usr/sbin:/sbin" "TMPDIR=${TMPDIR:-/tmp}")
if [ -n "${DEVELOPER_DIR:-}" ]; then
    SCRUBBED+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi

rm -f "$DESTINATION" "$DESTINATION.tmp"
cd "$TREE"

inputs_digest() {
    {
        printf 'script %s\n' "$SELF_DIGEST"
        printf 'swift %s\n' "$("${SCRUBBED[@]}" xcrun --find swift)"
        "${SCRUBBED[@]}" xcrun swift --version 2>&1
        for file in agent/Package.swift agent/Package.resolved; do
            if [ -f "$file" ]; then shasum -a 256 "$file"; else printf 'absent %s\n' "$file"; fi
        done
        find -L agent/Sources -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
    } | shasum -a 256 | cut -d' ' -f1
}

product_identity() {
    stat -f '%z %m' "$PRODUCT"
}

# True when a dependency's source lies outside the key: an edited package's state is `edited`,
# a path dependency's kind and state are `fileSystem`, a local git one's kind `localSourceControl`.
local_dependency() {
    [ -d agent/Packages ] && return 0
    [ -f "$SCRATCH/workspace-state.json" ] \
        && grep -q -E '"(name|kind)" *: *"(edited|fileSystem|localSourceControl)"' "$SCRATCH/workspace-state.json"
}

KEY="$(inputs_digest)"
LOCAL=0
if local_dependency; then
    # No stamp is kept for such a build either: after `swift package unedit` the key would match
    # again and skip the build that puts the pinned revision back.
    LOCAL=1
    rm -f "$STAMP"
fi
if [ "$LOCAL" = 0 ] && [ -f "$PRODUCT" ] && [ -f "$STAMP" ] \
    && [ "$(cat "$STAMP")" = "$KEY $(product_identity)" ]; then
    SAID="skipped: agent/ is unchanged since its build of $(date -r "$STAMP" '+%F %T')"
else
    rm -f "$STAMP"
    SAID="built"
    if [ -e "$SCRATCH" ]; then
        RECORDED="$(cat "$RECORD" 2>/dev/null || true)"
        if [ "$RECORDED" != "$SCRATCH" ]; then
            find "$SCRATCH" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            if [ -n "$RECORDED" ]; then WHERE="at $RECORDED"; else WHERE="with no record"; fi
            SAID="emptied, then built: the scratch path was made $WHERE"
        fi
    fi
    mkdir -p "$SCRATCH"
    printf '%s\n' "$SCRATCH" > "$RECORD"
    if [ "$LOCAL" = 1 ]; then SAID="$SAID (a dependency is edited or local, so SwiftPM always runs)"; fi
    # SwiftPM's release passes `-num-threads`, which batch mode cannot use; the driver ignores it
    # and says so on one `warning:` line per module, which Xcode would count as a build warning.
    # That exact line is dropped; pipefail keeps SwiftPM's exit status.
    if ! "${SCRUBBED[@]}" xcrun swift build --package-path "$TREE/agent" --scratch-path "$SCRATCH" \
        --configuration release --product framejob-agent \
        -Xswiftc -no-whole-module-optimization -Xswiftc -enable-batch-mode 2>&1 \
        | sed -l '/^warning: ignoring -num-threads argument; cannot multithread batch mode$/d'; then
        echo "error: build_helper.sh: SwiftPM failed to build framejob-agent from $TREE/agent" >&2
        exit 1
    fi
    if [ ! -f "$PRODUCT" ]; then
        echo "error: build_helper.sh: SwiftPM reported success but $PRODUCT is missing" >&2
        exit 1
    fi
    if [ "$LOCAL" = 0 ]; then printf '%s %s\n' "$KEY" "$(product_identity)" > "$STAMP"; fi
fi

mkdir -p "$(dirname "$DESTINATION")"
trap 'rm -f "$DESTINATION.tmp"' EXIT
cp -f "$PRODUCT" "$DESTINATION.tmp"
codesign --remove-signature "$DESTINATION.tmp"
"${SCRUBBED[@]}" xcrun strip -x "$DESTINATION.tmp"
mv -f "$DESTINATION.tmp" "$DESTINATION"
trap - EXIT
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
TIMESTAMP=()
if [ "$IDENTITY" != "-" ]; then TIMESTAMP=(--timestamp); fi
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$IDENTITY" "$DESTINATION"
echo "build_helper: $SAID; $DESTINATION signed $IDENTITY, hardened runtime, no entitlements"
