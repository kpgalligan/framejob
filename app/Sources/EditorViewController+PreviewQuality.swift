import AVFoundation
import AppKit

/// View ▸ Preview Quality ▸ Full / Half / Quarter (road map 2's phase 8a) — the
/// fraction of the canvas the PLAYER's video composition renders at, and
/// nothing else.
///
/// **What it buys, and what it does not.** The compositor's fragment work is
/// per DESTINATION pixel, so Half quarters it and Quarter divides it by
/// sixteen; the `AVPlayerLayer` then upsamples what it is handed, which is what
/// `.resizeAspect` was already doing to fit the canvas into the pane. Three
/// costs are untouched, and they are named here so nobody later reads a
/// smaller-than-expected saving as a bug:
///
/// · **The shadow passes.** `MetalRenderer.shadowSilhouette` allocates its
///   mask/blur pair at the RECIPE CANVAS's size (`Compositor.swift`), not at
///   the destination's, because the silhouette is drawn in canvas coordinates
///   and blurred with a σ derived from canvas pixels. A shadowed layer costs
///   exactly what it always did at every quality.
/// · **Decoding.** `Playback.finishRebuild` sets
///   `AVPlayerItem.preferredMaximumResolution` to the canvas size, and this
///   setting deliberately leaves it there: it is the DECODE ceiling, and
///   lowering it would degrade the picture by more than the resample the menu
///   promises — a paused Half frame is meant to be the Full frame through one
///   scaler, not a different frame.
/// · **The audio path**, which has no render size at all.
///
/// **It is the player's alone, by construction rather than by testing.** There
/// is exactly one constructor of `AVMutableVideoComposition` in the app
/// (`CompositionBuilder.build`), and it is shared by the preview, both export
/// passes and the offline one-frame render. Rather than give that function an
/// argument every caller would have to pass correctly, `Playback` takes the
/// composition it was handed, `mutableCopy()`s it and overrides `renderSize` on
/// the COPY — `ExportWriter.videoComposition(_:settings:)`'s shape exactly,
/// which does the same to `frameDuration` for the export sheet's frame-rate
/// popup. The export and `render_frame` paths are therefore not merely
/// unchanged but UNREACHABLE from this setting: they never see the copy.
///
/// **No MCP mirror is owed and none may be added.** The parity rule (spec §7.9)
/// is that every user-visible EDIT gets a tool; this edits nothing, and there
/// is nothing an agent could observe if it did — `render_frame` and `export`
/// ignore it by the paragraph above. Phase 7e's export queue is the precedent
/// for a feature that correctly earns none.
enum PreviewQuality: Int, CaseIterable {
    case full = 0
    case half = 1
    case quarter = 2

    /// The submenu's rows, in order. The raw value IS the menu tag, so a
    /// fourth quality goes at the END of this list.
    var title: String {
        switch self {
        case .full: return "Full"
        case .half: return "Half"
        case .quarter: return "Quarter"
        }
    }

    /// What the canvas is divided by — the fraction the row's name promises,
    /// before the aspect rule below has its say.
    var divisor: Int {
        switch self {
        case .full: return 1
        case .half: return 2
        case .quarter: return 4
        }
    }

    /// View state, so `UserDefaults` and not the project (spec §5.2's last
    /// bullet), and pinned by the offscreen harness like every other key the
    /// app reads (`tools/proof/harness/main.swift`).
    static let defaultsKey = "ReelcutPreviewQuality"

