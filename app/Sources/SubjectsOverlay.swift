import AppKit

/// View ▸ Show Subjects' drawing (spec §11 VR-13; road map "creator-jobs"
/// VR1): the selected clip's cached face, person and salient boxes at the
/// playhead, over the canvas. One per window while the item is on (the
/// canvas's `subjects`), never persisted.
///
/// **It draws only what is cached and never starts a job**: it never calls
/// `analysisRequest`, `AnalysisLane.want` or `cacheDirectory` (which would
/// create the folder); it reads markers and payloads under the document's
/// `intendedCacheDirectory`.
///
/// **Which sample.** The canvas's primary box, when its clip is a media clip
/// of a video media: the playhead's forward source tick through the clip's
/// source map and the reversed mirror (`sourceTick`, `TimelineView.sourceTime`,
/// `ReverseMirror`), then the kind's sample index (`sampleIndex`). A kind
/// draws only when that index is covered by a marker that answers for the
/// stamp `ProjectDocument.analysisRequest` would make.
///
/// **The memo** (CO-25's key, as `CutoutMasks`'): per kind, the marker's
/// (inode, size, mtime), the media, its URL and its LUT's URL; the marker, the
/// stamp check and the payload are read again only when one changes, and an
/// `.analysisDidPublish` of `faces` or `subjects` in the document's cache
/// folder drops the memo and redraws.
///
/// **Where.** Each box is placed in the layer's uncropped rectangle, turned
/// with the layer (`corners`, ProjectSnapshot's (★) through `CanvasLayerBox`),
/// and clipped to the layer's cropped corners. Faces in `DS.snapGuide`, people
/// in teal, salient regions in purple dashed, each over a black backing
/// stroke as the selection outline has. With neither kind covering, "Not
/// analyzed" at the layer's top-left corner. Main only.
final class SubjectsOverlay {
    static let notAnalyzed = "Not analyzed"
    /// The kinds drawn, back to front.
    static let kinds: [AnalysisKind] = [.subjects, .faces]

    private weak var document: ProjectDocument?
    private let redraw: () -> Void
    private var observer: NSObjectProtocol?
    private var memo: [AnalysisKind: Entry] = [:]

    /// What a kind's read depends on (CO-25).
    private struct Key: Equatable {
        let media: MediaSnapshot
        let url: URL
        let lut: URL?
        let marker: Signature?
    }

    private struct Signature: Equatable {
        let inode: UInt64
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
    }

    /// One kind's read: its covered ranges and boxes per sample (nil: no
    /// marker answering for the stamp).
    private struct Entry {
        let key: Key
        let covered: [ClosedRange<Int>]
        let boxes: [[(rect: CGRect, style: Style)]]
    }

    private enum Style { case face, person, salient }

