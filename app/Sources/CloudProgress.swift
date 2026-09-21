import Foundation

/// The cloud run's one number, and the words beside it — road map 6 §5a's
/// progress paragraph as a value with no run in it.
///
/// **Why a type and not four lines inside the run.** The bar is the only
/// thing a person watching a cloud transcription has to go on: a run is
/// minutes of somebody else's compute and nothing about it is visible
/// otherwise. A number that went backwards, or that reached 0.95 and sat
/// there for a media that had not started, would be read as a hang. So the
/// arithmetic is pure, takes no client, no file and no clock of its own, and
/// is measured by `cloud_captions_probe.py`'s section `run` against a table
/// — the sheet that shows it in c1-chrome inherits something proved rather
/// than something plausible.
///
/// **The shares.** A run uploads one media at a time, so its bar is the
/// media's own progress scaled into that media's slice of the whole, and the
/// slices are proportional to the SECONDS of audio each media carries —
/// which is the only number known before any work is done and is very nearly
/// proportional to every phase's cost (the extract reads it, the upload
/// sends a fixed rate of it, the wait is §3 q8's 147× of it). A media that
/// is served from the cache, and a media R6-11 HOLDS, are not in the list at
/// all: they cost nothing and a slice for them would make the bar stall.
///
/// Inside one media's slice the four phases divide it exactly as §5a says:
/// extraction 0–0.25, upload 0.25–0.65, the wait 0.65–0.95 and the write to
/// 1.0. The wait is the only one with no honest completion signal — a poll
/// answers `processing` or it does not — so it advances on the CLOCK against
/// q8's measured 147× real time and HOLDS at 0.95 rather than pretending to
/// finish.
struct CloudProgress {

    /// Where one media is in its own slice.
    enum Phase: Equatable {
        case extracting
        case uploading
        case waiting
        case saving
    }

    /// §5a's four boundaries, and q8's rate. `processingRate` is audio
    /// seconds transcribed per second of wall clock: C0 measured an hour
    /// completing in 24.4 s.
    static let extractEnd = 0.25
    static let uploadEnd = 0.65
    static let waitEnd = 0.95
    static let processingRate = 147.0

    /// Each media's slice, in run order, summing to 1. Empty when nothing is
    /// being uploaded, which is the cached-only run: its bar goes 0 → 1.
    private let shares: [Double]
    /// Where each slice begins.
    private let bases: [Double]

    /// `seconds` is one entry per media TO UPLOAD, in the order the run will
    /// do them. A total of zero — every media a zero-length extract — falls
    /// back to equal slices rather than dividing by it.
    init(seconds: [Double]) {
        let clean = seconds.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let total = clean.reduce(0, +)
        if clean.isEmpty {
            shares = []
        } else if total > 0 {
            shares = clean.map { $0 / total }
        } else {
            shares = clean.map { _ in 1 / Double(clean.count) }
        }
        var running = 0.0
        var starts: [Double] = []
        for share in shares {
            starts.append(running)
            running += share
        }
        bases = starts
    }

    /// The whole run's fraction while media `index` is `within` its `phase`.
    ///
    /// `within` is clamped into 0…1 — a phase reports its own completion and
    /// a caller that measured 1.4 of an upload is not allowed to move the
    /// bar past the media's slice. An index outside the list answers 0,
    /// which is also what a run with nothing to upload answers: neither has
    /// a slice to be inside.
    func fraction(media index: Int, phase: Phase, within: Double) -> Double {
        guard index >= 0, index < shares.count else { return 0 }
        let part = within.isNaN ? 0 : min(max(within, 0), 1)
        let span: (Double, Double)
        switch phase {
        case .extracting: span = (0, Self.extractEnd)
        case .uploading: span = (Self.extractEnd, Self.uploadEnd)
        case .waiting: span = (Self.uploadEnd, Self.waitEnd)
        case .saving: span = (Self.waitEnd, 1)
        }
        // The two ends are taken EXACTLY rather than computed: with one
        // media `0.65 + (0.95 − 0.65) × 1` is 0.9500000000000001 in binary
        // floating point, and "holds at 0.95" is a claim a proof compares
        // against the constant.
        let value = part >= 1 ? span.1 : (part <= 0 ? span.0 : span.0 + (span.1 - span.0) * part)
        return bases[index] + shares[index] * value
    }

    /// How far through the WAIT a media is, by the clock: `waited × 147`
    /// audio seconds' worth of somebody else's compute, over the audio there
    /// is. Capped at 1, which is where §5a's "holds at 0.95" comes from —
    /// this is the `within`, and 1 of the wait is 0.95 of the slice.
    ///
    /// Audio of zero or less answers 1: there is nothing to wait for and a
    /// division would be the wrong kind of infinity.
    static func waiting(waited: TimeInterval, audioSeconds: Double) -> Double {
        guard audioSeconds.isFinite, audioSeconds > 0 else { return 1 }
        guard waited.isFinite, waited > 0 else { return 0 }
        return min(1, waited * processingRate / audioSeconds)
    }

    /// §5a's detail line — the phase and the file, plus the megabytes for an
    /// upload and the seconds for a wait, so a stuck queue is visible rather
    /// than silent.
    ///
    /// Megabytes are 1 000 000 bytes, the unit a service's own dashboard
    /// counts in, and they are whole numbers: a tenth of a megabyte moving
    /// once a second is noise, not information.
    static func detail(
        _ phase: Phase, file: String, sent: Int64 = 0, total: Int64 = 0,
        waited: TimeInterval = 0
    ) -> String {
        switch phase {
        case .extracting:
            return "Extracting \(file)"
        case .uploading:
            return "Uploading \(file) · \(megabytes(sent)) MB of \(megabytes(total))"
        case .waiting:
            return "Waiting for AssemblyAI · \(Int(max(0, waited.rounded()))) s"
        case .saving:
            return "Saving \(file)"
        }
    }

    private static func megabytes(_ bytes: Int64) -> Int {
        Int((Double(max(0, bytes)) / 1_000_000).rounded())
    }
}
