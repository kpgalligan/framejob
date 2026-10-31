import Foundation

/// One composition track: its chunks not yet summed and how far it has
/// delivered since the reset.
final class LiveLoudnessLane {
    let track: LevelMeterTrack
    var pending: [MixChunk] = []
    var end: Int64?
    /// Where its last chunk ended, whether summed or not; kept across a
    /// reset (but an overrun's), so a chunk that continues it is not a move.
    var stream: Int64?
    /// Frames dropped while awaiting its move; nil when not awaiting.
    var awaiting: Int64?
    private var spanRate = 0
    private var spanFrames: [Range<Int64>] = []

    init(_ track: LevelMeterTrack) { self.track = track }

    /// Its `sounding` spans on the frame grid: f is in one when f's tick
    /// (`f·600000/rate`, rounded down) is.
    func spans(rate: Int) -> [Range<Int64>] {
        if rate != spanRate {
            spanRate = rate
            spanFrames = track.sounding.map { LiveLoudness.frames($0, rate: rate) }
        }
        return spanFrames
    }

    /// The first frame at or after `f` this track sounds at, or nil.
    func firstSounding(from f: Int64, rate: Int) -> Int64? {
        spans(rate: rate).filter { $0.upperBound > f }.map { max($0.lowerBound, f) }.min()
    }

    func sounds(in range: Range<Int64>, rate: Int) -> Bool {
        !range.isEmpty && spans(rate: rate).contains { $0.overlaps(range) }
    }
}

/// `LiveLoudness`'s sum (road map "audio" AP7, spec §11 AU-70, AU-72): what a
/// drained chunk does to the measurement, and the frame-by-frame sum. Its own
/// file under the 400-line rule; the state it reads is `LiveLoudness`'s.
extension LiveLoudness {
    /// [⌈a·rate/600000⌉, ⌈b·rate/600000⌉): the frames whose ticks fall in `span`.
    static func frames(_ span: Range<Ticks>, rate: Int) -> Range<Int64> {
        func up(_ t: Ticks) -> Int64 {
            let n = t * Int64(rate)
            return n >= 0 ? (n + ReelTime.perSecond - 1) / ReelTime.perSecond : n / ReelTime.perSecond
        }
        let low = up(span.lowerBound)
        return low..<max(low, up(span.upperBound))
    }

    /// A chunk MOVES its track when it continues neither the track's own
    /// stream (what it delivered last, kept across resets) nor what it
    /// delivered to the measurement; a new track's first chunk moves only
    /// while a measurement is running. With no move, every chunk is summed.
    /// Otherwise the chunks before each track's first move are summed, then
    /// the moves are asked the reset rule. On a jump, or on a move with no
    /// measurement running, each track keeps what follows its own last move
    /// (the new position) and a track with none is AWAITING: the player
    /// hands each track a buffer or two of the old position after a seek or
    /// a play from elsewhere, so what continues its old stream is dropped
    /// until it moves, for at most `stallLag` of frames.
    func admit(_ drained: [(lane: LiveLoudnessLane, chunks: [MixChunk])], rate: Int, now: TimeInterval) {
        var items: [(lane: LiveLoudnessLane, chunks: [MixChunk], first: Int?, last: Int?)] = []
        for (lane, all) in drained where !all.isEmpty {
            var chunks: [MixChunk] = []
            var first: Int?
            var last: Int?
            var end = lane.end
            for chunk in all {
                let moved = lane.stream.map {
                    !continues(chunk.start, after: $0, rate: rate)
                        || end.map { !continues(chunk.start, after: $0, rate: rate) } ?? false
                } ?? (reached != nil)
                lane.stream = chunk.end
                end = chunk.end
                if let dropped = lane.awaiting {
                    if !moved, dropped < Self.frames(Self.stallLag, rate) {
                        lane.awaiting = dropped + Int64(chunk.frames)
                        continue
                    }
                    lane.awaiting = nil
                }
                if moved {
                    first = first ?? chunks.count
                    last = chunks.count
                }
                chunks.append(chunk)
            }
            items.append((lane, chunks, first, last))
        }
        let moves = items.filter { $0.first != nil }
        guard !moves.isEmpty else {
            for item in items {
                for chunk in item.chunks { enqueue(chunk, to: item.lane, rate: rate) }
            }
            advance(rate: rate, now: now)
            return
        }
        let fresh = reached == nil
        if !fresh {
            for item in items {
                for chunk in item.chunks[..<(item.first ?? item.chunks.count)] {
                    enqueue(chunk, to: item.lane, rate: rate)
                }
            }
            advance(rate: rate, now: now)
        }
        if fresh || moves.contains(where: { isJump($0.chunks[$0.first ?? 0].start, rate: rate) }) {
            if !fresh { reset(.jump) }
            let moved = Set(moves.map { ObjectIdentifier($0.lane) })
            for lane in allLanes where !moved.contains(ObjectIdentifier(lane)) {
                lane.awaiting = 0
            }
            for item in moves {
                for chunk in item.chunks[(item.last ?? 0)...] {
                    enqueue(chunk, to: item.lane, rate: rate)
                }
            }
        } else {
            for item in moves {
                for chunk in item.chunks[(item.first ?? 0)...] {
                    enqueue(chunk, to: item.lane, rate: rate)
                }
            }
        }
        advance(rate: rate, now: now)
    }

