import Foundation

// What one composition audio track's tap is told, decided when the composition is built: the
// schedule of clip spans and the per-clip parameters, with where they come from. A pure move
// out of `AudioTap.swift` (road map "audio" AP0's toll T2), whose head says how the tap
// carries them into the audio path.

// MARK: - The schedule

/// One clip's stretch of a composition audio track, in composition ticks.
///
/// Composition time equals timeline time on these tracks — `CompositionBuilder`
/// fills them behind a cursor precisely so that stays true through speed
/// changes — so the plan's own `start` and `duration` are what a buffer's
/// timestamp is compared against.
struct AudioDSPSpan: Equatable {
    let start: Ticks
    /// Exclusive.
    let end: Ticks
    /// The clip's base settings; what every run reads on a span without
    /// `automation`.
    let dsp: AudioClipDSP
    /// The clip's automation when it moves the tap's settings (spec §11
    /// AU-87): each run then reads its settings at its anchor instead.
    let automation: AudioDSPAutomation?

    init(start: Ticks, end: Ticks, dsp: AudioClipDSP, automation: AudioDSPAutomation? = nil) {
        self.start = start
        self.end = end
        self.dsp = dsp
        self.automation = automation
    }
}

/// What one composition audio track's tap needs to know, decided once when
/// the composition is built.
struct AudioTrackDSP: Equatable {
    let spans: [AudioDSPSpan]
    /// Whether any clip on this track asks for anything at all. False means no
    /// tap is created, and the track's samples are exactly what the build
    /// before this file existed produced.
    let isActive: Bool
    /// Whether the noise reducer runs for the WHOLE track. It is all or
    /// nothing per track by design: the stage delays by 512 samples, and
    /// switching it in at a cut would jump the track 10 ms backwards
    /// mid-programme.
    let usesNoiseReduction: Bool
    /// Whether the limiter runs for the WHOLE track (spec §11 AU-23): once
    /// any clip on it has one, for the same reason as the noise reducer — its
    /// 158-sample delay may not come and go at a cut.
    let usesLimiter: Bool
    /// How far ahead of a buffer's composition time the tap looks its spans
    /// up: `AudioShift.limiterLead` on a limited track, else 0, plus
    /// `trackLead`. The media is placed that much earlier, so the samples
    /// entering the stages after the noise reducer belong to
    /// `t + lookupLead`, and the limiters' delays bring them back to `t`
    /// (AU-23, AU-153).
    let lookupLead: Ticks
    /// The track's compressor and limiter on a metering build (spec §11
    /// AU-153), run after the chain with the track's envelope; nil on every
    /// other build and for a track with neither.
    let dynamics: AudioTrackDynamics?
    /// `AudioShift.limiterLead` when `dynamics` has a limiter, else 0: the
    /// track limiter's delay, made up by placement (AU-153).
    let trackLead: Ticks
    /// How much further ahead the HEAD stages (the channel pick, the EQ and
    /// hum) look their clip up: `AudioShift.noiseReductionLead` on a
    /// noise-reduced track, else 0. They run before the reducer, whose delay
    /// is what brings the samples back to `t + lookupLead` (AU-34).
    let headLead: Ticks

    init(
        segments: [PlanSegment], parameters: AudioDSPParameters,
        dynamics: AudioTrackDynamics? = nil
    ) {
        var spans: [AudioDSPSpan] = []
        spans.reserveCapacity(segments.count)
        for segment in segments where segment.duration > 0 {
            var dsp = parameters.dsp(for: segment.clip)
            // The tracks' pans ride the plan, per segment (spec §11 AU-104).
            dsp.trackBalance = AudioTrackBalance(pans: segment.trackPans)
            // The clip's actions, when they move anything the tap runs (AU-87).
            // Inert points are the segment's whole state, so the base does
            // not stand in for them: nothing runs there.
            let automation = parameters.automation(for: segment)
            if let automation, automation.isInert { continue }
            guard !dsp.isInert || automation != nil else { continue }
            spans.append(
                AudioDSPSpan(
                    start: segment.start, end: segment.start + segment.duration, dsp: dsp,
                    automation: automation))
        }
        self.spans = spans
        isActive = !spans.isEmpty
        // A stage switched on at an action's end runs for the whole track too.
        usesNoiseReduction = spans.contains {
            $0.dsp.noiseReduction > 0 || $0.automation?.usesNoiseReduction == true
        }
        usesLimiter = spans.contains { $0.dsp.limiter != nil || $0.automation?.usesLimiter == true }
        self.dynamics = dynamics
        trackLead = dynamics?.settings.limiter == nil ? 0 : CompositionBuilder.AudioShift.limiterLead
        lookupLead = (usesLimiter ? CompositionBuilder.AudioShift.limiterLead : 0) + trackLead
        headLead = usesNoiseReduction ? CompositionBuilder.AudioShift.noiseReductionLead : 0
    }

