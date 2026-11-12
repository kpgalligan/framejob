import AVFoundation

extension Exporter {
    // MARK: - Offline single frame (spec §7.9's `render_frame`)

    /// One composed frame, rendered without a player — the agent's
    /// verification hook, and the M2 GIF/APNG writer's frame source.
    ///
    /// It goes through the SAME composition and video composition an export
    /// does, which is the entire value of it: what this returns is what the
    /// file will contain at `t`, not a second opinion about it. Both time
    /// tolerances are `.zero` so the frame is the one asked for rather than
    /// the nearest sync sample.
    ///
    /// Synchronous and disk-touching (it opens asset tracks and decodes):
    /// call it OFF the main thread. Returns nil rather than throwing for
    /// every failure — no plan, nothing to compose, a time past the end.
    ///
    /// **A timeline of nothing but text, shapes and images renders here.**
    /// This paragraph used to say the opposite — that such a project has no
    /// composition tracks, that `AVAssetImageGenerator` cannot run over a
    /// composition with none, and that it therefore rendered in the preview
    /// and not here. That was true once and stopped being true two milestones
    /// ago, while the sentence stayed: `CompositionBuilder.addPlaceholderIfNeeded`
    /// gives exactly that project an empty video track, whose one job is to
    /// make every frame time exist for the generator to ask about, and the
    /// recipe draws the picture as it always did. The guard below says the
    /// same thing in code four lines from here. Only a genuinely EMPTY
    /// timeline — `plan.duration == 0` — is refused.
    ///
    /// **`options` is a PARAMETER and not something read off the project**
    /// (`RecipeOptions`, spec §7.3), and that is load-bearing rather than
    /// belt-and-braces: this method registers a `RecipeSource` key of its
    /// OWN, so an option published against any other key — an export's, a
    /// document's — cannot reach the frames it renders. GIF and APNG never
    /// go through `ExportWriter` at all; `ImageSequenceWriter.append` calls
    /// this once per frame, and an option that travelled only on the export's
    /// key would leave every one of those files silently un-burnt.
    ///
    /// It defaults to `.none`, which is the right answer for a caller that
    /// wants the PICTURE rather than a deliverable: the canvas eyedropper
    /// samples what the canvas shows, and Save Frame grabs the frame. The
    /// callers that pass something are the export sheet, the `export` tool
    /// and `render_frame` — the last one both for agent parity and because it
    /// is the only way a proof script can photograph a burn-in at all.
    ///
    /// `graphics` is pinned on the frame's own key, as `export` pins it on
    /// its own; nil draws every graphic's slate, and the pin is marked deep when
    /// the reader reads the frame and `keepsDepth` (PR-15), as the key itself is for a
    /// gradient shape (PR-16) and a matte's coverage (PR-19). `keepsDepth` is the caller's
    /// format (`carriesDepth`): when true and `DeepVideoFrame.reads` the frame (a graphic,
    /// PR-20, a deep still, PR-9, or a deep VP9 track, PR-12), `DeepStillFrame.read`'s reader
    /// reads it, and it re-reads a frame the generator answers 8-bit while it shows a deep
    /// source (PR-14), or deep while it draws a gradient shape or a matte (PR-16, PR-19).
    static func renderFrame(
        project: ReelProject, urls: [UInt32: URL], at t: Ticks, maxWidth: Int?,
        options: RecipeOptions = .none, graphics: GraphicSet? = nil, keepsDepth: Bool = false
    ) -> CGImage? {
        renderFrameReported(
            project: project, urls: urls, at: t, maxWidth: maxWidth, options: options,
            graphics: graphics, keepsDepth: keepsDepth
        ).image
    }

