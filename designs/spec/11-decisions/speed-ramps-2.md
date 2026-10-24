# Spec §11 — decisions: Speed ramps, Keep pitch in rate mode onward (road map "speed-ramps", #111)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SR- series of [`speed-ramps.md`](speed-ramps.md), so a citation never has
to say which file; that file names the condensed record and the original, and what stands
beneath every SR- decision. This file is new because `speed-ramps.md` reached the spec's
~500-line split rule at the road map's close (2026-10-24); the entries moved here unchanged.
SR-13, the Keep pitch mechanism the owner chose on SR1d's diagnostic STOP (2026-10-23), SR-14,
the fourth spike's rule, and the Amended-by lines on SR-6's keep-pitch arm and on SR-8 were
recorded in SR1d before its code and its measured run, whose `results.json` pins the SHA-256 of
`speed-ramps.md` as it then stood, holding SR-1…SR-14. SR-15, the owner's acceptance of that
run's STOP (2026-10-23), with SR-11's lifted-by line and SR-12 (i)'s Amended-by line, was
recorded after the run and before the product switch it allows. SR-16, SR1e closed as measured
on the owner's answer to its diagnostic STOP (2026-10-23), with SR-15's Amended-by line, and
SR-17, the instrument rule that trims a corrected playback tap rather than zero-padding it, with
SR-7's PT1 Amended-by line, were recorded in SR1e before its instrument code; SR1e has no
measured run, so nothing pins a SHA-256 again. SR3 is split in two: SR3a (the trims, roll, slip,
the splitters, freeze and the handle transition, the road map's F–K) recorded SR-18 and SR-10's
Amended-by line before its code; SR3b (L and M) recorded SR-19 and the Amended-by lines on SR-10
and SR-18 before its code. SR4 (Swift's mappers, the road map's N and O) recorded SR-20 and the
road map's Amended-by lines on N and O before its code. SR5 (the UI, the road map's P and Q, and
#338) recorded SR-21, SR-22 and the Amended-by lines on SR-19 (i), on rule Q and on CI-6 before
its code. A later change records its rule as a new entry in
[`speed-ramps-3.md`](speed-ramps-3.md) (SR-23 on) or as an Amended-by line, before its code.

- **SR-13 — Keep pitch on is Apple's time-pitch unit in RATE mode, its rate commanded a measured
  lead ahead: SR-6's arm plus the lead, for ramps and held spans alike; it supersedes SR-8 whole.**
  The owner's answer to SR1d's diagnostic STOP (2026-10-23, "Rate mode + 60 ms lead"), quoted in
  the road map; SR-6's keep-pitch-off arm, the file, the cache and SR-3 stand.
  - **Feeding.** `AVAudioSourceNode` → `AVAudioUnitTimePitch` (pitch 0, the default overlap) →
    the main mixer, in `AVAudioEngine`'s offline manual rendering at 48 kHz (at most 4 096 frames
    a call). The source is fed as is, sequentially, from ⌊p(0)⌋ − P, P = 4 800 frames, a position
    before frame 0 read as zero.
  - **The rate.** Before each 256-frame `renderOffline`, with n = rendered − round(P / r(0)), the
    unit's rate is (p̃(n + L + 256) − p̃(n + L)) / 256 clamped to 1/32…32, p̃ being p extended
    before 0 at r(0) and past the end at the last breakpoint's slope, and L =
    `RampAudioRenderer.rateLeadFrames` (output frames), the lead SR-14's sweep picks.
  - **Discard.** The first round(P / r(0)) + the unit's reported latency output frames are
    discarded, so kept frame 0 is p(0).
  - **The bound is 1/32…32.** It contains every rate a ramp sounds at (the ×0.1 floor, and the
    ×12 peak above which the plan leaves the audio out, #190), so Keep pitch holds the source's
    pitch everywhere: SR-8's ±2400-cent clamp and its tape excess past ×0.25–×4 are gone.
  - **Held spans** render through the same arm. Once SR-14's run answers GO, keep pitch on
    renders the whole map through it and the plan's `glide` spans are ignored (SR-11 lifted); the
    core still writes `glide` and the cache key still names it, a harmless redundancy.
  - **Why:** SR1d's diagnostic (the road map's SR1d record) found SR-8's dropouts are the unit's
    own in pitch mode: one at each crossing of an 11.7 Hz analysis bin (FFT 4096 at 48 kHz) by a
    gliding partial — RK1's 17 crossings gave 17 dropouts, and no block size, flag, smoothness or
    K removed them — while the unit in rate mode gave none. SR1b's rate-driven arm misplaced
    clicks only because its rate was read at n while the unit's window follows behind it; read
    60 ms ahead, RK1's placement max was 8.86 ms (71/71 found) and RK2's 2.92 ms (23/23), with 0
    dropouts, inside SR-7's ceilings (17.60 and 19.14 ms). Apple's other unit (`AUTimePitch`,
    'tmpt') was not taken: its latency moves with the pitch and its timing jitters 7–15 ms. Still
    Apple's algorithm (SY-41: no own time-stretch).
  - Risk accepted: **the lead rests on Apple's unpublished internal behaviour** — a macOS change
    to the unit's window could move it — so `ramp_proof.py`'s L1 and L2 (Release, no spike) pin a
    Keep pitch ramp's placement under ceilings from SR-14's run and fail when the lead stops
    fitting. **The constant-rate finding:** SR-8's arm dropped out on gliding content at CONSTANT
    rates too (18 dropouts at ×2 on a 220→440 Hz sweep, where the composition's `spectral` gave
    0), and so did SR2b's held spans until this phase. One lead serves every map; keep pitch on
    stays measured against controls, never claimed sample-exact.