    private init() {
        spans = []
        isActive = false
        usesNoiseReduction = false
        usesLimiter = false
        lookupLead = 0
        dynamics = nil
        trackLead = 0
        headLead = 0
    }

    /// A track that asks for no processing at all. What a METERING-only tap is
    /// built with: it still has to fetch and hand on its source audio, and it
    /// still has to measure it, but no chain is built for it and no sample is
    /// touched.
    static let inert = AudioTrackDSP()
}

// MARK: - Parameters, and where they come from

/// Every clip's sample-level audio settings, keyed by clip id.
///
/// Only the clips that ask for something are in the dictionary: an empty one
/// means the whole project needs no tap anywhere, which is the state every
/// project made before this feature existed is in.
struct AudioDSPParameters: Equatable {
    private let clips: [UInt32: AudioClipDSP]
    /// Each clip's `audio.isolation` when above 0 (spec §11 AU-50, AU-53):
    /// the tap's crossfade with the clip's isolated render, before the chain.
    /// The BASE amount, never on a nest clip; an action's amounts ride the
    /// plan's automation (AU-88).
    private let isolation: [UInt32: Double]
    /// The clips whose isolated render is wanted: the base asks, or any
    /// action end's `audio.isolation` is above 0 (AU-88). Never a nest clip.
    private let wantedIsolation: Set<UInt32>
    /// Each non-nest clip's base volume (the limiter's divisor, AU-22) and
    /// measured level (AU-41), which its automation's settings keep.
    private let bases: [UInt32: Base]
    /// The gated or de-essed clips whose level is still pending (AU-42):
    /// they play without both stages, and an export waits for them.
    let pendingLevels: Set<UInt32>
    /// Each clip's voice effect as its chain reads it, when not inert (spec
    /// §11 AU-140, AU-141): rendered offline and played in place of the
    /// clip's sound before the chain (AU-143). Base only, never on a nest clip.
    private let voiceSettings: [UInt32: VoiceSettings]
    /// Each timeline track's compressor and limiter, by track id, when it has
    /// either (spec §11 AU-150): `snapshot.tracks` only, a nest's own tracks
    /// having none. Not counted by `isEmpty`, so a build whose taps would be
    /// what they were stays so (AU-153); a change still rebuilds the preview,
    /// this being part of the parameters' equality.
    let trackDynamics: [UInt32: AudioTrackDynamicsSettings]

    private struct Base: Equatable {
        let volume: Double
        let level: Double?
    }

    static let empty = AudioDSPParameters(clips: [:], isolation: [:], voiceSettings: [:])

    private init(
        clips: [UInt32: AudioClipDSP], isolation: [UInt32: Double],
        voiceSettings: [UInt32: VoiceSettings]
    ) {
        self.clips = clips
        self.isolation = isolation
        wantedIsolation = Set(isolation.keys)
        bases = [:]
        pendingLevels = []
        self.voiceSettings = voiceSettings
        trackDynamics = [:]
    }

