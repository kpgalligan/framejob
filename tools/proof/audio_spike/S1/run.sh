#!/bin/sh
# Runs the S1 tool with the rtcheck dylib inserted. Run: sh run.sh <command> [args]
D=/private/tmp/claude-501/-Users-kevingalligan-devel-framejob/9bb0487d-a352-45e3-9da8-07b6f4762c27/scratchpad/ap0/S1
cd "$D"
DYLD_INSERT_LIBRARIES="$D/rtcheck/librtcheck.dylib" exec "$D/bin/s1" "$@"
