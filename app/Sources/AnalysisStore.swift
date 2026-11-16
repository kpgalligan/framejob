import Foundation

/// The analysis store (spec §11 CJ-22; road map "creator-jobs" CJ2a): where a
/// kind's results for one media live, what they cover, the hit rule, and the
/// one door every write goes through.
///
/// `cache/analysis/<kind>/<media id>.json` is the marker (`AnalysisMarker`);
/// `cache/analysis/<kind>/<media id>/` holds the payload files the kind names.
/// A request is a HIT when the marker answers for its stamp, its first payload
/// file is on disk, and the coverage holds every index it needs (its window
/// plus the kind's read margin); otherwise the job runs only the missing
/// ranges (all of them when the file is gone, road map CO1).
///
/// **The publish** (`publishFile`) runs under a lock keyed by (cache folder,
/// kind, media id) and inside `CacheLedger.publish(in:for: nil, as:)` — never
/// mid-save, never waiting on main. It re-reads the marker, deletes marker
/// then payload when the on-disk stamp is not the job's or its first payload
/// file is missing, removes any old `.partial`, lets the kind write the
/// `.partial` (handed the on-disk file when there is one to merge onto), and
/// renames it into place; then it writes the marker LAST with the union of
/// the on-disk and the job's coverage when the kind merged, else the job's
/// alone, sorted keys, `.atomic`. A throw removes the `.partial` and leaves
/// marker and payload as they were. Two jobs of one media therefore merge
/// rather than overwrite one another (P8). `publish(…merge:)` is the same
/// door for a kind that edits its payload's bytes in memory (`shots`). Each
/// publish that lands posts `.analysisDidPublish` on main (spec §11 CO-22 (d)).
///
/// **A cancelled job's publish** (`publishCancelled`, spec §11 CJ-21 as
/// amended by #435) only merges: when the on-disk marker would be replaced
/// (another stamp, canned, undecodable, or its payload gone) it writes
/// nothing and leaves that cache as it is.
enum AnalysisStore {

    enum StoreError: LocalizedError {
        case saveInFlight
        case write(String)

        var errorDescription: String? {
            switch self {
            case .saveInFlight:
                return "a save of the project held the cache for longer than the analysis waits"
            case .write(let why): return "the analysis could not be written: \(why)"
            }
        }
    }

    /// What a lookup found.
    enum Lookup: Equatable {
        /// Every needed index is covered by a marker that answers for the
        /// stamp.
        case hit(AnalysisMarker)
        /// The ranges a job must run (never empty).
        case miss([ClosedRange<Int>])
    }

    // MARK: - Where

