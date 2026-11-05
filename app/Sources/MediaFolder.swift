// app/Sources/MediaFolder.swift — a folder handed to an import door (spec §11
// #497): a Media tab drop (`ProjectDocument.importMedia`) and `import_media`
// (`AgentServer+MediaFolder.swift`) both replace it by the media files
// directly inside it, one level down, in Finder order.

import Foundation
import UniformTypeIdentifiers

enum MediaFolder {
    /// Why a visible item inside the folder was not imported. A hidden file
    /// is left out and never named.
    enum Reason: String {
        case notMedia = "not a media file"
        case folder = "a folder"
        case package = "a package"
        case listed = "already in the media list"
    }

    /// One item left out: a `Reason`'s raw value, or a probe's own sentence.
    struct Skip {
        let url: URL
        let reason: String
    }

    /// A folder's media files and what was skipped, each sorted as the
    /// Finder sorts names.
    struct Listing {
        let folder: URL
        let files: [URL]
        let skipped: [Skip]
    }

    /// Whether `url` is a folder an import door expands: a directory, or a
    /// link to one, that is not a package (a `.framejob`, an `.rtfd`).
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resolvingSymlinksInPath().resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    /// Whether an import door can read `url`: a `.cube` by its extension, a
    /// type conforming to `public.audiovisual-content`, a still of
    /// `MediaImporter.imageTypes`, or a file beginning with an EBML header
    /// (a Matroska file with no extension among them). The type is the
    /// file's own, else its extension's.
    static func isMedia(_ url: URL) -> Bool {
        if MediaImporter.isLUT(url) { return true }
        let type =
            (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .audiovisualContent) == true { return true }
        if MediaImporter.isImage(url) { return true }
        return ContainerRewrap.isMatroska(url)
    }

    /// The media files directly inside `folder` and every other visible item
    /// as a skip. Hidden files are left out; an item that is a link is
    /// judged by what it names.
    static func list(_ folder: URL) -> Listing {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])) ?? []
        var files: [URL] = []
        var skipped: [Skip] = []
        for child in children {
            let values = try? child.resolvingSymlinksInPath().resourceValues(
                forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isPackage == true {
                skipped.append(Skip(url: child, reason: Reason.package.rawValue))
            } else if values?.isDirectory == true {
                skipped.append(Skip(url: child, reason: Reason.folder.rawValue))
            } else if isMedia(child.resolvingSymlinksInPath()) {
                files.append(child)
            } else {
                skipped.append(Skip(url: child, reason: Reason.notMedia.rawValue))
            }
        }
        files.sort(by: finderOrder)
        skipped.sort { finderOrder($0.url, $1.url) }
        return Listing(folder: folder, files: files, skipped: skipped)
    }

    /// `urls` with each folder replaced, in place, by its media files.
    static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { isFolder($0) ? list($0).files : [$0] }
    }

    /// The Finder's order of two names: numbers by value, case ignored.
    static func finderOrder(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }
}
