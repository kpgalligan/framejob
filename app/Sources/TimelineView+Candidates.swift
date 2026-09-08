import AppKit

/// The candidate-span wash Remove Silences puts on the timeline while its
/// sheet is up (road map 2 phase 3a) — the bodies of the two one-line hooks
/// `TimelineView.swift` carries, in the shape `TimelineView+Rename.swift` and
/// `EditorViewController+Edge.swift`'s `extension TimelineView` set.
///
/// **Why a hook and not an overlay view.** The other sanctioned route for an
/// extension that needs to draw is a subview found by kind, the way
/// `EditorViewController+Eyedropper.swift` finds its overlay on the canvas.
/// It cannot work here. `TimelineRulerView.draw` opens by filling its whole
/// bounds with `DS.chromeBackground`, so an overlay positioned BELOW the
/// ruler is painted straight over and one positioned above it hides the
/// ticks, the marker flags and the playhead's head. In the lanes it would be
/// wrong the other way: the in/out wash is drawn before the clip loop, i.e.
/// UNDER the clips, and a subview always paints over its superview's own
/// `draw`. Two one-line calls inside the frozen `draw`s are the only way to
/// land in the same two places the in/out range lands, which is what "in the
/// in/out style" means.
///
/// The ink is `DS.timelineCandidateShade` — the range's coral at roughly
/// double the wash — because a candidate span and an in/out range can overlap
/// and one constant would make them indistinguishable.

// MARK: - The lanes

extension TimelineContentView {
    /// Called from `draw(_:)` immediately after the in/out wash and before the
    /// clip loop, so the shading sits UNDER the clips exactly as the range's
    /// does. Both views draw in content coordinates, so a span's x comes
    /// straight from the layout with no scroll offset of its own.
    func drawCandidateSpans(owner: TimelineView, layout: TimelineLayout) {
        let spans = owner.candidateSpans
        guard !spans.isEmpty, layout.trackCount > 0 else { return }
        DS.timelineCandidateShade.setFill()
        for span in spans where span.end > span.start {
            NSRect(
                x: layout.x(for: span.start), y: layout.lanesTop,
                width: layout.width(of: span.end - span.start),
                height: layout.lanesHeight
            ).fill()
        }
    }
}

// MARK: - The ruler

extension TimelineRulerView {
    /// Called from `draw(_:)` after the band's own opaque fill and its in/out
    /// wash, and before the ticks — the same slot, for the same reason: the
    /// ticks and the marker flags have to stay readable through it.
    func drawCandidateSpans(owner: TimelineView, layout: TimelineLayout) {
        let spans = owner.candidateSpans
        guard !spans.isEmpty else { return }
        DS.timelineCandidateShade.setFill()
        for span in spans where span.end > span.start {
            NSRect(
                x: layout.x(for: span.start), y: 0,
                width: layout.width(of: span.end - span.start), height: bounds.height
            ).fill()
        }
    }
}
