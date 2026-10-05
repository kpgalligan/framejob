# 8. Repo layout, build, conventions

```
reelcut/
  CLAUDE.md           # points here; commands; the rules below
  Makefile            # app / test / lint / typecheck / project / run — Rasterize's, renamed
  project.yml         # xcodegen; macOS 26, arm64; document types below
  VERSION             # the base version, MAJOR.MINOR (§11 PUB-2)
  .github/            # workflows/publish.yml: the `publish` branch's signed, notarized DMG (§11 PUB-1..PUB-5)
  core/
    Cargo.toml        # reelcut-core; lib name reelcut_core; serde, serde_json, serde_path_to_error, tiny_http; lto
    include/reelcut_core.h
    src/  tests/
  agent/              # the assistant helper (§11 AI-1): Bun, src/ shared with Rasterize's; build.sh
  app/
    Bridging/Reelcut-Bridging-Header.h
    Sources/          # AppKit, programmatic, no storyboards
    Resources/Fonts   # Source Sans 3, IBM Plex Mono, Darker Grotesque (+ OFL files)
    Assets.xcassets   # AppIcon
  designs/            # this document
```

`project.yml` document types: `com.kgalligan.reelcut-project` (Owner,
`.reelcut`, conforms to `com.apple.package`), then as Alternate editors:
`com.apple.quicktime-movie`, `public.mpeg-4`, `com.apple.m4v-video`,
`public.movie`, `com.apple.m4a-audio`, `public.mp3`, `com.microsoft.waveform-audio`,
`public.aiff-audio`, `public.png`, `public.jpeg`, `public.heic`.
`ProjectDocument.read(from:ofType:)` on a non-package type imports the
file into a fresh project and marks the document untitled.

Commands (identical to Rasterize's):

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # make rust, cd core && cargo test --release, cd graphic && cargo test --release (black-box tests), then tools/proof/assistant_lane_proof.py (the agent lane's probe) and tools/proof/assistant_prompt_proof.py --probe (the prompt texts' drift checks)
make lint       # cargo clippy --all-targets -- -D warnings
make typecheck  # swiftc -typecheck of app/Sources/*.swift with the bridging header — the ONLY Swift check, then agent/'s tsc --noEmit (through bun)
make project    # xcodegen generate, with the base version from VERSION (§11 PUB-2)
make run
```

Files to copy from `~/devel/rasterize` at scaffold time, then rename:
`Makefile`, `project.yml`, `.gitignore`, `core/src/agent.rs`,
`core/src/ffi_util.rs`, `app/Sources/Theme.swift`, `Controls.swift`,
`OptionControls.swift`, `Sheets.swift`, `FileDropView.swift`,
`WelcomeWindowController.swift`, `app/Resources/Fonts/*`. Read before
writing the corresponding Reelcut file: `ImageDocument.swift` (undo and
dirty tracking), `RasterCore.swift` (wrapper shape), `AgentServer.swift`
+ `AgentCatalog.swift` (dispatch and parity check), `LivePhotoLayer.swift`
(AVFoundation frame extraction), `ToolOptionsBar.swift` +
`EditorViewController+ToolOptions.swift` (descriptor-driven controls),
and both `CLAUDE.md` files under `core/` and `app/`.

Rules carried over verbatim: pure ops, which here answer three arms rather
than Rasterize's `Option` (§5.5); the three-file lockstep (`ffi_*.rs` →
header → `ReelCore.swift`)
— with JSON ops the header changes rarely, but the op table in `edit.rs`
and the builders in `ReelCore.swift` still move together; every export
`catch_unwind` + NULL-tolerant + `err_out`; no panics on any input; the
frozen-file / extension-file rule (base VC, canvas, timeline, agent server
and sheets take wiring only); one document mutation point; no `!`, `as!`,
`try!`; `[weak self]`; main-thread AppKit; `async`/`await` only inside
`MediaImporter` and `SpeechEngine` (§11 W-8); `DispatchQueue` only at the documented seams (compositor
render queue, composition rebuild, import); MCP parity for every op;
`DS` tokens for all chrome; 4-space indent, ~100 columns; `cargo fmt` and
a clean `make lint` before finishing Rust work.
