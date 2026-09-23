import AppKit

/// Design tokens. Chrome colors come from the semantic AppKit system palette
/// so the app matches the OS in both appearances — an image editor's chrome
/// should stay neutral. The only fixed colors are the brand mark (welcome
/// motif, selection marquee) and the transparency checkerboard; fonts remain
/// the vendored Balopy faces. The chrome is square: every chrome radius token
/// below is 0, so controls, rows, fields and panels draw with sharp corners.
/// A clip bar is content, not chrome, and keeps `clipRadius`.
enum DS {
    // MARK: - Chrome colors (system palette)

    static var chromeBackground: NSColor { .windowBackgroundColor }
    static var hoverFill: NSColor { .quaternaryLabelColor }
    static var selectionFill: NSColor { .controlAccentColor.withAlphaComponent(0.22) }
    static var border: NSColor { .separatorColor }
    static var borderStrong: NSColor { .tertiaryLabelColor }
    /// The crisp offset block behind sticker controls.
    static var stickerShadow: NSColor { .shadowColor }
    static var textStrong: NSColor { .labelColor }
    static var textMuted: NSColor { .secondaryLabelColor }
    static var textFaint: NSColor { .tertiaryLabelColor }
    static var accent: NSColor { .controlAccentColor }
    static var onAccent: NSColor { .white }
    static var canvasVoid: NSColor { .underPageBackgroundColor }

    // MARK: - Fixed colors

    /// Brand inks — used only by the welcome motif and the marquee.
    static let forest = NSColor(srgbRed: 0x1F / 255, green: 0x85 / 255, blue: 0x64 / 255, alpha: 1)
    static let butter = NSColor(srgbRed: 0xF2 / 255, green: 0xC1 / 255, blue: 0x4E / 255, alpha: 1)
    static let coral = NSColor(srgbRed: 0xF4 / 255, green: 0x65 / 255, blue: 0x3F / 255, alpha: 1)

    /// The selection marquee — the app's one accent-colored canvas element.
    static var marquee: NSColor { coral.withAlphaComponent(0.9) }

    /// Neutral checkerboard for transparency, constant across appearances so
    /// transparent pixels always read against the same reference.
    static let checkerA = NSColor(white: 0.886, alpha: 1)
    static let checkerB = NSColor(white: 0.941, alpha: 1)

