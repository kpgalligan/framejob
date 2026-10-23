import Foundation

/// AssemblyAI's published prices, dated — road map 6 §8's two rows.
///
/// They are CONSTANTS with a date beside them rather than anything the app
/// asks the service for, because AssemblyAI publishes no price endpoint and a
/// number invented at run time would be worse than a stale one nobody can
/// check. Everything that shows them says "at AssemblyAI's published rate",
/// so a figure that has gone stale reads as one.
enum AssemblyAIRates {
    /// The day the two numbers below were read off AssemblyAI's pricing page.
    static let readOn = "2026-09-17"
    /// Dollars per hour of audio for Universal-3.5 Pro.
    static let perHour = 0.21
    /// What speaker labels add, per hour.
    static let speakersPerHour = 0.02
}

/// What a cloud caption run would cost and why — road map 6 §5e's summary
/// line, as a PURE value with no run, no client and no sheet in it.
///
/// **Why it is a type and not four lines inside the sheet.** The estimate is
/// the one thing a person sees before agreeing to spend somebody's money and
/// to send their audio to another company, and it has to be right about three
/// separate things: which files this run would upload, how much audio that is,
/// and what that costs. Each of those is a rule with an edge — R6-11 holds a
/// media whose earlier delete is unconfirmed, a cached media costs nothing, a
/// media whose file will not read costs nothing and transcribes nothing — so
/// the arithmetic is a value the probe reads over a table rather than a
/// summary somebody typed into a label.
///
/// **Spec §11's R6-13 is the whole of the awaiting clause.** A held media is
/// neither "to upload" (this run will not upload it, and quoting for it would
/// quote for work that is not going to happen) nor hidden (a file that
/// silently does not transcribe is the failure the clause exists to
/// prevent). It is its own count in `describe` and its own line in `reasons`,
/// and that line carries what it WOULD cost if the janitor clears the delete.
///
/// **One disk read, and it is not in this arithmetic.** `facts(jobs:…)` is
/// the only member that opens a file: it reads each media's marker, whether
/// the transcript itself reads back, and the janitor's list, once per media.
/// Everything else — `fate`, `uploadTicks`, `dollars`, `money`, `describe`,
/// `reasons` — is a function of those facts, so the sheet can recompute the
/// whole readout on every keystroke without touching the disk again.
struct CloudEstimate: Equatable {

    /// Why a media is not being served from the cache.
    enum Reason: Equatable {
        /// There is no marker for it, or the transcript beside the marker
        /// will not read.
        case notCached
        /// There IS a transcript, of a file that has changed since.
        case fileChanged
        /// There is a transcript of this file, of a different REQUEST. The
        /// fields are in a fixed order — `model`, `language`, `speakers`,
        /// `vocabulary` — so one call's answer is the same sentence every
        /// time.
        case requestChanged([String])
        /// It would have been served from the cache, and Transcribe again
        /// was asked for.
        case refresh
    }

    /// What this run would do with one media.
    enum Fate: Equatable {
        /// Uploaded, and why.
        case upload(Reason)
        /// Served from `cache/transcripts/`, at no cost at all.
        case cached
        /// R6-11 will hold it: an earlier remote delete is unconfirmed, so
        /// this run leaves it alone. The reason is what it would have been
        /// uploaded FOR, which is what makes its price meaningful.
        case awaitingDelete(Reason)
        /// Its media file could not be read, so nothing can be said about it.
        case unreadable
    }

    /// Everything the disk knows about one media, read once.
    struct Facts: Equatable {
        let media: UInt32
        let name: String
        let duration: Ticks
        /// The file as it is NOW, or nil when it could not be read at all.
        let source: MediaImporter.CacheStamp?
        /// `cache/transcripts/<id>.complete.json`, decoded, or nil.
        let marker: TranscriptStamp?
        /// Whether `cache/transcripts/<id>.json` reads back. Both, because
        /// they are separate files — `MediaTranscript.isCurrent`'s rule.
        let cacheReads: Bool
        /// Whether the janitor still owes AssemblyAI a delete for it.
        let deleteOwed: Bool
    }

    /// One media in the readout.
    struct Row: Equatable {
        let media: UInt32
        let name: String
        let duration: Ticks
        let fate: Fate
    }

    /// In the order of each media's FIRST clip, which is the order the run
    /// itself works in (`CloudTranscriber.transcribe`'s `order`).
    let rows: [Row]
    /// Whether speaker labels were asked for, which is what the rate adds to.
    let speakers: Bool

