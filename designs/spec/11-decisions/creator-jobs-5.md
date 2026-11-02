# Spec §11 — decisions: Creator jobs, the cutout's edges onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md) and
[`creator-jobs-4.md`](creator-jobs-4.md) (CJ-, VR-, TX-, SW-, CU- and CO-), so a citation never has
to say which file; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).
This file is new because `creator-jobs-4.md` passed the road map's ~500-line split rule with CO3's
entries (620 lines, 2026-11-02); each phase's decisions are appended here from now on, before its
code.

CO-40…CO-42 are CO4's (the cutout's edges), recorded before its code. S-KEY1 (`samples/README.md`:
the owner before an evenly lit plain cloth) does not exist, so CO-S3 — whether the edge needs
refinement, and which — cannot run; the road map's head rule for that case is that r0 ships and
the row is owed. The owner's answer of 2026-11-01 for CO4: Best is **not** the default on a short
clip — Standard always, Best chosen per clip. No format bump, no `rc_*`, no core change, no new
tool, no shader change: two doc comments, the documents and the proof. Vision runs on the Mac, so
nothing here is keyed (CJ-3).

- **CO-40 — r0 is the edge; CO-S3 is owed.**
  - **What ships.** The edge is CO-27's r0 and nothing else: the mask's `.r` sampled bilinearly
    and remapped by `cutoutCover` (`Compositor.metal`), `c = 0.5 − 0.5·edge`, `w = 0.5 +
    0.5·feather`, `lo = clamp(c − w/2, 0, 1)`, `hi = clamp(c + w/2, 0, 1)`, `cover =
    smoothstep(lo, hi, m)`. No r1 (joint bilateral) or r2 (guided filter), no pre-pass, no
    `KeyReading` passed to a refinement (CO-7's clause on a refinement's guide has nothing to
    read yet), no new uniform, no core constant; `LayerUniforms` stays at 160 floats.
  - **The documented amount (the contour rule).** At Feather 0 the outline — where coverage is
    one half, the midpoint of `smoothstep(lo, hi, ·)` — lies at the mask value **m½(e)**: `0.5 −
    0.5·e` for |e| ≤ 0.5, `0.375 − 0.25·e` for e > 0.5 (`lo` clamped at 0), `0.625 − 0.25·e` for
    e < −0.5 (`hi` clamped at 1). At e = −1, −0.5, 0, 0.5, 1 it is 0.875, 0.75, 0.5, 0.25,
    0.125. On a mask edge that rises linearly over R display pixels, Edge +1 moves the outline
    3R/8 outward from Edge 0 and −1 moves it 3R/8 inward; coverage is non-decreasing in `edge`
    at every mask value, so a larger Edge never draws less. This is what Edge means until a
    refinement replaces it; the guide states it in words, and `co4_proof.py` E4 measures it.
  - **CO-S3 runs when S-KEY1 exists**, unchanged: its rule as CJ0a pinned it (`rule_sha256`
    `84ae691664c9d8293b50f70e1f332e68a032984da4f2ae65500561f152e9319f`), after CO-S1's owed
    S-KEY1 rows. A refinement it picks is a new phase, with its own decisions, its own proof
    (CO4's E1–E3: B on S-KEY1's composites against CO-S3's, the same in an HLG project, the
    preview's cost bound) and its own mutants; until then E1–E3 are skipped by name and owed.
- **CO-41 — No Best yet; Best is never a default.** CO-S1 kept no Best (its rule (d) needs
  S-KEY1), so there is no `masks_best` kind, no Quality row (CO-30 stands) and `best` stays
  refused in CO-20's sentence ("video.cutout.quality must be standard: Best masks are not made
  yet") until CO-S1 (d) keeps Best on S-KEY1. When Best exists (the owner, 2026-11-01): Standard
  on every clip, Best only when chosen per clip, with no rule that picks it by duration.
- **CO-42 — CO4's proof.** `co4_proof.py`: B0 its probe (`co2a_probe.swift`, whose `pack` mode
  gains the `ramp` kind: every mask 512 × 288, column i `round(255·clamp((i − 240)/32, 0, 1))`)
  builds; E1, E2 and E3 skipped by name while `tools/proof/media/creator/S-KEY1/` is absent, and
  each a scored failure once it exists; E4 the documented amount on a 1920 × 1080 transparent
  canvas — the bar code at scale 1 over a canned `ramp` pack (a ramp of 32 texels, 120 display
  pixels), at Edge −1, −0.5, 0, 0.5 and 1, Feather 0: on rows 100, 540 and 980 the contour where
  alpha crosses 127.5 within 1 px of `3.75·(240.5 + 32·m½(e))`, and Edge 0 → +1 and −1 → 0 each
  45 ± 1 px; E4r the order on real masks — `push_1080.mov`'s, made by `get_media_analysis` — at
  Edge −1, 0 and +1: alpha non-decreasing in `edge` at every pixel within one level, and the
  count of pixels with alpha ≥ 128 strictly increasing; Z1 each launch's log free of `Frame
  Job: `. Two mutants on Release: Edge's sign reversed (E4, E4r) and `lo`/`hi` unclamped (E4).
  JOB-60 (`docs/manual-checks.md`) is the person's look at real edges.
