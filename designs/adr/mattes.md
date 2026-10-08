# The matte track (road map "mattes", issue batch B89, #240)

- **Status:** Built and closed 2026-10-08. Each phase was one litecode pipeline with its own review:
  - MT0, the decisions and the spike (`ee05bff`)
  - MT1, three pure moves to make room (`464a3aa`)
  - MT2, the matte end to end over MCP (`bead60f`)
  - MT3, nests, dissolves, shadow, reflection, Preview Quality, every export (`763cbd1`)
  - MT4, the chrome (`8843261`)
  - MT5, documents, the spike against the tree, the close (uncommitted when this was written)
- **Original:** `archive/mattes.md` (548 lines) is the full record. It has no section numbers, so it is cited by phase: "orig MT2" is its "MT2" section.
- **Spec decisions:** MT-1..MT-7 in spec §11 (`designs/spec/11-decisions/mattes.md`). They stay binding, and where the original words them differently, §11's text wins:
  - MT-1: a track's `matte` is `none`, `alpha`, `alpha_inverted`, `luma` or `luma_inverted`, set by `set_track {matte}`. A matte track's clips are never drawn; any clip that draws can be one. `tracks[].matte` is written only when not `none`; format 14, no migrate step.
  - MT-2: a matte cuts the track directly behind it in its own container, unless that track is a matte; with no target it cuts nothing and still draws nothing. Where it shows nothing, the track behind shows uncut. Read per instant, so no edit can break a link. Its clips still sound.
  - MT-3: the four modes over the matte's premultiplied composite in encoded sRGB (Rec. 709 luma); the value multiplies the matted layer's coverage at step 7, so the matted clip's shadow and reflection are cut too, and a dissolve on one matted track stays exact under a soft matte.
  - MT-4: a matte clip's placement, crop, opacity, colour, filters, actions and transitions shape the matte; its blend, shadow and reflection do nothing (the core's second override of model values).
  - MT-5: mattes in nests — the first matte level outward is where a layer draws; a group is keyed by the enclosing nest-clip path and the matte track's id; `nest` and `unnest` carry a matte only with its target and invert each other.
  - MT-6: the matte pass runs before the destination pass; one r8 coverage per cut set at `texture(1)`; an unmatted layer binds the 1×1 white placeholder.
  - MT-7: the chrome — Track ▸ Matte and the track context menu's submenu, the header tag, the half-opacity dashed lane and its bracket, the Clip tab's note, the canvas hit.

## Context

#240 asked for two things: a matte, and video as an input to a graphic. The owner chose the matte alone on 2026-10-07 (seven choices, orig "The owner's choices") and split the video input out to #251, iceboxed. The matte was to be a TRACK switched to "matte for the track below", any drawing clip a matte, all four modes, the track below uncut where the matte has no clip, and a matte clip's blend, shadow and reflection inert. Ten design questions (O1–O10) were answered on 2026-10-08, all as recommended. Road map 10 had already said "mattes are compositor features" (`designs/adr/svg-motion-plan.md`), so these are MT- decisions, not G- ones. Three files over the size rule (`recipe.rs` 596, `Compositor.swift` 1396, `ProjectSnapshot.swift` 2182) paid their tolls before anything was added (orig MT1).

## Decisions

- **The route was measured before it was built.** MT0's spike patched the shader at anchors asserted to occur once and timed two routes for an unmatted layer: V1, a 1×1 white placeholder at `texture(1)`, and V2, a `kMatte` function-constant specialization. V1 won by the rule written beforehand (S1 overhead within its bound plus a V0-against-V0 noise floor at both sizes), though V2 was faster at 4K. That cost is MT-6's accepted risk: one pipeline per layer specialization, not two. (orig MT0)
- **Every layer on a matte track carries a non-null `into`, listed or not.** Swift skips every such layer on the canvas and draws it into a target only for a listed group. Without this, a matte with no target had no way to say "not drawn". (orig MT2)
- **A level's cut is asked before its own matte test.** So `matte_target` is the one place that says a matte track is nobody's target. The other order made MT-2's "unless that track is a matte" clause redundant, and the mutant for it could not be killed. (orig MT2 "Mutants", deviation 1)
- **A cut naming a matte not yet drawn fails the frame** (`MatteError.unordered`), and every matte throw happens before its encoder opens. Drawing the layer uncut hid a core defect, and throwing with the resolve's encoder open killed the Debug app on a Metal assertion. A correct core never asks for this. (orig MT2)
- **A group member is drawn the way `render` draws a layer** (shadow, reflection, layer, `texture(1)`), not by a bare draw. This leaves the core's MT-4 override as the only thing that turns those off, so the mutant that drops the override can be caught. (orig MT2, deviation 3)
- **`unnest` counts depth from the nest's front-most NON-matte track.** Counting from the front-most track broke nest-then-unnest for a matte pair. `nest` carries a matte only when the nested track behind is the copy of its target. (orig MT3)
- **The dissolve's outgoing half weighs its partner's cover by its own coverage.** On one matted track both halves read the same coverage, so the pair composites to m·mix(out, in, p) + (1 − m)·bg under a soft matte as under a hard one. An unmatted layer reads the placeholder's exact 1.0, so no unmatted picture moved. (orig MT3)
- **The chrome's tag is placed by the row's geometry** (its own line when there is room above the toggles), and on a Small name line it reads "Matte" alone when the full words would leave the name under 40 pt. Its words are the primary label colour over an accent tint, never the accent: on most accents the owner can pick, accent text measured under 3:1. (orig MT4, its two fix passes)
- **The screen is `10c-matte-track`, not `17-…`**, because the recorder panel must be the catalog's last screen. (orig MT4 "Deviations")

