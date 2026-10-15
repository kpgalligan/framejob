# Spec §11 — decisions: Grading tier 4 (road map "grading-4")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is in progress at `designs/grading-4.md`; its own sections hold each
phase's record (T4-0 the road map, these decisions and the pure move; T4-1 the scopes; T4-2 the
hue curves and the curve editor's extras; T4-3 curves of different counts; T4-4 the qualifier's
cleanup blur; T4-5 the close). The IDs continue the GR- series of [`grading.md`](grading.md),
[`grading-2.md`](grading-2.md) and [`grading-3.md`](grading-3.md), so a citation never has to say
which file. GR-24…GR-30 were recorded in T4-0, before any tier-4 code, from the owner's answers of
2026-10-14 to the tier-4 brief's choices, every one the recommended answer
(`designs/grading-4.md`, "The owner's choices"; the brief is
`~/.claude/litecode/reelcut/grading-tier4/I-grading-tier4.md` and the answers `answers.md` beside
it, outside the repo). T4-1…T4-4 each record their numbers as a new entry (GR-31 on) or as
Amended-by lines before their code.

**Stands, and nothing here re-litigates it:** R5-1 (closed vocabularies, never a runtime);
PR-1…PR-12; MT-1…MT-9; GR-1; GR-3 (blending stays encoded); GR-6 (the blur FILTER on an
adjustment clip stays refused); GR-10…GR-23 except as amended below and by the phases.
**The Concat rule** (`designs/adr/effects-survey.md`, "Licensing") stands for every phase: the
scopes' maths stays the Rec. 709 Y′CbCr matrix (ITU-R BT.709-6), the hue curves' spline is
Fritsch and Carlson (1980) with its secants wrapped, and the selection's blur is a Gaussian;
nothing of Concat is opened, at design time or build time.

- **GR-24 — Tier 4 builds five extras and closes four.** Choices 1a, 3a, 5a, 6a, 8a and 9a
  (owner, 2026-10-14). Each build is as the brief's §0 chose it:
  - **T4-1, #265 — vectorscope zoom:** ×1, ×2 and ×4, counted at the zoom (`bin = 128 +
    round(255·zoom·c)`), not drawn larger: a one-level cast is half a bin at ×1, which a larger
    drawing cannot show, and at ×4 it moves 2 bins. At zoom > 1 an off-plot pixel is not
    counted (clamped to the edge it measured 1.67 ms at ×4 on a gradient and piles a false
    ring on the rim). The JSON gains `zoom` and `off_plot`. The six 75 % targets show as rim
    ticks toward them, since none fits from ×2; three cells "1× 2× 4×" sit in the square's
    bottom-right corner. The zoom is per slot, per window, not persisted, ×1 when a project
    opens (GR-10's rules for the slot picks). `render_frame {vectorscope_zoom}` takes 1, 2 or 4
    and refuses anything else by name. No format change.
  - **T4-2, #267 — hue curves:** Hue vs Hue and Hue vs Sat, the picker Master · Red · Green ·
    Blue · Hue · Sat, weighted by GR-13's chroma guard so a grey is never tinted; Hue vs Luma
    not now. With them #270's hover readout and ⇧ axis lock.
  - **T4-3, #271 — curves of different counts:** a channel whose two ends are non-identity
    curves of different counts is `(1−t)·a(x) + t·b(x)`, exact at both ends; no spline in Rust,
    no FFI, no format change; same-count actions keep §5.4's per-point lerp, so every existing
    render stays byte-identical. The issue's resampling is not built: measured, it moves the
    curve at the action's start (median 27.7 ten-bit levels, max 775, on 1,000 random 3 → 5
    rising pairs).
  - **T4-4, #268 — the qualifier's cleanup blur:** `video.qualifier.blur` at full resolution;
    0 is today's path, byte-identical; only q is blurred, never the matte coverage. GR-6 is
    unchanged: a blur of the selection is a key inside `video.qualifier`, not the blur filter
    GR-6 refuses.
  - **Closes:** GR-27…GR-30.
  - Risk accepted: no real footage has been graded yet, so every strength this tier adds is a
    first number, judged by GRD-11, GRD-13 and GRD-14.
- **GR-25 — Tier 4's working arrangement: each phase merged into main alone, main's numbers, no
  verdict phase.** Choice 11 (owner, 2026-10-14). GR-14 and GR-17 again: the worktree
  `~/devel/framejob-grading4` on branch `grading-4`; each phase merged into main alone after its
  `make gate`. Main's next format numbers (20 for T4-2 and 21 for T4-4 at T4-0) and main's next
  GR IDs, each renumbered before a merge if main moved. No verdict phase: each phase is kept when
  its proofs pass. Synthetic fixtures now; the GRD rows wait for real footage.
- **GR-26 — A flat saturated colour is GR-10's sixth timed fixture, and a non-central
  vectorscope bin shared by a whole SIMD group is added once.** Choice 2 (owner, 2026-10-14).
  - **Why:** a flat (0.8, 0.1, 0.1) frame puts every pixel in one bin outside the central
    64 × 64, so every pixel is one global atomic on one counter, the contention GR-10's counting
    rule exists to prevent. The shipped `framejob_vectorscope_bin` measured 7.29–7.33 ms at 4K
    on it, and 0.281–0.282 ms with the same-bin add (`simd_all`, `simd_sum`), its counts equal
    to the per-pixel kernel's (the tier-4 brief's §2 and §12; a scratch bench, M2 Max, a loaded
    host). GR-10's five fixtures have no flat saturated colour, so its T1 never met the case,
    which a solid-colour slide or title reaches in ordinary use.
  - **The bound** holds over the six fixtures at every zoom (GR-24's T4-1).
  - **When:** the code and the app-pass T1 land in T4-1.
  - Risk accepted: until T4-1 lands, the shipped kernel misses the bound on that fixture (one
    phase).
- **GR-27 — An Offset wheel is not wanted: #266 closed.** Choice 4a. Its master is Color's
  Brightness, Temperature and Tint already shift every level, and a fourth disc squeezes the row
  past the master field at the 280 pt pane.
- **GR-28 — A qualifier on picture clips is not wanted: #269 closed.** Choice 7a. A clip holds
  one grade, so a qualifier there would limit its only grade; Insert ▸ Adjustment Clip is the
  secondary.
- **GR-29 — 1,024-level scopes are not wanted: #273 closed.** Choice 10a. About 2.5 levels per
  drawn pixel, the 16-bit-float compositor never quantizes a grade, and `render_frame`'s PNG is
  already 16-bit for a deep source (PR-4).
- **GR-30 — A histogram behind the curve plot is not wanted: #270's first item closed.** Choice
  8a. The tap sees the frame after the curve, so it moves as the curve is dragged.
