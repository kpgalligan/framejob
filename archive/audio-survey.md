# Audio survey: what professional editors offer, and what Frame Job lacks

- **Status:** Survey, 2026-10-30. Proposals only: nothing here is a spec §11
  decision. A phase that takes one up records it in
  `designs/spec/11-decisions/audio.md` (the AU- series, begun by AU-1) before
  its code.
- **The question (owner, 2026-10-30):** "Review the audio editing features of
  other video editing tools. What other audio editing features should we
  support to be considered a professional-grade tool?"
- **The immediate case:** a quiet but clean RØDE USB desktop-microphone voice
  recording, `samples/Rode-usb-mic.m4a`, which the owner wants to turn into
  usable audio for videos. §2 measures it, and §5 marks which gaps it needs
  first.
- **Method:** every claim about another editor cites the vendor's own manual,
  help page, new-features guide or release notes (§7). Three limits on that:
  - **Adobe:** helpx.adobe.com refused direct fetches (HTTP 403). Premiere
    claims are therefore taken from search-engine excerpts of the cited
    helpx pages, not from a full read.
  - **Blackmagic:** the DaVinci Resolve Reference Manual (thousands of pages)
    was not read. Resolve claims come from Blackmagic's New Features Guides
    for 19, 19.1 and 20, and from its product and What's New pages.
  - **CapCut:** it publishes no help pages for its audio tools that I could
    find. Its claims come from CapCut's own marketing articles and are marked
    *unverified*.

  Apple framework claims were checked against developer.apple.com and the
  macOS 26.2 SDK headers.

## Contents