    /// What a new `Playback` starts at. An absent key — and a stored number
    /// outside the three cases, which is what a downgrade after a future
    /// fourth row would leave behind — both read as Full, because Full is the
    /// only value that cannot surprise somebody who does not know the setting
    /// exists.
    static func stored() -> PreviewQuality {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: defaultsKey) != nil,
            let quality = PreviewQuality(rawValue: defaults.integer(forKey: defaultsKey))
        else { return .full }
        return quality
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: PreviewQuality.defaultsKey)
    }

    /// The render size for `canvas` at this quality — **always at the canvas's
    /// EXACT aspect ratio**, which is the subtle half of this feature.
    ///
    /// `PreviewCanvasView` maps every mouse point and every drag handle through
    /// `AVPlayerLayer.videoRect` under `.resizeAspect` (`videoRectInView`,
    /// `canvasScale`, spec §4.2 and §11). `videoRect` is the aspect of the
    /// BUFFER the layer is showing, not of the canvas — so a render size whose
    /// aspect differs from the canvas's, even slightly, letterboxes inside the
    /// layer and moves every handle in the frame. Measured, because it is
    /// cheap to measure and expensive to be wrong about: a 640 × 360 timeline
    /// rendered at 501 × 333 comes back with `videoRect` at aspect 1.504505
    /// where the canvas is 1.777778, and the compositor draws the whole canvas
    /// into that box, so the picture is stretched as well.
    ///
    /// So the size must be an exact multiple of the canvas's REDUCED ratio.
    /// With `g = gcd(width, height)`, every exactly-proportional size is
    /// `m · (width/g, height/g)` for some whole `m ≤ g`, and this answers with
    /// `m = ceil(g / divisor)`:
    ///
    /// · when `divisor` divides `g` the answer is exactly the fraction the menu
    ///   row names — 1920 × 1080 (g = 120) gives 960 × 540 at Half and
    ///   480 × 270 at Quarter;
    /// · when it does not, `ceil` rounds toward a COARSER preview, never a
    ///   finer one, so the picture is never worse than the row asked for —
    ///   999 × 666 (g = 333) gives 501 × 334 at Half, which is 0.15 % above
    ///   half and exactly 3∶2;
    /// · and when the canvas cannot be divided at all — 1001 × 667, whose
    ///   dimensions are coprime — `m` clamps to 1 and every row renders at
    ///   FULL size. Falling back to Full is the conservative direction: the
    ///   setting is a performance affordance, and an editor whose handles
    ///   moved when it was switched on would be a defect where a preview that
    ///   is merely no faster is a disappointment.
    ///
    /// The clamp also bounds the answer from below: `m ≥ 1` and `m ≥ g/4`, so
    /// the result is never smaller than a quarter of the canvas and never
    /// degenerate however odd the canvas is.
    ///
    /// **Odd dimensions are fine, and that was measured rather than assumed**,
    /// because the rule above produces them (501 × 334 above): a custom
    /// compositor asked for 501 × 333, 1001 × 667 and 333 × 501 gets a render
    /// context and `newPixelBuffer()`s at exactly those sizes with no error,
    /// and an `AVPlayerLayer` fed a 304 × 171 composition of a 16∶9 source
    /// reports `displayedPixelBuffer` at 304 × 171 and `videoRect` at
    /// 1.777778. Nothing here rounds to even numbers, and nothing should:
    /// the buffers are 32BGRA with no chroma subsampling to make an odd edge
    /// meaningless. (`ExportWriter.encodedSize` rounds down to even for the
    /// opposite reason — an ENCODER's requirement, which this path has not
    /// got.)
    func renderSize(for canvas: CGSize) -> CGSize {
        let width = Int(canvas.width.rounded())
        let height = Int(canvas.height.rounded())
        guard width >= 1, height >= 1 else { return canvas }
        let g = PreviewQuality.greatestCommonDivisor(width, height)
        // ceil(g / divisor), never below 1 — see the doc: coarser, never finer.
        let steps = max(1, (g + divisor - 1) / divisor)
        return CGSize(width: width / g * steps, height: height / g * steps)
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

/// The menu half. The submenu is `AppDelegate+Menus.swift`'s
/// `previewQualityMenu()`, built exactly as `trackHeightMenu()` is — three
/// tagged rows, no key equivalents, the checkmark set by the validator below.
extension EditorViewController {

    /// View ▸ Preview Quality ▸ — the sender's tag is `PreviewQuality`'s raw
    /// value. `setTrackHeight`'s shape, including the beep: a tag outside the
    /// enum can only come from a menu somebody edited without reading this.
    @objc func setPreviewQuality(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag,
            let quality = PreviewQuality(rawValue: tag)
        else {
            NSSound.beep()
            return
        }
        playback.setPreviewQuality(quality)
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// one of mine" — the frozen file's chain is what calls it.
    ///
    /// The item is always enabled: a quality is a property of the preview and
    /// not of the timeline, so there is nothing to refuse on an empty project.
    /// It carries the checkmark for the current row, the way Timeline Track
    /// Height's three do.
    func validatePreviewQualityAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard action == #selector(setPreviewQuality(_:)) else { return nil }
        if let menuItem = item as? NSMenuItem {
            menuItem.state = menuItem.tag == playback.previewQuality.rawValue ? .on : .off
        }
        return true
    }
}