    func continues(_ start: Int64, after end: Int64, rate: Int) -> Bool {
        start >= end - Self.frames(Self.behindTolerance, rate)
            && start <= end + Self.frames(Self.aheadTolerance, rate)
    }

    /// AU-72's rule against the frame the sum reached.
    func isJump(_ start: Int64, rate: Int) -> Bool {
        guard let at = reached else { return false }
        if start < at - Self.frames(Self.behindTolerance, rate) { return true }
        guard start > at + Self.frames(Self.aheadTolerance, rate) else { return false }
        return allLanes.contains { $0.sounds(in: at..<start, rate: rate) }
    }

    static func frames(_ seconds: Double, _ rate: Int) -> Int64 {
        Int64((seconds * Double(rate)).rounded())
    }

    func enqueue(_ chunk: MixChunk, to lane: LiveLoudnessLane, rate: Int) {
        var chunk = chunk
        if let end = lane.end, chunk.start < end {
            if chunk.start + Int64(rate / 100) < end {
                // A restart behind its own delivery: what was pending was
                // rendered for a position the player left.
                lane.pending = []
                lane.end = nil
            } else {
                chunk = Self.dropping(chunk, before: end)
            }
        }
        lane.end = max(lane.end ?? chunk.end, chunk.end)
        guard chunk.frames > 0 else { return }
        if let reached {
            // Frames the sum already passed are not summed again.
            guard chunk.end > reached else { return }
        }
        lane.pending.append(chunk)
    }

    static func dropping(_ chunk: MixChunk, before frame: Int64) -> MixChunk {
        let skip = Int(min(max(0, frame - chunk.start), Int64(chunk.frames)))
        return MixChunk(
            start: chunk.start + Int64(skip), frames: chunk.frames - skip,
            channels: chunk.channels, sampleRate: chunk.sampleRate,
            left: Array(chunk.left[skip...]),
            right: chunk.channels == 2 ? Array(chunk.right[skip...]) : [])
    }

    /// Sums every frame every waited-on track has delivered past.
    func advance(rate: Int, now: TimeInterval) {
        let all = allLanes
        if reached == nil {
            guard let first = all.flatMap(\.pending).map(\.start).min() else { return }
            reached = first
        }
        guard let at = reached, let meter else { return }
        let leading = all.compactMap(\.end).max() ?? at
        var limit = leading
        for lane in all {
            let delivered = lane.end ?? at
            // The first frame it sounds at and has not delivered: none, and
            // it is not waited on.
            guard let owed = lane.firstSounding(from: delivered, rate: rate) else { continue }
            // A stalled track is silence, not waited on.
            if owed < leading - Self.frames(Self.stallLag, rate) { continue }
            if let wait = lane.firstSounding(from: max(delivered, at), rate: rate) {
                limit = min(limit, wait)
            }
        }
        guard limit > at else { return }
        let count = Int(limit - at)
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)
        for lane in all {
            let ramps = lane.track.ramps
            for chunk in lane.pending where chunk.end > at && chunk.start < limit {
                let origin = chunk.start
                for f in max(origin, at)..<min(origin + Int64(chunk.frames), limit) {
                    let gain = Float(MediaPeaks.envelope(ramps, at: f * ReelTime.perSecond / Int64(rate)))
                    let i = Int(f - origin)
                    let o = Int(f - at)
                    let x = chunk.left[i] * gain
                    left[o] += x
                    right[o] += chunk.channels == 2 ? chunk.right[i] * gain : x
                }
            }
            lane.pending.removeAll { $0.end <= limit }
        }
        var interleaved = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            interleaved[2 * i] = left[i]
            interleaved[2 * i + 1] = right[i]
        }
        interleaved.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: count) }
        pushBars(left, right, rate: rate)
        if measuredFrom == nil { measuredFrom = at }
        fedFrames += Int64(count)
        reached = limit
        lastAdvance = now
    }
}
