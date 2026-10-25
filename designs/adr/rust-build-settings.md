# The Rust build settings: no LTO, incremental release builds

- **Status:** Decided and landed 2026-09-19 (`af5907c`), in `core/Cargo.toml`, and in
  `graphic/Cargo.toml` since G1. Measured on an M2 Max at 12 jobs.
- **Original:** `archive/remaining.md` §6 (the measurement run); summarised with its
  lesson in `designs/adr/remaining-closed.md` ("§6 — the Rust build settings run").
- **Spec decisions:** none.

## Context

`[profile.release] lto = true` did not reach the shipped staticlib and did reach every test
binary. Cargo passes no `-C lto` to a unit whose crate types include `rlib`, and the lib is
`["staticlib", "rlib"]`. With `staticlib` alone it does, but every integration test (which links
the rlib) then fails to compile. So product LTO would cost a shim crate and ~18 s per `make app`,
for a JSON/arithmetic core nothing says would repay it. Meanwhile the line fat-LTO'd each test
binary: **166 s** for a test build after one edit, against **26 s** with `lto = false` and **3 s**
with `incremental = true` added.

## Decisions

```toml
[profile.release]
# No LTO: cargo skips it for a staticlib+rlib unit anyway, and asking for it
# fat-LTOs each of the 32 test binaries (designs/adr/rust-build-settings.md).
incremental = true
```

- In `[profile.release]` itself, not a custom profile, because `make rust`, `make test`, the Xcode
  pre-build script and `LIBRARY_SEARCH_PATHS` all hard-code `release`.
- `make test` stays `--release`: dev is no faster, and it tests a configuration that does not ship.
- Tried and bought nothing: rust-lld, `opt-level = 1` in dev, sccache, nextest.
- `panic = "abort"` is out: `ffi_agent.rs` catches unwinds.

## Known limits

- The shipped `.a` is codegen'd in more units (22 MB, not 32). `CARGO_INCREMENTAL=0 cargo build
  --release` is the one-off way back to a single-unit build.
- The parent `~/devel/rasterize/core/Cargo.toml` carries the same `lto = true` line, unmeasured
  there.

## Open items

None.
