import Foundation

/// Where Synchronize Audio looks and what it chooses (road map
/// "audio-sync-2", AS-3; spec §11 SY-13, SY-14, SY-17, SY-18): the clips'
/// played windows, the order of the two searches, the choice among a
/// search's candidates and its tier, the candidate moves the answer reports,
/// and the refusal that names them.
///
/// Pure, as `AudioSync.plan` is: two readings' features on their timeline
/// grids in, a lag or a refusal out. The arithmetic of one search is
/// `AudioSyncMatch.search`'s.
///
/// **The played windows first** (SY-13, reversing AS-1's whole files): what
/// the user trimmed each clip to is evidence of what they mean to line up,
/// and the owner's files share a second, unrelated stretch that wins any
/// whole-file search. The whole files are searched only when the played
/// windows chose nothing and either window is a strict part of its file.
extension AudioSync {

    /// Which stretches a match was found in.
    enum Search: String {
        case played, whole
    }

    /// Which rule chose it (SY-14): `.confidence` is the CONFIDENT tier,
    /// `.placement` the WEAK one, never applied silently (SY-18).
    enum ChosenBy: String {
        case confidence, placement
    }

    /// One candidate as the move it would make: its lag in ticks, the
    /// frame-snapped delta, and its z.
    struct CandidateMove: Equatable {
        let offset: Ticks
        let delta: Ticks
        let confidence: Double
    }

    /// A chosen match: its lag in frames (anchor minus mover, file-relative,
    /// on the timeline grid, refined), its z, where and how it was found,
    /// what it correlated (SY-17), and the candidates the answer lists.
    struct Found: Equatable {
        let lag: Double
        let confidence: Double
        let search: Search
        let chosenBy: ChosenBy
        let matchedOn: AudioSyncMatch.MatchedOn
        let candidates: [CandidateMove]
    }

    enum FindAnswer: Equatable {
        case found(Found)
        case refused(Problem)
    }

    // MARK: - The played window (SY-13)

    /// The frames of a file (`frames` of them, on its timeline grid) that a
    /// clip spanning `[start, end)` with its tick 0 at `zero` plays:
    /// `[⌊(start − zero)/frameTicks⌋, ⌈(end − zero)/frameTicks⌉)`, clamped to
    /// the file.
    static func playedWindow(start: Ticks, end: Ticks, zero: Ticks, frames: Int) -> Range<Int> {
        let step = Double(SyncFeatures.frameTicks)
        let lower = Int((Double(start - zero) / step).rounded(.down))
        let upper = Int((Double(end - zero) / step).rounded(.up))
        let low = min(max(0, lower), frames)
        return low..<min(max(low, upper), frames)
    }

    // MARK: - The choice (SY-14)

    /// The best candidate when it is confident on its own — z at least
    /// `confidentZ` and `confidentMargin` above the second, or no second —
    /// else the peak near the mover's placement when its z is at least
    /// `plausibleZ` (the weak tier, SY-18), else nothing.
    static func choose(_ result: AudioSyncMatch.SearchResult)
        -> (AudioSyncMatch.Candidate, ChosenBy)? {
        if let best = result.candidates.first, best.z >= AudioSyncMatch.confidentZ,
           result.candidates.count < 2
            || best.z - result.candidates[1].z >= AudioSyncMatch.confidentMargin {
            return (best, .confidence)
        }
        if let near = result.nearPlacement, near.z >= AudioSyncMatch.plausibleZ {
            return (near, .placement)
        }
        return nil
    }

    // MARK: - Finding (SY-13, SY-14)

