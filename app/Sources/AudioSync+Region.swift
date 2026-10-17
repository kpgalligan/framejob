import Foundation

/// Where Synchronize Audio's one GCC-PHAT refinement runs (#302; spec §11
/// SY-32, amending SY-20's and SY-29's centred region): moved out of
/// `AudioSync.swift`, where the region was the overlap's centre 30 s.
///
/// It is pure, as `plan` is: an overlap, the two readings' timeline-grid
/// features and masks and the line in, a range of anchor timeline samples
/// out. It only chooses WHERE: the refinement, its z and the gate are
/// `AudioSyncPHAT`'s and `plan`'s (SY-29), and there is still one region.
extension AudioSync {

    /// SY-32's region: `overlap` (anchor timeline frames) ×128, in anchor
    /// timeline samples, when it holds at most W = `maximumRegionSamples /
    /// hop` frames; else the W frames whose features agree most along
    /// `line`. Frame f scores `Σ_k A[f, k]·M[m(f), k]`, A and M the features
    /// `standardised` as the match was (over the speech frames when it
    /// matched on speech), `m(f) = f − round((c + ρ·128f)/128)`, and 0 when
    /// f or m(f) lies outside its file. The start s in `[lo, hi − W]` with
    /// the greatest summed score wins; the centred start `⌊(lo + hi)/2⌋ −
    /// ⌊W/2⌋` is the first candidate, replaced only by a strictly greater
    /// sum or an equal one nearer it.
    static func refinementRegion(
        overlap: Range<Int>, anchorFrames: [Float], moverFrames: [Float], anchorSpeech: [Bool]?,
        moverSpeech: [Bool]?, matchedOn: AudioSyncMatch.MatchedOn, line: AudioSyncPHAT.Line
    ) -> Range<Int> {
        let hop = SyncFeatures.hop
        let span = AudioSyncPHAT.maximumRegionSamples / hop
        let lo = overlap.lowerBound
        let hi = overlap.upperBound
        guard overlap.count > span else { return (lo * hop)..<(hi * hop) }

        let width = SyncFeatures.coefficients
        let onSpeech = matchedOn == .speech
        let a = AudioSyncMatch.standardised(anchorFrames, speech: onSpeech ? anchorSpeech : nil)
        let m = AudioSyncMatch.standardised(moverFrames, speech: onSpeech ? moverSpeech : nil)
        let anchorCount = a.count / width
        let moverCount = m.count / width

        // prefix[i] = Σ score over the overlap's first i frames.
        var prefix = [Double](repeating: 0, count: overlap.count + 1)
        a.withUnsafeBufferPointer { anchor in
            m.withUnsafeBufferPointer { mover in
                for (index, f) in overlap.enumerated() {
                    let lag = ((line.intercept + line.rate * Double(f * hop)) / Double(hop))
                        .rounded()
                    let g = f - Int(lag)
                    var score = 0.0
                    if f >= 0, f < anchorCount, g >= 0, g < moverCount {
                        let x = f * width
                        let y = g * width
                        for k in 0..<width { score += Double(anchor[x + k]) * Double(mover[y + k]) }
                    }
                    prefix[index + 1] = prefix[index] + score
                }
            }
        }
        func sum(_ start: Int) -> Double { prefix[start - lo + span] - prefix[start - lo] }

        let last = hi - span
        let centred = min(max(lo, (lo + hi) / 2 - span / 2), last)
        var best = centred
        var bestSum = sum(centred)
        for start in lo...last {
            let value = sum(start)
            if value > bestSum || (value == bestSum && abs(start - centred) < abs(best - centred)) {
                best = start
                bestSum = value
            }
        }
        return (best * hop)..<((best + span) * hop)
    }
}