    /// Reads the settings off a project snapshot, nests included — a nested
    /// clip gets its own composition audio track exactly as a top-level one
    /// does, and `Project.clips` and `Nest.clips` share one id space, so one
    /// flat dictionary covers both.
    ///
    /// **A nest CLIP is not in the dictionary, and its own `mono` is carried
    /// down instead.** The plan replaced a nest with the clips inside it
    /// (`nest.rs`), so an audio segment always names the INNERMOST clip and
    /// nothing could ever look a nest clip's entry up — a `mono` written on
    /// one would be accepted by the core, kept by the checkbox, saved with
    /// the project and silently fold nothing, which is what it did until this
    /// walk existed. So every clip inside a folded nest is marked
    /// `enclosingMono` and folds at the tail of its own chain, which sums to
    /// exactly the fold of the nest's mix (`AudioClipDSP.enclosingMono`).
    /// A nest inside a folded nest is walked too: an outer fold applies to
    /// everything within, and folding twice is folding once.
    ///
    /// **The nest clip's other three do NOT travel, and two of them cannot**
    /// (nor does its limiter, AU-21, for the compressor's reason, nor its
    /// channel pick, EQ and hum, AU-37).
    /// The compressor and the noise reducer are not linear, so running either
    /// on each contributor is a different sound from running it on the mix —
    /// bus compression is the whole reason a bus has a compressor — and the
    /// reducer would also delay each inner track by its own 512 samples. Pan
    /// is linear and could ride down the same walk, but two pans do not
    /// compose into one number (`AudioClipDSP` carries one `pan`, and the
    /// product of two constant-power pairs is no single position), and
    /// turning it on would change how projects that already carry a nest pan
    /// sound — the decision M3 recorded for `mono` itself, which phase 5
    /// took deliberately and one at a time. So a nest clip's pan, compressor
    /// and noise reduction reach nothing, exactly as they did in M3.
    ///
    /// **One limit the id space imposes:** two nest clips may show the SAME
    /// nest, and the dictionary is keyed by clip id while the plan's segments
    /// carry no instance path, so a fold asked for by one of them folds both.
    /// Folding is the choice that makes the control do what it says on the
    /// clip that asked; the alternative — fold only when every nest clip
    /// showing the nest agrees — makes the checkbox do nothing at all.
    ///
    /// **These are the BASE settings; actions move them through the plan.**
    /// A clip whose actions name a tap key has its segment's `automation`,
    /// points the core evaluated (spec §11 AU-85), and `automation(for:)`
    /// pairs them with the base facts they keep: the volume the limiter
    /// divides by (AU-22) and the measured level (AU-41). Evaluation stays
    /// Rust's; the tap only interpolates between points (AU-87).
    ///
    /// **The gate and the de-esser need `levels`** (AU-41, AU-42): a clip
    /// measured at L gets thresholds relative to L; a pending or unmeasurable
    /// one (or one `levels` does not name, which is every clip for the
    /// callers that pass none: isolation and ramp renders) gets neither, and
    /// a pending one is in `pendingLevels`.
    init(snapshot: ProjectSnapshot, levels: [UInt32: AudioDynamicsLevels.Level] = [:]) {
        var clips: [UInt32: AudioClipDSP] = [:]
        var isolation: [UInt32: Double] = [:]
        var wanted: Set<UInt32> = []
        var bases: [UInt32: Base] = [:]
        var pending: Set<UInt32> = []
        var voiceSettings: [UInt32: VoiceSettings] = [:]
        func collect(_ list: [ClipSnapshot]) {
            for clip in list {
                // A nest clip's own entry could never be looked up: its id
                // names no audio segment. `fold` below is where its `mono`
                // goes instead.
                guard clip.source.nestID == nil else { continue }
                let audio = clip.audio ?? AudioProps()
                if audio.isolation > 0 { isolation[clip.id] = min(audio.isolation, 1) }
                if audio.isolation > 0
                    || clip.actions.contains(where: { ($0.end.audio?.isolation ?? 0) > 0 })
                {
                    wanted.insert(clip.id)
                }
                var level: Double?
                switch levels[clip.id] {
                case .measured(let lufs): level = lufs
                case .pending: pending.insert(clip.id)
                case .unmeasurable, nil: break
                }
                bases[clip.id] = Base(volume: audio.volume, level: level)
                if let voice = audio.voice {
                    let settings = VoiceChain.settings(voice)
                    if !VoiceChain.isInert(settings) { voiceSettings[clip.id] = settings }
                }
                let dsp = AudioDSPParameters.dsp(
                    audio, volume: audio.volume, level: level, enclosingMono: false)
                guard !dsp.isInert else { continue }
                clips[clip.id] = dsp
            }
        }
        collect(snapshot.clips)
        for nest in snapshot.nests { collect(nest.clips) }

        // Marks everything `nestID` stands for, however deep. Bounded by the
        // core's `MAX_NEST_DEPTH` (8, `format.rs`) rather than trusted to
        // terminate: `validate` refuses a deeper — and so a circular — nest,
        // but this walk reads a decoded snapshot and a walk that can be
        // handed a cycle is a walk that must be bounded.
        func fold(contentsOf nestID: UInt32, depth: Int) {
            guard depth <= AudioDSPParameters.nestDepthCap, let nest = snapshot.nest(nestID)
            else { return }
            for clip in nest.clips {
                if let inner = clip.source.nestID {
                    fold(contentsOf: inner, depth: depth + 1)
                    continue
                }
                // Every clip inside, not only the ones carrying audio props:
                // which of them gets an audio segment is `evaluate.rs`'s rule
                // (the media has sound, and `enabled.audio` holds all the way
                // up), not one Swift may restate, and an entry the tap never
                // looks up costs a dictionary slot and nothing else.
                var dsp = clips[clip.id] ?? .inert
                dsp.enclosingMono = true
                clips[clip.id] = dsp
            }
        }
        func foldMonoNests(_ list: [ClipSnapshot]) {
            for clip in list where clip.audio?.mono == true {
                guard let nestID = clip.source.nestID else { continue }
                fold(contentsOf: nestID, depth: 1)
            }
        }
        foldMonoNests(snapshot.clips)
        for nest in snapshot.nests { foldMonoNests(nest.clips) }
        self.clips = clips
        self.isolation = isolation
        wantedIsolation = wanted
        self.bases = bases
        pendingLevels = pending
        self.voiceSettings = voiceSettings
        var dynamics: [UInt32: AudioTrackDynamicsSettings] = [:]
        for track in snapshot.tracks {
            if let settings = AudioTrackDynamicsSettings(track) { dynamics[track.id] = settings }
        }
        trackDynamics = dynamics
    }

