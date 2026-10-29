// app/Sources/GraphicPreviewPlayer.swift — the Insert ▸ Graphic… sheet's
// looping preview (spec §11 G-45): one graphic module drawn frame after
// frame on a thread of its own, each frame handed to main as a `CGImage`.
//
// **One Foundation `Thread` per player, 8 MiB of stack**
// (`GraphicPrefetch.workerStackBytes`): QuickJS needs the deep stack, which
// a GCD thread does not have. The thread waits on an `NSCondition` while
// there is nothing to play, draws the subject's frame ⌊elapsed × fps⌋ mod
// its length, and waits until the next frame is due — a frame that took
// longer than one frame is followed by the frame due NOW, so a slow graphic
// skips rather than drifts. `stop()` ends the thread; nothing restarts it.
//
// **The thread touches no AppKit and no document.** Everything it reads is
// handed to it in `play`: the module (which holds its library, so the
// document's rescans cannot pull it away), its name and `meta`, and the
// canvas captured at init. A frame is delivered by a main hop, and only
// while its subject is still the newest one and the player has not stopped.
//
// **The picture is `render_graphic`'s**: the ctx is `AgentServer.graphicContext`
// at the module's size (`meta` width and height, else the canvas), with
// `props` `{}` — the schema's defaults — at `GraphicRegistry.previewBudgetMs`,
// composited over the contact sheet's checker
// (`GraphicContactSheet.paintChecker`). A frame that throws, and a module
// that does not compile, is the error card (`LayerRenderers.errorCardText`,
// `paintErrorCard`).

import AppKit

final class GraphicPreviewPlayer {
    enum Subject {
        case module(GraphicModule, name: String, meta: [String: Any])
        case failed(name: String, [GraphicDiagnostic])
    }

    /// What the thread and main share, under `condition`.
    private final class State {
        let condition = NSCondition()
        var subject: Subject?
        var generation = 0
        var stopped = false
        var framesDrawn = 0
        var drewOnMain = false
    }

    private let state = State()
    private let canvas: CanvasSnapshot
    private let onFrame: (CGImage) -> Void
    /// The render thread, once the first `play` has started it.
    private(set) var thread: Thread?

    init(canvas: CanvasSnapshot, onFrame: @escaping (CGImage) -> Void) {
        self.canvas = canvas
        self.onFrame = onFrame
    }

    deinit { stop() }

    /// Plays `subject` from its frame 0, or nothing for nil. Main.
    func play(_ subject: Subject?) {
        state.condition.lock()
        let stopped = state.stopped
        state.subject = subject
        state.generation += 1
        state.condition.broadcast()
        state.condition.unlock()
        guard !stopped, thread == nil else { return }
        let state = self.state
        let canvas = self.canvas
        let made = Thread { [weak self] in
            Self.run(state, canvas) { image, generation in
                DispatchQueue.main.async { self?.deliver(image, generation) }
            }
        }
        made.stackSize = GraphicPrefetch.workerStackBytes
        made.qualityOfService = .userInitiated
        made.name = "framejob.graphic-preview"
        thread = made
        made.start()
    }

    /// Ends the render thread; a later `play` does nothing. Main.
    func stop() {
        state.condition.lock()
        state.stopped = true
        state.subject = nil
        state.condition.broadcast()
        state.condition.unlock()
    }

    /// Frames drawn so far, and whether any was drawn on the main thread
    /// (the probe's read of "off main"). Any thread.
    var drawn: (frames: Int, onMain: Bool) {
        state.condition.lock()
        defer { state.condition.unlock() }
        return (state.framesDrawn, state.drewOnMain)
    }

    /// Main: hands `image` on when it is still the newest subject's.
    private func deliver(_ image: CGImage, _ generation: Int) {
        state.condition.lock()
        let current = !state.stopped && state.generation == generation
        state.condition.unlock()
        if current { onFrame(image) }
    }

    // MARK: - The thread

