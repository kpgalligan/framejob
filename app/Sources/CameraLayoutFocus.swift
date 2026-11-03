import Foundation

// The camera's crop on the person (road map creator-jobs CO7, spec §11 CO-70): the `focus` the
// menu, the Layout section and `switch_layout` send — the mean centroid of the camera clip's
// cached person masks, minus the media's centre, in the media's source pixels. Only what is
// cached is read and no analysis is started (CO-6); nothing is keyed (CJ-3). Names no `rc_*`.

enum CameraLayoutFocus {

    /// What the focus is read from, captured on main.
    struct Inputs: Equatable {
        let camera: UInt32
        let pack: URL
        let need: [ClosedRange<Int>]
        let coverage: [ClosedRange<Int>]
        let mediaWidth: Int
        let mediaHeight: Int
    }

    /// The menu's and the section's reads.
    static let queue = DispatchQueue(
        label: "com.kgalligan.framejob.camera-layout-focus", qos: .userInitiated)

    /// The camera clip's inputs when its stamped `masks` coverage holds every index its windows
    /// need, else nil. Main thread: the windows over `CutoutStatus.detail`'s handles, CO-22's
    /// need, the marker that answers `CutoutStatus.stamp`.
    static func inputs(camera: UInt32, in document: ProjectDocument) -> Inputs? {
        let handles = document.scope == nil
            ? [document.project] : [document.project, document.editedProject]
        let found = handles.lazy.compactMap { handle in
            (handle.snapshot.clips + handle.snapshot.nests.flatMap(\.clips)).first {
                $0.id == camera
            }
        }.first
        guard let clip = found, let id = clip.source.mediaID,
            let media = document.project.snapshot.media(id), media.width > 0, media.height > 0
        else { return nil }
        let grid = AnalysisGrid(media: media)
        var windows: [CutoutWindow] = []
        for handle in handles {
            guard let plan = handle.plan else { continue }
            windows += CutoutWants.windows(of: camera, plan: plan, snapshot: handle.snapshot)
                .filter { $0.media == id }
        }
        let need = AnalysisStore.merged(windows.map { CutoutWants.need($0, grid: grid) })
        let frames = CutoutStatus.count(need)
        guard frames > 0, let url = mediaURL(for: media),
            let cacheDir = document.intendedCacheDirectory,
            let stamp = CutoutStatus.stamp(media: media, url: url, cacheDir: cacheDir, in: document),
            let marker = AnalysisStore.readMarker(.masks, media: id, in: cacheDir),
            marker.answers(for: stamp), let file = marker.files.first
        else { return nil }
        let pack = AnalysisStore.payloadURL(.masks, media: id, file: file, in: cacheDir)
        guard FileManager.default.fileExists(atPath: pack.path) else { return nil }
        let coverage = AnalysisStore.merged(marker.ranges)
        guard CutoutStatus.count(CutoutStatus.intersect(need, coverage)) == frames else { return nil }
        return Inputs(
            camera: camera, pack: pack, need: need, coverage: coverage,
            mediaWidth: media.width, mediaHeight: media.height)
    }

    // MARK: - The read, memoised

    private struct Key: Hashable {
        let path: String
        let size: UInt64
        let modified: Date
        let need: [ClosedRange<Int>]
        let width: Int
        let height: Int
    }

    private struct Point {
        let value: (Double, Double)?
    }

    private static let lock = NSLock()
    private static var memo: [Key: Point] = [:]
    private static let memoLimit = 64

    /// The mean centroid over the found frames minus `(w/2, h/2)`, or nil when no frame is
    /// found or the pack cannot be read. Any thread; memoised on the pack file's path, size and
    /// modification date, the need and the media's size.
    static func focus(_ inputs: Inputs) -> (Double, Double)? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputs.pack.path)
        let key = (attributes?[.size] as? NSNumber).flatMap { size in
            (attributes?[.modificationDate] as? Date).map { modified in
                Key(
                    path: inputs.pack.standardizedFileURL.path, size: size.uint64Value,
                    modified: modified, need: inputs.need, width: inputs.mediaWidth,
                    height: inputs.mediaHeight)
            }
        }
        if let key {
            lock.lock()
            let hit = memo[key]
            lock.unlock()
            if let hit { return hit.value }
        }
        var value: (Double, Double)?
        if let pack = try? MaskPack(contentsOf: inputs.pack),
            let point = (try? CutoutStatus.centroid(
                pack: pack, need: inputs.need, coverage: inputs.coverage,
                mediaWidth: inputs.mediaWidth, mediaHeight: inputs.mediaHeight)) ?? nil
        {
            value = (
                Double(point.x) - Double(inputs.mediaWidth) / 2,
                Double(point.y) - Double(inputs.mediaHeight) / 2
            )
        }
        if let key {
            lock.lock()
            if memo.count >= memoLimit { memo.removeAll() }
            memo[key] = Point(value: value)
            lock.unlock()
        }
        return value
    }
}