    /// One clip's chain settings from its audio props: the base's in `init`,
    /// a point's in `AudioDSPAutomation.settings(at:)`. `volume` is the BASE
    /// volume either way (the limiter's divisor, AU-22) and `level` the base
    /// measurement (AU-41); with no level the gate and de-esser are off.
    static func dsp(
        _ audio: AudioProps, volume: Double, level: Double?, enclosingMono: Bool
    ) -> AudioClipDSP {
        AudioClipDSP(
            pan: audio.pan,
            compressor: audio.compressor.map {
                AudioCompressorSettings(
                    thresholdDB: $0.thresholdDb, ratio: $0.ratio,
                    attackSeconds: seconds($0.attack), releaseSeconds: seconds($0.release),
                    makeupDB: $0.makeupDb)
            },
            noiseReduction: audio.noiseReduction,
            mono: audio.mono,
            enclosingMono: enclosingMono,
            // Told the clip's BASE volume, the fader's gain before fades and
            // ducks lower it (AU-22).
            limiter: audio.limiter.map {
                AudioLimiterSettings(
                    ceilingDb: $0.ceilingDb, volume: volume, releaseSeconds: seconds($0.release))
            },
            // The chain's head (AU-34, AU-30).
            channels: audio.channels,
            eq: AudioEQSettings(eq: audio.eq, hum: audio.hum),
            // After noise reduction, before the compressor (AU-47).
            gate: level.flatMap { l in audio.gate.map { AudioGateSettings(level: l, props: $0) } },
            deEsser: level.flatMap { l in
                audio.deEsser.map { AudioDeEsserSettings(level: l, props: $0) }
            })
    }

    /// The segment's automation with the base facts its settings keep (spec
    /// §11 AU-87, AU-88); nil when the plan gives it no points, or for a clip
    /// with no base here (a nest clip, whose keys reach nothing).
    func automation(for segment: PlanSegment) -> AudioDSPAutomation? {
        guard !segment.automation.isEmpty, let base = bases[segment.clip] else { return nil }
        return AudioDSPAutomation(
            points: segment.automation.sorted { $0.at < $1.at }, volume: base.volume,
            level: base.level, enclosingMono: dsp(for: segment.clip).enclosingMono,
            trackBalance: AudioTrackBalance(pans: segment.trackPans))
    }

    /// The parameters a project asks for with every gated or de-essed clip's
    /// level resolved (AU-41, AU-42): what the preview and the export build
    /// from. The plan is decoded only when a clip asks for a level.
    static func measured(project: ReelProject, cache: URL?) -> AudioDSPParameters {
        AudioDSPParameters(
            snapshot: project.snapshot,
            levels: AudioDynamicsLevels.shared.levels(for: project, cache: cache))
    }

    /// `format.rs`'s `MAX_NEST_DEPTH`. Duplicated rather than bridged: the
    /// FFI carries no constant for it, and a walk one level shallower than
    /// the core allows would silently stop folding, so the number is written
    /// where a reader comparing the two files can see it.
    private static let nestDepthCap = 8

