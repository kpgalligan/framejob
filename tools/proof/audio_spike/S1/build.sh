#!/bin/sh
# Builds the S1 tool and the rtcheck dylib. Run: sh build.sh
set -e
D=/private/tmp/claude-501/-Users-kevingalligan-devel-framejob/9bb0487d-a352-45e3-9da8-07b6f4762c27/scratchpad/ap0/S1
mkdir -p "$D/bin"
clang -O2 -dynamiclib -o "$D/rtcheck/librtcheck.dylib" "$D/rtcheck/rtcheck.c"
cd "$D/src"
swiftc -O -swift-version 5 -o "$D/bin/s1" RT.swift OwnDSP.swift OwnLimiter2.swift AppleHost.swift Tap.swift main.swift 2>&1 | grep -E "error" -A3 || true
ls -la "$D/bin/s1"