    static func kindFolder(_ kind: AnalysisKind, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    static func markerURL(_ kind: AnalysisKind, media: UInt32, in cacheDir: URL) -> URL {
        kindFolder(kind, in: cacheDir).appendingPathComponent("\(media).json")
    }

    static func payloadFolder(_ kind: AnalysisKind, media: UInt32, in cacheDir: URL) -> URL {
        kindFolder(kind, in: cacheDir).appendingPathComponent("\(media)", isDirectory: true)
    }

    static func payloadURL(
        _ kind: AnalysisKind, media: UInt32, file: String, in cacheDir: URL
    ) -> URL {
        payloadFolder(kind, media: media, in: cacheDir).appendingPathComponent(file)
    }

    // MARK: - Reading

    /// The marker, or nil when there is none or it will not decode (an
    /// older shape reads as absent, which is the answer that rebuilds).
    static func readMarker(_ kind: AnalysisKind, media: UInt32, in cacheDir: URL) -> AnalysisMarker?
    {
        guard let data = try? Data(contentsOf: markerURL(kind, media: media, in: cacheDir))
        else { return nil }
        return try? JSONDecoder().decode(AnalysisMarker.self, from: data)
    }

    /// The hit rule: a marker that answers for `stamp` and covers all of
    /// `need`; else the ranges of `need` it does not cover (all of it when
    /// no marker answers).
    static func lookup(
        _ kind: AnalysisKind, media: UInt32, stamp: AnalysisStamp, need: ClosedRange<Int>,
        in cacheDir: URL
    ) -> Lookup {
        guard let marker = readMarker(kind, media: media, in: cacheDir), marker.answers(for: stamp),
            let file = marker.files.first,
            FileManager.default.fileExists(
                atPath: payloadURL(kind, media: media, file: file, in: cacheDir).path)
        else { return .miss([need]) }
        let missing = missingRanges(need, covered: marker.ranges)
        return missing.isEmpty ? .hit(marker) : .miss(missing)
    }

    /// A payload file's bytes as they are on disk.
    static func readPayload(
        _ kind: AnalysisKind, media: UInt32, file: String, in cacheDir: URL
    ) -> Data? {
        try? Data(contentsOf: payloadURL(kind, media: media, file: file, in: cacheDir))
    }

    // MARK: - Coverage

    /// Sorted, merged where two overlap or touch.
    static func merged(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, range.lowerBound <= last.upperBound + 1 {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// The parts of `need` none of `covered` holds, in order.
    static func missingRanges(
        _ need: ClosedRange<Int>, covered: [ClosedRange<Int>]
    ) -> [ClosedRange<Int>] {
        var missing: [ClosedRange<Int>] = []
        var next = need.lowerBound
        for range in merged(covered) where range.upperBound >= next {
            guard range.lowerBound <= need.upperBound else { break }
            if range.lowerBound > next { missing.append(next...(range.lowerBound - 1)) }
            next = max(next, range.upperBound + 1)
            if next > need.upperBound { return missing }
        }
        if next <= need.upperBound { missing.append(next...need.upperBound) }
        return missing
    }

    /// How many of `window`'s indices `covered` holds.
    static func coveredCount(_ window: ClosedRange<Int>, covered: [ClosedRange<Int>]) -> Int {
        merged(covered).reduce(0) { sum, range in
            guard range.overlaps(window) else { return sum }
            return sum + (min(range.upperBound, window.upperBound)
                - max(range.lowerBound, window.lowerBound) + 1)
        }
    }

    // MARK: - The publish

    /// The thread mark `publishCancelled` sets around its body.
    private static let mergeOnlyKey = "FrameJobAnalysisMergeOnly"

    /// A cancelled job's last publish (spec §11 CJ-21 as amended by #435):
    /// runs `publish` with the calling thread marked merge-only, so every
    /// `store` inside it is merge-only. A throw is logged and swallowed, so
    /// the job still ends cancelled. A cache folder already removed (an
    /// untitled document's, at its close) is not made again.
    static func publishCancelled(_ request: AnalysisRequest, _ publish: () throws -> Void) {
        guard FileManager.default.fileExists(atPath: request.cacheDir.path) else { return }
        let thread = Thread.current.threadDictionary
        thread[mergeOnlyKey] = true
        defer { thread.removeObject(forKey: mergeOnlyKey) }
        do {
            try publish()
        } catch {
            NSLog(
                "AnalysisLane: %@ of media %u: the cancelled job's publish failed: %@",
                request.kind.rawValue, request.media.id, error.localizedDescription)
        }
    }

    private static let locksLock = NSLock()
    private static var locks: [String: NSLock] = [:]

    /// The lock of one (cache folder, kind, media id).
    private static func lock(_ kind: AnalysisKind, media: UInt32, in cacheDir: URL) -> NSLock {
        let key = "\(cacheDir.standardizedFileURL.path)|\(kind.rawValue)|\(media)"
        locksLock.lock()
        defer { locksLock.unlock() }
        if let lock = locks[key] { return lock }
        let lock = NSLock()
        locks[key] = lock
        return lock
    }

    /// Merges a job's results into what is on disk (above). `merge` is handed
    /// the kind's first payload file as it is on disk (empty when absent or
    /// when the stamp changed) and edits it in place. Throws when a save held
    /// the cache past the ledger's wait, or a write failed.
    static func publish(
        kind: AnalysisKind, cacheDir: URL, mediaID: UInt32, stamp: AnalysisStamp,
        covered: [ClosedRange<Int>], files: [String], merge: (inout Data) throws -> Void
    ) throws {
        try publishFile(
            kind: kind, cacheDir: cacheDir, mediaID: mediaID, stamp: stamp, covered: covered,
            files: files
        ) { onDisk, partial in
            var data = onDisk.flatMap { try? Data(contentsOf: $0) } ?? Data()
            try merge(&data)
            try data.write(to: partial)
            return onDisk != nil
        }
    }

    /// The publish (above), for a kind that writes its own `.partial`:
    /// `write(onDisk, partial)` is handed the first payload file when the
    /// on-disk marker answers for `stamp` and the file exists (else nil),
    /// writes `partial`, and answers whether it merged `onDisk` — only then
    /// does the marker keep the on-disk coverage. Throws when a save held the
    /// cache past the ledger's wait, or a write failed.
    static func publishFile(
        kind: AnalysisKind, cacheDir: URL, mediaID: UInt32, stamp: AnalysisStamp,
        covered: [ClosedRange<Int>], files: [String],
        write: (_ onDisk: URL?, _ partial: URL) throws -> Bool
    ) throws {
        let perMedia = lock(kind, media: mediaID, in: cacheDir)
        perMedia.lock()
        defer { perMedia.unlock() }
        var failure: Error?
        var wrote = false
        func body() {
            do {
                wrote = try store(
                    kind: kind, cacheDir: cacheDir, mediaID: mediaID, stamp: stamp,
                    covered: covered, files: files, write: write)
            } catch {
                failure = error
            }
        }
        let published = MediaImporter.CacheLedger.shared.publish(
            in: cacheDir, for: nil, as: ledgerWriter(kind, media: mediaID)) { body() }
        guard published else { throw StoreError.saveInFlight }
        if let failure { throw failure }
        guard wrote else { return }
        // A paused preview redraws with what just landed (spec §11 CO-22 (d)).
        let name = kind.rawValue, folder = cacheDir.standardizedFileURL.path
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .analysisDidPublish, object: nil,
                userInfo: ["kind": name, "media": mediaID, "cacheDir": folder])
        }
    }

    /// The store's name at the cache ledger, one per kind and media, so
    /// `analysis_job`'s `save_waits` counts one job's publishes (spec §11
    /// #429, #552).
    static func ledgerWriter(_ kind: AnalysisKind, media: UInt32) -> String {
        "analysis/\(kind.rawValue)/\(media)"
    }

    /// The publish's body; the per-media lock and the ledger are held.
    /// Answers whether it wrote: false only on a merge-only thread
    /// (`publishCancelled`) whose on-disk marker would be replaced, and then
    /// nothing on disk is touched.
    private static func store(
        kind: AnalysisKind, cacheDir: URL, mediaID: UInt32, stamp: AnalysisStamp,
        covered: [ClosedRange<Int>], files: [String],
        write: (_ onDisk: URL?, _ partial: URL) throws -> Bool
    ) throws -> Bool {
        let fm = FileManager.default
        let marker = markerURL(kind, media: mediaID, in: cacheDir)
        let folder = payloadFolder(kind, media: mediaID, in: cacheDir)
        guard let file = files.first else { throw StoreError.write("the kind names no file") }
        let target = folder.appendingPathComponent(file)
        var onDisk = readMarker(kind, media: mediaID, in: cacheDir)
        let replaces = fm.fileExists(atPath: marker.path)
            && (onDisk?.canned == true || onDisk?.stamp?.matches(stamp) != true
                || !fm.fileExists(atPath: target.path))
        // A cancelled job's publish never replaces another stamp's cache (#435).
        if replaces, Thread.current.threadDictionary[mergeOnlyKey] != nil { return false }
        if replaces {
            try? fm.removeItem(at: marker)
            try? fm.removeItem(at: folder)
            onDisk = nil
        }
        let partial = folder.appendingPathComponent(file + ".partial")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fm.removeItem(at: partial)
            let mergedOnDisk: Bool
            do {
                mergedOnDisk = try write(onDisk == nil ? nil : target, partial)
            } catch {
                try? fm.removeItem(at: partial)
                throw error
            }
            guard rename(partial.path, target.path) == 0 else {
                let why = String(cString: strerror(errno))
                try? fm.removeItem(at: partial)
                throw StoreError.write(why)
            }
            let coverage = merged((mergedOnDisk ? onDisk?.ranges ?? [] : []) + covered)
            let next = AnalysisMarker(
                stamp: stamp, canned: nil, source: stamp.source, files: files,
                coverage: coverage.map { [$0.lowerBound, $0.upperBound] })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: marker, options: .atomic)
            return true
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.write(error.localizedDescription)
        }
    }
}

extension Notification.Name {
    /// A publish landed (spec §11 CO-22 (d)): `userInfo` `kind` (the raw value), `media`
    /// (`UInt32`) and `cacheDir` (the standardized path); posted on main, object nil.
    static let analysisDidPublish = Notification.Name("FrameJobAnalysisDidPublish")
}
