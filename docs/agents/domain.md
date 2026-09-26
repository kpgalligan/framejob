# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root: the glossary.
- **Spec §11, "Decisions made — do not re-litigate"** (`designs/spec/11-decisions/`): this repo's decision record, in the role ADRs play elsewhere. Its `README.md` indexes every decision by ID and names the file it is in; read only the entries that touch the area you're about to work in.

If `CONTEXT.md` doesn't exist, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. `/domain-modeling` creates it lazily when a term actually gets resolved.

## Decisions go in spec §11, not `docs/adr/`

`CLAUDE.md` makes §11 binding: a decision there is not re-litigated, and a phase that needs a new one records it there before the code. So when a skill would write an ADR, add a §11 entry instead, in that section's style: a bold one-line decision, then its reasoning and the risk it accepts. Don't create `docs/adr/`.

`designs/adr/` is something else: one condensed record per CLOSED road map, written when the road map is archived (root `CLAUDE.md` says how). It explains the history behind the code and cites §11's IDs; it is not where a new decision goes. Read the one for your area when you need to know why the code is shaped as it is.

## File structure

```
/
├── CONTEXT.md                  ← glossary, created lazily
├── designs/spec/               ← the spec, one file per section; 11-decisions/ is the decision record
├── designs/adr/                ← condensed records of closed road maps
├── archive/                    ← their originals; read only when asked (INDEX.md)
├── core/                       ← Rust staticlib
└── app/                        ← Swift/AppKit
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Until a term is there, use the name the spec and the op table in `core/src/edit.rs` give it. Don't drift to synonyms.

If the concept you need has no name in either, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag §11 conflicts

If your output contradicts a §11 decision, surface it explicitly rather than silently overriding. Reopening one is the user's call:

> _Contradicts spec §11 (one JSON op entry point), but worth raising because…_