    /// The Generate Captions sheet's preview plate: a stand-in for footage,
    /// the same in both appearances, so a white caption always reads.
    static let captionPreviewPlate = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)

    // MARK: - Timeline (spec §4.4)

    /// Clip tints by source kind — "video slate, audio green, still violet,
    /// text amber, shape teal, nest grey". Fixed inks rather than semantic
    /// ones: a clip's kind must read the same in both appearances, and the
    /// bars carry white-ish labels either way. `ClipKindStyle` is
    /// the only mapping from a clip to one of these.
    static let clipVideo = NSColor(
        srgbRed: 0x3E / 255, green: 0x50 / 255, blue: 0x63 / 255, alpha: 1)
    static let clipAudio = NSColor(
        srgbRed: 0x2C / 255, green: 0x7A / 255, blue: 0x58 / 255, alpha: 1)
    static let clipStill = NSColor(
        srgbRed: 0x6A / 255, green: 0x4B / 255, blue: 0x93 / 255, alpha: 1)
    static let clipText = NSColor(
        srgbRed: 0xB1 / 255, green: 0x7C / 255, blue: 0x1E / 255, alpha: 1)
    static let clipShape = NSColor(
        srgbRed: 0x24 / 255, green: 0x76 / 255, blue: 0x86 / 255, alpha: 1)
    static let clipNest = NSColor(
        srgbRed: 0x55 / 255, green: 0x59 / 255, blue: 0x5F / 255, alpha: 1)

    /// The empty lane and the alternating band that separates two tracks.
    static var timelineLane: NSColor { .underPageBackgroundColor }
    static var timelineLaneAlt: NSColor { .controlBackgroundColor }
    /// The playhead, its ruler head, and the selection outline — one ink, so
    /// "where you are" and "what you picked" read as the same accent.
    static var playhead: NSColor { coral }
    /// The snap guide drawn while a drag is locked to a candidate.
    static var snapGuide: NSColor { butter }
    /// The in/out range wash over the ruler and the lanes.
    static var timelineRangeShade: NSColor { coral.withAlphaComponent(0.12) }
    /// Remove Silences' candidate spans, shaded the same way while the sheet
    /// is up. The same ink at roughly double the wash, because an in/out range
    /// and a candidate span can overlap: one constant for both would leave the
    /// user looking at a single tint with no way to tell which is which, or
    /// how many spans are under it.
    static var timelineCandidateShade: NSColor { coral.withAlphaComponent(0.24) }

    /// The timeline bar's output level meter (`LevelMeterView`). The fill is
    /// the clip palette's audio green — the app's one "this is sound" ink, so
    /// a meter reads as the same family as the clips it is summing — over a
    /// neutral trough that has to sit quietly in both appearances, which is
    /// why the trough is semantic and the fill is not.
    ///
    /// Coral is load-bearing (`playhead`, `marquee`, the brand mark) so the
    /// meter spends it on the ONE thing in a meter that means stop: the clip
    /// cell. There is deliberately no amber step — a green/amber/red ladder
    /// would be three more fixed inks with no precedent in this palette, and
    /// the number that matters is the over.
    static var meterFill: NSColor { clipAudio }
    static var meterTrough: NSColor { .quaternaryLabelColor }
    static var meterClip: NSColor { coral }

    // MARK: - Type

    /// Source Sans 3 for UI text; system face when the vendored font is
    /// missing. Variable-font named instances resolve per weight.
    static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name: String
        switch weight {
        case .semibold: name = "SourceSans3-SemiBold"
        case .bold: name = "SourceSans3-Bold"
        default: name = "SourceSans3-Regular"
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// IBM Plex Mono for machine-produced numbers.
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .regular ? "IBMPlexMono-Regular" : "IBMPlexMono-Medium"
        return NSFont(name: name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Darker Grotesque for display headlines only, never below 28px.
    static func display(_ size: CGFloat) -> NSFont {
        NSFont(name: "DarkerGrotesque-Black", size: size)
            ?? .systemFont(ofSize: size, weight: .black)
    }

    /// 10-11px uppercase micro-label attributes (0.09em tracking).
    static func microLabel(_ text: String, size: CGFloat = 10) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: mono(size),
                .kern: size * 0.09,
                .foregroundColor: textFaint,
            ])
    }

    // MARK: - Metrics (the redesign's fixed chrome dimensions)

    static let railWidth: CGFloat = 48
    static let railSlot: CGFloat = 34
    static let railSlotRadius: CGFloat = 0
    static let optionsBarHeight: CGFloat = 36
    static let controlHeight: CGFloat = 22
    static let controlRadius: CGFloat = 0
    static let statusBarHeight: CGFloat = 26
    static let panelWidth: CGFloat = 304
    static let tabHeight: CGFloat = 32
    static let layerRow: CGFloat = 44
    static let popoverWidth: CGFloat = 268
    static let menuMinWidth: CGFloat = 206
    static let canvasInset: CGFloat = 36

    // MARK: - Metrics (the chrome cleanup)

    /// The window's own two bars. `optionsBarHeight` is also 36 and they are
    /// deliberately separate names: Rasterize's options bar and Reelcut's
    /// timeline bar are the same height for the same reason, not the same
    /// thing.
    static let toolbarHeight: CGFloat = 44
    static let timelineBarHeight: CGFloat = 36
    /// The timeline's track-header column and its ruler band.
    static let trackHeaderWidth: CGFloat = 132
    static let rulerHeight: CGFloat = 22

    /// A clip bar: its corner, the name strip along its top, the grips that
    /// appear on the selected one, and the width of one filmstrip tile.
    static let clipRadius: CGFloat = 2
    static let clipHeaderHeight: CGFloat = 16
    static let trimGripWidth: CGFloat = 6
    static let filmstripThumb: CGFloat = 34

    /// Lane heights by track size (S/M/L) and track kind (text, video,
    /// audio). At S a clip is its name strip and little else, which is
    /// intended. `TimelineLayout` is the only reader.
    static let trackHeights: [[CGFloat]] = [
        [30, 54, 40],
        [44, 84, 60],
        [58, 116, 82],
    ]

    /// The radius scale: the chrome is square, so controls (`controlRadius`),
    /// buttons, list rows and the bordered fields are all 0; a clip keeps 2.
    static let buttonRadius: CGFloat = 0
    static let listRowRadius: CGFloat = 0
    static let fieldRadius: CGFloat = 0

    // MARK: - Motion

    static let hoverDuration: TimeInterval = 0.14
    static let stateDuration: TimeInterval = 0.22

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animate(_ duration: TimeInterval, _ changes: () -> Void) {
        if reduceMotion {
            changes()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
            context.allowsImplicitAnimation = true
            changes()
        }
    }
}