    /// Ticks → seconds, the one place the compressor's two times and the
    /// limiter's release cross that boundary.
    private static func seconds(_ ticks: Ticks) -> Double {
        Double(max(ticks, 0)) / Double(ReelTime.perSecond)
    }

    func dsp(for clip: UInt32) -> AudioClipDSP { clips[clip] ?? .inert }

    /// The clip's BASE isolation amount, 0 when it asks for none (AU-53); a
    /// voiced clip's render is made from it (AU-143).
    func isolation(for clip: UInt32) -> Double { isolation[clip] ?? 0 }

    /// Whether the clip's isolated render is wanted: its base or any action
    /// end asks (AU-88).
    func wantsIsolation(_ clip: UInt32) -> Bool { wantedIsolation.contains(clip) }

    /// Whether any clip wants isolation.
    var isolates: Bool { !wantedIsolation.isEmpty }

    /// The clip's voice effect, nil when it has none or an inert one (AU-141).
    func voice(for clip: UInt32) -> VoiceSettings? { voiceSettings[clip] }

    /// Whether any clip has a voice effect.
    var voices: Bool { !voiceSettings.isEmpty }

    var isEmpty: Bool { clips.isEmpty && wantedIsolation.isEmpty && voiceSettings.isEmpty }
}

/// The process-wide place `CompositionBuilder` finds a document's audio DSP
/// parameters, keyed by the same `RecipeSource` slot the compositor reads
/// recipes under.
///
/// **Why this is not simply read off the project.** The parameters are per
/// clip, and `CompositionBuilder.build` is handed the composition PLAN, not
/// the project: the plan is `plan.rs`'s structural description and carries
/// no audio properties beyond the envelope and the time-pitch algorithm. Both
/// callers do publish the project first — `Playback.update` and
/// `Exporter.export` each call `RecipeSource.shared.set` before building — but
/// `RecipeSource` exposes only `recipe(for:at:)`, and a frame recipe has no
/// audio in it. So this mirror exists beside it, published from `Playback`.
///
/// **Why a key with no entry still gets the right answer.** An export mints a
/// FRESH `RecipeSource` key (`Exporter.swift`: "NOT the document's", so a
/// frame already queued cannot be composed from a project the user changed
/// mid-write), and nothing publishes a document's parameters under that new
/// key. What every such caller DOES publish under it is the project handle
/// itself, so the lookup reads that handle back through
/// `RecipeSource.project(for:)` and derives the parameters from its snapshot —
/// the same pure `init(snapshot:)` `Playback` publishes through, applied to
/// exactly the project being built.
///
/// It was once a scan for the published document whose plan JSON matched the
/// one being built. That is a guess, and it guessed wrong the moment two
/// documents were open with byte-identical composition plans: it could not
/// tell them apart, so it returned nothing and every export ran with the DSP
/// silently switched off. Measured, not theorised — two projects each holding
/// one clip of the same file was enough. A key names one composition; ask it
/// rather than the population.
final class AudioDSPSource {
    static let shared = AudioDSPSource()

    private let lock = NSLock()
    private var entries: [Int: AudioDSPParameters] = [:]

    private init() {}

    /// Publishes a document's parameters. Main thread, after every edit.
    ///
    /// `Playback` publishes here so the player never pays for a decode on a
    /// scrub; the derivation in `parameters(for:)` is the same function, so
    /// the two can never disagree about what a project asks for.
    func publish(_ parameters: AudioDSPParameters, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = parameters
    }

    /// Drops a document's slot, the way `RecipeSource.unregister` does.
    func unpublish(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    /// The parameters for the composition being built under `key`: the
    /// published entry, or — for a key minted for one export or one rendered
    /// frame — derived from the project that key was registered with.
    ///
    /// Never guesses. A key with no entry and no published project is a
    /// composition nothing claims, and that gets `.empty`: an unprocessed
    /// export, not a wrongly processed one.
    func parameters(for key: Int) -> AudioDSPParameters {
        lock.lock()
        let published = entries[key]
        lock.unlock()
        if let published = published { return published }
        guard let project = RecipeSource.shared.project(for: key) else { return .empty }
        return .measured(project: project, cache: ReverseSource.shared.resolution(for: key).cache)
    }
}
