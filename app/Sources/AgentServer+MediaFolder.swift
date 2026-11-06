import AppKit

/// `import_media` given a folder (spec §11 #497) — the Media tab's folder drop
/// (`MediaPane.performDragOperation` → `ProjectDocument.importMedia`, which
/// expands it through `MediaFolder`), and the descriptor fields every media
/// answer shares.
extension AgentServer {

    /// The media files directly inside `folder`, probed in Finder order on the
    /// server thread (`AgentServer.offMainTools`, `importMedia`'s reason),
    /// then added as ONE undo step under the drop's name. A probe's refusal,
    /// a file already in the media list and every item `MediaFolder.list`
    /// skips are named in `skipped`; when nothing is left to add, the call is
    /// refused naming them. A folder whose items cannot be listed is refused
    /// in `MediaFolder.Unreadable`'s sentence, the one the drop's alert shows.
    func importMediaFolder(_ folder: URL, _ document: ProjectDocument) throws -> String {
        let listing: MediaFolder.Listing
        do {
            listing = try MediaFolder.list(folder)
        } catch let error as MediaFolder.Unreadable {
            throw ToolError(message: error.errorDescription!)
        }
        var skipped = listing.skipped
        var probed: [(url: URL, descriptor: MediaDescriptor)] = []
        for url in listing.files {
            do {
                let descriptor = try probe(url)
                probed.append((url, descriptor))
            } catch let error as ToolError {
                skipped.append(MediaFolder.Skip(url: url, reason: error.message))
            }
        }
        return try onMain {
            let listed = Set(document.project.snapshot.media.map { $0.path })
            var adding: [MediaDescriptor] = []
            for (url, descriptor) in probed {
                if listed.contains(descriptor.path) {
                    skipped.append(
                        MediaFolder.Skip(url: url, reason: MediaFolder.Reason.listed.rawValue))
                } else {
                    adding.append(descriptor)
                }
            }
            skipped.sort { MediaFolder.finderOrder($0.url, $1.url) }
            let name = folder.lastPathComponent
            guard !adding.isEmpty else {
                guard !skipped.isEmpty else {
                    throw ToolError(
                        message: "Nothing in \(name) was added: it has no files directly inside it.")
                }
                let named = skipped.map { "\($0.url.lastPathComponent) (\($0.reason))" }
                throw ToolError(
                    message: "Nothing in \(name) was added. Skipped: "
                        + named.joined(separator: "; ") + ".")
            }
            let count = adding.count
            let before = try self.performGroupedEdit(
                document, count == 1 ? "Add Media" : "Add \(count) Media Files",
                adding.map { .addMedia(descriptor: $0) })
            let added = Set(ProjectSnapshot.addedMedia(from: before, to: document.project.snapshot))
            let media = document.project.snapshot.media.filter { added.contains($0.id) }
            document.generateCaches()
            // Each new id is the one whose entry has the descriptor's path; the
            // core stamps a list's ids in its order from `next_id`, the fallback.
            let imported: [[String: Any]] = adding.enumerated().map { index, descriptor in
                let id = media.first { $0.path == descriptor.path }?.id
                    ?? before.nextId + UInt32(index)
                return Self.descriptorFields(descriptor, media: Int(id))
            }
            return try self.jsonResult([
                "ok": true,
                "folder": folder.path,
                "imported": imported,
                "skipped": skipped.map { ["path": $0.url.path, "reason": $0.reason] },
                "note": "The files are in the project's media list but not on the timeline yet — "
                    + "place each with add_clip {track, media, at}. A LUT (kind lut) is never "
                    + "placed: apply it as a look with set_video {clips, patch: {look: {kind: "
                    + "\"lut\", media: N}}}.",
                "project": self.summary(document),
            ])
        }
    }

    /// What a probe found, as `import_media` and `relink_media` answer it.
    /// The path is the DESCRIPTOR's, not the argument's: an ffmpeg-assisted
    /// import rewraps the file and the model stores the conversion, so
    /// echoing what was asked for would answer `.mkv` about an entry that is
    /// really a `.mov` — the answer describes what landed in the project.
    static func descriptorFields(_ d: MediaDescriptor, media: Int) -> [String: Any] {
        var fields: [String: Any] = [
            "media": media, "path": d.path, "kind": d.kind.rawValue, "duration": d.duration,
            "width": d.width, "height": d.height, "fps": [d.fps.num, d.fps.den],
            "has_video": d.hasVideo, "has_audio": d.hasAudio, "has_alpha": d.hasAlpha,
        ]
        // A copy's or an ffmpeg conversion's original (spec §11 #228-O,
        // #233): the file the caller named, which the media is named after.
        if let original = d.original { fields["original"] = original.path }
        return fields
    }
}