## What it built — where it lives now

- Core: `model_matte.rs` (45; `TrackMatte`), `Track.matte` in `model.rs`, `set_track`'s `matte` (`edit_track.rs`, `op_table.rs`'s `Kind::Matte`), `recipe_matte.rs` (219; `matte_target`, `MatteKey`, `frame_mattes`), the 21st layer key in `recipe_layer.rs` (98, out of `recipe.rs` in MT1) and the recipe's `mattes`, `edit_nest.rs`'s carry and front-track rules (366). `RC_FORMAT_VERSION` 14. Tests: `core/tests/matte.rs`, `matte_nest.rs`, `schema_v14.rs`.
- App: `TrackMatte.swift`, `FrameRecipe.swift` (334, out of `ProjectSnapshot.swift` in MT1), `Compositor+Matte.swift` (272; `encodeMattes`, `MattePool`, the resolve), `Compositor+Shadow.swift` (out of `Compositor.swift` in MT1), step 7c and `reelcut_matte_resolve_fragment` in `Compositor.metal`; the chrome in `TimelineView+Matte.swift`, `ClipPane+Matte.swift`, `EditorViewController+Matte.swift`, `TimelineView+TrackMenu.swift` and `AppDelegate+Menus.swift`; `set_track`'s handler and catalog entry.
- Proofs: `tools/proof/matte_spike/` (MT0; `--tree` since MT5), `matte_proof.py` (MT2–MT3: 36 rows over MCP, every export), `matte_probe.py` (Preview Quality), `matte_chrome_probe.py` (the chrome), `track_menu_probe.py`'s Matte rows, screen `designs/screens/10c-matte-track.md`. `tools/proof/README.md` has a section per phase.
- Person checks: MAT-1 (a matte plays, edges and a slow luma gradient) and MAT-2 (the chrome reads right) in `docs/manual-checks.md`.
- Docs: spec §4.2, §4.3a, §4.4, §5.2, §6b, §6c, §7.3, §7.4, §7.5, §7.10, §9; `docs/graphics-api.md`'s "Video inside a graphic: the matte"; the README's Looks bullet.

**Headline numbers.** The spike against the tree's own shader (`matte_spike.py --measure --tree`, 2026-10-08, Apple M2 Max, macOS 26.5.1, `powermode 0`, AC power; ms, the median of three runs' medians; noise floor 0.002 ms at 1080p and 0.001 ms at 4K):

| | 1920×1080 | 3840×2160 |
|---|---|---|
| one unmatted full-bleed layer: pre-MT2 shader → shipped shader | 0.108 → 0.120 | 0.388 → 0.442 |
| one alpha matte (S3 − S2: mask pass, resolve, sample) | 0.033 | 0.070 |
| two mattes in one coverage, with the gradient's own draw (S4 − S2) | 0.154 | 0.549 |
| memory per matte target (bgra8), per coverage (r8) | 8.3 MB, 2.1 MB | 33.2 MB, 8.3 MB |

The budget was 0.50 ms at 1080p and 2.00 ms at 4K (MT0's figures, with V1 0.014 / 0.052 ms over V0, are in orig MT0). Scores on the final instruments: `matte_proof.py` 36/36 on Release, `matte_probe.py` 4/4, `matte_chrome_probe.py` 10/10, `track_menu_probe.py` 25/25, `v2_menu.py` 28/28 on Release; 28 mutants across MT0–MT4 (2, 8, 8 and 10), all caught.

## Known limits

- **At 4K every unmatted full-bleed layer pays about 0.05 ms for the placeholder sample** (MT-6's accepted risk; 0.054 ms in the tree).
- **A nest clip's soft-edged matted layers show through each other**, the recorded limit of nest opacity (§7.3, MT-5).
- **A dissolve between two nest clips cut by different mattes** weighs the outgoing half by its own coverage, which is exact only where the two coverages agree (N7 claims channel isolation, not the weights). #252.
- **The matte pool has no cap**: each matte drawn in a frame holds a destination-sized target (33.2 MB at 4K). #253.
- **The coverage is r8.** The matte's own target is bgra8, so the luma it yields is already 8-bit and r8 adds at most one rounding (L1 holds a gradient matte to ±1). Whether that reads as banding to an eye is MAT-1.
- **Video as an input to a graphic is #251**, iceboxed; nothing here decides it.

## Open items

- #252 and #253, filed at the close, and the owner's MAT-1 and MAT-2.

## Where to look in the original

- "The owner's choices": choices 1–7 (2026-10-07) and O1–O10 (2026-10-08).
- MT0: the spike's instrument, host, full figure table, why the 1080p series did not resolve, and its two mutants.
- MT1: what moved, the widened access, before and after `wc -l`.
- MT2: the core's walk, the app's passes, both mutant passes and the two holes they found (the encoder assertion).
- MT3: the carry and unnest rules, the dissolve change, which claims moved from the proof into `matte_nest.rs`, and the eight mutants.
- MT4: the tag's placement and its two fix passes (the Small row, contrast and the accent ruling), and the four deviations.
- MT5: the spike against the tree and the "Not established" list reviewed item by item.
