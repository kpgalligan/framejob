import AppKit

/// The derived document (spec §11 CJ-51; road map "creator-jobs" CJ5b): a new
/// document built from a handle — `keep_range` applied when a range is given,
/// the handle as it is when none (VR3's copy) — with each kept media's caches
/// and the drawn graphics carried, so it opens with no cache pass to run.
/// File ▸ New Project from Range… (`EditorViewController+NewFromRange.swift`)
/// and `new_project_from_range` (`AgentServer+Derived.swift`) are its doors;
/// VR3 and FC8a build on it. What is carried is `DerivedCarry`'s.
///
/// **The order is CJ-51 (c)'s, and each step leans on the one before:**
/// 1. `P/project.json` written (atomic), P being `path` or a staging folder
///    `NSTemporaryDirectory()/FrameJob/<UUID>-derived/`.
/// 2. The document opened: with `path`, made from P and added, so `cache/`
///    lands once, inside the package; untitled, `openUntitledDocumentAndDisplay(false)`
///    (the controller adds it), read from the staging folder, named, then
///    counted dirty with no undo step — `untitled(around:)`'s shape.
/// 3. The caches listed in the source's cache folder and copied into the new
///    document's, inside the source's save bracket (`saveBegan` …
///    `saveEnded`, `ProjectDocument+CacheSaves.swift`'s), so the listing and
///    the copy never straddle a publication into the source's cache.
/// 4. `makeWindowControllers()`: `startCaches()` finds the carried markers
///    current and starts no pass; the graphic store starts.
/// 5. The drawn modules, fonts and assets through the started store.
/// 6. `showWindows()` when `display`; 7. with `path`, the recent item.
///
/// A throw after the document exists closes it, and with `path` removes P,
/// which this call created; the staging folder goes on every exit. The source
/// document is never edited: `keep_range` goes through `ReelProject.applying`.
extension ProjectDocument {

    /// The document, and what was carried. Main only.
    static func derived(
        from source: ProjectDocument, handle: ReelProject, range: (from: Ticks, to: Ticks)?,
        path: URL?, display: Bool, name: String
    ) throws -> (document: ProjectDocument, carried: DerivedCarry.Report) {
        assert(Thread.isMainThread)
        let project = try derivedProject(handle, range: range)
        let files = FileManager.default
        if let path, files.fileExists(atPath: path.path) {
            throw ReelCoreError(
                message: "\(path.path) already exists, so the new project was not written there.")
        }
        let package = path ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FrameJob", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-derived", isDirectory: true)
        defer { if path == nil { try? files.removeItem(at: package) } }
        let document: ProjectDocument
        do {
            try files.createDirectory(at: package, withIntermediateDirectories: true)
            try Data(project.json.utf8).write(
                to: package.appendingPathComponent("project.json"), options: .atomic)
            document = try open(package, saved: path != nil, name: name)
        } catch {
            if path != nil { try? files.removeItem(at: package) }
            throw error
        }
        let carried: DerivedCarry.Report
        do {
            carried = try carryCaches(from: source, into: document)
            document.makeWindowControllers()
            if let store = document.graphicStore,
                let folder = source.graphicStore?.folderURL
                    ?? source.fileURL?.appendingPathComponent(
                        GraphicStore.folderName, isDirectory: true)
            {
                try DerivedCarry.carryGraphics(
                    names: DerivedCarry.drawnGraphicNames(document.project.snapshot),
                    from: folder, into: store)
            }
        } catch {
            document.close()
            if path != nil { try? files.removeItem(at: package) }
            throw error
        }
        if display { document.showWindows() }
        if let path { NSDocumentController.shared.noteNewRecentDocumentURL(path) }
        return (document, carried)
    }

    /// CJ-51 (a): `keep_range` applied purely to `handle`, or `handle` itself
    /// with no range. A refusal is thrown in the core's own sentence.
    private static func derivedProject(
        _ handle: ReelProject, range: (from: Ticks, to: Ticks)?
    ) throws -> ReelProject {
        guard let range else { return handle }
        switch try handle.applying(.keepRange(from: range.from, to: range.to)) {
        case .applied(let project): return project
        case .identity: return handle
        case .refused(let refusal): throw ReelCoreError(message: refusal.reason)
        }
    }

    /// Step 2: the package at `package` made into a document — saved there
    /// when `saved`, else untitled, named `name` and dirty with no undo step.
    /// A throw after the untitled document exists closes it.
    private static func open(_ package: URL, saved: Bool, name: String) throws -> ProjectDocument {
        let controller = NSDocumentController.shared
        if saved {
            guard let document = try controller.makeDocument(
                withContentsOf: package, ofType: projectTypeIdentifier) as? ProjectDocument
            else {
                throw ReelCoreError(
                    message: "\(package.lastPathComponent) did not open as a Frame Job project.")
            }
            controller.addDocument(document)
            return document
        }
        guard let document = try controller.openUntitledDocumentAndDisplay(false)
            as? ProjectDocument
        else {
            throw ReelCoreError(message: "The new project could not be created.")
        }
        do {
            try document.read(from: package, ofType: projectTypeIdentifier)
        } catch {
            document.close()
            throw error
        }
        try? FileManager.default.removeItem(at: package)
        document.displayName = name
        document.fileModificationDate = nil
        document.countEditChange(.changeDone)
        return document
    }

    /// Step 3: the kept media's caches copied from the source's cache folder
    /// into `document`'s, inside the source's save bracket. No ledger call on
    /// the derived folder: nothing publishes there before step 4.
    private static func carryCaches(
        from source: ProjectDocument, into document: ProjectDocument
    ) throws -> DerivedCarry.Report {
        guard let from = source.intendedCacheDirectory,
            FileManager.default.fileExists(atPath: from.path),
            let to = document.cacheDirectory
        else { return .none }
        let ledger = MediaImporter.CacheLedger.shared
        let save = ledger.saveBegan(cacheDir: from)
        defer { ledger.saveEnded(cacheDir: from, save: save) }
        let paths = DerivedCarry.cachePaths(
            of: document.project.snapshot, mediaURLs: source.mediaURLs(), in: from)
        return try DerivedCarry.copy(paths, from: from, to: to)
    }
}