1. [Frame Job today](#1-frame-job-today)
2. [The owner's recording, measured](#2-the-owners-recording-measured)
3. [What the other editors offer](#3-what-the-other-editors-offer)
4. [Feature matrix](#4-feature-matrix)
5. [The gaps, tiered](#5-the-gaps-tiered)
6. [Sample recordings to add](#6-sample-recordings-to-add)
7. [Sources](#7-sources)

## Spec §1's non-goals, and the flags below

Spec §1 (`designs/spec/01-what-this-is.md`) lists as a deliberate non-goal
"audio beyond what shipped (volume, fades, duck, pan, compressor, noise
reduction, peak normalize, the transition crossfade and the export's loudness
target — M3 and §11 R5-2; so no EQ, mix buses or Audio Units, while offline
voice effects are deferred rather than out)". The same section sets the bar
"without Final Cut's magnetic timeline, roles, multicam, scopes, or a plugin
ecosystem", and lists "a plugin system" (§11 G-1) as a non-goal.

Every proposal below goes beyond "what shipped", and the owner's audio pass
has already begun lifting that umbrella clause (AU-1 raised the volume
ceiling). Each gap is therefore flagged only against the **named** items:

| Flag | Non-goal it would lift |
|---|---|
| **NG-EQ** | "no EQ" |
| **NG-BUS** | "no … mix buses" |
| **NG-AU** | "no … Audio Units". This survey reads it as *hosting Audio Units as a feature*. Frame Job already runs one of Apple's units internally: `AVAudioUnitTimePitch` renders speed-ramp audio (`app/Sources/RampAudioRenderer+TimePitch.swift`). A gap built on an Apple unit is marked **NG-AU?** for the owner to rule on. |
| **NG-ROLES** | "roles" (the §1 bar) |
| **NG-PLUGIN** | "a plugin system" (§11 G-1) |
| **E8** | "offline voice effects are deferred rather than out" (issue #123) |

## 1. Frame Job today

Written from the guide pages, which are written from the code.

| Area | What exists | Guide |
|---|---|---|
| Clip level | Volume 0–3200 % (slider 0–400 %, field to 3200 %, AU-1); Mute; gain read-out in dB | `docs/guide/audio.md` |
| Normalize | Peak only: sets Volume so the clip's loudest moment over the played range, read from its cached waveform, reaches −1 dBFS (agents: `peak_db` −60…0). Each clip separately; no matching across clips | audio.md |
| Fades | Fade in and out, 0–10 s, straight-line ramps; handles on the clip | audio.md |
| Ducking | Lowers every *other* clip while this one is on the timeline: Level, Attack, Release. Follows the clip's extent, not voice activity | audio.md |
| Noise reduction | One Amount (0–100 %). Profiles steady noise from the clip itself ("hiss, hum and fan noise"); not a gate; doesn't remove sudden sounds | audio.md |
| Compressor | Threshold −60…0 dB (default −18), ratio 1–20:1, attack 0–200 ms, release 10–2000 ms, makeup 0–24 dB. Acts *before* Volume | audio.md |
| Mix | Pan (a balance on stereo; a true pan with Mix to mono); Mix to mono (averages channels) | audio.md |
| Detach Audio | Splits sound onto its own clip on the track below. One way: no control re-links or re-enables it (Undo, or an agent's `set_enabled`) | audio.md, `editing.md` |
| Speed | Keep pitch (on by default); ramp and tape-speed audio rendered offline; no sound above ×12 | `speed.md` |
| Transitions | Optional constant-power audio crossfade (R5-2) | audio.md |
| Tracks | Mute, Solo. No track volume, pan or effects | audio.md |
| Animation | Volume, Mute and the fades only, through actions on the clip's action lane. Pan, mono, Keep pitch, compressor, noise reduction and ducking can't be animated. Nothing is drawn on the waveform | audio.md, `timeline.md` |
| Metering | Live two-channel meter of the mix: RMS bar, peak wash, 1.2 s peak hold, clip cells, −60…0 dB. It shows peaks, not loudness. The recorder has its own microphone meter | audio.md |
| Export loudness | Optional integrated target (BS.1770-4): −14, −16, −23 or custom −70…0 LUFS, under a −1 dBTP ceiling (agents −20…0). **Gain only, no limiter**: "A target the ceiling will not allow lands quieter than asked." Every export reports its true peak and LUFS | `export.md` |
| Export formats | Stereo 48 kHz: AAC, Opus, or 16-bit LPCM in ProRes. Audio-only M4A, WAV and AIFF (WAV and AIFF are 16-bit only) | export.md |
| Sync | Synchronize Audio: MFCC/speech match, waveform gate, sub-frame offset, drift corrected up to 0.2 % | audio.md |
| Clean-up | Remove Silences (on-device voice model, or a level threshold); Remove Filler Words (AssemblyAI, bring-your-own key) | `cleanup-tools.md` |
| Recording | Microphone recorded as mono 48 kHz AAC, a separate file from system audio; voice-overs land on a new Microphone track. No processing at record time | `screen-recording.md` |
| Scrubbing | Silent: "Playback stops while you scrub" | timeline.md |
| Copying | Paste Attributes carries the whole sound setup | audio.md |

Open issues on audio include #86 (decode the export mix as float, then offer
24-bit WAV and AIFF), #123 (E8 offline voice effects), and #299 (Keep pitch
timing).

### How it is built, as far as it bears on feasibility

- **Per-clip effects run in a tap, before the fader.** Pan, mono,
  compressor and noise reduction run in one `MTAudioProcessingTap` per
  composition audio track, created PreEffects [AD10]. Volume, fades and ducking
  come after it, as the plan's envelope applied as volume ramps
  (`app/Sources/AudioTap.swift`). A new per-clip stage therefore sees the
  clip at its recorded level, before Volume (up to ×32) is applied.
- **The preview has no post-mix insert; the export does.** Each track carries
  exactly one tap, and the metering build already uses it
  (`AudioTap.swift`). The export reads a 32-bit float mix and applies its
  loudness gain there (`app/Sources/ExporterAudioGain.swift`).
- **Heavy or pitch-changing work renders offline.** Speed-ramp audio is
  rendered offline into the package's `cache/` (`speed.md`). With Keep pitch
  on, that render drives Apple's `AVAudioUnitTimePitch` in `AVAudioEngine`'s
  offline manual rendering mode [AD9]
  (`app/Sources/RampAudioRenderer+TimePitch.swift`). E8's design (#123)
  measured the same pattern for Apple's effect units, because the live tap
  "cannot host a pitch shifter".

## 2. The owner's recording, measured

`samples/Rode-usb-mic.m4a`: 30.4 s, AAC mono, 48 kHz. Measured 2026-10-30
with ffmpeg's `astats` and `ebur128=peak=true` and a numpy pass over
50 ms windows and FFT bands. The script lived in a scratch folder and is not
in the tree.

| Measure | Value |
|---|---|
| Sample peak / true peak | −18.6 dBFS / −18.5 dBTP |
| Integrated loudness | −44.7 LUFS |
| Loudness range (LRA) | 21.1 LU (LRA low −64.3 LUFS, high −43.1 LUFS) |
| 50 ms RMS, 10th percentile (the floor) | −64.3 dBFS |
| 50 ms RMS, 90th / 99th percentile (speech) | −43.2 / −35.8 dBFS |
| Windows within 6 dB of the floor | 65 % |
| Pause noise below 80 Hz / below 300 Hz | 20 % / 78 % of its energy |
| Tonal peaks at 50, 100 / 60, 120 Hz in pauses | 9–11 dB over neighbouring bins, in both mains families |
| 5–9 kHz vs 0.3–4 kHz on active windows | median −22.4 dB, 95th percentile −0.2 dB |

What the numbers say:

1. **Peak normalize and the export's loudness target both stop near
   −27 LUFS.** The peak-to-loudness ratio is 26 dB. Normalize to −1 dBFS
   applies +17.6 dB, so the clip lands at about −27.1 LUFS. A −16 LUFS
   target needs +28.7 dB and −14 LUFS needs +30.7 dB, which would put the
   true peak at about +10 or +12 dBTP. The export's gain is capped at the
   −1 dBTP ceiling, so the file lands at the same −27 LUFS, "quieter than
   asked". Reaching either target takes **about 11–13 dB of peak
   reduction**: a compressor and a limiter, not just gain.
2. **At its defaults, the shipped compressor never acts on this file.** Its
   threshold is −18 dB and it runs before Volume, while the file peaks at
   −18.6 dBFS. To use it here, a person has to know to drop the threshold
   to around −40 dB.
3. **The lift raises the floor into earshot.** After +28.7 dB, the pause
   floor sits around −36 dBFS, and the pauses fill 65 % of the 50 ms
   windows. The pause noise is low: 78 % of it lies below 300 Hz, but only
   20 % below 80 Hz. A high-pass at 80 Hz takes about 1 dB off it. The rest
   shares the voice's own range, so it needs noise reduction, voice
   isolation, or a downward expander that closes in the pauses.
4. **The 21 LU loudness range is the pauses, not the voice.** LRA's low end,
   −64.3 LUFS, *is* the noise floor: its −68.4 LUFS relative gate lets the
   quiet stretches in. A dialogue leveller is not this file's first need.
5. **Mains hum and sibilance are not indicated.** Both are inconclusive.
   The low bins rise by a similar amount in the 50 Hz and 60 Hz families,
   which reads as the low-frequency slope rather than a hum. Fricatives
   reach the voice band's energy in 5 % of active windows, which needs a
   listen. Sibilance matters more once EQ presence and heavy compression
   are added.

Not measured: what the shipped noise reducer does to this file's floor.
That is the first comparison a phase should make, with Apple's
`AUSoundIsolation` as the other side (see A4).

## 3. What the other editors offer

Each line cites §7. "Studio" means Resolve's paid edition.

### DaVinci Resolve (Fairlight, Edit and Cut pages)

- **Clean-up and repair:**
  - Voice Isolation and Dialogue Leveler, as track FX in the Fairlight
    mixer [R3] and in the Cut page's Voiceover tool [R2]. Voice Isolation is
    a Studio feature [R6]. Whether they also sit on clips was not verified.
  - Over 25 Fairlight FX, including a de-esser, a de-hummer and noise
    reduction that "automatically detects noise in a selection" or learns
    it [R1].
  - Stereo Fixer [R2].
  - Dialogue Separator, which sets the levels of dialogue, background and
    "ambience" separately. It is mono only [R3].
- **Dynamics and loudness:**
  - Each channel strip has an expander/gate, a compressor and a limiter
    [R1].
  - Clip normalization to target levels [R1].
  - The Deliver page can "Normalize loudness or peak" or "Optimize loudness
    and peak … peaks remain lower than threshold" [R3].
  - AI Level Matcher [R2].
- **EQ:**
  - Every clip has a 6-band parametric EQ [R1, R2, R5].
  - The track EQ's high-pass and low-pass slopes reach 24 dB/octave, with an
    RTA display [R3].
  - AI EQ Matcher, which "is automatically automated across your clip" in
    21 [R2, R5].
  - AI Dialogue Matcher matches "tone, level" and room [R2].
- **Mixing and routing:**
  - Faders, panners and 6 plug-in slots per track [R1].
  - FlexBus buses up to 36 channels wide [R1].
  - Sidechaining for any capable FX or plug-in [R3].
  - Track folders (21) [R5].
- **Automation:** "record changes to virtually any control setting or effect
  over time" [R1]. Per-channel automation modes arrived in 20 [R2].
  IntelliTrack writes pan automation by tracking an object in the picture
  (Studio) [R3].
- **Ducking:** a Ducker track FX keyed by the *signal* of one or more source
  tracks or a bus. Its controls are Duck Amount, Lookahead, Rise, Hold and
  Recovery, and "The Ducker uses changes in level only" [R3, R4].
- **Editing workflow:**
  - Waveform editing down to the sample with a pencil [R1].
  - Elastic Wave retiming "without changing pitch" [R1].
  - Track layers for takes [R1].
  - AI Remove Silence (Studio) [R2].
  - Clip EQ settings copy and paste [R2].
- **Metering and analysis:**
  - Loudness meters with selectable standards, a loudness graph, and offline
    "analyze audio level" [R1].
  - A Frequency Analyzer FX with spectrum and waterfall views [R3].
- **Sync and multitrack:**
  - Channel mapping on "adaptive" tracks up to 36 channels [R1].
  - Changing mono sources within a multichannel clip [R4].
  - Checkerboard to New Tracks, which splits speakers onto tracks
    (Studio) [R2].
- **AI and voice (Studio unless noted):**
  - AI Audio Assistant, which sorts tracks, evens dialogue, applies Voice
    Isolation and de-essing, ducks music and masters to a chosen delivery
    standard [R2].
  - Music Remixer, which splits music into vocals, drums, bass, guitar and
    other [R3].
  - AI Music Editor, which fits music to a length without stretching [R2].
  - AI Beat Detector [R2].
  - AI Voice Convert [R2].
  - Speech generation from text in 21 [R5].
- **Recording:** the Cut page's Voiceover tool can apply Voice Isolation,
  Dialog Leveler and Stereo Fixer *while recording* [R2]. ADR cue tools are
  also offered [R1, R2].
- **Plug-ins and round-trip:** VST and Audio Unit plug-ins; Chain FX presets;
  sending clips to external processors such as iZotope RX [R1, R5].
- **Delivery:** mono through 22.2 and 3D formats [R1]. A per-track stem
  render was **not verified** here.

### Final Cut Pro

- **Clean-up and repair** ("Audio Enhancements", per *component*, not per
  clip) [F1]:
  - Voice Isolation, with an Amount.
  - Noise Removal.
  - Hum Removal at 50 or 60 Hz.
  - **Modify ▸ Enhance Audio** (⌥⌘A) analyses the clip and turns on what it
    needs, except Equalization and Voice Isolation.
- **Dynamics and loudness:**
  - The Loudness enhancement has Amount (compression) and Uniformity [F1].
  - Logic effects include Compressor, Limiter, Adaptive Limiter, Expander,
    Noise Gate, Spectral Gate, Multipressor, Enveloper and DeEsser 2 [F4].
  - No loudness-target normalization or export loudness option was found in
    the pages read.
- **EQ:**
  - Equalization presets with manual controls [F1].
  - Match Audio, which EQ-matches a clip to another (⇧⌘M) [F2].
  - Channel EQ, Linear Phase EQ and the vintage EQs [F4].
- **Mixing and routing:**
  - Roles, subroles and audio lanes [F8], instead of a track mixer. No
    fader mixer was found in the pages read.
  - Effects go on clips, components or compound clips, and run in list
    order [F3].
- **Automation:** keyframes on volume and on effect parameters in the Audio
  Animation editor (⌃A) [F11].
- **Editing workflow:**
  - Expand Audio (⌃S) and split edits for J- and L-cuts, keeping sync [F10].
  - Crossfades (⌥T); a transition crossfades attached audio [F12].
  - Four fade shapes: Linear, S-curve, +3 dB and −3 dB [F13].
  - Audio skimming (⇧S) [F14].
- **Metering:**
  - Level meters [F6].
  - The MultiMeter effect: Peak, RMS and True Peak, a LUFS loudness meter
    (integrated and short-term), an analyzer, goniometer and correlation
    meter [F5].
- **Sync and multitrack:**
  - Synchronize Clips, with "Use audio for synchronization" [F15].
  - Channel configuration (mono, stereo, 5.1); components switched on or
    off [F7].
- **AI and voice:**
  - Pitch Shifter, Vocal Transformer and Pitch Correction [F4].
  - Transcript Search and **Beat Detection** in 12.0 [F16].
- **Delivery:** roles shared as separate files or as a multitrack QuickTime
  or MXF ("handing off media stems"), with mono, stereo or surround per
  output [F9].
- **Plug-ins:** "64-bit macOS built-in and third-party Audio Units" [F3].

### Premiere Pro (through search excerpts; see the Method note)

- **Clean-up and repair (Essential Sound ▸ Repair, each 0–10):**
  - Reduce Noise, Reduce Rumble (below about 80 Hz), DeHum (50 or 60 Hz),
    DeEss and Reduce Reverb [P5].
  - Effects behind them: DeNoise, DeReverb, DeHummer and DeEsser (Broadband
    or Multiband), and a Notch Filter [P5, P7].
  - **Enhance Speech** reduces noise and improves clarity, with a Mix Amount
    [P1]. It takes mono and stereo only, and stereo comes out as a mono
    downmix [P2]. Whether it runs on the device is not stated.
- **Dynamics and loudness:**
  - Clarity ▸ Dynamics [P6].
  - Hard Limiter [P7].
  - **Auto-Match** loudness by audio type, with the clip's LUFS shown [P3].
  - Audio Gain: "Normalize Max Peak to" and "Normalize All Peaks to" [P11].
  - Export loudness normalization (ATSC A/85, EBU R128, ITU BS.1770-3), with
    a configurable **true-peak limiter** and a loudness report [P9].
- **EQ:** the Clarity EQ preset and amount [P6]. The Parametric Equalizer
  has five bands plus high-pass, low-pass and shelves [P7].
- **Mixing and routing:**
  - The Audio Track Mixer: submixes, five pre- or post-fader sends per track,
    track effects [P10].
  - Automation modes Off, Read, Latch, Touch and Write [P10].
- **Automation:** clip and track keyframes, drawn with the Pen tool on the
  clip's volume line [P11].
- **Ducking:** **Auto Ducking** ducks against chosen audio types, with
  Sensitivity, Duck Amount, Fade Duration and Fade Position. It writes
  editable keyframes [P4].
- **Editing workflow:**
  - Unlink or ⌥-drag for J- and L-cuts [P16].
  - Constant Gain, Constant Power and Exponential crossfades [P18].
  - Text-based editing deletes pauses and filler words [P17].
  - **Remix** retimes music to a target length [P13].
- **Metering:** a Loudness Meter with presets and a maximum true peak; it
  replaced Loudness Radar [P8].
- **Sync and multitrack:** Synchronize, and multicam sync by audio [P19].
  Modify ▸ Audio Channels remaps source channels [P12].
- **AI:** Auto Tag classifies clips as Dialogue, Music, SFX or Ambience
  [P15].
- **Round-trip:** sends a clip or a whole sequence to Audition [P14].

### Descript

- **Clean-up:** **Studio Sound** reduces noise and echo, with an Intensity
  slider [D1]. It "requires an internet connection" and applies to the
  source file. It can be on while recording [D1].
- **Effects** [D2]:
  - Compressor and Limiter.
  - Equalizer (five bands), Graphic EQ (ten bands), high and low shelf,
    high-pass and low-pass.
  - Reverb, Bitcrusher, Distortion and Flanger.
- **Ducking:** "Lower audio of other layers". It works on clip presence, not
  on the words, and applies per layer [D3]. The effects table describes it
  as speech-detected [D2]; the dedicated page [D3] is the more specific of
  the two.
- **Export:** M4A, WAV or MP3; mono or stereo; 44.1 or 48 kHz. Normalize to
  Off, Peak, −14, −16, −18, −23 or −24 LUFS [D4]. An article named "Export
  individual sequence tracks as mono files" is linked but was not read [D4].
- **Text-based editing:**
  - Filler-word removal and Shorten Word Gaps [D6].
  - Edit for Clarity and Remove Retakes [D5].
  - Regenerate, AI Speakers (text-to-speech) and Dub [D5].

### CapCut desktop (*unverified*: vendor marketing pages only)

- **Basic tab:** volume, fade in and out, Reduce noise and Beat detection
  [C1].
- **Enhance voice:** a 0–100 strength [C2].
- **Loudness normalization:** "to achieve a standard sound value", target
  not stated [C2].
- **Voice changer:** filters and characters [C1].
- **Speed** with pitch [C1].
- **Auto Cut** cuts to beats or speech pauses. This one is from CapCut's
  help site [C3].

### Camtasia (TechSmith)

- **Audio effects:** Audio Compression (a "Volume variation" preset, or
  Ratio, Threshold and Gain), Clip Speed, Emphasize, Fade In and Out, Pitch
  (Mac only) and Noise Removal [T1].
- **Emphasize** lowers all other tracks while a clip plays. Emphasis 100 %
  mutes them, and Ramp Position is Outside, Span or Inside [T1].
- **Editing:**
  - Audio points for volume, which also make fades [T2].
  - Separate Video and Audio; Silence Audio; Mix to Mono [T2].
  - Export audio only as M4A or WAV [T2].
- **Recent versions:** an "AI Noise Removal" effect exists (named in a
  2026.2.0 fix), and 2026.1.0 "Added ability to sync the timing of media by
  their audio" [T3]. No loudness target or EQ is in Camtasia's effects list
  [T1].

### ScreenFlow (Telestream), User Guide 10, August 2025 [S1]

- **Audio filters:** "EQ, multi-band compression, peak limiting, and delay",
  several per clip, on nested clips too. Third-party Audio Unit filters
  work, with a sandbox caveat for the App Store build.
- **Audio Properties:**
  - Volume above 100 %; Mute.
  - **Ducking**: "lowers the audio levels for background audio whenever
    there is a voiceover", by a percentage, set on the narration clips.
  - **Smooth Volume Levels**.
  - **Remove Background Noise**, with an amount.
  - A per-clip channel mixer with RMS, peak and peak-hold meters, solo, and
    per-channel pan and level. "Mix to Mono" was replaced by the pan.
- **Audio actions:** property changes over time, as with video actions.

## 4. Feature matrix

| Code | Meaning |
|---|---|
| **yes** | Documented by the vendor |
| **part.** | Partly; see the footnote |
| **—** | Not found in the vendor documentation read for this survey. It may still exist |
| **n/c** | Not checked |
| **unv.** | Claimed only on CapCut's marketing pages |

| Feature | Resolve | FCP | Premiere | Descript | CapCut | Camtasia | ScreenFlow | Frame Job |
|---|---|---|---|---|---|---|---|---|
| Peak normalize | yes² | — | yes | part.¹ | n/c | — | — | yes |
| Loudness-target (LUFS) clip normalize or match | part.² | — | yes | — | unv. | — | — | no |
| Export loudness target | yes | — | yes³ | yes | n/c | — | — | part.⁴ |
| Limiter (clip, track or mix) | yes | yes | yes | yes | n/c | — | yes | no⁵ |
| Compressor | yes | yes | yes | yes | n/c | yes | yes | yes |
| Noise gate or downward expander | yes | yes | n/c | — | n/c | — | — | no |
| Parametric EQ and high-pass | yes | yes | yes | yes | n/c | —⁶ | yes | no |
| Match EQ or voice to another clip | yes | yes | — | — | n/c | — | — | no |
| ML voice isolation or speech enhancement | yes⁷ | yes | yes | yes⁸ | unv. | part.⁹ | — | no |
| Broadband noise reduction | yes | yes | yes | part.¹⁰ | unv. | yes | yes | yes¹¹ |
| Hum removal (50/60 Hz) | yes | yes | yes | — | n/c | — | — | part.¹¹ |
| De-esser | yes | yes | yes | — | n/c | — | — | no |
| De-reverb | part.¹² | — | yes | yes | n/c | — | — | no |
| Dialogue leveller or auto level | yes | part.¹³ | part.¹³ | — | n/c | part.¹³ | part.¹³ | part.¹³ |
| Auto-analysis that turns fixes on | yes⁷ | yes | part.¹⁴ | part.¹⁵ | n/c | — | — | no |
| Ducking | yes¹⁶ | — | yes¹⁶ | part.¹⁷ | n/c | part.¹⁷ | part.¹⁷ | part.¹⁷ |
| Volume keyframes drawn on the clip | yes | yes | yes | n/c | n/c | yes | part.¹⁸ | part.¹⁸ |
| Animate pan and effect parameters | yes | yes | yes | n/c | n/c | n/c | n/c | no |
| Fade and crossfade curve shapes | n/c | yes | yes | n/c | n/c | n/c | n/c | part.¹⁹ |
| Track faders or mixer | yes | —²⁰ | yes | n/c | n/c | part.²¹ | part.²¹ | part.²¹ |
| Buses, submixes, track effects | yes | part.²² | yes | n/c | n/c | — | — | no |
| Stems or roles as separate files | n/c | yes | n/c | part.²³ | n/c | n/c | n/c | no |
| Channel configuration and selection | yes | yes | yes | part.²⁴ | n/c | part.²⁴ | yes | part.²⁴ |
| Split edits (J/L) that keep sync | n/c | yes | yes | n/c | n/c | part.²⁵ | n/c | part.²⁵ |
| Audio scrubbing | n/c | yes | n/c | n/c | n/c | n/c | n/c | no |
| Live LUFS meter | yes | yes | yes | — | n/c | — | — | part.²⁶ |
| Sync by audio | n/c | yes | yes | n/c | n/c | yes | n/c | yes |
| Remove silences or pauses | yes⁷ | n/c | yes | yes | yes²⁷ | n/c | n/c | yes |
| Filler-word removal | n/c | n/c | yes | yes | n/c | n/c | n/c | yes²⁸ |
| Clean-up applied while recording | yes | n/c | n/c | yes | n/c | n/c | n/c | no |
| Beat detection | yes⁷ | yes | n/c | n/c | unv. | n/c | n/c | no |
| Music retimed to a length | yes⁷ | n/c | yes | n/c | n/c | n/c | n/c | no |
| Source separation (dialogue or music stems) | yes⁷ | n/c | n/c | n/c | n/c | n/c | n/c | no |
| Voice effects or changer | yes⁷ | yes | n/c | part.²⁹ | unv. | part.²⁹ | part.²⁹ | no (#123) |
| AI speech (text-to-speech, regenerate) | yes | n/c | n/c | yes | n/c | n/c | n/c | no |
| Third-party plug-ins (AU, VST) | yes | yes | n/c | n/c | n/c | n/c | yes | no |
| Round-trip to an audio editor | yes | n/c | yes | n/c | n/c | n/c | n/c | no |

Footnotes:

1. Descript: "Peak" is an export normalize option, not a clip operation [D4].
2. Resolve: the Deliver page normalizes "loudness or peak" [R3]; on the
   timeline, clip normalization sets target levels [R1] and the AI Level
   Matcher matches clips [R2]. The clip normalization's modes are in the
   Reference Manual, which was not read.
3. Premiere: documented on Media Encoder's page, which Premiere's export
   uses [P9].
4. Frame Job: gain only, capped at the true-peak ceiling. A target the
   ceiling won't allow lands quieter (`export.md`).
5. Frame Job: the compressor at 20:1 "acts like a limiter" (audio.md), but it
   has no lookahead and no true-peak detection. The export has no limiter.
6. Camtasia: no EQ in Camtasia's effects list [T1]. TechSmith's separate
   Audiate product has one.
7. Resolve Studio only: Voice Isolation and the Dialogue Separator [R6]; AI
   Audio Assistant, Remove Silence, Beat Detector, Music Editor and Voice
   Convert [R2]; Music Remixer [R3].
8. Descript: needs an internet connection [D1].
9. Camtasia: "AI Noise Removal" is named in the 2026 version history [T3].
   No help page describing it was read.
10. Descript: noise is handled inside Studio Sound only [D1, D2].
11. Frame Job: the steady-noise reducer is said to work on hum (audio.md).
    It has no tonal notch.
12. Resolve: the Dialogue Separator's ambience level, mono only [R3].
13. FCP: Loudness Uniformity [F1]. Premiere: Dynamics [P6]. Camtasia: Audio
    Compression "Volume variation" [T1]. ScreenFlow: Smooth Volume Levels
    [S1]. Frame Job: the compressor. All are compressors or smoothers rather
    than slow gain riders.
14. Premiere: Auto Tag plus per-type Auto-Match [P15, P3].
15. Descript: Studio Sound is one toggle [D1].
16. Driven by the sound: Resolve by the source signal [R3]; Premiere by
    detected dialogue, writing keyframes [P4].
17. Descript: clip presence [D3]. Camtasia: clip extent [T1]. Frame Job:
    clip extent (audio.md). ScreenFlow: set on narration clips, to lower
    "background audio whenever there is a voiceover"; whether it follows
    speech or the clip is not stated [S1].
18. ScreenFlow: audio actions [S1]. Frame Job: volume, mute and fades
    through actions on an action lane, with no line on the waveform.
19. Frame Job: linear fades; the transition crossfade is constant power
    (R5-2).
20. FCP: roles and audio lanes [F8]; no fader mixer was found.
21. Camtasia: a project master gain [T2]. ScreenFlow: a per-clip channel
    mixer [S1]. Frame Job: track mute and solo only.
22. FCP: effects on compound clips [F3].
23. Descript: a linked article, "Export individual sequence tracks as mono
    files", was not read [D4].
24. Descript: mono or stereo output [D4]. Camtasia: Mix to Mono [T2]. Frame
    Job: Mix to mono (averages all channels) and pan. None of these picks a
    single channel.
25. Camtasia: Separate Video and Audio [T2]. Frame Job: Detach Audio, which
    is one way.
26. Frame Job: the live meter is peak and RMS. LUFS appears only in the
    export's report.
27. CapCut: Auto Cut cuts at speech pauses, per its help site [C3].
28. Frame Job: needs a cloud transcript (AssemblyAI, the person's own key).
29. Descript: Reverb, Distortion, Bitcrusher, Flanger [D2]. Camtasia: Pitch,
    Mac only [T1]. ScreenFlow: delay [S1].

**Reading the matrix:** Frame Job's clip strip (volume, fades, noise
reduction, compressor, pan, mono) and its clean-up tools already match the
creator tier: Camtasia, ScreenFlow and much of Descript. Against the three
professional editors, the shortfall falls into four groups:

- **Dynamics:** limiting, gating or expansion, and loudness-target
  normalization.
- **Tone:** EQ, de-essing and hum notches.
- **ML voice clean-up.**
- **Mix structure:** track faders, buses, animating any parameter, and
  stems.

## 5. The gaps, tiered

Each gap gives what it is, who has it, why it matters here, a one-line
feasibility note on Apple Silicon and macOS 26 (AVFoundation, no ffmpeg),
and any non-goal flag. **Mic** marks what `samples/Rode-usb-mic.m4a` needs,
per §2's measurements.

### What the quiet desktop-mic recording needs first

The order below follows the §2 measurements, not assumptions:

| Order | Gap | Why, from §2 |
|---|---|---|
| 1 | A1 limiter and A2 loudness-target normalize, together | Peak normalize and the gain-only export target both stop near −27 LUFS; −16 or −14 LUFS needs 11–13 dB of peak reduction |
| 2 | B1 a voice preset chain | The compressor exists but is inert at its defaults on a −18.6 dBFS peak, because it runs before Volume |
| 3 | A5 expander, or A4 voice isolation, beside the shipped noise reduction | After the lift, the pause floor sits around −36 dBFS in 65 % of the windows |
| 4 | A3 high-pass and EQ | A standard step, though only about 1 dB here; presence and tone after that |
| Later | A6 de-esser, B3 leveller, A7 hum removal | Not indicated by the measurements: sibilance inconclusive, LRA is the pauses, no clear hum |

### Tier A: needed to be called professional-grade

**A1. A true-peak limiter, and an export loudness target that reaches its
number.** **Mic: first.**

- **What:** a lookahead, true-peak limiter on the clip strip and on the
  export's mix. The export's loudness stage limits instead of capping gain,
  so −14 LUFS means −14 LUFS.
- **Who:**
  - Resolve: the channel-strip limiter [R1], and Deliver's "Optimize
    loudness and peak" [R3].
  - FCP: Limiter and Adaptive Limiter [F4].
  - Premiere: Hard Limiter [P7], and Media Encoder's true-peak limiter
    inside loudness normalization [P9].
  - Descript: Limiter [D2].
  - ScreenFlow: peak limiting [S1].
- **Why:** quiet voice recordings have a high peak-to-loudness ratio (26 dB
  here), so gain alone hits the ceiling long before any streaming target.
- **Feasibility:** `AUPeakLimiter` exists (attack, decay, pre-gain
  −40…+40 dB) [AD3], but true-peak detection is not documented for it. A
  limiter written beside `AudioDSP.swift`'s compressor, oversampled, is the
  surer route. The mix stage belongs where the export already gains in
  float (`ExporterAudioGain.swift`). A clip limiter in the tap must carry
  the clip's gain itself, because Volume is applied after the tap. The
  preview has no post-mix insert, so a preview master limiter is an open
  design question.
- **Flags:** none named (it is dynamics, like the shipped compressor).
  **NG-AU?** if built on `AUPeakLimiter`.

**A2. Loudness-target clip normalization and level matching.** **Mic:
first.**

- **What:** "Normalize to −16 LUFS" per clip, measured over the played
  range with the BS.1770 gate, and optionally speech-only. Also "match these
  clips' loudness". A clip's measured LUFS is shown in the inspector.
- **Who:** Premiere Auto-Match, with the clip's LUFS displayed [P3]; Resolve
  clip normalization [R1] and the AI Level Matcher [R2]; Descript's LUFS
  export options [D4].
- **Why:** peak normalize lands this file at −27 LUFS while a louder take
  lands elsewhere. Loudness is what a viewer hears, and clips cut together
  need to match.
- **Feasibility:** the BS.1770-4 measurement already exists for the export
  (`Loudness.swift`, `ExporterLoudness.swift`). It needs only a per-clip
  read like Normalize's. The ×32 ceiling (AU-1) covers the gain, and A1
  catches the peaks.
- **Flags:** none named.

**A3. EQ: high-pass, low-pass, shelves and parametric bands, with voice
presets.** **Mic: fourth.**

- **Who:** every professional editor and two creator tools:
  - Resolve: a 6-band clip EQ and a track EQ with 24 dB/octave filters [R1,
    R2, R3].
  - FCP: Equalization presets, Channel EQ and Match [F1, F2, F4].
  - Premiere: Parametric Equalizer and Clarity EQ [P6, P7].
  - Descript: EQs and high-pass [D2].
  - ScreenFlow: EQ [S1].
- **Why:** desk mics pick up rumble, desk thumps and plosives, and EQ is
  the basic tone control. Several other gaps are built from it (A6, A7,
  B6).
- **Feasibility:** `AVAudioUnitEQ` offers parametric, low-pass, high-pass,
  shelf and band-stop types [AD7], and `AUNBandEQ` the same per band [AD6].
  Biquads in the tap are cheap DSP of Frame Job's own and stay live.
- **Flags:** **NG-EQ**.

**A4. ML voice isolation (speech enhancement).** **Mic: third (with A5).**

- **Who:** FCP Voice Isolation [F1]; Resolve Voice Isolation (Studio) [R2,
  R6]; Premiere Enhance Speech [P1]; Descript Studio Sound (cloud) [D1];
  Camtasia AI Noise Removal [T3]; CapCut Enhance voice (*unverified*) [C2].
- **Why:** this is now the baseline one-control fix for noisy rooms and
  cheap microphones, and the creator audience expects it. Frame Job's
  reducer handles only steady noise.
- **Feasibility:** Apple's `AUSoundIsolation` runs on the device (macOS
  13+). Its parameters are a wet/dry mix and a sound type; the
  HighQualityVoice model needs macOS 15+ [AD1]. Render it offline into
  `cache/`, as speed-ramp audio is, with a wet/dry Amount. Its latency, CPU
  cost and quality on this file are unmeasured.
- **Flags:** **NG-AU?**

**A5. Downward expander or noise gate.** **Mic: third.**

- **Who:** Resolve's expander/gate on every strip [R1]; FCP Expander,
  Noise Gate and Spectral Gate [F4].
- **Why:** gain lifts the floor (to around −36 dBFS here). An expander
  pulls the pauses down without touching the speech, and it handles
  non-steady room noise that a spectral reducer can't learn.
- **Feasibility:** `AUDynamicsProcessor` has an expansion ratio and
  threshold [AD4]. A stage written beside the compressor reuses its
  envelope follower.
- **Flags:** none named. **NG-AU?** if built on `AUDynamicsProcessor`.

**A6. De-esser.**

- **Who:** Resolve [R1]; FCP DeEsser 2 [F4]; Premiere DeEss and DeEsser
  [P5].
- **Why:** EQ presence and heavy compression, both needed for quiet voices,
  bring sibilance forward. For this file it is inconclusive (§2).
- **Feasibility:** no Apple de-esser unit was found. Either a
  side-chain-filtered compressor in `AudioDSP`, or `AUMultiBandCompressor`
  (four bands) [AD5].
- **Flags:** **NG-EQ** (a de-esser is a dynamic EQ).

**A7. Hum removal: a notch at 50 or 60 Hz and its harmonics.**

- **Who:** FCP Hum Removal [F1]; Premiere DeHum, DeHummer and Notch Filter
  [P5, P7]; Resolve de-hummer [R1].
- **Why:** ground-loop hum from USB and laptop chargers is common in
  desktop setups. A notch removes it surgically where a spectral reducer
  smears. Not indicated for this file (§2).
- **Feasibility:** band-stop filters at f0 and its multiples:
  `AVAudioUnitEQ`'s band-stop type [AD7], or biquads in the tap.
- **Flags:** **NG-EQ**.

**A8. Live loudness metering, and a per-clip loudness readout.**

- **Who:** Resolve loudness meters and graph [R1]; FCP MultiMeter (LUFS,
  true peak) [F5]; Premiere Loudness Meter [P8].
- **Why:** mixing to a target needs momentary, short-term and integrated
  LUFS and true peak while playing, not only after export.
- **Feasibility:** K-weighting and gating already exist (`Loudness.swift`).
  The metering build already reads every track's tap and applies the plan's
  envelope (`AudioTap.swift`, `LevelMeter.swift`).
- **Flags:** none.

**A9. Animate every audio parameter, and draw volume on the clip.**

- **What:** pan, EQ and effect parameters over time, plus a rubber-band
  volume line on the waveform.
- **Who:** Resolve automation of "virtually any control" [R1]; FCP's Audio
  Animation editor [F11]; Premiere clip and track keyframes with the Pen
  tool, and automation modes [P10, P11]; Camtasia audio points [T2].
- **Why:** a static pan or EQ per clip is a creator-tier limit. Professional
  mixes ride levels inside clips, and Frame Job's actions can't reach pan
  or effects today (audio.md).
- **Feasibility:** core and UI work with no new framework. The tap already
  schedules settings by clip span (`AudioDSPSpan`); per-parameter envelopes
  would extend that schedule.
- **Flags:** none.

**A10. Split edits (J- and L-cuts) that keep sync, and reversible
detaching.**

- **Who:** FCP Expand Audio and split edits [F10]; Premiere Unlink and
  ⌥-drag [P16].
- **Why:** J- and L-cuts are the most common dialogue edit. Frame Job's
  Detach Audio is one way, and "no control … switches a clip's audio back
  on" (audio.md).
- **Feasibility:** a model and timeline-gesture change; no framework
  needed.
- **Flags:** none.

**A11. Stems: each track, or each group of tracks, as its own file.**

- **Who:** FCP roles as separate files or a multitrack QuickTime [F9];
  Descript per-track mono files (an article title only) [D4]. Resolve and
  Premiere were not verified.
- **Why:** hand-off to a mixer, music-and-effects versions, a
  voice-without-music version for translation.
- **Feasibility:** per-track files can reuse the export with the other
  tracks silenced. A multitrack MOV would need several `AVAssetWriterInput`s
  (unverified here).
- **Flags:** **NG-ROLES** only if it is done by role rather than by track.

**A12. Track faders and track or bus processing.**

- **Who:** Resolve's mixer, buses and FlexBus [R1]; Premiere's Audio Track
  Mixer and submixes [P10]. FCP gets by without a mixer, through roles and
  compound clips [F3, F8].
- **Why:** "music 6 dB down everywhere" is one fader, not forty clip edits.
  A compressor or limiter across a whole voice track behaves differently
  from per-clip ones at clip boundaries.
- **Feasibility:** a track fader is an envelope in the plan. Track effects
  have no natural home, because composition audio tracks are not timeline
  tracks (`AudioTap.swift` notes the A/B assignment). They need a design
  spike.
- **Flags:** **NG-BUS**.

**A13. 24-bit (and float-decoded) audio export.**

- **Who:** not verified across editors.
- **Why:** a delivery and archival expectation.
- **Feasibility:** issue #86 has the design: a float decode before the gain,
  then an `audio_bits` override.
- **Flags:** none.

### Tier B: expected by the creator and screencast audience

**B1. A one-click "Enhance voice" chain.** **Mic: second.**

- **What:** high-pass → noise reduction or isolation → compressor set
  relative to the clip's measured level → limiter → loudness target. It
  writes ordinary clip settings that a person can then edit.
- **Who:** FCP Enhance Audio [F1]; Resolve AI Audio Assistant (Studio)
  [R2]; Premiere Auto Tag plus Auto-Match [P15, P3]; Descript Studio Sound
  [D1].
- **Why:** a screencaster wants one button. The shipped compressor shows
  that defaults fixed in dBFS fail on a quiet mic (§2).
- **Feasibility:** no DSP beyond A1–A5. The assistant and agents get it
  through the same tool (agent parity).
- **Flags:** inherits its parts' flags.

**B2. Speech-aware ducking.**

- **What:** keyed by voice activity, not clip extent, with a pre-roll. It
  is drawn as an envelope the person can see and edit.
- **Who:** Premiere Auto Ducking, which writes keyframes [P4]; Resolve's
  signal-keyed Ducker with lookahead [R3, R4].
- **Why:** today's ducking holds music down through every pause of a long
  voice clip (audio.md).
- **Feasibility:** the on-device voice model already runs per media for
  Remove Silences (`cleanup-tools.md`). Its speech spans can shape the duck
  envelope in the plan, deterministically, with no new framework.
- **Flags:** none.

**B3. Dialogue leveller (a slow gain rider).**

- **Who:** Resolve Dialogue Leveler [R2, R3].
- **Why:** a speaker who leans in and out, or a two-person recording. Not
  indicated for this file, whose LRA is the pauses (§2).
- **Feasibility:** computed offline from short-term loudness into the
  envelope, or a slow stage of Frame Job's own.
- **Flags:** none.

**B4. De-reverb.**

- **Who:** Premiere Reduce Reverb and DeReverb [P5, P7]; Descript Studio
  Sound "echo" [D1]; Resolve's Dialogue Separator ambience [R3].
- **Why:** laptop microphones in untreated rooms.
- **Feasibility:** no Apple de-reverb unit was found. Whether
  `AUSoundIsolation` removes reverberation is unverified.
- **Flags:** **NG-AU?** if it rides on A4.

**B5. Audio scrubbing.**

- **Who:** FCP audio skimming [F14].
- **Why:** finding a word by ear while dragging the playhead. Frame Job's
  scrub is silent (`timeline.md`).
- **Feasibility:** unverified. It needs short-grain playback at the scrub
  position.
- **Flags:** none.

**B6. Match one clip to another: EQ, level and room.**

- **Who:** FCP Match Audio [F2]; Resolve AI EQ Matcher, Level Matcher and
  Dialogue Matcher [R2].
- **Why:** a camera's scratch audio cut against the RØDE, or two sessions
  on different days.
- **Feasibility:** a spectrum difference becomes an EQ curve (needs A3). The
  level half is A2.
- **Flags:** **NG-EQ**.

**B7. Channel selection: left only, right only, dual mono.**

- **Who:** FCP channel configuration [F7]; Premiere Modify ▸ Audio Channels
  [P12]; Resolve channel mapping [R1, R4]; ScreenFlow per-channel pan and
  level [S1].
- **Why:** USB and XLR interfaces often record a mono mic onto one channel
  of a stereo file. Frame Job's Mix to mono averages the channels, which
  lands 6 dB down when one channel is silent.
- **Feasibility:** a channel pick before the mono fold in the tap. Trivial
  DSP, plus a model field.
- **Flags:** none.

**B8. Clean-up at record time.**

- **Who:** Resolve's Voiceover tool, with Voice Isolation, Dialog Leveler
  and Stereo Fixer while recording [R2]; Descript Studio Sound while
  recording [D1].
- **Why:** a voice-over should land ready to use.
- **Feasibility:** the raw file is kept, and the B1 chain is applied as
  clip settings when the Microphone clip lands, so no new DSP. Apple's
  voice processing on the input node [AD12] was not evaluated and is not
  proposed.
- **Flags:** none.

**B9. Fade and crossfade curve shapes.**

- **Who:** FCP Linear, S-curve, +3 dB and −3 dB [F13]; Premiere Constant
  Gain, Constant Power and Exponential [P18].
- **Feasibility:** envelope shapes in the core's plan.
- **Flags:** none.

**B10. Voice effects (E8).**

- **Who:** FCP Pitch Shifter, Vocal Transformer and reverbs [F4]; Resolve
  Voice Convert (Studio) [R2]; Camtasia Pitch (Mac) [T1]; Descript's
  creative effects [D2]; CapCut voice changer (*unverified*) [C1].
- **Feasibility:** already designed and measured as E8 (#123): fixed chains
  of Apple units rendered offline.
- **Flags:** **E8**; **NG-AU?**

### Tier C: nice to have

| Gap | Who | Feasibility (one line) | Flags |
|---|---|---|---|
| **C1 Beat detection** (snap edits to beats) | Resolve AI Beat Detector (Studio) [R2]; FCP 12.0 [F16]; CapCut (*unverified*) [C1] | No Apple beat API found; Frame Job's own onset and tempo analysis, cached per media like the sync features | — |
| **C2 Music retimed to a length** | Premiere Remix [P13]; Resolve AI Music Editor (Studio) [R2] | Builds on C1: beat-aligned cuts plus crossfades | — |
| **C3 Source separation** (dialogue, background and ambience; music stems) | Resolve Dialogue Separator, Music Remixer (Studio) [R3] | Apple's `AUAudioMix` (macOS 26) separates foreground and background but reads "Remix metadata from the file asset" [AD2], i.e. Spatial Audio captures, not arbitrary files | NG-AU? |
| **C4 AI speech** (text-to-speech, word regeneration, voice conversion) | Descript Regenerate, AI Speakers [D5]; Resolve Voice Convert [R2], speech generator (21) [R5] | Cloud, so bring-your-own key and no relay; cloning a voice raises consent questions | — |
| **C5 Audio Unit plug-in hosting** | FCP [F3]; Resolve (VST, AU) [R1]; ScreenFlow [S1] | `AVAudioUnitComponentManager` lists installed units [AD11]; hosting live in the tap is the hard part (#123: the tap can't host a pitch shifter); offline render works | NG-AU, NG-PLUGIN |
| **C6 Round-trip to an external audio editor** | Premiere → Audition [P14]; Resolve → external tools such as iZotope RX [R1] | Render a clip's window to WAV and relink the edited return | — |
| **C7 Automatic audio-type tagging** (dialogue, music, effects) | Premiere Auto Tag [P15] | Sound Analysis's built-in classifier ("hundreds of sounds") [AD8]; it would feed B1 and B2 | NG-ROLES if it becomes roles |
| **C8 Spectrum analyzer** | Resolve Frequency Analyzer, RTA [R3]; FCP MultiMeter analyzer [F5] | vDSP FFT on the metering tap (`RealFFT.swift` already exists) | — |
| **C9 Sample-level waveform repair** (pencil, de-click) | Resolve [R1] | Destructive edits to a cached copy; a large UI piece | — |
| **C10 Surround and immersive mixing; ADR tooling** | Resolve [R1, R2]; FCP 5.1 [F7] | Outside the screencast audience | — |

## 6. Sample recordings to add

The owner asked for more real recordings. Each one below is chosen to give a
gap a "before" to measure against. Keep each 30–90 s, record at the device's
native rate, and add a `samples/README.md` row measured the way
`Rode-usb-mic.m4a`'s was: true peak, integrated LUFS, LRA, plus the measure
named here.

| # | Recording | Exercises | Measure for the README row |
|---|---|---|---|
| 1 | The same RØDE, the same words, mouth about 10 cm from the mic with the gain up, including a laugh or shout that **clips** | A1, A2; what clipping at the source does to them (de-clipping was not surveyed) | Sample peak at 0 dBFS, count of full-scale samples |
| 2 | Desk mic with a **fan, HVAC or laptop-charger hum** audible in the pauses | A7, A4, the shipped noise reducer, A5 | Tonal peak at 50/60 Hz and its harmonics over neighbouring bins; floor in dBFS |
| 3 | A **sibilant** voice close to the mic (lines dense in "s", "sh", "ch") | A6, and A3's presence boost making it worse | 5–9 kHz vs 0.3–4 kHz ratio, 95th percentile |
| 4 | The **MacBook's built-in mic** in a hard-walled room, 1 m away | A4, B4 | The decay after a hand clap (a reverb time estimate) |
| 5 | **Plosives**: "p" and "b" lines close to a mic with no pop filter | A3 high-pass | Energy below 80 Hz on the plosive windows |
| 6 | **Two people, two mics**, a conversation with cross-talk and bleed (two files) | A5, B2, B3, A12, Synchronize Audio | LRA per file; bleed level of one voice on the other's mic |
| 7 | A voice-over with **pauses over a music bed** (two files, voice and music) | B2, A8, A11, C1, C2 | Music's integrated LUFS; voice's speech spans |
| 8 | A speaker who **moves off-mic** and back (turning away mid-sentence) | B3 | Short-term loudness spread over speech-only windows |
| 9 | A **stereo file with the mic on one channel only** (a USB or XLR interface's input 1) | B7 | Per-channel peak; the silent channel's floor |
| 10 | A **screen recording with system audio** (app sounds, a notification ding) **and the mic** | A12, A11, B2 | Per-file integrated LUFS |
| 11 | The **GH5's camera audio and the RØDE**, the same take | B6, A2, Synchronize Audio | Integrated LUFS and spectral tilt of each |
| 12 | An **iPhone video with Spatial Audio** capture (the owner's iPhone) | C3: does `AUAudioMix` read its remix metadata | Whether the asset carries the metadata; separation result |
| 13 | A **10-minute** talking-head take on the RØDE | Offline render time and cache size for A4 and B1; A2 on long material | Duration; render time per minute when built |

## 7. Sources

### DaVinci Resolve (Blackmagic Design)

- [R1] Fairlight product page: https://www.blackmagicdesign.com/products/davinciresolve/fairlight
- [R2] DaVinci Resolve 20 New Features Guide (April 2025): Voice Convert, Voiceover tool, AI Dialogue Matcher, AI Music Editor, AI Beat Detector, and the Fairlight chapter (AI IntelliCut, EQ Matcher, Level Matcher, AI Audio Assistant, Clip EQ, automation): https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_20_New_Features_Guide.pdf
- [R3] DaVinci Resolve 19 New Features Guide (April 2024): Deliver audio normalization; Fairlight chapter (IntelliTrack panning, sidechaining, Dialogue Separator, Music Remixer, Ducker, Voice Isolation and Dialogue Leveler updates, Frequency Analyzer, track EQ): https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_19_New_Features_Guide.pdf
- [R4] DaVinci Resolve 19.1 New Features Guide (November 2024): Ducker with several sources, automation, channel source: https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_19_1_New_Features_Guide.pdf
- [R5] DaVinci Resolve What's New (Resolve 21): https://www.blackmagicdesign.com/products/davinciresolve/whatsnew
- [R6] DaVinci Resolve Studio page: https://www.blackmagicdesign.com/products/davinciresolve/studio

### Final Cut Pro (Apple)

- [F1] Enhance audio: https://support.apple.com/guide/final-cut-pro/enhance-audio-verc1fab873/mac
- [F2] Match audio: https://support.apple.com/guide/final-cut-pro/match-audio-ver1632db40/mac
- [F3] Add audio effects: https://support.apple.com/guide/final-cut-pro/add-audio-effects-verb71ca88f/mac
- [F4] Final Cut Pro Logic Effects (contents): https://support.apple.com/guide/final-cut-pro-logic-effects/welcome/mac
- [F5] MultiMeter level and loudness controls: https://support.apple.com/guide/final-cut-pro-logic-effects/level-and-loudness-controls-lgex1d0722a3/mac
- [F6] View and change audio levels: https://support.apple.com/guide/final-cut-pro/view-and-change-audio-levels-verc1faad4f/mac
- [F7] Configure audio channels: https://support.apple.com/guide/final-cut-pro/configure-audio-channels-verc1fab5f6/mac
- [F8] Organize the timeline with audio lanes: https://support.apple.com/guide/final-cut-pro/organize-the-timeline-with-audio-lanes-verb71cb913/mac
- [F9] Share roles as files: https://support.apple.com/guide/final-cut-pro/share-roles-as-files-verc9c84cdbc/mac
- [F10] Create split edits: https://support.apple.com/guide/final-cut-pro/create-split-edits-ver1632d82c/mac
- [F11] Keyframe audio effects: https://support.apple.com/guide/final-cut-pro/keyframe-audio-effects-ver717f5914/mac
- [F12] Crossfade audio: https://support.apple.com/guide/final-cut-pro/crossfade-audio-ver66d503b23/mac
- [F13] Fade audio in and out: https://support.apple.com/guide/final-cut-pro/fade-audio-in-and-out-ver39580fed/mac
- [F14] Skim media: https://support.apple.com/guide/final-cut-pro/skim-media-vere9ba3609/mac
- [F15] Sync audio and video: https://support.apple.com/guide/final-cut-pro/sync-audio-and-video-verc1fabc30/mac
- [F16] Final Cut Pro release notes (12.0: Beat Detection, Transcript Search): https://support.apple.com/en-us/102825

### Premiere Pro and Media Encoder (Adobe; read through search excerpts)

- [P1] Enhance speech: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/enhance-speech.html
- [P2] Enhance Speech technical requirements: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/enhance-speech-technical-requirements.html
- [P3] Auto-match audio loudness: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/auto-match-audio-loudness.html
- [P4] Automatically duck audio: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/automatically-duck-audio.html
- [P5] Repair dialogue: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/repair-dialogue.html
- [P6] Improve dialogue clarity: https://helpx.adobe.com/premiere/desktop/add-audio-effects/adjust-volume-and-levels/improve-dialogue-clarity.html
- [P7] Audio effects and transitions (Hard Limiter, DeNoise, DeReverb, Parametric Equalizer, Notch): https://helpx.adobe.com/se/premiere-pro/using/audio-effects-transitions.html
- [P8] Loudness Meter overview: https://helpx.adobe.com/premiere/desktop/add-audio-effects/apply-audio-effects/about-loudness-meter.html
- [P9] Media Encoder, automatic loudness correction: https://helpx.adobe.com/media-encoder/using/automatic-loudness-correction.html
- [P10] Audio Track Mixer: https://helpx.adobe.com/premiere/desktop/add-audio-effects/advanced-audio-techniques/about-audio-track-mixer.html, and its automation modes: https://helpx.adobe.com/uk/premiere/desktop/add-audio-effects/apply-audio-effects/audio-track-mixer-automation-modes.html
- [P11] Adjusting gain and volume (Audio Gain normalize, keyframes): https://helpx.adobe.com/be_en/premiere-pro/using/adjusting-volume-levels.html
- [P12] Change source audio channel mapping: https://helpx.adobe.com/nz/premiere/desktop/add-audio-effects/advanced-audio-techniques/change-source-audio-channel-mapping.html
- [P13] Remix audio: https://helpx.adobe.com/premiere/desktop/add-audio-effects/apply-audio-effects/remix-audio-in-premiere.html
- [P14] Edit Premiere sequences in Audition: https://helpx.adobe.com/premiere/desktop/use-premiere-with-other-apps/working-with-other-adobe-applications/edit-premiere-sequences-in-audition.html
- [P15] Auto tag audio categories: https://helpx.adobe.com/uk/premiere-pro/using/audio-auto-tagging.html
- [P16] Create J and L cuts: https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-j-cuts-and-l-cuts.html
- [P17] Detect and delete pauses in transcripts: https://helpx.adobe.com/premiere/desktop/edit-projects/edit-video-using-text-based-editing/detect-and-delete-pauses-in-transcripts.html
- [P18] Apply audio crossfade transitions: https://helpx.adobe.com/premiere/desktop/add-audio-effects/apply-audio-transitions/audio-crossfade-transitions.html
- [P19] Synchronize audio and video: https://helpx.adobe.com/premiere/desktop/add-audio-effects/basic-audio-editing/synchronize-audio-and-video.html

### Descript

- [D1] Studio Sound: https://help.descript.com/hc/en-us/articles/10327603613837-Studio-Sound
- [D2] Audio effects: https://help.descript.com/hc/en-us/sections/22869936117645-Audio-effects
- [D3] Lower audio of other layers: https://help.descript.com/effects-animations-transitions/lower-other-audio.md
- [D4] Export an audio file: https://help.descript.com/hc/en-us/articles/10255754857741-Export-an-audio-file
- [D5] Descript terms and concepts: https://help.descript.com/descript-terms-and-concepts
- [D6] Filler words: https://help.descript.com/hc/en-us/articles/10164806394509-Filler-words, and Shorten word gaps: https://help.descript.com/hc/en-us/articles/10164807277453-Shorten-word-gaps

### CapCut (vendor marketing, not documentation, except C3)

- [C1] How to edit a voice recording: https://www.capcut.com/resource/edit-voice-recording
- [C2] Audio booster for PC: https://www.capcut.com/resource/audio-booster-for-pc
- [C3] What is Auto Cut in CapCut (help site, read through a search excerpt): https://www.capcut.com/help/auto-cut-in-capcut

### Camtasia (TechSmith)

- [T1] Add audio effects: https://www.techsmith.com/learn/tutorials/camtasia/add-audio-effects/
- [T2] Edit audio: https://www.techsmith.com/learn/tutorials/camtasia/editing-audio/
- [T3] Camtasia Mac 2026 version history: https://support.techsmith.com/hc/en-us/articles/41263167862285-Camtasia-Mac-2026-Version-History

### ScreenFlow (Telestream)

- [S1] ScreenFlow 10 User Guide (August 2025): Audio Properties, the Audio Filters pane, the audio mixer, ducking, audio actions, filters and the Audio Unit sandbox note: https://www.telestream.net/pdfs/user-guides/ScreenFlow-10-User-Guide.pdf

### Apple developer documentation and the macOS 26.2 SDK

- [AD1] `kAudioUnitSubType_AUSoundIsolation` (macOS 13.0+): https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_ausoundisolation. Its parameters `kAUSoundIsolationParam_WetDryMixPercent` and `kAUSoundIsolationParam_SoundToIsolate`, and `kAUSoundIsolationSoundType_HighQualityVoice` (macOS 15.0+), are in the SDK's `AudioToolbox/AudioUnitParameters.h`.
- [AD2] `kAudioUnitSubType_AUAudioMix` (macOS 26.0+): https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_auaudiomix. `AUComponent.h` describes it as "AudioMix separate-and-remix functionality". `AudioUnitProperties.h` gives `kAUAudioMixProperty_SpatialAudioMixMetadata`: "Remix metadata from the file asset".
- [AD3] `kAudioUnitSubType_PeakLimiter`, "An audio unit that enforces an upper dynamic limit on an audio signal": https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_peaklimiter. Its parameters (`kLimiterParam_AttackTime`, `DecayTime`, `PreGain` −40…40 dB) are in `AudioUnitParameters.h`.
- [AD4] `kAudioUnitSubType_DynamicsProcessor`: https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_dynamicsprocessor. Its expansion ratio and threshold parameters are in `AudioUnitParameters.h`.
- [AD5] `kAudioUnitSubType_MultiBandCompressor`, "four-bands of dynamic compression or expansion": https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_multibandcompressor
- [AD6] `kAudioUnitSubType_NBandEQ`, "A generalized N-band graphic EQ with specifiable filter types per-band" (`AUComponent.h`): https://developer.apple.com/documentation/audiotoolbox/kaudiounitsubtype_nbandeq
- [AD7] `AVAudioUnitEQ` (macOS 10.10+): https://developer.apple.com/documentation/avfaudio/avaudiouniteq. Its filter types (parametric, low and high pass, band-pass, band-stop, shelves) are in `AVFAudio/AVAudioUnitEQ.h`.
- [AD8] `SNClassifySoundRequest` (macOS 10.15+), the built-in classifier `SNClassifierIdentifier.version1`: https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest
- [AD9] `AVAudioEngine.enableManualRenderingMode(_:format:maximumFrameCount:)`, offline rendering: https://developer.apple.com/documentation/avfaudio/avaudioengine/enablemanualrenderingmode(_:format:maximumframecount:)
- [AD10] `AVMutableAudioMixInputParameters.audioTapProcessor`: https://developer.apple.com/documentation/avfoundation/avmutableaudiomixinputparameters/audiotapprocessor, and Technical Q&A QA1783 (the PreEffects and PostEffects tap flags): https://developer.apple.com/library/archive/qa/qa1783/_index.html
- [AD11] `AVAudioUnitComponentManager`: https://developer.apple.com/documentation/avfaudio/avaudiounitcomponentmanager
- [AD12] `AVAudioIONode.setVoiceProcessingEnabled(_:)`: https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)

### Frame Job's own pages

- `docs/guide/audio.md`, `docs/guide/export.md`, `docs/guide/cleanup-tools.md`, `docs/guide/speed.md`, `docs/guide/screen-recording.md`, `docs/guide/timeline.md`, `docs/guide/editing.md`
- `designs/spec/01-what-this-is.md` (the non-goals); `designs/spec/11-decisions/audio.md` (AU-1)
- `app/Sources/AudioTap.swift`, `app/Sources/ExporterAudioGain.swift`, `app/Sources/RampAudioRenderer+TimePitch.swift`
- Issues #86, #123, #299
- `samples/Rode-usb-mic.m4a` and `samples/README.md`
