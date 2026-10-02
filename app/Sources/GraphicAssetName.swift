// app/Sources/GraphicAssetName.swift — what an asset may be called, so that
// `asset(name)` can use it (spec §11 G-23). Pure: the rule, the legaliser
// both import doors run, the `-N` suffixer for a renamed copy whose legal
// name is held, and the sentences. The scan skips an illegal file by `isLegal`.

import Foundation

enum GraphicAssetName {
    /// 255 (APFS's name limit) − ".partial".utf8.count: `GraphicStore.land(at:writing:)`
    /// (GraphicStore+Files.swift) writes `<name>.partial` first.
    static let maxBytes = 247
    static let rule = "is not an asset name (no leading . or #; no / : \" ' < > & or "
        + "control character; at most \(maxBytes) bytes)"

    private static let forbidden: Set<Unicode.Scalar> = ["/", ":", "\"", "'", "<", ">", "&"]

    private static func isForbidden(_ s: Unicode.Scalar) -> Bool {
        forbidden.contains(s) || s.value <= 0x1F || (0x7F...0x9F).contains(s.value)
    }

    static func isLegal(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let head = scalars.first, name.utf8.count <= maxBytes else { return false }
        return head != "." && head != "#" && !scalars.contains(where: isForbidden)
    }

    /// Precondition: `name` is non-empty, holds no "/", and its extension is one of
    /// `GraphicStore.assetExtensions`. Identity on a legal name.
    static func legalized(_ name: String) -> String {
        let (stem, ext) = split(name)
        var scalars = Array(stem)
        while let head = scalars.first, head == "." || head == "#" || isForbidden(head) {
            scalars.removeFirst()
        }
        while let tail = scalars.last, isForbidden(tail) { scalars.removeLast() }
        var clean: [Unicode.Scalar] = []
        var inRun = false
        for s in scalars {
            if !isForbidden(s) {
                clean.append(s)
            } else if !inRun {
                clean.append("-")
            }
            inRun = isForbidden(s)
        }
        if clean.isEmpty { clean = Array("image".unicodeScalars) }
        return fitted(clean, suffix: ext)
    }

    /// `<stem>-<n>.<ext>`, the stem's tail cut by whole scalars so the result is ≤ maxBytes.
    static func withSuffix(_ name: String, _ n: Int) -> String {
        let (stem, ext) = split(name)
        return fitted(stem, suffix: "-\(n)" + ext)
    }

    static func renameNotice(from: String, to: String) -> String {
        "\"\(from)\" was added as \"\(to)\": asset(name) cannot use the name it had."
    }

    /// The scalars before the last ".", and the rest from that "." on ("" when none).
    private static func split(_ name: String) -> ([Unicode.Scalar], String) {
        let scalars = Array(name.unicodeScalars)
        guard let dot = scalars.lastIndex(of: ".") else { return (scalars, "") }
        let ext = String(String.UnicodeScalarView(scalars[dot...]))
        return (Array(scalars[..<dot]), ext)
    }

    /// `stem` cut by whole scalars from its tail until `stem + suffix` fits maxBytes.
    private static func fitted(_ stem: [Unicode.Scalar], suffix: String) -> String {
        var stem = stem
        let budget = maxBytes - suffix.utf8.count
        var bytes = stem.reduce(0) { $0 + String($1).utf8.count }
        while bytes > budget, let last = stem.popLast() { bytes -= String(last).utf8.count }
        return String(String.UnicodeScalarView(stem)) + suffix
    }
}
