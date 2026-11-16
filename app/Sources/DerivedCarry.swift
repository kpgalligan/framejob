import Foundation

/// What a derived document carries from its source (spec §11 CJ-51 (b), (e);
/// road map "creator-jobs" CJ5b): which cache paths the kept media own, the
/// clone-or-copy that lands them, the graphic modules the kept clips draw,
/// and the fonts and assets beside them. `ProjectDocument+Derived.swift` is
/// the door that calls it, in CJ-51 (c)'s order.
///
/// Carried per kept media id `m` (a media the DERIVED snapshot still lists):
/// `thumbs/m/`; `peaks/m.bin` and its marker; `loudness/m.bin` and its
/// marker; `speech/m.bin` and its marker; `sync/m.bin`, `sync/m.pcm` and
/// their marker; every `device-transcripts/m-*.json`; for every kind folder
/// under `analysis/`, `analysis/<kind>/m.json` and `analysis/<kind>/m/`;
/// `transcripts/m.json` and its marker only when the file records
/// `remote_deleted: true` (one still owed a DELETE stays in the source, N4);
/// and the reversed render of each media a kept clip plays backwards (N5).
/// Never media files, `ramp-audio/`, `isolated/`, `voiced/` or
/// `graphics/history/`.
enum DerivedCarry {

    /// What one carry copied: regular files, their bytes, and the seconds the
    /// copy took on the main thread.
    struct Report: Equatable {
        let files: Int
        let bytes: Int64
        let seconds: Double

        static let none = Report(files: 0, bytes: 0, seconds: 0)
    }

    // MARK: - Caches

    /// Relative paths under `cacheDir` (files or folders) that exist and that
    /// `snapshot`'s media carry, sorted. `mediaURLs` resolves a media to the
    /// file its reversed render's digest was taken over.
    static func cachePaths(
        of snapshot: ProjectSnapshot, mediaURLs: [UInt32: URL], in cacheDir: URL
    ) -> [String] {
        let files = FileManager.default
        var paths: [String] = []
        func keep(_ relative: String) {
            if files.fileExists(atPath: cacheDir.appendingPathComponent(relative).path) {
                paths.append(relative)
            }
        }
        let analysisKinds = folders(in: cacheDir.appendingPathComponent("analysis"))
        let deviceTranscripts = names(in: cacheDir.appendingPathComponent(
            DeviceTranscriptCache.kind))
        for media in snapshot.media {
            let m = media.id
            keep("thumbs/\(m)")
            for kind in ["peaks", "loudness", "speech"] {
                keep("\(kind)/\(m).bin")
                keep("\(kind)/\(m).complete.json")
            }
            for name in ["\(m).bin", "\(m).pcm", "\(m).complete.json"] { keep("sync/\(name)") }
            for name in deviceTranscripts where name.hasPrefix("\(m)-") && name.hasSuffix(".json") {
                keep("\(DeviceTranscriptCache.kind)/\(name)")
            }
            for kind in analysisKinds {
                keep("analysis/\(kind)/\(m).json")
                keep("analysis/\(kind)/\(m)")
            }
            if MediaTranscript.read(for: m, in: cacheDir)?.header.remoteDeleted == true {
                keep("\(MediaImporter.transcriptsKind)/\(m).json")
                keep("\(MediaImporter.transcriptsKind)/\(m).complete.json")
            }
        }
        for name in reversedRenders(of: snapshot, mediaURLs: mediaURLs, in: cacheDir) {
            keep("\(ReverseCache.directoryName)/\(name)")
        }
        return paths.sorted()
    }

    /// The file name of each existing reversed render a kept clip — top level
    /// or nest — plays, its media not an image (`reverseState`'s walk).
    private static func reversedRenders(
        of snapshot: ProjectSnapshot, mediaURLs: [UInt32: URL], in cacheDir: URL
    ) -> Set<String> {
        var media: [UInt32: MediaSnapshot] = [:]
        for entry in snapshot.media where media[entry.id] == nil { media[entry.id] = entry }
        var names: Set<String> = []
        for clip in snapshot.clips + snapshot.nests.flatMap(\.clips) where clip.source.isReversed {
            guard let id = clip.source.mediaID, let entry = media[id], entry.kind != .image,
                let source = mediaURLs[id],
                let url = ReverseCache.existing(media: id, source: source, in: cacheDir)
            else { continue }
            names.insert(url.lastPathComponent)
        }
        return names
    }

    /// What a carry copies, both relative to the source and sorted: the folders it creates and
    /// the regular files it clones.
    struct Listing: Equatable {
        let folders: [String]
        let files: [String]
    }

