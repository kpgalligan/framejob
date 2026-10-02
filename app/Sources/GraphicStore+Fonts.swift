// app/Sources/GraphicStore+Fonts.swift — the scan's font pass (road map 10
// §5f, G-6), with a verdict per font file kept across passes (spec §11 G-23
// (f)): a file whose size, modification date and file number are those of
// its last verdict is not read or validated again. A miss reads the file and
// validates it on a throwaway `GraphicLibrary`, as every pass did before.
// Accepted: a rewrite that keeps all three is not seen until one changes.
//
// Queue only: `fontVerdicts` is queue-confined like the rest of the store's
// pass state (`GraphicStore.swift`'s threading note), and nothing clears it
// at `stop()` or `start()`.

import Foundation

/// What identifies a font file's contents for the verdict cache.
struct GraphicFontIdentity: Equatable {
    let size: UInt64
    let modified: Date
    let fileNumber: UInt64

    /// The file's identity, or nil when its attributes cannot be read.
    init?(of url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.uint64Value,
            let modified = attributes[.modificationDate] as? Date,
            let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return nil }
        self.size = size
        self.modified = modified
        self.fileNumber = fileNumber
    }
}

/// One font file's last verdict: the accepted file, or the refusal's warning.
struct GraphicFontVerdict {
    let identity: GraphicFontIdentity
    let file: GraphicFile?
    let warning: String?
}

extension GraphicStore {
    /// Queue only. Answers the accepted fonts and the refusal warnings in `urls` order;
    /// prunes `fontVerdicts` to `urls`.
    func validatedFonts(_ urls: [URL]) -> (fonts: [GraphicFile], warnings: [String]) {
        var fonts: [GraphicFile] = []
        var warnings: [String] = []
        var kept: [String: GraphicFontVerdict] = [:]
        for url in urls {
            let key = url.standardizedFileURL.path
            let identity = GraphicFontIdentity(of: url)
            let verdict: (file: GraphicFile?, warning: String?)
            if let cached = fontVerdicts[key], let identity = identity,
                cached.identity == identity
            {
                verdict = (cached.file, cached.warning)
            } else {
                // An unreadable file is skipped silently, as the scan always did.
                guard let bytes = try? Data(contentsOf: url) else { continue }
                do {
                    try GraphicLibrary().addFont(bytes)
                    let file = GraphicFile(name: url.lastPathComponent, url: url, bytes: bytes)
                    verdict = (file, nil)
                } catch {
                    verdict = (nil, "\(Self.relative(url)): \(error.localizedDescription)")
                }
            }
            if let file = verdict.file { fonts.append(file) }
            if let warning = verdict.warning { warnings.append(warning) }
            if let identity = identity {
                kept[key] = GraphicFontVerdict(
                    identity: identity, file: verdict.file, warning: verdict.warning)
            }
        }
        fontVerdicts = kept
        return (fonts, warnings)
    }
}
