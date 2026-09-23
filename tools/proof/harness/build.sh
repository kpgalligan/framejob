#!/bin/bash
# tools/proof/harness/build.sh — build the offscreen chrome harness.
#
# Compiles every app/Sources/*.swift except the app's main.swift together
# with tools/proof/harness/main.swift (last, so its top-level code is the
# entry point), links core/target/release/libreelcut_core.a, and puts the
# binary in tools/proof/work/harness/harness with the app's Fonts copied
# beside it (the harness registers them at launch). The build is skipped
# when that binary is newer than every source, this script's main.swift and
# the staticlib — `make test` / `cargo build --release` produce the
# staticlib; this script never runs cargo or xcodebuild itself.
#
#   tools/proof/harness/build.sh            # build if stale, print the path
#   tools/proof/harness/build.sh --force    # rebuild regardless
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/tools/proof/work/harness"
bin="$out/harness"
lib="$root/core/target/release/libreelcut_core.a"

if [ ! -f "$lib" ]; then
    echo "build.sh: $lib is missing — run 'cd core && cargo build --release' first" >&2
    exit 1
fi

sources=()
for file in "$root"/app/Sources/*.swift; do
    case "$file" in */main.swift) ;; *) sources+=("$file") ;; esac
done

force=0
[ "${1:-}" = "--force" ] && force=1
if [ "$force" = 0 ] && [ -x "$bin" ]; then
    stale=0
    for file in "${sources[@]}" "$here/main.swift" "$lib"; do
        [ "$file" -nt "$bin" ] && { stale=1; break; }
    done
    if [ "$stale" = 0 ]; then
        echo "$bin"
        exit 0
    fi
fi

mkdir -p "$out"
start=$(date +%s)
swiftc \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos26.0 \
    -module-name Reelcut \
    -import-objc-header "$root/app/Bridging/Reelcut-Bridging-Header.h" \
    -L "$root/core/target/release" -lreelcut_core \
    "${sources[@]}" "$here/main.swift" \
    -o "$bin"
rm -rf "$out/Fonts"
cp -R "$root/app/Resources/Fonts" "$out/Fonts"
rm -rf "$out/Models"
cp -R "$root/app/Resources/Models" "$out/Models"
end=$(date +%s)
echo "built $bin in $((end - start)) s" >&2
echo "$bin"