    init(facts: [Facts], options: TranscriptOptions, refresh: Bool) {
        self.rows = facts.map {
            Row(
                media: $0.media, name: $0.name, duration: $0.duration,
                fate: Self.fate($0, options: options, refresh: refresh))
        }
        self.speakers = options.speakerLabels
    }

    // MARK: - The facts, and the ONE disk read

    /// One `Facts` per media, in first-clip order — the only member of this
    /// type that opens a file.
    ///
    /// It is a static function taking a cache directory rather than anything
    /// holding a document, so the sheet reads it once when it opens and the
    /// pure arithmetic above runs on every control change.
    static func facts(
        jobs: [Transcriber.Job], media: [UInt32: MediaSnapshot], cacheDirectory: URL
    ) -> [Facts] {
        var order: [UInt32] = []
        var first: [UInt32: Transcriber.Job] = [:]
        for job in jobs where first[job.media] == nil {
            order.append(job.media)
            first[job.media] = job
        }
        let owed = Set(MediaTranscript.undeleted(in: cacheDirectory).map { $0.media })
        var out: [Facts] = []
        for id in order {
            guard let job = first[id] else { continue }
            let entry = media[id]
            let stamp = entry.flatMap { MediaImporter.CacheStamp.stamp(for: $0, url: job.source) }
            out.append(
                Facts(
                    media: id, name: entry?.name ?? job.name, duration: entry?.duration ?? 0,
                    source: stamp,
                    marker: MediaTranscript.readStamp(for: id, in: cacheDirectory),
                    cacheReads: MediaTranscript.read(for: id, in: cacheDirectory) != nil,
                    deleteOwed: owed.contains(id)))
        }
        return out
    }

    // MARK: - The rules

    /// What this run would do with one media — `CloudTranscriber.transcribe`'s
    /// own classification, said in the vocabulary a person reads.
    ///
    /// It is deliberately NOT shared code with the run: the run answers for
    /// what it did and this answers for what it would do, and a probe row
    /// compares the two so the day they disagree is a scored failure rather
    /// than a refactor nobody checked.
    static func fate(_ facts: Facts, options: TranscriptOptions, refresh: Bool) -> Fate {
        guard let source = facts.source else { return .unreadable }
        let wanted = TranscriptStamp(source: source, options: options)
        let current = facts.marker?.serves(wanted, for: .captions) == true && facts.cacheReads
        if current, !refresh { return .cached }
        let reason: Reason
        if current {
            reason = .refresh
        } else if facts.marker == nil || !facts.cacheReads {
            reason = .notCached
        } else if let marker = facts.marker, marker.source != wanted.source {
            reason = .fileChanged
        } else {
            reason = .requestChanged(changed(facts.marker, wanted))
        }
        return facts.deleteOwed ? .awaitingDelete(reason) : .upload(reason)
    }

    /// Which of the request's four parts differ, in the fixed order
    /// `model`, `language`, `speakers`, `vocabulary`.
    private static func changed(_ marker: TranscriptStamp?, _ wanted: TranscriptStamp) -> [String] {
        guard let marker = marker else { return [] }
        var out: [String] = []
        if marker.speechModels != wanted.speechModels { out.append("model") }
        if marker.languageCode != wanted.languageCode { out.append("language") }
        if marker.speakerLabels != wanted.speakerLabels { out.append("speakers") }
        if marker.keytermsPrompt != wanted.keytermsPrompt { out.append("vocabulary") }
        return out
    }

    // MARK: - The counts

    var uploads: [Row] { rows.filter { if case .upload = $0.fate { return true } else { return false } } }
    var cached: [Row] { rows.filter { $0.fate == .cached } }
    var awaiting: [Row] {
        rows.filter { if case .awaitingDelete = $0.fate { return true } else { return false } }
    }
    var unreadable: [Row] { rows.filter { $0.fate == .unreadable } }

    /// A keyless run is admitted only when every distinct media is current.
    var canReuseWithoutCredential: Bool {
        !rows.isEmpty && rows.allSatisfy { $0.fate == .cached }
    }

    /// The audio this run would upload, in ticks.
    ///
    /// Each row is bounded into `[0, Transcriber.maxSourceTicks]` and the sum
    /// SATURATES, for that constant's own reason (R6-10): a media's duration
    /// comes out of a `project.json` a person can hand-write, and a readout
    /// that trapped on one would take the sheet down with it.
    var uploadTicks: Ticks {
        var total: Ticks = 0
        for row in uploads {
            let bounded = min(max(row.duration, 0), Transcriber.maxSourceTicks)
            let (sum, overflow) = total.addingReportingOverflow(bounded)
            total = overflow ? Ticks.max : sum
        }
        return total
    }

    // MARK: - The money

