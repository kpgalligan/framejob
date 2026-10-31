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
    let dsp: AudioClipDSP
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
    /// up: `AudioShift.limiterLead` on a limited track, else 0. The media is
    /// placed that much earlier, so the samples entering the stages after
    /// the noise reducer belong to `t + lookupLead`, and the limiter's delay
    /// brings them back to `t` (AU-23).
    let lookupLead: Ticks

    init(segments: [PlanSegment], parameters: AudioDSPParameters) {
        var spans: [AudioDSPSpan] = []
        spans.reserveCapacity(segments.count)
        for segment in segments where segment.duration > 0 {
            let dsp = parameters.dsp(for: segment.clip)
            guard !dsp.isInert else { continue }
            spans.append(
                AudioDSPSpan(
                    start: segment.start, end: segment.start + segment.duration, dsp: dsp))
        }
        self.spans = spans
        isActive = !spans.isEmpty
        usesNoiseReduction = spans.contains { $0.dsp.noiseReduction > 0 }
        usesLimiter = spans.contains { $0.dsp.limiter != nil }
        lookupLead = usesLimiter ? CompositionBuilder.AudioShift.limiterLead : 0
    }

    private init() {
        spans = []
        isActive = false
        usesNoiseReduction = false
        usesLimiter = false
        lookupLead = 0
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
    /// Base only, as the rest, and never on a nest clip.
    private let isolation: [UInt32: Double]

    static let empty = AudioDSPParameters(clips: [:], isolation: [:])

    private init(clips: [UInt32: AudioClipDSP], isolation: [UInt32: Double]) {
        self.clips = clips
        self.isolation = isolation
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
    /// (nor does its limiter, AU-21, for the compressor's reason).
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
    /// **Base properties only, never through actions.** A clip's numbers can
    /// be animated (`actions.rs` lerps any of them), and none of the four is
    /// read at the animated value: the plan carries no per-tick audio, the
    /// tap would have to evaluate the action itself, and evaluation is Rust's
    /// job. Ducking already works this way — `audio.rs`'s `duckers()` reads
    /// base props and says so — so this is the established answer rather than
    /// a new exception. An action that animates `pan` moves nothing.
    init(snapshot: ProjectSnapshot) {
        var clips: [UInt32: AudioClipDSP] = [:]
        var isolation: [UInt32: Double] = [:]
        func collect(_ list: [ClipSnapshot]) {
            for clip in list {
                // A nest clip's own entry could never be looked up: its id
                // names no audio segment. `fold` below is where its `mono`
                // goes instead.
                guard clip.source.nestID == nil, let audio = clip.audio else { continue }
                if audio.isolation > 0 { isolation[clip.id] = min(audio.isolation, 1) }
                let dsp = AudioClipDSP(
                    pan: audio.pan,
                    compressor: audio.compressor.map {
                        AudioCompressorSettings(
                            thresholdDB: $0.thresholdDb, ratio: $0.ratio,
                            attackSeconds: AudioDSPParameters.seconds($0.attack),
                            releaseSeconds: AudioDSPParameters.seconds($0.release),
                            makeupDB: $0.makeupDb)
                    },
                    noiseReduction: audio.noiseReduction,
                    mono: audio.mono,
                    // Told the clip's BASE volume, the fader's gain before
                    // fades and ducks lower it (AU-22).
                    limiter: audio.limiter.map {
                        AudioLimiterSettings(
                            ceilingDb: $0.ceilingDb, volume: audio.volume,
                            releaseSeconds: AudioDSPParameters.seconds($0.release))
                    })
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

    /// The clip's isolation amount, 0 when it asks for none (AU-53).
    func isolation(for clip: UInt32) -> Double { isolation[clip] ?? 0 }

    /// Whether any clip asks for isolation.
    var isolates: Bool { !isolation.isEmpty }

    var isEmpty: Bool { clips.isEmpty && isolation.isEmpty }
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
        return AudioDSPParameters(snapshot: project.snapshot)
    }
}