    /// `renderFrame`, with what the frame's graphics reported while it was
    /// drawn — read off the key's pin before it is dropped — and each cursor
    /// file it could not draw. It waits first for the cursor tracks the
    /// recipe at `t` names (spec §11 CU-37 (b), `waitForCursors`), then, when
    /// `cutoutWait` is positive (`render_frame` and Save Frame pass
    /// `frameCutoutWait`), up to that long for the person masks it draws
    /// (spec §11 CO-22 (f), `waitForFrameMasks`), and reports in `uncut` the
    /// clips drawn without theirs.
    static func renderFrameReported(
        project: ReelProject, urls: [UInt32: URL], at t: Ticks, maxWidth: Int?,
        options: RecipeOptions, graphics: GraphicSet?, keepsDepth: Bool = false,
        cutoutWait: TimeInterval = 0
    ) -> RenderedFrame {
        // No videoTracks is NOT a refusal: CompositionBuilder gives a
        // timeline of nothing but text, shapes and images a placeholder track
        // so the recipe can still drive every frame. Only a genuinely empty
        // timeline has nothing to render.
        guard let plan = project.plan, plan.duration > 0 else {
            return RenderedFrame(image: nil, graphics: [], cursorWarnings: [], uncut: [])
        }
        let key = RecipeSource.shared.register()
        defer { RecipeSource.shared.unregister(key) }
        RecipeSource.shared.set(project, for: key)
        if let graphics = graphics { GraphicRegistry.shared.pin(graphics, for: key) }
        // Runs after the `return` below has read the reports.
        defer { GraphicRegistry.shared.unpin(key) }
        // Before the build, not after: the generator may ask for a frame the
        // moment the composition exists, and a frame composed against this
        // key's defaults would be one frame short of what was asked for.
        RecipeSource.shared.setOptions(options, for: key)
        // Every caller is off main (`render_frame`, Save Frame, the eyedropper,
        // image sequences, look thumbnails); nothing here cancels the wait, so
        // `.cancelled`, its only throw, cannot happen and `try?`'s `[]` is never
        // taken.
        let cursorWarnings = (try? waitForCursors(
            project: project, key: key, at: max(0, t), options: options, cancelled: { false })) ?? []
        let uncut = cutoutWait > 0
            ? waitForFrameMasks(
                project: project, urls: urls, key: key, at: max(0, t), options: options,
                limit: cutoutWait)
            : []

        let built: BuiltComposition
        do {
            built = try CompositionBuilder.build(
                plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key)
        } catch {
            return RenderedFrame(
                image: nil, graphics: GraphicRegistry.shared.reports(for: key),
                cursorWarnings: cursorWarnings, uncut: uncut)
        }
        let reads = DeepVideoFrame.reads(
            project, built, urls: urls, at: t, options: options, keepsDepth: keepsDepth)
        // Spec §11 PR-15, PR-20: a frame the reader reads, in a format that keeps depth, draws
        // its graphics deep (a frame that draws one is always read here); every other frame
        // keeps the dithered 8-bit raster.
        if reads {
            // PR-16: a gradient shape is drawn deep too, whether or not a graphic set is pinned.
            if keepsDepth { RecipeSource.shared.markDeep(key) }
            if keepsDepth { GraphicRegistry.shared.markDeep(key) }
            return RenderedFrame(
                image: DeepStillFrame.read(built, at: t, maxWidth: maxWidth),
                graphics: GraphicRegistry.shared.reports(for: key), cursorWarnings: cursorWarnings,
                uncut: uncut)
        }

        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The video composition already applies every source's orientation
        // (`CompositionBuilder.orientationCode`), so asking the generator to
        // apply a preferred transform on top would turn the frame twice.
        generator.appliesPreferredTrackTransform = false
        if let maxWidth = maxWidth, maxWidth > 0 {
            generator.maximumSize = scaledSize(built.videoComposition.renderSize, to: maxWidth)
        }
        var image = try? generator.copyCGImage(
            at: CompositionBuilder.time(max(0, t)), actualTime: nil)
        // The generator answered deep with the frame's gradient shapes drawn at 8 bits and its
        // mattes resolved at 8 bits: the reader reads it again with them deep (PR-16, PR-19). A
        // frame with neither is not read twice, and a frame that draws a graphic never gets
        // here when `keepsDepth` (PR-20: `reads` took it).
        if keepsDepth, let first = image, first.bitsPerComponent > 8 {
            let gradient =
                drawsGradientShape(project, at: t, options: options)
            let matte = drawsMatte(project, at: t, options: options)
            if gradient || matte {
                RecipeSource.shared.markDeep(key)
                image = DeepStillFrame.read(built, at: t, maxWidth: maxWidth) ?? image
            }
        }
        // The generator's depth follows the lowest track that has video, so a
        // deep clip above an 8-bit one comes back 8-bit (spec §11 PR-14). A
        // frame already deep never asks, so HEVC or ProRes alone stays byte for
        // byte; a read that fails keeps the generator's image.
        if keepsDepth, let shallow = image, shallow.bitsPerComponent <= 8,
            DeepVideoFrame.showsDeepSource(project, built, at: t, options: options)
        {
            RecipeSource.shared.markDeep(key)
            image = DeepStillFrame.read(built, at: t, maxWidth: maxWidth) ?? image
        }
        return RenderedFrame(
            image: image, graphics: GraphicRegistry.shared.reports(for: key),
            cursorWarnings: cursorWarnings, uncut: uncut)
    }

    /// `size` capped to `maxWidth`, aspect kept, never upscaled and never
    /// zero in either axis.
    static func scaledSize(_ size: CGSize, to maxWidth: Int) -> CGSize {
        guard size.width >= 1, size.height >= 1 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }
        guard CGFloat(maxWidth) < size.width else { return size }
        let scale = CGFloat(maxWidth) / size.width
        return CGSize(width: CGFloat(maxWidth), height: max(1, (size.height * scale).rounded()))
    }
}
