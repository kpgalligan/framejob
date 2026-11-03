import Foundation

/// A sampled kind's job loop (spec §11 CJ-33; road map "creator-jobs" CJ3,
/// lifted out of `AnalysisFaces.run` at VR1 for `subjects`): generic over what
/// one analysed frame yields, so `faces` and `subjects` share one sample rule.
///
/// **The grid** is the kind's sample grid: sample k at `grid.ticks(of: k)`
/// takes the first kept frame whose pts lies in `[ticks(k), ticks(k) + one
/// sample interval)`, else none — whatever the job's bounds; a frame serving
/// two samples is analysed once (`AnalysisFaces.samples(at:after:grid:)`).
///
/// **The frames** are read through `AnalysisFrames.read`'s standard arms at
/// `min(longSide, the media's long side)`, over each of `request`'s ranges in
/// order. `publish` is handed each range's samples at its end and every
/// `publishInterval` mid-range, then only through the samples decided (every
/// sample whose interval ended before the frame read); an index no frame
/// served is absent from `found`.
enum AnalysisSampleJob {

    /// Runs `request`'s ranges (sample indices of `grid`) in order. False when
    /// `cancelled()` stopped it; `progress` hears the share of samples decided.
    static func run<Value>(
        _ request: AnalysisRequest, grid: AnalysisGrid, longSide: Int,
        publishInterval: TimeInterval, cancelled: () -> Bool, progress: (Double) -> Void,
        analyse: (AnalysisPicture) throws -> Value,
        publish: (_ covering: ClosedRange<Int>, _ found: [Int: (pts: Int64, value: Value)])
            throws -> Void
    ) throws -> Bool {
        let frames = AnalysisGrid(media: request.media)
        let source = AnalysisFrames.Source(
            media: request.media, url: request.url, input: request.input)
        let side = min(longSide, max(request.media.width, request.media.height))
        let total = max(1, request.ranges.reduce(0) { $0 + $1.count })
        var before = 0
        for range in request.ranges {
            var job = Job<Value>(range: range)
            let first = frames.index(of: grid.ticks(of: range.lowerBound))
            let reach = grid.ticks(of: range.upperBound) + Ticks(grid.frameTicks.rounded(.up))
            let last = min(frames.lastIndex, frames.index(of: reach) + 1)
            var previous: Int64?
            var lastPublish = Date()
            let finished = try AnalysisFrames.read(
                range: first...max(first, last), grid: frames, source: source, longSide: side,
                cancelled: cancelled
            ) { _, pts, picture in
                defer { previous = pts }
                // Every sample whose interval ended before this frame is decided.
                while job.decided < range.upperBound,
                    Double(grid.ticks(of: job.decided + 1)) + grid.frameTicks <= Double(pts)
                {
                    job.decided += 1
                }
                if let served = AnalysisFaces.samples(at: pts, after: previous, grid: grid),
                    served.upperBound >= range.lowerBound, served.lowerBound <= range.upperBound
                {
                    let value = try autoreleasepool { try analyse(picture) }
                    let mine = max(served.lowerBound, range.lowerBound)...min(
                        served.upperBound, range.upperBound)
                    for k in mine { job.found[k] = (pts, value) }
                    job.decided = max(job.decided, mine.upperBound)
                }
                progress(Double(before + job.decided - range.lowerBound + 1) / Double(total))
                if Date().timeIntervalSince(lastPublish) >= publishInterval,
                    job.decided >= job.from
                {
                    try flush(&job, through: job.decided, publish: publish)
                    lastPublish = Date()
                }
            }
            guard finished else { return false }
            if job.from <= range.upperBound {
                try flush(&job, through: range.upperBound, publish: publish)
            }
            before += range.count
        }
        return true
    }

    /// One range's job state: the samples found and not yet published.
    private struct Job<Value> {
        let range: ClosedRange<Int>
        var from: Int
        var decided: Int
        var found: [Int: (pts: Int64, value: Value)] = [:]

        init(range: ClosedRange<Int>) {
            self.range = range
            from = range.lowerBound
            decided = range.lowerBound - 1
        }
    }

    /// Hands `publish` the job's samples `from…through`, then drops them.
    private static func flush<Value>(
        _ job: inout Job<Value>, through: Int,
        publish: (_ covering: ClosedRange<Int>, _ found: [Int: (pts: Int64, value: Value)])
            throws -> Void
    ) throws {
        let covering = job.from...through
        try publish(covering, job.found)
        job.found = job.found.filter { !covering.contains($0.key) }
        job.from = through + 1
    }
}
