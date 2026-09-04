# CLAUDE.md

Reelcut — a screencast-style video editor for macOS: Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`.

**Nothing is built yet.** The accepted design and implementation spec is
`designs/reelcut-design.md`. Read it fully before writing code; start at
§10 (the M1 build order, each step with its verification) and treat §11 as
settled decisions, not open questions.

## Commands

Identical to Rasterize's once the scaffold (spec §8, M1 step 1) exists:

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release
make lint       # cargo clippy --all-targets -- -D warnings
make typecheck  # swiftc -typecheck of app/Sources/*.swift — the ONLY authoritative Swift check
make project    # xcodegen generate (Reelcut.xcodeproj is generated; project.yml is the source of truth)
make run
```

## Rules

- Conventions are Rasterize's. Read `~/devel/rasterize/CLAUDE.md`,
  `core/CLAUDE.md` and `app/CLAUDE.md` there before writing on either
  side; spec §8 lists the files to copy verbatim and the ones to read
  first.
- Rust decides, AVFoundation and Metal do (spec §7). No pixel or sample
  work in Rust; no ffmpeg dependency.
- `app/Sources/ReelCore.swift` is the only file that calls `rc_*`. Edits
  are JSON ops through `rc_project_apply`; the op table is the module doc
  of `core/src/edit.rs` and spec §6, and the typed Swift builders in
  `ReelCore.swift` mirror it.
- Every edit is pure and returns `Option` (identity = `None`); undo is a
  stack of handles in `ProjectDocument`, the single mutation point.
- Every op gets an MCP mirror (spec §7.9); the built app is verified by
  driving it over MCP and `render_frame`.
- Keep this file current as code lands: commands, the file map, the
  verification flow. Move per-side rules into `core/CLAUDE.md` and
  `app/CLAUDE.md` once those directories exist.
