# The matte track (road map "mattes", issue batch B89, #240)

- **Status:** Built and closed 2026-10-08. Each phase was one litecode pipeline with its own review:
  - MT0, the decisions and the spike (`745a36a`)
  - MT1, three pure moves to make room (`63f1524`)
  - MT2, the matte end to end over MCP (`a3c54d3`)
  - MT3, nests, dissolves, shadow, reflection, Preview Quality, every export (`a8ec753`)
  - MT4, the chrome (`b333661`)
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
- App: `TrackMatte.swift`, `FrameRecipe.swift` (334, out of `ProjectSnapshot.swift` in MT1), `Compositor+Matte.swift` (272; `encodeMattes`, `MattePool`, the resolve), `Compositor+Shadow.swift` (out of `Compositor.swift` in MT1), step 7c and `framejob_matte_resolve_fragment` in `Compositor.metal`; the chrome in `TimelineView+Matte.swift`, `ClipPane+Matte.swift`, `EditorViewController+Matte.swift`, `TimelineView+TrackMenu.swift` and `AppDelegate+Menus.swift`; `set_track`'s handler and catalog entry.
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
- **A dissolve or zoom with a nested half: fixed, MT-8** (#252, issue batch B90 phase 4). It is routed: each half drawn alone into a pool target and mixed, a zoom's halves scaled at the mix about their anchors, so a nested zoom's half is resampled once from its target. Phase 1 measured the dip (nest ↔ nest G 113 for 170, D0, and the rest in `tools/proof/README.md`); phase 4 holds every D row to the exact mix. Cost: two destination-sized targets per routed dissolve while it draws (66.4 MB at 3840×2160), one suspended pass and one full-frame draw. A timeline pair of clips that are not nest clips keeps MT-3's per-layer correction (DR exact).
- **The matte pool has no cap** (spec §11 MT-9; #253, issue batch B90 phase 3). A frame holds a composite only while a cut set still needs it, and one coverage per distinct cut set; between frames the pool keeps the most the last 30 frames held. Ten mattes in one frame, each cutting its own set, hold 116,121,600 B at 3840×2160, where MT-6's pool held 414,720,000 B (`matte_pool_probe.py` P1). Mattes that cut one set together are all live at once, and a frame that needs more targets gets them.
- **The coverage is r8.** The matte's own target is bgra8, so the luma it yields is already 8-bit and r8 adds at most one rounding (L1 holds a gradient matte to ±1). Whether that reads as banding to an eye is MAT-1.
- **Video as an input to a graphic is #251**, iceboxed; nothing here decides it.

## Open items

- The owner's MAT-1, MAT-2 and MAT-3. #252 and #253, filed at the close, are fixed (MT-8 and MT-9, issue batch B90 phases 4 and 3).

## Follow-ups (issue batch B90)

- **Phase 1, the pre-fix measurement (#252; 2026-10-08).** No product code changed.
  - `matte_proof.py` gained DR (a control) and D0–D8, one row per nested-dissolve case, D8 the zoom. Each asserts today's picture from its full formula and prints the exact mix beside it. p comes from DR or from the row's own un-nested frame, never from the row's own frame.
  - Every prediction held at the first run, with DR exact. Scores: Debug 11/11 (DR, D0–D8, Z1); `make gate` PASS; recorded on the gate's Release build, `matte_proof.py` whole 46/46 (E3 ran). The figures are in the Known-limits bullet above and in `tools/proof/README.md`'s "Mattes follow-up B90" section.
  - One mutant, `dissolve-cover-everywhere` (an outgoing half with no partner box takes its own cover), was caught: D0 D1 D2 D4 D5 D6 D7 D8 failed. Under it D0, D2, D4, D6 and D7 read the exact mix, so their dip is the missing partner correction alone.
- **Phase 3, the matte pool (#253, spec §11 MT-9; 2026-10-08).** MT-9 was recorded in spec §11 before the code.
  - `MattePlan.swift` (new, 73 lines, no Metal) plans a frame's mattes before any is drawn. Each cut set is resolved at the step that draws the last matte it names. A composite is given back once every set naming it is resolved, and a set naming a group no step draws is never resolved.
  - `MattePool` (`Compositor+Matte.swift`) lost `fit` and `composite(_:)` and took `beginFrame`, `takeComposite` (the lowest free index), `giveComposite`, `endFrame` and `held`. `endFrame` keeps, of each kind, the most any of the last `keepFrames` (30) frames held, and releases the rest. `render` brackets each frame with `beginFrame` and a deferred `endFrame`, so a frame with no matte counts as holding none.
  - `encodeMattes` runs the plan. A released composite also leaves the frame's map of drawn mattes, so a wrong plan fails the frame (`unordered`) rather than read a target another matte has drawn over. The old final loop over the canvas layers' cuts is gone, because the plan resolves every layer's set.
  - Scores: `matte_pool_probe.py` (new; no app) 4/4. P1 shows ten one-set mattes at one composite live and ten coverages: 116,121,600 B at 3840×2160 against 414,720,000 B. Debug `matte_proof.py --only A1,MM,L3,N3,N5,N7,T1,T3,S1,RF1,D1,D3,D6,E1,F1,Z1` 16/16; `matte_probe.py` 4/4; `make gate` PASS; recorded on the gate's Release build, `matte_proof.py` whole 46/46 (E3 ran). Every row and printed value matches phase 2's recorded run, so no picture changed.
  - Six mutants were caught. In `matte_pool_probe.py`: `no-release` (P1), `give-ignored`, `trim-never` and `trim-early` (P2). In `matte_proof.py`: `free-ignores-liveness` and `early-resolve` (N5; under both the frame fails, `unordered`).
- **Phase 4, the routed dissolve (#252, spec §11 MT-8; 2026-10-08).** MT-8 was recorded in spec §11, before MT-9, ahead of the code.
  - Core: `recipe_dissolve.rs` (new, 247 lines) walks each layer's levels inner to outer through `transition_among` — `recipe.rs`'s `transition_of` moved there. A `cross_dissolve` or `zoom` whose container is a nest, or one of whose clips is a nest clip, is routed (`routed`): an entry in the layer's new `dissolve` key (the twenty-second, `recipe_layer.rs`) with its kind, role, eased progress and its half's anchor, ids dense per frame, outermost first; `transition` is the innermost unrouted level; a layer drawn into a matte keeps only the levels at or inside its first matte level. `blend` is `normal` under either key. Tests: `core/tests/dissolve_nest.rs` (new, 8); `recipe.rs`'s key list (22), `nest.rs`'s inheritance test on `push_left`, `evaluate_tests.rs`'s inherited-dissolve test.
  - App: `Compositor+Dissolve.swift` (new, 190 lines) holds `encodeLayers` (the one walk over a layer list: the canvas in `render`, a group's members in `encodeMattes`), the routed draw (two halves from `MattePool`, then the seventh pipeline, `framejob_dissolve_fragment`, over the shadow's full-frame quad) and `drawLayer`, `Compositor+Matte.swift`'s `draw` moved verbatim. `RecipeLayerDissolve` in `FrameRecipe.swift`. `Compositor.swift` 1005 → 959.
  - Scores: Debug `matte_proof.py` 21/21 on the D rows and the matte rows they share code with; `matte_probe.py` 6/6 (Q3, Q4 new: the mix at Full, Half and Quarter, and the zoom's in-box where Full's is); `matte_pool_probe.py` 4/4; `make gate` PASS; recorded on the gate's Release build, `matte_proof.py` whole 46/46 (E3 ran), every D row at the exact mix (figures in `tools/proof/README.md`). The other rows read as phase 3's run did but N7, a split nest clip in a dissolve, whose halves no longer dip.
  - Twelve mutants were caught: five in the core (`routed` false, zoom unrouted, a routed level kept as `transition`, no matte-level stop, the chain inner first) and four in the app (the mix's weights swapped, one shared half target, the matte members walked plain, the zoom's scale dropped), plus three re-pinned and re-run (`source-drawn`, `reflection-placeholder`, `core-no-override`). Phase 1's `dissolve-cover-everywhere` is retired: no D row reaches that term now.
  - Person check: MAT-3 (`docs/manual-checks.md`), a nested dissolve and zoom at 4K, Full and Quarter.

## Where to look in the original

- "The owner's choices": choices 1–7 (2026-10-07) and O1–O10 (2026-10-08).
- MT0: the spike's instrument, host, full figure table, why the 1080p series did not resolve, and its two mutants.
- MT1: what moved, the widened access, before and after `wc -l`.
- MT2: the core's walk, the app's passes, both mutant passes and the two holes they found (the encoder assertion).
- MT3: the carry and unnest rules, the dissolve change, which claims moved from the proof into `matte_nest.rs`, and the eight mutants.
- MT4: the tag's placement and its two fix passes (the Small row, contrast and the accent ruling), and the four deviations.
- MT5: the spike against the tree and the "Not established" list reviewed item by item.
