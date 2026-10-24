import Foundation

/// The tape glide (spec §11 SR-6's keep-pitch-off kernel) as a forward
/// stream at 48 kHz: frame j is `RampAudioResampler` at p(j) =
/// `RampAudioRenderer.position(map, j)` with the cutoff of the rate
/// p(j+1) − p(j). Keep pitch off reads it from frame 0 (the output itself).
///
/// A read is cut into chunks of at most `RampAudioRenderer.chunkFrames`;
/// for each the source is read ahead to the chunk's reach and dropped
/// behind the map's steepest reach: a later chunk's `lo` can fall below
/// this one's when the rate jumps, never below that bound. A start before 0
/// is allowed (the map extrapolates at its first slope; a file frame before
/// 0 reads zero).
final class RampVarispeedStream {
    let channels: Int
    /// The next frame `read` writes.
    private(set) var next: Int64
    private let map: RampAudioMap
    private let source: RampSourceReader
    private let resampler = RampAudioResampler()
    private let behind: Int64

    init(map: RampAudioMap, source: RampSourceReader, from start: Int64) {
        self.map = map
        self.source = source
        channels = source.channels
        next = start
        // + 1 past `chunk`'s own, + 1 for a measured rate a rounding above the slope.
        behind = Int64(RampAudioResampler.reach(rate: Self.steepest(map))) + 2
    }

    /// The map's steepest slope: source ticks per clip tick, its fastest rate.
    static func steepest(_ map: RampAudioMap) -> Double {
        var steepest = 0.0
        for i in 1..<map.clipTicks.count {
            steepest = max(
                steepest,
                (map.sourceTicks[i] - map.sourceTicks[i - 1])
                    / Double(map.clipTicks[i] - map.clipTicks[i - 1]))
        }
        return steepest
    }

    /// Writes frames `next ..< next + count` into `out`, interleaved.
    func read(_ count: Int, into out: UnsafeMutableBufferPointer<Float>) throws {
        var done = 0
        while done < count {
            let part = min(RampAudioRenderer.chunkFrames, count - done)
            let span = RampAudioRenderer.chunk(map, from: next, count: part)
            try source.fill(through: span.hi)
            source.drop(before: Int64(span.positions[0].rounded(.down)) - behind)
            for i in 0..<part {
                let p = span.positions[i]
                let r = span.positions[i + 1] - p
                let base = (done + i) * channels
                for c in 0..<channels {
                    out[base + c] = resampler.value(at: p, rate: r) {
                        source.sample($0, channel: c)
                    }
                }
            }
            done += part
            next += Int64(part)
        }
    }
}
