#!/bin/bash
# tools/proof/harness/build.sh — build the offscreen chrome harness.
#
# Compiles every app/Sources/*.swift except the app's main.swift together
# with tools/proof/harness/main.swift (last, so its top-level code is the
# entry point), links core/target/release/libframejob_core.a, and puts the
# binary in tools/proof/work/harness/harness with the app's Fonts and Models
# copied beside it (the harness registers the fonts at launch). It compiles
# with `-D FRAMEJOB_DEV_TOOLS`, as the app's Debug and Release do, so the
# harness links what the app links. The build goes through
# tools/proof/swift_build.py (issue batch B88): reused when every input is
# byte-identical to a cached build's, else compiled on every core; `--force`
# rebuilds. `make test` / `cargo build --release` produce the staticlib; this
# script never runs cargo or xcodebuild itself. Fonts and Models are recopied
# only when their digest (sha256 over each file's relative path and content
# sha256) differs from app/Resources', through a sibling `.new` folder renamed
# into place. On EVERY run docs/graphics-api.md and docs/graphics-api.d.ts are
# copied beside Fonts as GraphicsAPI.md and GraphicsAPI.d.ts — the app
# bundle's names — so the harness's stores write the manual
# (`GraphicStore+Manual.swift`) and an edit to the docs alone reaches it.
#
#   tools/proof/harness/build.sh            # build or reuse, print the path
#   tools/proof/harness/build.sh --force    # rebuild regardless
#
# The last line of stdout is the binary's path; swift_build.py's `reused …` /
# `built …` line goes to stderr.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/tools/proof/work/harness"
bin="$out/harness"
lib="$root/core/target/release/libframejob_core.a"

if [ ! -f "$lib" ]; then
    echo "build.sh: $lib is missing — run 'cd core && cargo build --release' first" >&2
    exit 1
fi

sources=()
for file in "$root"/app/Sources/*.swift; do
    case "$file" in */main.swift) ;; *) sources+=("$file") ;; esac
done

mkdir -p "$out"
for doc in md d.ts; do
    cp "$root/docs/graphics-api.$doc" "$out/GraphicsAPI.$doc.tmp-$$"
    mv -f "$out/GraphicsAPI.$doc.tmp-$$" "$out/GraphicsAPI.$doc"
done

force=()
[ "${1:-}" = "--force" ] && force=(--force)
python3 "$root/tools/proof/swift_build.py" build --output "$bin" --define FRAMEJOB_DEV_TOOLS \
    ${force[@]+"${force[@]}"} "${sources[@]}" "$here/main.swift" >/dev/null

# sha256 over the sorted "relative path, content sha256" of every file in $1.
digest() {
    python3 - "$1" <<'EOF'
import hashlib, os, sys
top, rows = sys.argv[1], []
for folder, _, names in os.walk(top):
    for name in names:
        path = os.path.join(folder, name)
        with open(path, "rb") as f:
            rows.append(f"{os.path.relpath(path, top)} {hashlib.sha256(f.read()).hexdigest()}")
print(hashlib.sha256("\n".join(sorted(rows)).encode()).hexdigest())
EOF
}

for name in Fonts Models; do
    src="$root/app/Resources/$name"
    dst="$out/$name"
    if [ ! -d "$dst" ] || [ "$(digest "$src")" != "$(digest "$dst")" ]; then
        rm -rf "$out/.$name.new-$$"
        cp -R "$src" "$out/.$name.new-$$"
        [ -e "$dst" ] && { mv "$dst" "$out/.$name.old-$$" 2>/dev/null || true; }
        if [ -e "$dst" ]; then rm -rf "$out/.$name.new-$$"; else mv "$out/.$name.new-$$" "$dst"; fi
        rm -rf "$out/.$name.old-$$"
    fi
done
echo "$bin"
