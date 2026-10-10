import AppKit

/// The Look section's gallery model (spec §11 GR-7 [b], grading GR5b):
/// which clips a look applies to, the op a tile or a menu item sends,
/// and the nine thumbnails — None and the eight — each the composited frame
/// with that tile's click applied, then one per imported `.cube` LUT (spec
/// §11 GR-8 [b]), in the media list's order.
///
/// **It lives on `ClipPane`, not on the view**, because the pane rebuilds its
/// sections on every structure change and a thumbnail set that died with each
/// build would re-render for nothing. A view attaches itself (`view`) when it
/// is built, and an update from any other view — a retired build's late
/// `viewDidMoveToWindow` — is ignored.
///
/// **When it renders.** Its inputs are the edited project's HANDLE, the target
/// ids and the thumbnail time. An update or a playhead poke with the inputs it
/// last scheduled does nothing; anything else re-arms one `settle` timer, so a
/// playhead moving every frame (playback, a scrub) never renders. The timer
/// renders only if the gallery is open then (its section expanded, its window
/// there); hiding it or leaving the window cancels the timer and supersedes a
/// running generation. A generation applies the trial ops (the nine, then one
/// per LUT) on main and renders them off main, one tile after another, through
/// `Exporter.renderFrame` — `render_frame`'s renderer, so a thumbnail is the
/// bytes that tool writes —
/// with `RecipeOptions.none` (thumbnails ignore Show Ungraded, as an export
/// does). A superseded generation skips its remaining tiles, and its results
/// never land.
final class LookGallery {
    /// None, then the eight in the core's order: the gallery's reading order.
    static let tiles: [LookKind?] = [nil] + LookKind.builtIns.map { Optional($0) }
    static let thumbnailWidth = 256
    static let settle: TimeInterval = 0.3
    #if REELCUT_DEV_TOOLS
    /// A launch default naming a folder: each completed generation N writes
    /// `<folder>/<N>/<tile>.png` and then `<folder>/<N>/manifest.json`.
    static let dumpKey = "RCDevLookGalleryDump"
    #endif

    private(set) var thumbnails: [CGImage?] = Array(repeating: nil, count: tiles.count)
    /// The Imported group's thumbnails, by the LUT's media id.
    private(set) var lutThumbnails: [UInt32: CGImage] = [:]
    /// The attached view; an update from any other is ignored.
    weak var view: LookGalleryView?

    private struct Inputs {
        let project: ReelProject
        let ids: [UInt32]
        let time: Ticks

        func same(_ other: Inputs?) -> Bool {
            guard let other else { return false }
            return project === other.project && ids == other.ids && time == other.time
        }
    }

    /// A generation's cancel flag, read off main between tiles.
    private final class Token {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private weak var document: ProjectDocument?
    private var targets: [ClipSnapshot] = []
    private var open = false
    /// What the last update or poke asked for, what was last scheduled (timer
    /// armed, rendering or rendered), and what the thumbnails show.
    private var latest: Inputs?
    private var scheduled: Inputs?
    private var rendered: Inputs?
    private var timer: Timer?
    private var running: Token?
    private var generation = 0

    /// The one serial queue the generations render on (a one-frame render
    /// queue, beside the eyedropper's and Save Frame's).
    private static let queue = DispatchQueue(label: "com.kgalligan.Reelcut.lookGallery")
    /// Every gallery, weakly, for `playheadMoved(in:)`. Main thread.
    private static let live = NSHashTable<LookGallery>.weakObjects()

    init() {
        Self.live.add(self)
    }

    /// Open, and either asked for inputs it has not shown or still rendering.
    var isPending: Bool {
        guard open, let latest else { return false }
        return !latest.same(rendered) || running != nil
    }

    // MARK: - Updates

    func update(
        from view: LookGalleryView, document: ProjectDocument?, targets: [ClipSnapshot],
        open: Bool
    ) {
        guard view === self.view else { return }
        self.document = document
        self.targets = targets
        self.open = open
        reschedule()
    }

    /// The playhead moved in `document`: each of its live galleries asks again.
    static func playheadMoved(in document: ProjectDocument) {
        for gallery in live.allObjects where gallery.document === document {
            gallery.reschedule()
        }
    }