    private static func run(
        _ state: State, _ canvas: CanvasSnapshot, _ deliver: (CGImage, Int) -> Void
    ) {
        var playing = -1
        var subject: Subject?
        var start = Date()
        var cardShown = false
        while true {
            state.condition.lock()
            while !state.stopped && state.subject == nil { state.condition.wait() }
            if state.stopped {
                state.condition.unlock()
                return
            }
            if state.generation != playing {
                playing = state.generation
                subject = state.subject
                start = Date()
                cardShown = false
            }
            state.condition.unlock()
            guard let current = subject else { continue }

            let fps = max(canvas.fps.double, 1)
            var next = Date().addingTimeInterval(1 / fps)
            switch current {
            case .failed(let name, let diagnostics):
                if !cardShown {
                    let text = LayerRenderers.errorCardText(
                        name: name, frame: nil, diagnostic: diagnostics.first)
                    if let image = card(text, width: canvas.width, height: canvas.height) {
                        record(state)
                        deliver(image, playing)
                    }
                    cardShown = true
                }
                next = .distantFuture
            case .module(let module, let name, let meta):
                let size = Self.size(meta, name, canvas)
                let length = Self.length(meta, name, fps: fps)
                let elapsed = Date().timeIntervalSince(start)
                let absolute = Int((elapsed * fps).rounded(.down))
                let frame = absolute % length
                if let image = Self.frame(
                    module, name: name, frame: frame, length: length, size: size, canvas: canvas)
                {
                    record(state)
                    deliver(image, playing)
                }
                next = start.addingTimeInterval(Double(absolute + 1) / fps)
                if next <= Date() {
                    next = start.addingTimeInterval(
                        (Date().timeIntervalSince(start) * fps).rounded(.up) / fps)
                }
            }
            state.condition.lock()
            if !state.stopped && state.generation == playing {
                _ = state.condition.wait(until: next)
            }
            state.condition.unlock()
        }
    }

    private static func record(_ state: State) {
        state.condition.lock()
        state.framesDrawn += 1
        if Thread.isMainThread { state.drewOnMain = true }
        state.condition.unlock()
    }

    /// The module's size: `meta` width and height, else the canvas's.
    private static func size(
        _ meta: [String: Any], _ name: String, _ canvas: CanvasSnapshot
    ) -> (width: Int, height: Int) {
        let width = try? AgentServer.metaWhole(meta, "width", name, in: AgentServer.sides)
        let height = try? AgentServer.metaWhole(meta, "height", name, in: AgentServer.sides)
        return (width ?? canvas.width, height ?? canvas.height)
    }

    /// `meta.durationInFrames`, else 5 s at `fps`, ceiled.
    private static func length(_ meta: [String: Any], _ name: String, fps: Double) -> Int {
        let declared = try? AgentServer.metaWhole(
            meta, "durationInFrames", name, in: 1...1_000_000)
        return max(declared ?? Int((5 * fps).rounded(.up)), 1)
    }

    /// One frame over the checker, or its error card.
    private static func frame(
        _ module: GraphicModule, name: String, frame: Int, length: Int,
        size: (width: Int, height: Int), canvas: CanvasSnapshot
    ) -> CGImage? {
        let ctx = AgentServer.graphicContext(
            frame: frame, fps: canvas.fps, length: length, width: size.width,
            height: size.height, canvas: canvas)
        let ctxJSON = (try? JSONSerialization.data(withJSONObject: ctx))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        do {
            let drawn = try module.svg(
                frame: frame, propsJSON: "{}", ctxJSON: ctxJSON,
                budgetMs: GraphicRegistry.previewBudgetMs)
            let raster = try module.library.rasterize(
                drawn.svg, width: size.width, height: size.height)
            guard let picture = raster.cgImage(),
                let context = Self.context(size.width, size.height)
            else { return nil }
            GraphicContactSheet.paintChecker(context, width: size.width, height: size.height)
            context.draw(picture, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return context.makeImage()
        } catch {
            let text = LayerRenderers.errorCardText(
                name: name, frame: frame, diagnostic: GraphicDiagnostic.of(error).first)
            return card(text, width: size.width, height: size.height)
        }
    }

    private static func card(_ text: String, width: Int, height: Int) -> CGImage? {
        guard let context = Self.context(width, height) else { return nil }
        LayerRenderers.paintErrorCard(
            text, in: context, bounds: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A premultiplied BGRA sRGB bitmap, the contact sheet's.
    private static func context(_ width: Int, _ height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
    }
}
