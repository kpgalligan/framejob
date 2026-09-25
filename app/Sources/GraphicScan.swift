// app/Sources/GraphicScan.swift — what `GraphicStore` found in a package's
// `graphics/` folder: a module file, a font or asset file, and one pass's
// scan (road map 10 §5f, G3a). A pure move out of `GraphicStore.swift`.

import CryptoKit
import Foundation

/// One module file: its name (the file's stem), its bytes and its revision,
/// the SHA-256 of the bytes as 64 lowercase hex digits (G-13).
struct GraphicModuleFile: Equatable {
    let name: String, url: URL, bytes: Data, revision: String
}

/// One font or asset file; `name` is its last path component.
struct GraphicFile: Equatable {
    let name: String, url: URL, bytes: Data
}

/// What one pass over the folder found.
struct GraphicScan: Equatable {
    let modules: [String: GraphicModuleFile]
    let fonts: [GraphicFile], assets: [GraphicFile]
    /// The SHA-256 over the fonts then the assets, each name then bytes, in
    /// name order. The empty set hashes nothing.
    let libraryVersion: String
    /// A file the scan skipped, in its own sentence.
    let warnings: [String]

    static let empty = GraphicScan(
        modules: [:], fonts: [], assets: [],
        libraryVersion: GraphicStore.hex(SHA256().finalize()), warnings: [])
}
