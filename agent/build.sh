#!/bin/sh
# The one place bun is found and run (spec §11 AI-1): `helper` is the last
# Xcode build step (project.yml's "Build Agent Helper"), `typecheck` is the
# last line of `make typecheck`. Neither skips when bun is missing.
set -e

AGENT="$(cd "$(dirname "$0")" && pwd -P)"
export PATH="$HOME/.bun/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"

usage() {
  echo "usage: agent/build.sh helper|typecheck" >&2
  exit 2
}

[ $# -eq 1 ] || usage
case "$1" in
  helper|typecheck) ;;
  *) usage ;;
esac

if ! command -v bun >/dev/null 2>&1; then
  echo "error: bun is not installed (looked on PATH, in ~/.bun/bin, mise's shims, /opt/homebrew/bin and /usr/local/bin); agent/ needs it to build and typecheck the assistant helper, and a build never skips it. Install it from https://bun.sh." >&2
  exit 1
fi

cd "$AGENT"
case "$1" in
  typecheck)
    bun install --frozen-lockfile
    bun run typecheck
    ;;
  helper)
    if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$CONTENTS_FOLDER_PATH" ]; then
      echo "error: build.sh helper runs as Xcode's build step" >&2
      exit 2
    fi
    bun install --frozen-lockfile
    bun run build
    HELPERS="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    mkdir -p "$HELPERS"
    cp "$AGENT/../build/agent/reelcut-agent" "$HELPERS/"
    IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    TIMESTAMP=""
    if [ "$IDENTITY" != "-" ]; then TIMESTAMP="--timestamp"; fi
    codesign --force --options runtime $TIMESTAMP \
      --entitlements "$AGENT/entitlements.plist" \
      --sign "$IDENTITY" "$HELPERS/reelcut-agent"
    ;;
esac
