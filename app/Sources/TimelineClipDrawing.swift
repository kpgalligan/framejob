import AppKit

/// One clip, drawn as ONE OBJECT (the redesign's §3).
///
/// The old bar had no boundary: the filmstrip and the waveform ran edge to
/// edge as two stacked bands and the name sat in a black strip that read as
/// part of the image, so you could not see where one clip ended and the next
/// began. What replaces it is a body — inset 3 pt from the lane, rounded,
/// clipped, with a 1 pt light border — carrying a 16 pt name strip along its
/// top and the media UNDER a wash of the clip's own tint, so a filmstrip reads
/// as a tinted clip rather than as a strip of photographs.
///
/// The alpha washes here are white-over-tint and black-over-tint literals
/// (0.14 border, 0.26 strip, 0.44 waveform, 0.54 wash, 0.62/0.72/0.92 inks).
/// They are deliberately NOT `DS` tokens: each is relative to the clip tint
/// underneath it, which is a fixed ink in both appearances, so a semantic
/// colour would break the contrast the design chose.
///
/// This is an extension of `TimelineContentView` — `TimelineView.swift` is
/// frozen at wiring (app/CLAUDE.md) and this is where the redesign's work
/// went.
extension TimelineContentView {
    /// The clip's body: the lane rect inset 3 pt top and bottom, which is the
    /// gap that makes two lanes read as two rows of objects.
    static func bodyRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX, y: rect.minY + 3, width: rect.width,
            height: max(rect.height - 6, 1))
    }

    /// The body under the name strip — where the filmstrip, the waveform and
    /// the fade handles live.
    ///
    /// The HIT TEST reads this too (`TimelineContentView.hit(at:)` looks for a
    /// fade handle at the audio region's corner): the handles moved down by
    /// the strip's height when the body arrived, and a hit test still measuring
    /// from the lane's top edge would leave them undraggable.
    static func contentRect(_ rect: CGRect) -> CGRect {
        let body = bodyRect(rect)
        return CGRect(
            x: body.minX, y: body.minY + DS.clipHeaderHeight, width: body.width,
            height: max(body.height - DS.clipHeaderHeight, 0))
    }

    /// One clip bar, in paint order: body, media, the selected action's wash,
    /// name strip, action lane, fade handles, grips, border, the transition
    /// zone — which belongs to two clips and so is drawn outside the body's
    /// clip — and the selection ring last, so nothing paints over it.
    func draw(
        clip: ClipSnapshot, in rect: CGRect, track: TrackSnapshot, previous: ClipSnapshot?,
        owner: TimelineView, visible: CGRect
    ) {
        let layout = owner.layout
        let body = Self.bodyRect(rect)
        let dimmed = track.hidden || (!clip.enabled.video && !clip.enabled.audio)
        var tint = ClipKindStyle.tint(for: clip, in: owner.snapshot)
        if dimmed {
            tint = tint.blended(withFraction: 0.5, of: DS.chromeBackground) ?? tint
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(
            roundedRect: body, xRadius: TimelineLayout.clipRadius,
            yRadius: TimelineLayout.clipRadius
        ).addClip()
        tint.setFill()
        body.fill()

        // Everything below the name strip. At the Small text lane (30 pt) this
        // is a sliver, which the design says is correct: a clip there IS its
        // name strip.
        let content = Self.contentRect(rect)

        let hasVideo = owner.hasVideo(clip)
        let hasAudio = owner.hasAudio(clip)
        let regions = Self.regions(in: content, hasVideo: hasVideo, hasAudio: hasAudio)
        if !regions.video.isEmpty {
            drawFilmstrip(clip, in: regions.video, tint: tint, owner: owner, visible: visible)
        }
        if !regions.audio.isEmpty {
            // Silent is what the core mixes as silent (`audio.rs`'s
            // `silenced`): muted, or some OTHER track in the container soloed.
            // The header's M stays unlit under a solo — it shows the switch —
            // but the waveform shows the mix. Nested clips are never drawn
            // here, so the container is always the timeline's own track set.
            let silencedBySolo = owner.snapshot.tracks.contains { $0.solo } && !track.solo
            let muted = clip.audioProps.muted || track.muted || silencedBySolo
            drawWaveform(clip, in: regions.audio, owner: owner, visible: visible, muted: muted)
        }
        drawActionWash(clip, body: body, owner: owner)
        drawNameStrip(clip, in: body, owner: owner)
        drawActionBands(clip, rect: rect, owner: owner)

        if hasAudio, regions.audio.height >= TimelineLayout.fadeHandle + 2 {
            for edge in [TimelineEdge.start, TimelineEdge.end] {
                let handle = Self.fadeRect(clip, edge: edge, audio: regions.audio, layout: layout)
                NSColor.white.withAlphaComponent(0.7).setFill()
                handle.fill()
            }
        }

        // Trim grips are a DRAWING, not a hit target: `TimelineLayout.edgeGrab`
        // stays 7 pt, so making these 6 pt bars the grab zone would shrink an
        // affordance that already works. They appear on the selected clip only
        // so an unselected timeline stays quiet.
        //
        // The threshold is the HIT TEST's, not the grip's own width: `hit(at:)`
        // and `resetCursorRects` both give up on a bar narrower than
        // `edgeGrab * 3` (21 pt), and a grip drawn on a 19 pt clip would be an
        // affordance that cannot be grabbed. `body.width` is `rect.width` —
        // `bodyRect` insets only top and bottom — so this is the same number
        // the hit test measures. A LOCKED track is excluded for the same
        // reason: `hit(at:)` returns `.clip` there before it ever reaches the
        // width test, so a grip drawn on one could only lie.
        if owner.selection.contains(clip.id), !track.locked,
           body.width > TimelineLayout.edgeGrab * 3 {
            NSColor.white.withAlphaComponent(0.38).setFill()
            NSRect(
                x: body.minX, y: body.minY, width: DS.trimGripWidth, height: body.height
            ).fill()
            NSRect(
                x: body.maxX - DS.trimGripWidth, y: body.minY, width: DS.trimGripWidth,
                height: body.height
            ).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        let border = NSBezierPath(
            roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: TimelineLayout.clipRadius,
            yRadius: TimelineLayout.clipRadius)
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.14).setStroke()
        border.stroke()

        // The transition goes down BEFORE the ring. Its zone starts at
        // `clip.start`, which is the body's own left edge, so a hatch drawn
        // after the ring paints white 0.26 and a solid white edge straight over
        // the coral — the selected clip would lose its left side exactly where
        // it overlaps its predecessor.
        drawTransition(clip, previous: previous, in: body, layout: layout)

        if owner.selection.contains(clip.id) {
            DS.playhead.setStroke()
            let outline = NSBezierPath(
                roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: TimelineLayout.clipRadius,
                yRadius: TimelineLayout.clipRadius)
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    // MARK: - Name strip

    /// The 16 pt strip along the body's top: a black wash over the tint, the
    /// kind symbol, the name truncated with an ellipsis, and — when the clip
    /// carries a label — a 6 pt dot in the label's colour at the right end.
    /// The kind symbol is the point of it — a clip's kind used to be
    /// invisible. The label is a DOT and never the tint: the tint says what a
    /// clip IS (spec §4.4's six inks, which the washes below are calibrated
    /// for), and a label is something the user said about it.
    private func drawNameStrip(_ clip: ClipSnapshot, in body: CGRect, owner: TimelineView) {
        let strip = CGRect(
            x: body.minX, y: body.minY, width: body.width,
            height: min(DS.clipHeaderHeight, body.height))
        NSColor.black.withAlphaComponent(0.26).setFill()
        strip.fill()
        // `hasPixels` is the test the Motion section and Clip ▸ Motion gate
        // on: a detached audio twin clones the video props, and its strip
        // must not claim a motion it never shows.
        let motion = InspectorTab.hasPixels(clip, in: owner.snapshot) ? clip.videoProps.motion : nil
        if let motion = motion {
            drawMotionWedges(motion, clip: clip, strip: strip, body: body)
        }

        let padding: CGFloat = 6
        var x = strip.minX + padding
        var nameEnd = strip.maxX - padding
        let symbol = ClipKindStyle.symbol(for: clip, in: owner.snapshot)
        let iconBox = CGRect(x: x, y: strip.minY, width: 11, height: strip.height)
        if iconBox.maxX <= strip.maxX - padding {
            TimelineDraw.symbol(
                symbol.name, fallback: symbol.fallback, in: iconBox,
                tint: NSColor.white.withAlphaComponent(0.62))
            x = iconBox.maxX + 5
        }
        // Guarded like the icon: a strip too narrow for both keeps the kind
        // and drops the dot, rather than painting one over its own edge. The
        // name gives up the dot's 6 pt plus the icon's 5 pt gap for it. Any
        // non-empty label draws — an unknown name in the neutral ink — so a
        // project from a newer build still shows WHERE its labels are.
        // Where the dot's own left edge landed, or nil when no dot drew. The
        // glyph below needs THAT, and `nameEnd` is not it: `nameEnd` is where
        // the NAME stops, which three different branches move.
        var dotLeft: CGFloat?
        if let label = clip.label, !label.isEmpty {
            let dot = CGRect(
                x: strip.maxX - padding - 6, y: strip.midY - 3, width: 6, height: 6)
            if dot.minX >= x {
                ClipLabel.color(named: label).withAlphaComponent(0.92).setFill()
                NSBezierPath(ovalIn: dot).fill()
                nameEnd = dot.minX - 5
                dotLeft = dot.minX
            }
        }
        // The during glyph: an 11 pt box (the kind icon's) at the right end,
        // 4 pt left of the label dot when one drew, guarded like the dot.
        if motion?.during != nil {
            let right = dotLeft.map { $0 - 4 } ?? (strip.maxX - padding)
            let glyph = CGRect(x: right - 11, y: strip.minY, width: 11, height: strip.height)
            if glyph.minX >= x {
                TimelineDraw.symbol(
                    "waveform.path", fallback: "~", in: glyph,
                    tint: NSColor.white.withAlphaComponent(0.62))
                nameEnd = glyph.minX - 5
            }
        }
        TimelineDraw.truncated(
            owner.snapshot.name(of: clip),
            in: CGRect(x: x, y: strip.minY, width: max(nameEnd - x, 0), height: strip.height),
            font: DS.sans(10, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.92))
    }

    /// The in and out wedges along the strip's bottom edge: a triangle as
    /// long as the preset's duration at this zoom, rising to 4 pt at its
    /// inner end, so the ramp reads as "how far in the motion runs". Base
    /// props, because motion ignores actions. A tent simply overlaps — the
    /// core resolves it, and no tent arithmetic belongs here.
    private func drawMotionWedges(
        _ motion: MotionProps, clip: ClipSnapshot, strip: CGRect, body: CGRect
    ) {
        let perTick = body.width / CGFloat(max(clip.duration, 1))
        // 2 pt minimum so a short preset still shows; never wider than the clip.
        func width(_ edge: MotionEdge) -> CGFloat {
            min(max(CGFloat(edge.duration) * perTick, 2), body.width)
        }
        // 0.55 white: a strip literal, a shade under the icon's 0.62.
        NSColor.white.withAlphaComponent(0.55).setFill()
        if let edge = motion.inEdge, edge.isActive {
            let w = width(edge)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: strip.minX, y: strip.maxY))
            path.line(to: CGPoint(x: strip.minX + w, y: strip.maxY))
            path.line(to: CGPoint(x: strip.minX + w, y: strip.maxY - 4))
            path.close()
            path.fill()
        }
        if let edge = motion.out, edge.isActive {
            let w = width(edge)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: strip.maxX, y: strip.maxY))
            path.line(to: CGPoint(x: strip.maxX - w, y: strip.maxY))
            path.line(to: CGPoint(x: strip.maxX - w, y: strip.maxY - 4))
            path.close()
            path.fill()
        }
    }

    // There is deliberately NO second line under the name strip for a text or
    // shape clip. The design's mock shows one ("Title card" over "Nightfall"),
    // but a clip's own `name` (format version 3) is optional and most have
    // none: `ProjectSnapshot.name(of:)` then falls back to `clip.fallbackName`,
    // which for a text clip IS the text and for a shape clip IS the kind's
    // display name. Drawing it again under the strip made every text clip
    // stutter its own content. The strip carries whichever name the clip has.

    // MARK: - Transition

    /// The overlap with the previous clip, drawn above both bars and so
    /// outside the body's clip. 45° hatch on the design's 3 pt line and 7 pt
    /// period (`hatchSpacing` below explains the √2) with a solid edge down
    /// each side, which is what makes the zone read as a span rather than as
    /// texture.
    ///
    /// `TimelineDraw.hatch` gained a defaulted line width for this — the
    /// locked-track hatch that shares it keeps its hairline — but it draws no
    /// edges, so those two are here.
    private func drawTransition(
        _ clip: ClipSnapshot, previous: ClipSnapshot?, in body: CGRect, layout: TimelineLayout
    ) {
        guard let transition = clip.transitionIn, let previous = previous,
              previous.end > clip.start
        else { return }
        let zone = CGRect(
            x: layout.x(for: clip.start), y: body.minY,
            width: max(layout.width(of: previous.end - clip.start), 2), height: body.height)
        TimelineDraw.hatch(
            zone, color: NSColor.white.withAlphaComponent(0.26), spacing: Self.hatchSpacing,
            lineWidth: 3)
        NSColor.white.withAlphaComponent(0.4).setFill()
        NSRect(x: zone.minX, y: zone.minY, width: 1, height: zone.height).fill()
        NSRect(x: zone.maxX - 1, y: zone.minY, width: 1, height: zone.height).fill()

        // The kind is drawn only when the whole word fits between the two
        // edges with a little air. `TimelineDraw.label` CLIPS, so a 0.48 s
        // cross dissolve used to read "s Diss" — a middle of a word, which
        // says less than nothing. The Transition section of the inspector
        // names the kind, so a zone too short to hold it loses no information.
        let font = DS.sans(9)
        let name = transition.kind.displayName
        let width = name.size(withAttributes: [.font: font]).width
        guard width + 8 <= zone.width else { return }
        TimelineDraw.label(
            name,
            in: CGRect(x: zone.minX, y: zone.maxY - 13, width: zone.width, height: 12),
            font: font, color: NSColor.white.withAlphaComponent(0.85), centered: true)
    }

    /// The hatch spacing that gives the design's 7 pt PERPENDICULAR period.
    ///
    /// `TimelineDraw.hatch` steps each line's origin along X while drawing at
    /// 45°, so the gap measured across the lines is `spacing / √2` — passing
    /// the design's 7 straight through gave a 4.95 pt period, and a 3 pt line
    /// on that is 61 % coverage where the design asks for 43 %. The scaling
    /// lives at THIS call site rather than in `hatch`, because the locked-track
    /// hatch shares that helper and its hairline lattice is what it should be.
    private static let hatchSpacing: CGFloat = 7 * 2.0.squareRoot()

    // MARK: - Media

    /// Thumbnails at the design's fixed 34 pt tile, then the clip's tint
    /// washed back over them at 54 %.
    ///
    /// The tile used to be the region's aspect-derived width, which made the
    /// strip's rhythm depend on the lane height; a fixed tile means the image
    /// no longer fits the box, so each one is drawn to FILL 34 pt and cropped
    /// rather than letterboxed.
    func drawFilmstrip(
        _ clip: ClipSnapshot, in rect: CGRect, tint: NSColor, owner: TimelineView, visible: CGRect
    ) {
        guard rect.height >= 10, rect.width > 0 else { return }
        if let directory = owner.cacheDirectory, let media = owner.snapshot.media(for: clip),
           media.width > 0, media.height > 0 {
            let tile = DS.filmstripThumb
            let skipped = max(((visible.minX - rect.minX) / tile).rounded(.down), 0)
            var x = rect.minX + skipped * tile
            let limit = min(rect.maxX, visible.maxX)
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            NSGraphicsContext.current?.cgContext.setAlpha(0.72)
            while x < limit {
                let time = max(owner.layout.time(atX: x + tile / 2), clip.start)
                let source = TimelineView.sourceTime(of: clip, in: media, at: time)
                let index = Int(max(source, 0) / ReelTime.perSecond)
                let image = owner.caches.thumbnail(
                    media: media.id, index: index, in: directory)
                if let image = image {
                    Self.fill(
                        image, in: CGRect(x: x, y: rect.minY, width: tile, height: rect.height))
                }
                x += tile
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        tint.withAlphaComponent(0.54).setFill()
        rect.fill()
    }

    /// A thumbnail scaled to COVER `rect` and cropped to it, which is what a
    /// fixed tile width needs — `TimelineDraw.image` stretches to fit and
    /// would squash every frame at the small lane sizes.
    private static func fill(_ image: CGImage, in rect: CGRect) {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = max(rect.width / width, rect.height / height)
        let target = CGRect(
            x: rect.midX - width * scale / 2, y: rect.midY - height * scale / 2,
            width: width * scale, height: height * scale)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        TimelineDraw.image(image, in: target)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// The cached peaks (100 buckets per source second) as a column plot,
    /// symmetric about the REGION's centre line and filled at 44 % white.
    /// Muted draws at 40 % of that (spec §4.4).
    func drawWaveform(
        _ clip: ClipSnapshot, in rect: CGRect, owner: TimelineView, visible: CGRect, muted: Bool
    ) {
        guard rect.height >= 8, let directory = owner.cacheDirectory,
              let media = owner.snapshot.media(for: clip),
              let peaks = owner.caches.peaks(media: media.id, in: directory), !peaks.isEmpty
        else { return }
        let alpha: CGFloat = muted ? 0.4 : 1
        NSColor.white.withAlphaComponent(0.44 * alpha).setFill()
        let midY = rect.midY
        let half = rect.height / 2 - 1
        let from = max(rect.minX, visible.minX)
        let to = min(rect.maxX, visible.maxX)
        var x = from.rounded(.down)
        let bucketsPerSecond = Double(MediaImporter.peakBucketsPerSecond)
        while x < to {
            let time = max(owner.layout.time(atX: x), clip.start)
            let source = TimelineView.sourceTime(of: clip, in: media, at: time)
            let bucket = Int(
                (Double(max(source, 0)) / Double(ReelTime.perSecond) * bucketsPerSecond)
                    .rounded(.down))
            guard peaks.indices.contains(bucket) else {
                x += 1
                continue
            }
            let amplitude = CGFloat(min(max(peaks[bucket], 0), 1)) * half
            NSRect(x: x, y: midY - amplitude, width: 1, height: max(amplitude * 2, 1)).fill()
            x += 1
        }
    }
}

// MARK: - Truncating label

extension TimelineDraw {
    /// A one-line label that ends in an ellipsis instead of being cut off.
    ///
    /// `TimelineDraw.label` clips, which is right for a ruler tick that either
    /// fits or does not; a clip name has to say "there is more" — a strip
    /// reading "IMG_96" and one reading "IMG_96…" are different claims. Text
    /// is centred vertically in `rect` so a call site can pass the strip's
    /// whole height.
    static func truncated(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        guard rect.width > 4, rect.height > 4, !text.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ]
        // The box is the LINE's natural height, centred on `rect`, never
        // `rect` itself: `draw(in:)` drops a line that does not fit its box
        // outright, so clamping the height to a 13 pt strip would silently
        // lose the name instead of shortening it.
        let height = ceil(text.size(withAttributes: attributes).height)
        text.draw(
            in: CGRect(
                x: rect.minX, y: (rect.midY - height / 2).rounded(), width: rect.width,
                height: height),
            withAttributes: attributes)
    }
}
