import AppKit

// The graphics engine's wrappers — `GraphicLibrary`, `GraphicModule`, `ReelGraphicPackage` —
// and their diagnostics: a pure move out of `ReelCore.swift` (road map creator-jobs CJ0d, T15).

// MARK: - Graphics

/// Decodes and frees a `diag_out`. An unreadable one is one error saying so.
private func takeDiagnostics(_ raw: UnsafeMutablePointer<CChar>?) -> [GraphicDiagnostic] {
    takeString(raw).map(GraphicDiagnostic.list(json:)) ?? []
}

/// The engine's fonts and assets (`RcGraphicLibrary`), frozen by its first compile or rasterize;
/// it and a module compiled against it may be freed in either order.
final class GraphicLibrary {
    /// The header's `RC_GRAPHIC_MAX_SIDE`; a larger side is refused before allocating.
    static let maxSide = Int(RC_GRAPHIC_MAX_SIDE)
    fileprivate let handle: OpaquePointer

    init() { handle = rc_graphic_library_new() }
    deinit { rc_graphic_library_free(handle) }

    func addFont(_ bytes: Data) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let ok = withByteBuffer(bytes) { rc_graphic_library_add_font(handle, $0, $1, &err) }
        if !ok { throw ReelCoreError(message: takeErrorMessage(err, fallback: "No font added.")) }
    }

    func addAsset(name: String, bytes: Data) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let ok = withByteBuffer(bytes) { rc_graphic_library_add_asset(handle, name, $0, $1, &err) }
        if !ok { throw ReelCoreError(message: takeErrorMessage(err, fallback: "No asset added.")) }
    }

    /// Sets the per-process image cache's limit (spec §11 G-39); answers the bytes it holds.
    @discardableResult static func imageCache(limit: Int) -> Int {
        rc_graphic_image_cache(max(0, limit))
    }

    /// The engine's family names, sorted. FREEZES the library.
    func families() -> [String] {
        guard let json = takeString(rc_graphic_library_families(handle)) else { return [] }
        return ReelJSON.decode([String].self, from: json) ?? []
    }

    /// What every parse and measure has used (spec §11 G-46 (b)). FREEZES the library.
    func usage() -> GraphicUsage {
        GraphicUsage.decoded(takeString(rc_graphic_library_usage(handle)))
    }

    /// `svg` drawn at `width`×`height`, rows `width × 4` bytes apart; `deep` draws it at 16
    /// bits a channel (`rc_graphic_rasterize_deep`, spec §11 PR-15), rows `width × 8` bytes
    /// apart, for a frame delivered deeper than 8 bits.
    func rasterize(
        _ svg: String, width: Int, height: Int, deep: Bool = false
    ) throws -> GraphicRaster {
        try GraphicFailure.checkSides(width, height, max: Self.maxSide)
        if deep { return try rasterizeDeep(svg, width: width, height: height) }
        let stride = width * 4
        var bgra = [UInt8](repeating: 0, count: max(height * stride, 1))
        var diag: UnsafeMutablePointer<CChar>? = nil
        let ok = bgra.withUnsafeMutableBufferPointer { out in
            rc_graphic_rasterize(
                handle, svg, UInt32(width), UInt32(height), out.baseAddress, stride, &diag)
        }
        let diagnostics = takeDiagnostics(diag)
        guard ok else { throw GraphicFailure(diagnostics: diagnostics) }
        return GraphicRaster(
            width: width, height: height, stride: stride, bgra: bgra, warnings: diagnostics)
    }

    /// The deep draw: the export writes every value on success and the call throws
    /// otherwise, so the buffer is made without a zero fill.
    private func rasterizeDeep(_ svg: String, width: Int, height: Int) throws -> GraphicRaster {
        let values = width * 4
        var diag: UnsafeMutablePointer<CChar>? = nil
        var ok = false
        let rgba16 = [UInt16](unsafeUninitializedCapacity: max(height * values, 1)) { out, count in
            ok = rc_graphic_rasterize_deep(
                handle, svg, UInt32(width), UInt32(height), out.baseAddress, values, &diag)
            if !ok { out.initialize(repeating: 0) }
            count = out.count
        }
        let diagnostics = takeDiagnostics(diag)
        guard ok else { throw GraphicFailure(diagnostics: diagnostics) }
        return GraphicRaster(
            width: width, height: height, stride: values * 2, bgra: [], warnings: diagnostics,
            rgba16: rgba16)
    }
}

/// One compiled graphic module (`RcGraphic`). Holds its library strongly.
final class GraphicModule {
    let library: GraphicLibrary
    private let handle: OpaquePointer

    private init(library: GraphicLibrary, handle: OpaquePointer) {
        self.library = library
        self.handle = handle
    }

    deinit { rc_graphic_free(handle) }

    static func compile(
        library: GraphicLibrary, name: String, source: String, budgetMs: Int
    ) throws -> GraphicModule {
        var diag: UnsafeMutablePointer<CChar>? = nil
        let made = rc_graphic_compile(
            library.handle, name, source, UInt32(clamping: budgetMs), &diag)
        let diagnostics = takeDiagnostics(diag)
        guard let handle = made else { throw GraphicFailure(diagnostics: diagnostics) }
        return GraphicModule(library: library, handle: handle)
    }

    /// `{"meta":…,"schema":…,"revision":…,"warnings":[…]}`, the schema in the module's order.
    func describeJSON() -> String {
        takeString(rc_graphic_describe(handle)) ?? "{}"
    }

    func svg(
        frame: Int, propsJSON: String, ctxJSON: String, budgetMs: Int
    ) throws -> (svg: String, warnings: [GraphicDiagnostic]) {
        var diag: UnsafeMutablePointer<CChar>? = nil
        let out = rc_graphic_svg(
            handle, Int64(frame), propsJSON, ctxJSON, UInt32(clamping: budgetMs), &diag)
        let diagnostics = takeDiagnostics(diag)
        guard let svg = takeString(out) else { throw GraphicFailure(diagnostics: diagnostics) }
        return (svg, diagnostics)
    }
}

/// The core's `.fjgraphic` writer (spec §11 G-46 (c)) and reader (G-47 (c)).
enum ReelGraphicPackage {
    /// Writes the package at `path` from `packageJSON` and `data` (the files' bytes in order);
    /// answers its `manifest.json`, or throws the core's sentence.
    static func write(path: String, packageJSON: String, data: Data) throws -> String {
        var err: UnsafeMutablePointer<CChar>? = nil
        let raw = withByteBuffer(data) { rc_graphic_package_write(path, packageJSON, $0, $1, &err) }
        guard let manifest = takeString(raw) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be written"))
        }
        return manifest
    }

    /// Checks the package held in `data` (spec §11 G-47 (c)); answers its manifest with each
    /// file's `offset` in `data`, or throws the core's sentence.
    static func read(_ data: Data) throws -> String {
        var err: UnsafeMutablePointer<CChar>? = nil
        let raw = withByteBuffer(data) { rc_graphic_package_read($0, $1, &err) }
        guard let answer = takeString(raw) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        return answer
    }
}