- **SR-14 — The fourth spike's rule (SR1d), fixed before its run: the lead swept first, then
  SR-7's arm ON over RK1, RK2 and a held-out RK3, SR-9's pitch rows under the rate-mode command,
  and a gliding fixture's dropouts, with a verdict for arm ON alone.**
  `tools/proof/ramp_spike/render_spike.py --lead-sweep`, then `--verdict rate` with `--variants
  RK1,RK2,RK3,RC-on-x0.5,RC-on-x0.9,RC-on-x1.1,RC-on-x2,C-on-x0.5,C-on-x0.9,C-on-x1.1,C-on-x2,
  RC-off-x1,RC-on-x1,RC-on-x3,RC-on-x6,RC-on-x0.2,RB-on-x2,RW-on-x0.9,RW-on-x1.1,RW-on-x2`, every
  group, through SR-7's instrument.
  - **The lead, first.** A render-only sweep over L ∈ {0, 2, …, 100} ms (round(L · 48) output
    frames): RK1 and RK2 rendered from the clicks fixture into the work folder's `lead/`, each
    render's clicks placed against the ideal map by SR-7's keep-pitch method (the template
    unscaled), reading found, of and max |diff|. Only a lead at which BOTH ramps find every click
    (found = of, of > 0) is eligible; L* is the eligible lead minimising the greater of the two
    maxima, a tie going to the smaller lead. No eligible lead is a STOP (`STOP — lead: no lead
    finds every click`). Each ramp's own best lead is reported. Per K is not applicable: there is
    one rate, 48 kHz. L* is written into `rateLeadFrames` before the measured run.
  - **Variants.** SR-9's, unchanged, plus RK3 (keep pitch on, ×2 → ×0.5 ease in-out over 1–3 s,
    8 s; rendered and staged as RK1 is, its frames read in playback, its end-rate controls
    RC-on-x2 and RC-on-x0.5), which the sweep never renders, so the lead is not fitted to
    everything scored; and RW-on-x0.9, RW-on-x1.1, RW-on-x2 (keep pitch on, constant, 6 s),
    rendered only, from `glide.wav`: 20 s, 48 kHz, mono, amplitude 0.5, phase-continuous, 220 Hz
    to 2 s, an exponential sweep to 440 Hz at 4 s, then 440 Hz — the content that made SR-8's
    held spans drop out.
  - **Scoring.** SR-7's arm ON rule unchanged over RK1, RK2 and RK3 — placement against their
    RC-on end-rate controls, click, dropout and video in export and in playback, plus agreement —
    and each RC-on anchor's placement against its C-on control in export and in playback. **Pitch**
    is SR-9's with c the rate-mode command, c = clamp(−1200 · log₂ r, ±6000) cents (the rate's
    1/32…32 bound), so f_e = 220 Hz at every rate a variant sounds: PR |median cents| ≤ 25 for
    RK1, RK2, RK3 and each RC-on anchor, and LG RMS at the best τ ≤ 25 for RK1, RK2 and RK3.
    **The sweep:** each RW-on-* render shows no dropout by SR-5's (a) and (b), its local period
    1 / glide_hz(1 + r · t) s, glide_hz the fixture's frequency at source second 1 + r · t. A rule
    not measured fails.
  - **The template.** SR-7's unscaled template stands: SR1c's slowed-click problem does not
    arise in rate mode (SR1b's rate-driven RC-on controls found 15/15 at ×0.5), and RC-on-x0.5's
    anchor row confirms it in this run.
  - **Instrument checks** (exit 1, nothing judged): as SR-9 — Z0, every render answered, R44
    refused as `unreadable`, ID1, PT1's tap called. **Off-arm identity**, before the measured run:
    a render-only run of RV1, RV2, RV3, RF1, RV1-edit and RC-off-*, both fixtures, each CAF equal
    byte for byte to SR1b's (`ramp-render-spike-sr1b/renders/`), or the phase stops.
  - **The verdict**: `VERDICT: GO — arm ON (rate) …` when nothing above fails, else `VERDICT:
    STOP — <each failing variant and rule>`. GO lifts SR-11 (SR-13); a STOP lands nothing and goes
    to the owner with the measurement.
  - Reported, not scored: RS (render seconds per audio second, bytes, peak RSS, the lead, the
    unit's reported latency, and pulled − map frames, the map frames read from the variant's
    map); RP-<name>; PR-<name> for every keep-pitch sine render (RC-on-x0.2 and RC-on-x6 now
    expect 220 Hz) and PR-source; LG-RK1…RK3; BW-RB-on-x2; RW-<name>'s dropout events; the
    sweep's table; SR-7's other rows.
  - **Why:** the lead is a fitted constant, so it is fitted first, on two ramps only, and the
    rule then judges it on a third ramp it never saw and on constant renders of a gliding source,
    the case the diagnostic found SR-8 failing at constant rates; SR-9's pitch rows still apply
    because keeping the pitch is the point, and the rate-mode command makes their expectation the
    source's own 220 Hz.
  - Risk accepted: the fixtures stay synthetic (a click train, one sine, one sweep), so whether a
    ramp sounds right is a person's check (SR5); one lead is fitted for every map, so a ramp much
    steeper than RK1–RK3 is judged only by L1 and L2's ceilings after the switch.
- **SR-15 — SR-13's arm lands with L* = 56 ms though SR-14's run stopped: a deep slow-down plays
  up to about 22 ms late, accepted by the owner as a known limit until SR1e.** The owner's answer to
  SR1d's measured STOP (2026-10-23, "Land it, then tighten"), quoted in the road map; SR-14's text
  and its verdict stand as recorded.
  - **What lands.** Keep pitch on renders every ramped clip through SR-13's arm at
    `rateLeadFrames` = 2 688 (56 ms, the sweep's L*), ramps and held spans alike: SR-11 is lifted,
    `+Hybrid` is deleted, `RampAudioRenderer.version` is 4.
  - **The limit, measured.** RK3 (×2 → ×0.5 ease in-out over 1–3 s), which the sweep never saw,
    placed its export clicks up to 22.10 ms from the ideal map against SR-14's ceiling of 19.14 ms
    (RC-on-x0.5's 14.14 + 5.0): −1.7 to +12.9 ms through the ×2 head, climbing through the
    slow-down, +18.2 to +22.1 ms late through the held ×0.5 tail, where a constant ×0.5 render sits
    12.6 ms early — the unit about 33 ms behind after a ×4 slow-down, which one constant lead cannot
    correct. RK1 (8.06 ms against 17.60) and RK2 (5.55 against 19.14) passed, with no dropout and
    every pitch reading within 0.01 cents of 220 Hz.
  - **The run's playback failures are the instrument's.** That session's ×1 tap read 86.333 ms
    early (#335), so PT1's correction moved every corrected playback signal 4 144 samples later and
    its first 86 ms are zeros: SR-5's dropout rule (b) reads them as a dropout at 0.05 s, and a
    click expected at 0.050 s is matched to the onset at 0.086 s (36.3 ms). RC-off-x1, a keep-pitch-
    off ×1 render, showed the same 0.05 s "dropout"; so RK1's, RK2's and RK3's playback dropouts,
    RC-on-x2's playback anchor and RK3's agreement are not the arm.
  - **The guard.** `ramp_proof.py`'s L1 (RK1) and L2 (RK2) hold a Keep pitch ramp's export under
    SR-7's floor and ceiling from that run's export controls; L3 holds RK3's case under its measured
    worst plus a stated margin, so a macOS change to the unit that moves the lead fails a Release
    row rather than passing unseen.
  - **SR1e follows**, in its own handoff: a closed-loop correction that steers the rate from how
    much source the unit has actually consumed, so the lag cannot accumulate; if it passes, it
    replaces the constant lead and L3 tightens to SR-7's ceiling.
  - **Why:** the owner judged a ≤ 22 ms lag after a deep slow-down, with the pitch kept and no
    dropout, better than SR-11's tape glide inside every Keep pitch ramp.
  - Risk accepted: a Keep pitch clip that slows hard plays its audio up to about 22 ms behind its
    picture after the slow-down, until SR1e; a ramp steeper than RK3 may lag more, and only L3's
    pinned case is guarded.
  - *Amended by SR-16 (SR1e):* SR1e did not tighten, and the 56 ms lead stays. The limit, as SR1e
    measured it at 56 ms (render-only): ×2 → ×0.5 linear (H7) and ease-out (H8) over 1–3 s read
    22.47 and 23.90 ms against SR-7's 19.14 ms, and RK3 reads 22.10. ×4 → ×1 linear over 1–3 s
    (H3) finds 44/70 clicks. SR-7's reach there is 20 ms (0.4 × the 50 ms click spacing at ×4),
    and the constant ×4 render sits at that edge (92/95, max 21.00 ms). The loss depends on the
    lead (68–69/70 at 46–52 ms, 42/70 at 53, 44/70 at 56) with the same template on the same
    content, so it is the render's output at that lead, not the template failing on ×4 content.
    The diagnostic does not separate misplacement past 20 ms from a smeared click found at r < 0.5,
    so about 26 of H3's 70 clicks are **unmeasured**: each either more than 20 ms off or found at
    r < 0.5, and the diagnostic does not say which. ×3 → ×0.5 linear over 0.5 s (H5) drops out
    once (1.452 s) with a 150-cent window at both 50 and 56 ms: the unit's own behaviour, which
    SR-15's "no dropout" did not cover. L3 stays the one pinned case.
- **SR-16 — SR1e closes as measured: the 56 ms lead stays, no closed loop and no re-fit lands, and
  product behaviour is unchanged.** The owner's answer to SR1e's diagnostic STOP (2026-10-23,
  "Keep 56 ms, close SR1e"), quoted in the road map: `rateLeadFrames` stays 2 688,
  `RampAudioRenderer.version` stays 4, no product code changes; SR-13's mechanism and SR-15's
  acceptance stand, SR-15's risk line widened by its Amended-by line.
  - **The diagnostic** (render-only, a scratch probe of SR-13's `renderTimePitch` loop compiled
    from b4b63c9's `app/Sources` with `-O`, scored by SR-7's reach and edge rules, `ramp_spike`'s
    dropouts and `render_spike.pitch_track`, imported unchanged; not run under a SHA-pinned rule).
    Its sources are at `~/.claude/litecode/framejob/speed-ramps-sr1e/diag/` (`main.swift`,
    `build.py`, `run.py`, `look.py`, `dlag.py`, `tail.py`, `series.py`, `grid.py`, `ilc.py`); their
    `H` names that session's scratchpad, where the outputs went. **The replica is exact**: at
    56 ms it reads RK1 71/71 max 8.06 ms, RK2 23/23 5.55 ms and RK3 35/35 22.10 ms, SR1d's measured
    run to the hundredth.
  - **The look-ahead.** At a constant rate the unit pulls exactly r × 256 frames a block, and
    fed − p(output) holds constant: 3 264, 3 456, 3 840, 5 632, 7 424 and 9 216 frames at ×0.25,
    ×0.5, ×1, ×2, ×3 and ×4, which is A(r) = 3 072 + 768·r for r ≤ 1 and 2 048 + 1 792·r for
    r ≥ 1, exact at constant rates and the same on either fixture. **While the rate moves it pulls
    on its own**: RK3 at lead 0, commanded r(n) exactly, climbs from 5 632 to 6 718 (+1 086 frames
    beyond the command, in lumps). **What it pulls depends on the content**: the same map and
    commands pull 512 frames apart on the clicks and the sine by RK3's end, 768 on the dip (H2).
  - **Consumed input does not fix placement; it is path-dependent.** In the held ×1 tail, X1
    (constant) has fed − p 3 840 and places at 0.00 ms; the dip at 56 ms 4 896 (+1 056) and
    0.00 ms; the dip with a loop holding fed at p + A(r) 3 837 (−3) and +20 ms (17–23). RK3's ×0.5
    tails follow no one curve: lead 0 excess +3 262 at −41 ms, the loop 0 at −5 to −8 ms, lead 56
    −759 at +20 ms, the ×0.5 control 0 at −12 ms.
  - **The controller fails.** Target fed(m) = p(m + tl) + A(r(m + tl)), a proportional correction
    cmd = ff + (need − ff)·256/horizon bounded to ±bound × ff, ff = r(n + lead); swept horizon 5,
    10, 20, 40, 80, 320 ms, bound 0.1, 0.25, 0.5, feed-forward lead 0, 28, 56 ms and tl 0, 28,
    56 ms. Its best rows (max |diff| ms, RK1 / RK2 / RK3 / H1 / H2 / H4 / H5), against the
    product's 8.06 / 5.55 / 22.10 / 20.56 / 2.08 / 14.14 / 27.54: h 20 b 0.25 ff 28 16.02 / 14.06
    / 18.54 / 27.66 / 33.44 / 35.48 / 26.62; h 40 b 0.1 ff 0 14.86 / 14.61 / 20.05 (34/35) / 26.68
    / 55.96 / 24.99 / 25.68; deadbeat h 5.3 b 0.5 ff 0 16.86 / 14.19 / 20.08 / 27.66 / 55.23 /
    33.96 / 26.16. It fixes the ×2 → ×0.5 tails (RK3, H7, H8 end within 0–2 ms) and costs
    everything else; every loop row rides its bound, 10–25 % around the map's rate, and tl > 0
    makes every row worse (RK1 29–41 ms, RK2 42–60 ms).
  - **The oracle loop does not converge.** The true click error of each pass, warped into the map
    as r·e·48 source frames at 56 ms, over passes 0–3: RK1 8.06 → 5.44 → 18.31 → 21.97; RK3 22.10
    → 19.06 → 17.86 → 21.90; H5 27.54 → 27.67 → 27.67 → 27.67 (≈ 27.6).
  - **The re-fit, not taken.** SR-14's sweep rule over RK1, RK2 and RK3 together (2 ms grid, every
    click found, minimax, a tie to the smaller lead) picks 50 ms (2 400 frames), minimax 11.38 ms,
    with every held-out shape H1–H8 under its SR-7 ceiling; RK3 is flat at 11.38 ms over 46–52 ms
    and meets a cliff at 53 (15.01, then 22.10 at 56, 36.60 at 60). The owner chose not to take it.
  - **The guard: no new `ramp_proof.py` L row.** H7 and H8 are the same deep ×2 → ×0.5 slow-down
    L3 already pins: at 53 → 60 ms all three move together across one cliff (RK3 15.01 → 36.60,
    H7 14.30 → 33.81, H8 14.09 → 33.94), so L3 already fails when they would. H3's 44/70 is below
    any found floor an L row can hold.
  - **Why:** the closed loop the request named cannot pass on this unit (its consumed input does
    not fix where its output sits), and the owner judged the measured 56 ms limit acceptable
    rather than re-fitting a constant that sits 3 ms from a cliff.
  - Risk accepted: SR-15's, as widened by its Amended-by line — a deep slow-down plays up to about
    24 ms late, a ×4 → ×1 ramp's placement is partly unmeasured, a 0.5 s ×3 → ×0.5 slow-down (H5) can drop out
    once; only L3's case is pinned.
- **SR-17 — A corrected playback tap holds only the samples the tap carried: the whole-sample
  correction trims, never zero-pads.** The instrument rule for #335's artifact, fixed in SR1e.
  - **The rule.** PT1's correction by k = round(m1 · rate / 1000) samples cuts off the head
    (k < 0) or the tail (k > 0) that a shift would zero-fill. Every SR-5/SR-7 rule reads the
    trimmed window as the signal's extent, with its own edges: EDGE_SKIP_S for placement, the
    50 ms dense-scan and dropout edges. A click expected outside the window is **unobserved**, not
    missed: it is out of the found share, counted apart, and agreement still pairs by index. k = 0
    is unchanged.
  - **Where.** PT1, every corrected playback signal in `render_spike.py`, and `ramp_proof.py`'s
    P1.
  - **Why:** SR1d's m1 of −86.333 ms zero-filled every corrected playback signal's first 86 ms,
    which SR-5's dropout rule (b) read as a 0.05 s "dropout" and placement matched to a 36.3 ms
    miss, out of zeros (SR-15).
  - **Shown by** `render_spike.py --selftest`'s S22 (a synthetic ±86.333 ms tap, trimmed and
    padded) and the mutants `trim-off` and `window-off`. No measured re-run: the selftest
    reproduces the −86.333 ms case synthetically, and SR-14's text and SR1d's `results.json` stand
    as run.
  - Risk accepted: clicks in the trimmed span plus its edge go unscored.
- **SR-18 — Edits on a ramped clip (SR3a): the window measured through S, the head at the base
  rate, a split's halves meeting at S(cut).** The road map's F–K, as built; L and M are SR3b's.
  - **(a) S∞.** Past a clip's end the map reads on with the clip's own actions: an action running
    past the end keeps ramping, otherwise the last rate holds — H's "tail at its last rate". It is
    how `trim_end`, `roll`'s predecessor and the tail handle measure (`source_length_on_timeline`,
    `longest_duration_on_grid`, `latest_end_on_grid`). S∞ is monotone, so each is closed form
    through `time_for_source` (S∞⁻¹, floored, over a horizon past the file).
  - **(b) The head reads at the base rate.** `trim_start`'s extension, `roll`'s target and the
    transition head all read at it (`source_head_on_timeline` is unchanged). `add_transition`
    already rebases the incoming clip's actions by the head, so its out point stays.
  - **(c) Trims and roll hold the out point's fit.** `trim_start` and `roll`'s target keep their
    actions in clip time: `in` advances by round(S(Δ)) when the edge moves in, and moves back at
    the base rate when it moves out (`source_advanced_through`). When the resulting out point
    would pass the file, the edge clamps through `front_edge_held`: a bisection over the grid
    positions from the asked edge back toward the clip's start, because the fit is not monotone
    in the edge. A gesture clamps; it never refuses.
  - **(d) `slip`** converts its delta at the base rate and clamps at `file − S(D)`. No code
    changes.
  - **(e) `split`, and every splitter: the halves meet at in + round(S(cut)), for every curve.**
    The second half's `in` is `in + round(S(cut))`, and its `speed` is `rate_at(cut)`. A
    straddled speed action's head ends at the cut (an action never runs past its clip:
    `add_action`/`set_action` refuse it, `frame_grid.rs` clamps it), keeps its curve, and its
    `end.speed` is `head_end_rate(action, cut)` = r_from + (r_to − r_from)·E(c)/(c·E(1)), the
    closed form of R1's affine solve, so the first half reads exactly S(cut). For `linear` and
    `ease_in` that equals `rate_at(cut)`; for `ease_out` and `ease_in_out` the rate steps at the
    cut from the head's end rate to the second half's `rate_at(cut)`: the source position is
    continuous, the rate is not. The head's other end keys keep `narrow_to`'s value at the cut.
    The tail keeps the original end and curve from `rate_at(cut)`: exact when the curve is
    `linear` or `ease_out`; for `ease_in` and `ease_in_out` the second half's out point moves
    (rule I's accepted re-ease). The head never overruns, because it reads exactly what the
    original read by the cut. When the second half's straddled speed action is `ease_in` or
    `ease_in_out` and the second half would overrun, that action's end rate is lowered to
    `largest_fitting_end_rate` (R1's solve and step down); when none fits it is left as is (the
    plan's clamp holds it). A `linear` or `ease_out` tail is never lowered, because its rounding
    is the constant clip's ±1 tick. No splitter gains a refusal.
    *Amended by SR-19 (SR3b):* "`frame_grid.rs` clamps it" no longer holds for a ramped clip's
    speed action, which a re-snap snaps without clamping into the clip (SR-19 (g)); the head rule
    above stands.
  - **(f) `freeze_frame`'s** still `at` is `in + round(S(at − start))`: the join tick of (e), the
    frame the first half ends on and the second half starts on.
  - **(g) F and G are no case.** `in` and S are measured in play direction, and `scope` applies
    the op unchanged.
  - **(h) Interim until SR3b.** `relink_media`, the re-snaps and `set_speed`'s hold already read
    the ramp-aware bound through `duration_resnapped` / `source_length_on_timeline`; L's profile
    scaling and M's carry rules are SR3b's.
    *Amended by SR-19 (SR3b):* the interim ends. `set_speed` and `rate_stretch` scale the whole
    rate profile by one factor and their hold reads the scaled actions (SR-19 (a), (b)); the
    re-snaps snap a ramped clip's speed actions without clamping them and hold again (SR-19 (g));
    `relink_media`'s hold stands as built (SR-19 (h)).
  - **Why:** S is what the clip reads, so a bound that divides by one rate is wrong on every
    ramped clip; the head has no actions in front of it to read; and a split whose halves met at
    two different source ticks would play footage twice or skip it at an invisible join (the
    objection's `ease_out` case repeated 1/3 s), which the owner's preference for precision rules
    out — a rate step at the cut is the cheaper loss.
  - Risk accepted: an `ease_out` or `ease_in_out` split steps the rate at the cut; an `ease_in` or
    `ease_in_out` split moves the second half's out point; a `trim_start` that would read a
    ramped clip past its file lands nearer its old start than asked.
- **SR-19 — Rate edits and carries on a ramped clip (SR3b): one factor scales the whole profile;
  what copies, re-snaps or holds a ramped clip keeps what it reads; one ×12 figure.** The road
  map's L and M, as built.
  - **(a) The factor f.** `set_speed`'s `rate` arm sets f = clamp(rate, ×0.1, ×1000) ÷ `speed`.
    Its `duration` arm sets d = snapped(duration), at least a frame: f = 1 when d is the clip's
    duration D, else f = D ÷ d. `rate_stretch` sets f = D ÷ (to_end − start). `set_speed` clamps f
    into the range that keeps every rate the clip names — its base and every action's `end.speed`
    — inside ×0.1–×1000 (`profile_factors`): when one rate would pass a limit, the whole profile
    stops there, so the clip keeps its shape and its base is `speed`·f rather than the rate asked.
    When f does not clamp, the `rate` arm writes the base as the clamped rate itself, never
    `speed`·f, which doubles can miss by an ULP (×49 → ×1), so a repeat is an identity.
    When f clamps to 1 the edit is an identity apart from `keep_pitch`. A `rate_stretch` whose f
    lies outside that range is an identity, as today's out-of-range rate is. Every rate is
    multiplied by the same f, each product clamped to the limits; at f = 1 no rate is rewritten.
  - **(b) Duration and actions.** For `set_speed`, D′ = snapped(round(D ÷ f)), at least a frame;
    the `duration` arm with an unclamped f writes d itself, and `rate_stretch` writes to_end −
    start. Every SPEED action's start and duration scale by D′/D, snapped and NOT clamped into
    D′: one that ran past the clip's end, or started past it, still does. Every other action is
    rescaled and clamped into the clip as before. Exactly, S∞′(t·D′/D) = S∞(t) at every t, so the
    window is the same and only the grid's rounding can pass the file; D4-3's hold through
    `duration_resnapped` (S∞) catches that, and leaves the speed actions where they are, as
    `trim_end` does (SR-18 (a)); when it shortens the clip, every other action is re-clamped into
    what is left, as the re-snap's second pass (g) does.
  - **(c) No refusal.** R1–R3 refuse because a ramp edit keeps its slot and so cannot shorten. L
    changes the slot by definition and keeps the window, so it clamps like a constant
    `set_speed`.
  - **(d) One ×12 figure.** The plan leaves a ramped clip's audio out when `peak_rate` of its own,
    unlifted clip is above ×12. `peak_rate` is the greatest rate the clip NAMES: its base and
    every end rate, reached inside [0, D) or not. That is the figure `SpeedAudioDrop.peakSpeed`
    already reads off the snapshot, so the Speed sheet's question, an MCP answer's
    `audio_left_out` / `audio_note` and the plan agree on every clip, trimmed or not. No Swift
    code changes. It amends SR-10's piece-edge figure, which SR3a's past-end actions made
    disagree with Swift's.
  - **(e) `detach_audio`** copies every action whole with new ids, so the twin reads the same
    map. The road map M's reduction to `{speed, audio}` is not built: the twin keeps its video
    props and video actions so that re-enabling its video is not lossy, which is that op's
    existing rule.
  - **(f) `paste` and `paste_attributes`.** `paste` lands every clip, the clips inside the nests
    it brings, and a paste under `scope` into a nest through the re-snap (g). `paste_attributes`
    carries no profile: speed and actions are not properties, so a target keeps its own speed and
    actions, and its window does not change.
  - **(g) The re-snap** (`set_canvas`'s fps change, both paste loops, `unnest`). On a ramped clip
    a speed action is snapped onto the grid and not clamped into the clip: it keeps running past
    the end, as `trim_end` leaves it, so S∞ and what the clip reads by its end are kept up to the
    grid's rounding. The duration is then held again with the re-snapped actions, and the other
    actions are re-clamped into it. Every other action, and every clip that is not ramped, clamps
    as before.
  - **(h) `relink_media`** needs no code: `hold_to_file`'s `duration_resnapped` reads S∞ with the
    actions unchanged (SR-18 (a)), so the held clip fits the shorter file exactly.
  - **(i) `set_action` on an action running past its clip's end** keeps its refusal
    (`action_past_end`). It is the crate's rule for every clip, a constant clip's trimmed zoom
    action included, so it is not a ramp's. SR5 (rule Q, where a person reaches it) records its
    rule before its code.
    *Amended by SR-22 (SR5):* the refusal is narrowed for every clip: only an edit that ends the
    action past the clip's end AND later than it ended before is refused; a curve, the same span,
    an earlier start or a shorter length applies (#338).
  - **Why:** one factor applied to every rate and every speed span is the only scaling that keeps
    both the shape and the window. A copy or a re-snap that changed what a ramp reads would change
    the picture with no edit. A named figure is one both readers take from stored numbers (no rate
    computed in Swift, D2-1); it is never below the reached peak, so audio is never kept above
    ×12, and a trim never changes whether a clip sounds.
  - Risk accepted: a clamped f leaves the base off the asked rate; a ramped `rate_stretch` that
    the hold trims lands up to a frame short; a re-snap moves a ramp's out point by the grid's
    rounding; a speed action can lie past its clip's end after any of these ops; a ramp that names
    a rate above ×12 past its clip's end leaves the audio out though the clip never plays above
    ×12.
- **SR-20 — Swift's mappers (SR4): one core answer per clip, `rc_project_source_map`; a reader
  takes it only for a ramped clip; one read-side interpolation, checked once and read by binary
  search; Synchronize Audio refuses a ramp.** The road map's N and O, as built.
  - **(a) The export.** `rc_project_source_map(project, clip)` answers a media clip's map as
    compact JSON, `{"ramped": bool, "map": [[clip_tick, source_tick], …]}`, from
    `Project::source_map` (`speed_segments.rs`). Let in′ be the clip's `in` clamped to
    [0, media.duration − 1], as the plan's ramp segment clamps it. A RAMPED clip (`SpeedMap::of`
    is `Some`) answers `ramped: true` and `ramp_audio`'s map from in′: byte-equal to the plan's
    audio segment's `ramp.map` for a top-level clip. A constant clip answers `ramped: false` and
    the two points [[0, in′], [D, in′ + `content_length_in_source`]]. A clip is read from the
    handle it is asked of, unlifted, so a clip in a nest answers through `rc_project_scoped` its
    own map, not the nest clip's cut of it. NULL for a NULL project, an unknown id, a clip that
    is not a media clip, or one whose media is gone; a query has no `err_out`.
  - **(b) Only a ramp takes it.** A reader converts through the map only when it is `ramped`. A
    constant clip, or a nil map, reads exactly as before, byte for byte: Swift computes no rate
    (D2-1), and no existing assertion changes.
  - **(c) One read-side interpolation.** `SourceMap` (`SourceMap.swift`) holds the core's pairs
    and is the one place Swift reads between them, linearly, as the renderer does; the renderer's
    `RampAudioMap` is not touched. A map is checked ONCE, O(n), when it is decoded — at least two
    pairs of two, the first clip tick 0, both columns strictly increasing — in
    `ReelProject.sourceMap`'s memo (per handle and clip) and in `PlanSpeedRamp.source` at plan
    decode; a map that fails is nil and its reader takes the constant path. Each reading finds
    its bracketing pair by binary search, O(log n), in both directions (clip → source,
    source → clip), each clamped to the map's ends. Why: a map holds a point every `MAP_STEP` =
    600 ticks, about 100 000 for a 60 s ramp, and the waveform reads it per pixel column and the
    silence walk per 10 ms bucket, so a linear scan or a per-call check would be quadratic.
  - **(d) The readers.** The filmstrip and the waveform read `TimelineView.sourceMaps`, set from
    `document.editedProject` with the snapshot, through a map-aware `sourceTime` (a reversed clip
    mirrored about the media's duration, as today). `Transcriber.Job.ramp` carries the map and the
    clip's start, so a job's source window is the map's (`sourceIn`, `sourceLength` held to the
    recognition cap) and every word is placed through `clip(atSource:)`: captions, `transcribe`,
    `detect_fillers`, `get_transcript` and its TR-13 window (whose recognition sub-job pads 2 s
    of SOURCE each side and maps its ends back through the map) follow it. `detect_silence` and
    voice mode read the plan's ramp audio segment's map through `MediaPeaks.sourceTick`; this
    amends N's "tested, not changed": the audio segment is one ×1 segment over the slot, so its
    linear reading would misplace a span mid-clip. Normalize Clip is unchanged: it reads the whole
    segment, whose two ends both readings agree on.
  - **(e) Synchronize Audio refuses a ramped clip**, mover or anchor, through the menu and
    `sync_audio` alike, by `AudioSync.ramped`: "ramps its speed (a speed action changes its rate
    over its length); Synchronize Audio lines up clips playing at one rate." Its drift line
    assumes one rate.
  - **(f) The instrument door.** `Transcriber.jobs(for:in:urls:)`, the three-argument form old
    trees' probes build, keeps its signature and reads no map; for a media clip whose actions
    name `end.speed` it answers no job and the problem "its speed ramps, and no speed map was read
    for it", so no caller places a ramp's words at one rate unawares.
  - **(g) Rule O.** Words placed before a ramp edit are not re-timed by it, as `set_speed` does not
    re-time them; captions and transcripts made after it follow the ramp.
  - **(h) The person check** — a ramped clip's filmstrip and waveform look right — is SR5's row in
    `docs/manual-checks.md`, because no UI makes a ramp until SR5.
  - **Why:** the core owns S (D2-1), and its plan already holds the map the renderer plays, so the
    readers take the same pairs rather than a second rate rule; gating on `ramped` keeps every
    constant clip's arithmetic as it is.
  - Risk accepted: words, fillers and silences are placed through a piecewise-linear chord of S
    with 1 ms steps, the chord the renderer plays; captions made before a ramp edit keep their old
    times until they are made again.
- **SR-21 — The UI of a speed ramp (SR5): the Speed section's Rate writes the selected action's
  `end.speed`; a band names `speed`; the ×12 question covers a ramp edit; the Speed sheet scales
  a ramp.** The road map's P and Q, as built.
  - **(a) Rate inside an action.** With an action SELECTED on the single selected media clip
    (CI-2; the playhead entering a span selects it, CI-1), the Speed section's Rate writes that
    action's `end.speed`: one `set_action_end {patch: {speed}}`, undo name "Set Speed". With none
    selected, or with several clips selected, it is one `set_speed` per media clip as before.
    The section's Reset does the same at ×1 (×1 at the action's end inside one). Keep pitch is
    `set_speed` at the clip's BASE rate with `keep_pitch`, and Fit to is `set_speed`'s duration
    arm: both stay clip-level whatever is selected, and are ⊘ while an action is selected.
  - **(b) The read.** Inside an action Rate shows the end's stored rate when the end names one,
    else the rate in force at the action's end, read from the core: `rc_project_clip_state`
    answers a top-level `speed`, the rate the clip plays at that clip time (`rate_in_force`, the
    clip's `SpeedMap` read there, or its `speed` when constant). The coral "now" reads the same
    key at the playhead. No rate is computed in Swift (D2-1); outside an action Rate reads the
    clip's base `speed` as before.
  - **(c) The `speed` path.** A row's marks name `speed`: `set_speed` writes it and an end's
    top-level `speed` keys it. Rate inside an action naming a rate is ◆ with the keyed border,
    its key is cleared by a `null` (the gutter's ×, "Remove from action N", the section's Clear),
    the Clip sub-tab's `◆N` counts it (CI-6 amended), and the Speed section is revealed under a
    keying action (CI-8). Outside an action Rate's mark is ◇ "Changed by action N" when an action
    names a rate, and so are Keep pitch's and Fit to's: all three write `set_speed`, so they
    share the `speed` path's marks. Only `speed` is read by its own name; any other non-object
    value in an end patch keys nothing, as before.
  - **(d) The band.** A band's label lists `speed` beside the end's other keys (`ActionBands.keys`),
    and an action naming a rate is never drawn with the zoom glyph, whatever its video keys.
  - **(e) The ×12 question (#190, rule P).** Asked, and an agent's answer carries `audio_left_out`
    and `audio_note`, for `set_speed`, `rate_stretch` and a `set_action_end` naming `speed`, read
    off the core's trial as before, on SR-19 (d)'s named peak. Not for `set_action`,
    `remove_action` or a Clear: none of them can raise the greatest rate a clip names, so none can
    cross (amending rule P's list). The Speed section's note reads the named peak too.
    *Amended by SR-24 (#340):* `add_speed_ramp` asks the question, and answers
    `audio_left_out` and `audio_note`, as `set_speed` does.
  - **(f) The Speed sheet** (Clip ▸ Speed…) edits the base rate under rule L (SR-19 (a)): Apply
    is `set_speed` as before, and a ramp keeps its shape. When a selected clip is ramped its
    readout adds the line "Each speed ramp keeps its shape: the rates it names scale with the base
    rate." A constant selection's readout is unchanged, byte for byte.
  - **(g) Menus.** No menu item, key or tool is added, and no validator changes: Clip ▸ Speed…
    stays live on a ramped clip, which is a media clip.
    *Amended by SR-24 (#340):* Clip ▸ Speed Ramp… is added after Speed…, with its validator and
    no key, and so is its tool, `add_speed_ramp` (SR-25).
  - **(h) Person checks** in `docs/manual-checks.md`, RMP-1..RMP-4: a ramp sounds right with Keep
    pitch on and off, playback through a ramp looks smooth, a ramped clip's filmstrip and waveform
    look right (SR-20 (h)), and the Speed section inside an action feels right.
  - **Why:** the inspector's one rule is that a field inside an action writes that action's end
    (CI-2), and `speed` is an end key like opacity (SR-10); Keep pitch and Fit to are the clip's,
    as CI-3's pitch and length are; a read from the core keeps one rate rule.
  - Risk accepted: the question reads the named peak, so an end rate above ×12 on an action past
    the clip's end asks though the clip never plays above ×12 (SR-19's risk line).
- **SR-22 — `set_action` refuses only an edit that takes an action further past its clip's end
  (#338).** For every clip, ramped or constant: with `new_end = new_start + new_duration`, the
  edit is refused with `action_past_end`'s sentence, unchanged, only when `new_end` is past the
  clip's end AND past the action's own end before the edit. So on an action already running past
  the end, a curve change, the same span, an earlier start and a shorter length apply; a longer
  length or a later start is refused. An action inside the clip pushed past its end is refused
  exactly as before. The overlap check and a speed action's slot refusal (R3) after it are
  unchanged, and `add_action` is unchanged.
  - **Why:** SR-19 (b) and (g) leave a speed action past its clip's end, and `trim_end` leaves any
    action there; refusing every edit of one left the person no way to re-curve or pull it in,
    while an edit that leaves it no further out takes nothing the clip had. A band's drag already
    stops at its own end (`ActionDragSession`), so the timeline gains nothing new to reach.
  - Risk accepted: an action may stay past its clip's end after an edit, as `trim_end` already
    leaves it.