    /// Each of `paths` that exists under `source`: a file as itself; a folder as itself and
    /// every regular file under it. A folder that vanishes while it is enumerated contributes
    /// nothing. Main.
    static func listing(_ paths: [String], in source: URL) -> Listing {
        let files = FileManager.default
        var folders: [String] = []
        var regular: [String] = []
        for relative in paths {
            var isFolder: ObjCBool = false
            let from = source.appendingPathComponent(relative)
            guard files.fileExists(atPath: from.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else {
                regular.append(relative)
                continue
            }
            guard let inner = try? regularFiles(under: from) else { continue }
            folders.append(relative)
            regular += inner.map { "\(relative)/\($0)" }
        }
        return Listing(folders: folders.sorted(), files: regular.sorted())
    }

    /// `copy(_:from:to:)` over `listing(paths, in: source)`. Main.
    static func copy(_ paths: [String], from source: URL, to destination: URL) throws -> Report {
        try copy(listing(paths, in: source), from: source, to: destination)
    }

    /// Each folder of `listing` created under `destination`, then each file cloned from
    /// `source` (`copyfile` with `COPYFILE_CLONE`, which falls back to a copy where the volume
    /// cannot clone). A file gone from the source when it is cloned is skipped and not counted
    /// — the thumbnail pass prunes its tiles outside the save bracket, and the copy's own pass
    /// makes them again (#459); any other failure throws, naming the file. Main.
    static func copy(_ listing: Listing, from source: URL, to destination: URL) throws -> Report {
        let began = Date()
        let files = FileManager.default
        var count = 0
        var bytes: Int64 = 0
        for relative in listing.folders {
            try files.createDirectory(
                at: destination.appendingPathComponent(relative), withIntermediateDirectories: true)
        }
        for relative in listing.files {
            let from = source.appendingPathComponent(relative)
            let to = destination.appendingPathComponent(relative)
            try files.createDirectory(
                at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_CLONE)) == 0 else {
                let why = String(cString: strerror(errno))
                if !files.fileExists(atPath: from.path) { continue }
                throw ReelCoreError(message: "cache/\(relative) could not be carried: \(why)")
            }
            count += 1
            let size = (try? files.attributesOfItem(atPath: to.path)[.size] as? NSNumber)
            bytes += size?.int64Value ?? 0
        }
        return Report(files: count, bytes: bytes, seconds: Date().timeIntervalSince(began))
    }

    /// Every regular file under `folder`, as paths relative to it, sorted.
    private static func regularFiles(under folder: URL) throws -> [String] {
        let files = FileManager.default
        var found: [String] = []
        for relative in try files.subpathsOfDirectory(atPath: folder.path) {
            var isFolder: ObjCBool = false
            let path = folder.appendingPathComponent(relative).path
            if files.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue {
                found.append(relative)
            }
        }
        return found.sorted()
    }

    /// The folder names directly inside `folder`, sorted; none when it is absent.
    private static func folders(in folder: URL) -> [String] {
        names(in: folder).filter { name in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(name).path, isDirectory: &isFolder)
                && isFolder.boolValue
        }
    }

    /// The entries directly inside `folder`, sorted; none when it is absent.
    private static func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Graphics

    /// Every graphic clip's module name, top level and every nest
    /// (`reconcileGraphicNames`' set).
    static func drawnGraphicNames(_ snapshot: ProjectSnapshot) -> Set<String> {
        Set(
            (snapshot.clips + snapshot.nests.flatMap(\.clips))
                .compactMap { $0.graphic?.name }.filter(GraphicStore.isModuleName))
    }

    /// `<name>.js` of each drawn name present in `folder` through
    /// `store.write(name:bytes:)`; every regular file of `fonts/` and
    /// `assets/` through `store.importFile(from:into:as:)`; then ONE
    /// `store.rescan()`. Never `history/`. Main.
    static func carryGraphics(names: Set<String>, from folder: URL, into store: GraphicStore) throws {
        let files = FileManager.default
        for name in names.sorted() {
            let module = folder.appendingPathComponent(name + ".js")
            guard files.fileExists(atPath: module.path) else { continue }
            try store.write(name: name, bytes: try Data(contentsOf: module))
        }
        for subfolder in [GraphicStore.fontsFolderName, GraphicStore.assetsFolderName] {
            let from = folder.appendingPathComponent(subfolder, isDirectory: true)
            for name in Self.names(in: from) {
                var isFolder: ObjCBool = false
                let file = from.appendingPathComponent(name)
                guard files.fileExists(atPath: file.path, isDirectory: &isFolder),
                    !isFolder.boolValue
                else { continue }
                _ = try store.importFile(from: file, into: subfolder, as: name)
            }
        }
        store.rescan()
    }
}