    private func reschedule() {
        guard open, let document, let first = targets.first else {
            latest = nil
            cancel()
            return
        }
        let inputs = Inputs(
            project: document.editedProject, ids: targets.map(\.id),
            time: Self.time(first: first, playhead: document.playhead))
        latest = inputs
        if inputs.same(scheduled) { return }
        cancel()
        scheduled = inputs
        if inputs.same(rendered) { return }
        let timer = Timer(timeInterval: Self.settle, repeats: false) { [weak self] _ in
            self?.fire()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the timer and supersedes a running generation; what was last
    /// scheduled falls back to what the thumbnails show.
    private func cancel() {
        timer?.invalidate()
        timer = nil
        running?.cancel()
        running = nil
        scheduled = rendered
    }

    // MARK: - A generation

    private func fire() {
        timer = nil
        guard open, let view, view.window != nil, let document, let inputs = scheduled,
              !inputs.same(rendered)
        else {
            // Nothing rendered, so a later update with these inputs must arm again.
            scheduled = rendered
            return
        }
        generation += 1
        let number = generation
        let token = Token()
        running = token
        func trial(_ edit: ReelEdit?) -> ReelProject? {
            switch edit {
            case .applied(let project)?: return project
            case .identity?: return inputs.project
            default: return nil
            }
        }
        let luts = Self.luts(in: inputs.project.snapshot).map(\.id)
        let trials: [ReelProject?] = Self.tiles.map { tile in
            trial(try? inputs.project.applying(Self.op(tile, clips: inputs.ids)))
        } + luts.map { lut in
            trial(try? inputs.project.applying(Self.op(lut: lut, clips: inputs.ids)))
        }
        let urls = document.mediaURLs()
        let graphics = GraphicRegistry.shared.snapshot(for: document.recipeKey)
        var dump: URL?
        #if REELCUT_DEV_TOOLS
        if let folder = UserDefaults.standard.string(forKey: Self.dumpKey), !folder.isEmpty {
            dump = URL(fileURLWithPath: folder).appendingPathComponent(String(number))
        }
        #endif
        Self.queue.async { [weak self] in
            var images: [CGImage?] = []
            for trial in trials {
                if token.isCancelled { return }
                images.append(trial.flatMap {
                    Exporter.renderFrame(
                        project: $0, urls: urls, at: inputs.time, maxWidth: Self.thumbnailWidth,
                        options: .none, graphics: graphics)
                })
            }
            if token.isCancelled { return }
            let names = Self.tiles.map { $0?.rawValue ?? "none" } + luts.map { "lut-\($0)" }
            if let dump { Self.write(images, names, generation: number, inputs: inputs, to: dump) }
            DispatchQueue.main.async {
                guard let self, self.running === token, !token.isCancelled else { return }
                self.running = nil
                self.thumbnails = Array(images.prefix(Self.tiles.count))
                self.lutThumbnails = [:]
                for (lut, image) in zip(luts, images.dropFirst(Self.tiles.count)) {
                    self.lutThumbnails[lut] = image
                }
                self.rendered = inputs
                self.view?.showThumbnails()
            }
        }
    }

    /// The dev dump: the PNGs (the nine, then `lut-<id>`), then the
    /// manifest, last, with `tiles` the names in order.
    private static func write(
        _ images: [CGImage?], _ names: [String], generation: Int, inputs: Inputs, to folder: URL
    ) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var missing: [String] = []
        for (name, image) in zip(names, images) {
            guard let image else {
                missing.append(name)
                continue
            }
            _ = try? FrameWriter.write(
                image, as: .png, to: folder.appendingPathComponent(name + ".png"))
        }
        let manifest: [String: Any] = [
            "generation": generation, "t": inputs.time, "clips": inputs.ids, "missing": missing,
            "tiles": names,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: manifest) {
            try? data.write(to: folder.appendingPathComponent("manifest.json"))
        }
    }

    // MARK: - Pure answers

    /// The clips a look applies to: those that draw and take a grade —
    /// source pixels of their own, or an adjustment clip.
    static func targets(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        clips.filter {
            InspectorTab.hasPixels($0, in: snapshot)
                && (InspectorTab.hasSourcePixels($0, in: snapshot) || InspectorTab.isAdjustment($0))
        }
    }

    /// What a tile or a menu item sends: the kind alone, so each clip keeps
    /// its amount (1 on a clip with none), or `look: null` for None.
    static func op(_ kind: LookKind?, clips: [UInt32]) -> ReelOp {
        .setVideo(clips: clips, patch: VideoPatch(look: .some(kind.map { LookPatch(kind: $0) })))
    }

    /// What a LUT's tile or menu item sends: `{kind: lut, media}`, no amount.
    static func op(lut media: UInt32, clips: [UInt32]) -> ReelOp {
        .setVideo(clips: clips, patch: VideoPatch(look: .some(LookPatch(kind: .lut, media: media))))
    }

    /// The project's `.cube` LUTs, in the media list's order (GR-8 [b]).
    static func luts(in snapshot: ProjectSnapshot) -> [MediaSnapshot] {
        snapshot.media.filter { $0.kind == .lut }
    }

    /// A LUT's tile and item title: its name less a trailing `.cube`.
    static func lutName(_ media: MediaSnapshot) -> String {
        let name = media.name
        return name.lowercased().hasSuffix(".cube") ? String(name.dropLast(5)) : name
    }

    /// The thumbnail time: the playhead inside the first clip, else its first
    /// frame.
    static func time(first: ClipSnapshot, playhead: Ticks) -> Ticks {
        first.start <= playhead && playhead < first.end ? playhead : first.start
    }

    /// `.some(kind)` when every look is that kind, `.some(nil)` when none has
    /// a look, nil when they disagree or there are none.
    static func shared(_ looks: [LookProps?]) -> LookKind?? {
        guard let first = looks.first else { return nil }
        let kind = first?.kind
        return looks.allSatisfy({ $0?.kind == kind }) ? .some(kind) : nil
    }

    /// "Warm 80%" when kind, LUT and amount are shared (a LUT by `names`,
    /// "LUT" when it has none), "none" when no clip has a look, "mixed"
    /// otherwise.
    static func summary(_ looks: [LookProps?], names: [UInt32: String] = [:]) -> String {
        guard let first = looks.first else { return "none" }
        guard looks.allSatisfy({ $0 == first }) else { return "mixed" }
        guard let look = first else { return "none" }
        let name = look.kind == .lut ? look.media.flatMap { names[$0] } ?? "LUT"
            : look.kind.displayName
        return name + String(format: " %.0f%%", look.amount * 100)
    }
}
