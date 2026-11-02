import Foundation

/// A clip's played source window and its times (CJ-25): source ticks of the
/// FORWARD media to clip ticks, through its source map when it ramps, its
/// speed when not, and the reversed mirror first when it plays backwards.
struct AnalysisClipTimes {
    let id: UInt32
    let start: Ticks
    let sourceIn: Ticks
    let speed: Double
    let pivot: Ticks?
    let map: SourceMap?
    /// The played window in the forward media's ticks, [lower, upper).
    let window: ClosedRange<Ticks>

    init(clip: ClipSnapshot, media: MediaSnapshot, map: SourceMap?) {
        id = clip.id
        start = clip.start
        speed = clip.speed > 0 && clip.speed.isFinite ? clip.speed : 1
        let ramp = map.flatMap { $0.ramped ? $0 : nil }
        self.map = ramp
        sourceIn = ramp?.sourceIn ?? clip.source.sourceIn
        let length = ramp?.sourceLength ?? Transcriber.contentLength(of: clip)
        pivot = clip.source.isReversed ? media.duration : nil
        let played = sourceIn...(sourceIn + length)
        let forward = pivot.map { ReverseMirror.mirrored(played, about: $0) } ?? played
        let low = min(max(0, forward.lowerBound), media.duration)
        window = low...max(low, min(media.duration, forward.upperBound))
    }

    /// Ticks from the clip's start, in its playing direction, at forward
    /// source tick `source`.
    func clipTime(ofSource source: Int64) -> Ticks {
        let played = pivot.map { ReverseMirror.mirrored(source, about: $0) } ?? source
        if let map { return Ticks(map.clip(atSource: Double(played)).rounded()) }
        return Ticks((Double(played - sourceIn) / speed).rounded())
    }
}