    /// The match between `anchor` and `mover`, whose features
    /// (`anchorFrames`, `moverFrames`) and speech masks (`anchorSpeech`,
    /// `moverSpeech`, one per frame; nil without the model) are already on
    /// their timeline grids: the played windows when both hold
    /// `minimumStretchFrames`, then the whole files when a window is a
    /// strict part of its file; else the refusal naming each search's
    /// candidates and the rule.
    static func find(
        anchor: Reading, anchorFrames: [Float], anchorSpeech: [Bool]?, mover: Reading,
        moverFrames: [Float], moverSpeech: [Bool]?, fps: Fps
    ) -> FindAnswer {
        let width = SyncFeatures.coefficients
        let anchorCount = anchorFrames.count / width
        let moverCount = moverFrames.count / width
        let step = SyncFeatures.frameTicks
        let placementLag = Double(mover.zero - anchor.zero) / Double(step)
        let anchorWindow = playedWindow(
            start: anchor.start, end: anchor.end, zero: anchor.zero, frames: anchorCount)
        let moverWindow = playedWindow(
            start: mover.start, end: mover.end, zero: mover.zero, frames: moverCount)

        func move(_ candidate: AudioSyncMatch.Candidate) -> CandidateMove {
            let offset = Ticks((candidate.lag * Double(step)).rounded())
            return CandidateMove(
                offset: offset,
                delta: ReelTime.snapToFrame(anchor.zero - mover.zero + offset, fps: fps),
                confidence: candidate.z)
        }
        var ran: [(Search, [CandidateMove])] = []
        func settle(_ search: Search, _ result: AudioSyncMatch.SearchResult?) -> Found? {
            guard let result else {
                ran.append((search, []))
                return nil
            }
            let moves = result.candidates.map(move)
            ran.append((search, moves))
            guard let choice = choose(result) else { return nil }
            let (chosen, rule) = choice
            let listed = rule == .placement && !result.candidates.contains(chosen)
                ? moves + [move(chosen)] : moves
            return Found(
                lag: chosen.lag, confidence: chosen.z, search: search, chosenBy: rule,
                matchedOn: result.matchedOn, candidates: listed)
        }
        func slice(_ frames: [Float], _ window: Range<Int>) -> [Float] {
            Array(frames[(window.lowerBound * width)..<(window.upperBound * width)])
        }
        func slice(_ mask: [Bool]?, _ window: Range<Int>) -> [Bool]? {
            mask.map { mask in
                window.map { $0 < mask.count && mask[$0] }
            }
        }

        let playable = anchorWindow.count >= AudioSyncMatch.minimumStretchFrames
            && moverWindow.count >= AudioSyncMatch.minimumStretchFrames
        if playable {
            let result = AudioSyncMatch.search(
                anchor: slice(anchorFrames, anchorWindow), mover: slice(moverFrames, moverWindow),
                anchorSpeech: slice(anchorSpeech, anchorWindow),
                moverSpeech: slice(moverSpeech, moverWindow),
                offset: anchorWindow.lowerBound - moverWindow.lowerBound,
                placementLag: placementLag)
            if let found = settle(.played, result) { return .found(found) }
        }
        if anchorWindow.count < anchorCount || moverWindow.count < moverCount {
            let result = AudioSyncMatch.search(
                anchor: anchorFrames, mover: moverFrames, anchorSpeech: anchorSpeech,
                moverSpeech: moverSpeech, offset: 0, placementLag: placementLag)
            if let found = settle(.whole, result) { return .found(found) }
        }
        return .refused(
            Problem(
                clip: nil,
                reason: refusal(anchor: anchor.clip, mover: mover.clip, ran: ran)))
    }

    /// "no matching sound found between clip A and clip N: in the played
    /// windows, moving clip N by +0.77 s (confidence 4.31) or −12.40 s (3.90);
    /// in the whole files, …. A match applies on its own at …" — every search that ran with
    /// its candidates, and the rule printed from its constants; "…: too
    /// little room to compare their sound." when no search had a candidate.
    static func refusal(anchor: UInt32, mover: UInt32, ran: [(Search, [CandidateMove])])
        -> String {
        let head = "no matching sound found between clip \(anchor) and clip \(mover)"
        let named = ran.filter { !$0.1.isEmpty }
        guard !named.isEmpty else { return head + ": too little room to compare their sound." }
        func seconds(_ delta: Ticks) -> String {
            String(format: "%+.2f", Double(delta) / Double(ReelTime.perSecond))
                .replacingOccurrences(of: "-", with: "−") + " s"
        }
        let parts = named.map { search, moves -> String in
            let place = search == .played ? "in the played windows" : "in the whole files"
            var items = moves.enumerated().map { index, move in
                seconds(move.delta) + " ("
                    + (index == 0 ? "confidence " : "") + String(format: "%.2f", move.confidence)
                    + ")"
            }
            let last = items.removeLast()
            let list = items.isEmpty ? last : items.joined(separator: ", ") + " or " + last
            return "\(place), moving clip \(mover) by \(list)"
        }
        let radius = Double(Ticks(AudioSyncMatch.placementRadiusFrames) * SyncFeatures.frameTicks)
            / Double(ReelTime.perSecond)
        return head + ": " + parts.joined(separator: "; ")
            + ". A match applies on its own at confidence ≥ "
            + String(format: "%g", AudioSyncMatch.confidentZ) + " and "
            + String(format: "%g", AudioSyncMatch.confidentMargin)
            + " above the next candidate; one ≥ " + String(format: "%g", AudioSyncMatch.plausibleZ)
            + " within " + String(format: "%.0f", radius) + " s of where clip \(mover) sits now "
            + "is offered as a weak match."
    }
}
