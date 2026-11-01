import Foundation

/// The analysis store (spec §11 CJ-22; road map "creator-jobs" CJ2a): where a
/// kind's results for one media live, what they cover, the hit rule, and the
/// one door every write goes through.
///
/// `cache/analysis/<kind>/<media id>.json` is the marker (`AnalysisMarker`);
/// `cache/analysis/<kind>/<media id>/` holds the payload files the kind names.
/// A request is a HIT when the marker answers for its stamp and the coverage
/// holds every index it needs (its window plus the kind's read margin);
/// otherwise the job runs only the missing ranges.
///
/// **The publish** runs under a lock keyed by (cache folder, kind, media id)
/// and inside `CacheLedger.publish(in:for: nil)` — never mid-save, never
/// waiting on main. It re-reads the marker, deletes marker then payload when
/// the on-disk stamp is not the job's, reads the payload as it is on disk,
/// applies the job's merge, writes it through a `.partial` and a rename, then
/// writes the marker with the union of the on-disk and the job's coverage,
/// sorted keys, `.atomic`. Two jobs of one media therefore merge rather than
/// overwrite one another (P8).
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
        guard let marker = readMarker(kind, media: media, in: cacheDir), marker.answers(for: stamp)
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
        let perMedia = lock(kind, media: mediaID, in: cacheDir)
        perMedia.lock()
        defer { perMedia.unlock() }
        var failure: Error?
        func body() {
            do {
                try write(
                    kind: kind, cacheDir: cacheDir, mediaID: mediaID, stamp: stamp,
                    covered: covered, files: files, merge: merge)
            } catch {
                failure = error
            }
        }
        let published = MediaImporter.CacheLedger.shared.publish(in: cacheDir, for: nil) { body() }
        guard published else { throw StoreError.saveInFlight }
        if let failure { throw failure }
    }

    /// The publish's body; the per-media lock and the ledger are held.
    private static func write(
        kind: AnalysisKind, cacheDir: URL, mediaID: UInt32, stamp: AnalysisStamp,
        covered: [ClosedRange<Int>], files: [String], merge: (inout Data) throws -> Void
    ) throws {
        let fm = FileManager.default
        let marker = markerURL(kind, media: mediaID, in: cacheDir)
        let folder = payloadFolder(kind, media: mediaID, in: cacheDir)
        var onDisk = readMarker(kind, media: mediaID, in: cacheDir)
        if fm.fileExists(atPath: marker.path),
            onDisk?.canned == true || onDisk?.stamp?.matches(stamp) != true
        {
            try? fm.removeItem(at: marker)
            try? fm.removeItem(at: folder)
            onDisk = nil
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let file = files.first else { throw StoreError.write("the kind names no file") }
            let target = folder.appendingPathComponent(file)
            var data = onDisk == nil ? Data() : ((try? Data(contentsOf: target)) ?? Data())
            try merge(&data)
            let partial = folder.appendingPathComponent(file + ".partial")
            try data.write(to: partial)
            guard rename(partial.path, target.path) == 0 else {
                let why = String(cString: strerror(errno))
                try? fm.removeItem(at: partial)
                throw StoreError.write(why)
            }
            let coverage = merged((onDisk?.ranges ?? []) + covered)
            let next = AnalysisMarker(
                stamp: stamp, canned: nil, source: stamp.source, files: files,
                coverage: coverage.map { [$0.lowerBound, $0.upperBound] })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: marker, options: .atomic)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.write(error.localizedDescription)
        }
    }
}
