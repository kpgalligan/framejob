import AppKit

/// What a press on a band grabbed: its body, or one of its outer 5 pt.
enum ActionDragMode: Equatable {
    case move
    case resize(TimelineEdge)
}

/// The band under the pointer while nothing is pressed — which band, and
/// which grip when it is over one. Both lanes keep one, and `ActionBands.draw`
/// paints its hover arm and grips from it (spec §11 CI-11).
struct ActionBandHover: Equatable {
    let clip: UInt32
    let action: UInt32
    let edge: TimelineEdge?
}

/// Retiming an action by drag (spec §11 CI-11, §6 `set_action`), the ONE
/// session the timeline's lane and the Clip tab's lane both drag with.
///
/// Everything here is CLIP time. Every tick sends start AND duration, frame
/// snapped, as one `set_action`; `ProjectDocument.updateLiveEdit` re-applies
/// it to the handle the gesture started from, so the ops never compound.
///
/// The clamp is a PREVIEW clamp, `TrimSession`'s kind: it mirrors the two
/// walls the core's refusals name — another action (`edit_action.rs`
/// `overlapping_action`, `start < o.end && o.start < end`, which makes a
/// zero-length action at the band's start or end a wall) and the clip's own
/// length — so the band stops where the core would refuse. It does not
/// replace the core's check; a tick the core still refuses is swallowed.
///
/// `originalDuration > 0` is an invariant both callers hold: a zero-length
/// action is never dragged, because `duration: 0` is invalid input to the
/// core (the `err_out` channel), not a refusal.
struct ActionDragSession {
    let clip: UInt32
    let action: UInt32
    let mode: ActionDragMode
    let originalStart: Ticks
    let originalDuration: Ticks
    /// Pointer clip time − `originalStart` at mouse-down, so the band keeps
    /// its place under the pointer instead of jumping to it.
    let grabOffset: Ticks
    /// One frame of the document's grid: the minimum length, the core's own.
    let frame: Ticks
    /// The latest end at or before `originalStart` among the clip's OTHER
    /// actions, or 0.
    let lowerWall: Ticks
    /// The earliest start at or after the original end among the clip's
    /// OTHER actions, or the clip's length floored to the frame grid.
    let upperWall: Ticks
    let fps: Fps

    var start: Ticks
    var duration: Ticks
    /// False until the pointer moves — a press that only selects registers
    /// no undo step.
    var didMove = false

    init(
        clip: ClipSnapshot, action: ActionSnapshot, mode: ActionDragMode, grabAt clipTime: Ticks,
        fps: Fps
    ) {
        self.clip = clip.id
        self.action = action.id
        self.mode = mode
        originalStart = action.start
        originalDuration = action.duration
        grabOffset = clipTime - action.start
        frame = max(fps.frameDuration, 1)
        self.fps = fps
        let end = action.endTime
        var lower: Ticks = 0
        // Floored: an off-grid length would let a clamped edge snap past it.
        // Never below the action's own end, or a move would clamp it left.
        var upper = max(clip.duration - clip.duration % frame, end)
        for other in ActionBands.ordered(clip) where other.id != action.id {
            if other.endTime <= action.start { lower = max(lower, other.endTime) }
            if other.start >= end { upper = min(upper, other.start) }
        }
        lowerWall = max(0, lower)
        upperWall = upper
        start = action.start
        duration = action.duration
    }

    var endTime: Ticks { start + duration }

    var changed: Bool { start != originalStart || duration != originalDuration }

    var op: ReelOp { .setAction(clip: clip, action: action, start: start, duration: duration) }

    var undoName: String { mode == .move ? "Move Action" : "Resize Action" }

    /// `clipTime` is the pointer's clip time. The grabbed edge (both edges,
    /// for a move) travels by the pointer's travel, snapped to the frame
    /// grid, then clamped to the walls and the one-frame minimum.
    mutating func update(clipTime: Ticks) {
        let low = lowerWall, high = upperWall
        let travel = clipTime - (originalStart + grabOffset)
        let originalEnd = originalStart + originalDuration
        switch mode {
        case .move:
            let proposed = ReelTime.snapToFrame(originalStart + travel, fps: fps)
            start = max(min(proposed, high - originalDuration), low)
            duration = originalDuration
        case .resize(.start):
            let proposed = ReelTime.snapToFrame(originalStart + travel, fps: fps)
            start = max(min(proposed, originalEnd - frame), low)
            duration = originalEnd - start
        case .resize(.end):
            let proposed = ReelTime.snapToFrame(originalEnd + travel, fps: fps)
            let end = min(max(proposed, originalStart + frame), high)
            start = originalStart
            duration = end - originalStart
        }
        didMove = true
    }

    /// The HUD's text. A move or a start resize: "new start → new end  +s:ff"
    /// (the start's offset, in seconds and frames); an end resize:
    /// "len +Nf". `base` turns clip time into the time the caller shows.
    func hud(base: Ticks, frames: Bool) -> String {
        if mode == .resize(.end) {
            let delta = (duration - originalDuration) / frame
            return "len \(delta < 0 ? "−" : "+")\(abs(delta))f"
        }
        let from = ReelTime.format(base + start, fps: fps, frames: frames)
        let to = ReelTime.format(base + endTime, fps: fps, frames: frames)
        let offset = start - originalStart
        let magnitude = abs(offset)
        let seconds = magnitude / ReelTime.perSecond
        let rest = (magnitude % ReelTime.perSecond) / frame
        let sign = offset < 0 ? "−" : "+"
        return "\(from) → \(to)  \(sign)\(seconds):\(rest < 10 ? "0" : "")\(rest)"
    }
}

// MARK: - What both lanes draw while a drag is live

extension ActionDragSession {
    static let hudHeight: CGFloat = 16

    private static var hudAttributes: [NSAttributedString.Key: Any] {
        [.font: DS.mono(10), .foregroundColor: DS.textStrong]
    }

    /// The HUD's width for `text`: the text and 4 pt either side.
    static func hudWidth(_ text: String) -> CGFloat {
        ceil(text.size(withAttributes: hudAttributes).width) + 8
    }

    /// The HUD tag with its top-left at `origin`: mono 10 `DS.textStrong` on
    /// `DS.chromeBackground`, a 1 pt `DS.borderStrong` edge, 16 pt tall.
    static func drawHUD(_ text: String, at origin: CGPoint) {
        let box = CGRect(x: origin.x, y: origin.y, width: hudWidth(text), height: hudHeight)
        DS.chromeBackground.setFill()
        box.fill()
        DS.borderStrong.setStroke()
        NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let size = text.size(withAttributes: hudAttributes)
        text.draw(
            at: NSPoint(x: box.minX + 4, y: box.midY - size.height / 2),
            withAttributes: hudAttributes)
    }

    /// The original band: a 1 pt dashed [3, 3] outline in the action ink.
    static func drawGhost(_ band: CGRect) {
        let path = NSBezierPath(rect: band.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.setLineDash([3, 3], count: 2, phase: 0)
        DS.action.setStroke()
        path.stroke()
    }
}