    /// Ticks of audio at the published rate, in dollars.
    static func dollars(ticks: Ticks, speakers: Bool) -> Double {
        let hours = Double(max(ticks, 0)) / 600_000 / 3600
        return hours * (AssemblyAIRates.perHour + (speakers ? AssemblyAIRates.speakersPerHour : 0))
    }

    /// `"about $0.36"`, and `"under $0.01"` for anything above nothing that
    /// rounds to no cents — quoting "about $0.00" for a run that will be
    /// billed is the one wrong answer this function can give.
    ///
    /// Formatted POSIX, never in the person's locale: this is a dollar figure
    /// with a dot in it, and a comma decimal separator would read as
    /// thousands.
    static func money(_ dollars: Double) -> String {
        guard dollars.isFinite else { return "about $0.00" }
        let cents = (dollars * 100).rounded()
        if dollars > 0, cents < 1 { return "under $0.01" }
        return "about $" + amount(max(cents, 0) / 100)
    }

    private static func amount(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - The words

    /// §5e's summary line: what would be uploaded, how much audio that is,
    /// what it costs, and then each of the three things that cost nothing,
    /// named only when there are any.
    static func describe(_ estimate: CloudEstimate, fps: Fps) -> String {
        guard !estimate.rows.isEmpty else { return "Nothing to transcribe" }
        var parts: [String] = []
        let uploads = estimate.uploads.count
        if uploads == 0 {
            parts.append("Nothing to upload")
        } else {
            parts.append("\(uploads) \(files(uploads)) to upload")
            parts.append(
                ReelTime.format(estimate.uploadTicks, fps: fps, frames: false) + " of audio")
            parts.append(
                money(dollars(ticks: estimate.uploadTicks, speakers: estimate.speakers))
                    + " at AssemblyAI's published rate")
        }
        let cached = estimate.cached.count
        if cached > 0 { parts.append("\(cached) \(files(cached)) already transcribed") }
        let awaiting = estimate.awaiting.count
        if awaiting > 0 {
            parts.append("\(awaiting) \(files(awaiting)) waiting on an earlier delete")
        }
        let unreadable = estimate.unreadable.count
        if unreadable > 0 { parts.append("\(unreadable) \(files(unreadable)) could not be read") }
        return parts.joined(separator: " · ")
    }

    private static func files(_ count: Int) -> String { count == 1 ? "file" : "files" }

    /// One line per row that is not being served from the cache, by FILE
    /// NAME, and then the rate sentence.
    ///
    /// By name rather than by media id because the person chose files, not
    /// ids, and an id is the tool's vocabulary. R6-13: an awaiting row's line
    /// says what it would cost if the delete clears, so its price is never
    /// hidden by the count that leaves it out of the total.
    static func reasons(_ estimate: CloudEstimate) -> [String] {
        var out: [String] = []
        for row in estimate.rows {
            switch row.fate {
            case .cached:
                continue
            case .unreadable:
                out.append("“\(row.name)” could not be read, so it cannot be transcribed.")
            case .upload(let reason):
                out.append(sentence(row, reason))
            case .awaitingDelete(let reason):
                let bounded = min(max(row.duration, 0), Transcriber.maxSourceTicks)
                let price = money(dollars(ticks: bounded, speakers: estimate.speakers))
                out.append(
                    sentence(row, reason)
                        + " It is waiting on an earlier delete and will not be uploaded in this "
                        + "run — \(price) more if it does.")
            }
        }
        if !out.isEmpty { out.append(rateSentence(speakers: estimate.speakers)) }
        return out
    }

    private static func sentence(_ row: Row, _ reason: Reason) -> String {
        switch reason {
        case .notCached:
            return "“\(row.name)” has not been transcribed yet."
        case .fileChanged:
            return "“\(row.name)” has changed since it was transcribed."
        case .requestChanged(let fields):
            guard !fields.isEmpty else {
                return "“\(row.name)” was transcribed for a different request."
            }
            return "“\(row.name)” was transcribed with a different "
                + fields.joined(separator: ", ") + "."
        case .refresh:
            return "“\(row.name)” is already transcribed, and Transcribe again was asked for."
        }
    }

    /// The dated rate, in one sentence, with the speakers surcharge folded in
    /// when it applies — so the figure named here is the figure the total was
    /// computed from.
    static func rateSentence(speakers: Bool) -> String {
        let rate = AssemblyAIRates.perHour + (speakers ? AssemblyAIRates.speakersPerHour : 0)
        return "At AssemblyAI's published rate of $\(amount(rate)) an hour, read on "
            + "\(AssemblyAIRates.readOn)."
    }
}