    init(document: ProjectDocument, redraw: @escaping () -> Void) {
        self.document = document
        self.redraw = redraw
        observer = NotificationCenter.default.addObserver(
            forName: .analysisDidPublish, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.didPublish(note) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func didPublish(_ note: Notification) {
        guard let kind = note.userInfo?["kind"] as? String,
            kind == AnalysisKind.faces.rawValue || kind == AnalysisKind.subjects.rawValue,
            let folder = note.userInfo?["cacheDir"] as? String,
            folder == document?.intendedCacheDirectory?.standardizedFileURL.path
        else { return }
        memo.removeAll()
        redraw()
    }

    // MARK: - Drawing

    func draw(on canvas: PreviewCanvasView) {
        guard let document, let layer = canvas.primaryBox,
            case .media(let id, _, _) = layer.clip.source,
            let media = canvas.snapshot.media(id), media.kind == .video, media.hasVideo
        else { return }
        let urls = document.mediaURLs()
        guard let url = urls[id], let cacheDir = document.intendedCacheDirectory else {
            label(on: canvas, layer: layer)
            return
        }
        let source = Self.sourceTick(
            of: layer.clip, in: media, at: canvas.playhead,
            map: canvas.project?.sourceMap(layer.clip.id))
        var drew = false
        NSGraphicsContext.saveGraphicsState()
        canvas.polygon(layer.corners).addClip()
        for kind in Self.kinds {
            let entry = read(kind, media: media, url: url, urls: urls, cacheDir: cacheDir)
            let k = Self.sampleIndex(at: source, grid: kind.grid(of: media))
            guard entry.covered.contains(where: { $0.contains(k) }), k < entry.boxes.count
            else { continue }
            drew = true
            for (rect, style) in entry.boxes[k] {
                stroke(canvas.polygon(Self.corners(of: rect, on: layer)), style)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if !drew { label(on: canvas, layer: layer) }
    }

    private func stroke(_ path: NSBezierPath, _ style: Style) {
        NSColor.black.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 2
        path.stroke()
        switch style {
        case .face: DS.snapGuide.setStroke()
        case .person: NSColor.systemTeal.setStroke()
        case .salient:
            NSColor.systemPurple.setStroke()
            let dash: [CGFloat] = [4, 3]
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.lineWidth = 1
        path.stroke()
    }

    /// "Not analyzed" at the layer's top-left corner, on a dark backing.
    private func label(on canvas: PreviewCanvasView, layer: CanvasLayerBox) {
        guard let corner = layer.corners.first else { return }
        let at = canvas.canvasToView(corner)
        let text = NSAttributedString(
            string: Self.notAnalyzed,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
        let size = text.size()
        let y = canvas.overlay.isFlipped ? at.y + 4 : at.y - 4 - size.height
        let box = CGRect(x: at.x + 4, y: y, width: size.width + 8, height: size.height + 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(rect: box).fill()
        text.draw(at: CGPoint(x: box.minX + 4, y: box.minY + 1))
    }

    // MARK: - The read

    private func read(
        _ kind: AnalysisKind, media: MediaSnapshot, url: URL, urls: [UInt32: URL], cacheDir: URL
    ) -> Entry {
        let markerURL = AnalysisStore.markerURL(kind, media: media.id, in: cacheDir)
        let key = Key(
            media: media, url: url, lut: media.color?.lut.flatMap { urls[$0] },
            marker: Self.signature(of: markerURL))
        if let entry = memo[kind], entry.key == key { return entry }
        var entry = Entry(key: key, covered: [], boxes: [])
        if key.marker != nil,
            let marker = AnalysisStore.readMarker(kind, media: media.id, in: cacheDir),
            case let (input, fullRange) = ProjectDocument.analysisInput(
                media: media, url: url, urls: urls),
            let stamp = AnalysisStamp.make(
                kind: kind, media: media, url: url, input: input, fullRange: fullRange),
            marker.answers(for: stamp),
            let boxes = Self.boxes(kind, media: media.id, cacheDir: cacheDir)
        {
            entry = Entry(key: key, covered: AnalysisStore.merged(marker.ranges), boxes: boxes)
        }
        memo[kind] = entry
        return entry
    }

    /// Each sample's boxes and styles; nil when the payload does not decode.
    private static func boxes(_ kind: AnalysisKind, media: UInt32, cacheDir: URL)
        -> [[(rect: CGRect, style: Style)]]?
    {
        func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> CGRect {
            CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        }
        switch kind {
        case .faces:
            guard let data = AnalysisStore.readPayload(
                .faces, media: media, file: AnalysisFaces.payloadName, in: cacheDir),
                let decoded = AnalysisFaces.decode(data)
            else { return nil }
            return decoded.samples.map { sample in
                sample.faces.map { (rect($0.x, $0.y, $0.width, $0.height), Style.face) }
            }
        case .subjects:
            guard let data = AnalysisStore.readPayload(
                .subjects, media: media, file: AnalysisSubjects.payloadName, in: cacheDir),
                let decoded = AnalysisSubjects.decode(data)
            else { return nil }
            return decoded.samples.map { sample in
                sample.subjects.salient.map {
                    (rect($0.x, $0.y, $0.width, $0.height), Style.salient)
                } + sample.subjects.people.map {
                    (rect($0.x, $0.y, $0.width, $0.height), Style.person)
                }
            }
        case .shots, .masks, .soundEvents:
            return nil
        }
    }

    private static func signature(of url: URL) -> Signature? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Signature(
            inode: UInt64(info.st_ino), size: Int64(info.st_size),
            seconds: Int(info.st_mtimespec.tv_sec), nanoseconds: Int(info.st_mtimespec.tv_nsec))
    }

    // MARK: - Pure mapping

    /// The forward media's source tick under `playhead` in `clip`: through
    /// its source map when it ramps, its speed when not, mirrored about the
    /// media's duration when it plays backwards (`TimelineView.sourceTime`).
    static func sourceTick(
        of clip: ClipSnapshot, in media: MediaSnapshot, at playhead: Ticks, map: SourceMap?
    ) -> Ticks {
        TimelineView.sourceTime(of: clip, in: media, at: playhead, map: map)
    }

    /// The sample whose instant is the last at or before `source`:
    /// ⌊source · rate⌋, clamped to 0…lastIndex.
    static func sampleIndex(at source: Ticks, grid: AnalysisGrid) -> Int {
        min(grid.lastIndex, max(0, Int((Double(source) * grid.rate).rounded(.down))))
    }

    /// A normalised box (0…1, top-left, of the upright picture) placed in the
    /// layer's UNCROPPED rectangle and turned with the layer: its four
    /// corners in canvas pixels, TL TR BR BL.
    static func corners(of box: CGRect, on layer: CanvasLayerBox) -> [CGPoint] {
        let r = layer.uncroppedRect
        let placed = CGRect(
            x: r.minX + box.minX * r.width, y: r.minY + box.minY * r.height,
            width: box.width * r.width, height: box.height * r.height)
        return layer.corners(of: placed)
    }
}
