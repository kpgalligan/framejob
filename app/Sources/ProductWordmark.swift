import AppKit

/// An app's wordmark as paths (spec §11 NM-16): the letters, filled with the text colour so they
/// follow the appearance, and the motif from the app's icon, always brand coral. Frame Job's is
/// `frameJob`, parsed from `FrameJobWordmark`'s compiled-in data.
///
/// The paths are in the artwork's own units: 1000 per em, y growing downward, the baseline at
/// y = 0 (letters at negative y), inside a viewBox 1140 units tall whose top is y = −1100. Every
/// Boppa Llewyn wordmark shares that box, so at one font size their caps match Geist's.
struct WordmarkArtwork {
    /// The viewBox's width, in units.
    let width: CGFloat
    /// The letters, one compound path, nonzero: the glyphs overlap at −0.04em tracking, and
    /// even-odd would punch holes where they do.
    let letters: NSBezierPath
    /// The motif (Frame Job's playhead), a filled path.
    let motif: NSBezierPath

    /// The viewBox's top, height and units per em, shared by every wordmark.
    static let top: CGFloat = -1100
    static let height: CGFloat = 1140
    static let unitsPerEm: CGFloat = 1000
    /// Geist's cap height in units: the caps' top is this far above the baseline.
    static let capHeight: CGFloat = 710

    /// Frame Job's wordmark; nil only if its compiled-in data does not parse, which
    /// `tools/proof/wordmark_proof.py` rules out.
    static let frameJob = WordmarkArtwork(
        width: FrameJobWordmark.width,
        letters: FrameJobWordmark.letters,
        motif: FrameJobWordmark.motif)

    /// Nil when either path holds anything but absolute M, L, C and Z commands with their
    /// numbers.
    init?(width: CGFloat, letters lettersData: String, motif motifData: String) {
        guard let letters = Self.path(lettersData), let motif = Self.path(motifData)
        else { return nil }
        self.width = width
        self.letters = letters
        self.motif = motif
    }

    /// Parses absolute M, L, C and Z commands, their numbers separated by whitespace or commas.
    /// Any other command, or a command short of numbers, makes the data malformed: nil.
    static func path(_ data: String) -> NSBezierPath? {
        var tokens: [String] = []
        var number = ""
        for character in data {
            if character.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(character))
            } else if character.isWhitespace || character == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else {
                number.append(character)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        let path = NSBezierPath()
        path.windingRule = .nonZero
        var index = 0
        func next() -> CGFloat? {
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            index += 1
            return CGFloat(value)
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M", "L":
                guard let x = next(), let y = next() else { return nil }
                let point = NSPoint(x: x, y: y)
                if command == "M" { path.move(to: point) } else { path.line(to: point) }
            case "C":
                guard let x1 = next(), let y1 = next(), let x2 = next(), let y2 = next(),
                    let x = next(), let y = next()
                else { return nil }
                path.curve(
                    to: NSPoint(x: x, y: y),
                    controlPoint1: NSPoint(x: x1, y: y1),
                    controlPoint2: NSPoint(x: x2, y: y2))
            case "Z":
                path.close()
            default:
                return nil
            }
        }
        return path.isEmpty ? nil : path
    }
}

// MARK: - ProductWordmarkView

/// The wordmark as a view, sized by a font size the way text is: its caps are as tall as Geist's
/// at `fontSize`, and it reports its first baseline. VoiceOver reads it once, as static text
/// carrying the name, never as an image.
final class ProductWordmarkView: NSView {
    private let artwork: WordmarkArtwork
    private let fontSize: CGFloat
    private let textColor: NSColor

    init(artwork: WordmarkArtwork, name: String, fontSize: CGFloat, textColor: NSColor) {
        self.artwork = artwork
        self.fontSize = fontSize
        self.textColor = textColor
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(name)
        setAccessibilityValue(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ProductWordmarkView does not support NSCoder")
    }

    /// Points per unit.
    var scale: CGFloat { fontSize / WordmarkArtwork.unitsPerEm }

    /// The distance from the view's top to its cap line: the box's top is 1100 units above the
    /// baseline and the caps 710.
    var capLineFromTop: CGFloat { (-WordmarkArtwork.top - WordmarkArtwork.capHeight) * scale }

    /// The data is y-down, as the SVG writes it.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: artwork.width * scale, height: WordmarkArtwork.height * scale)
    }

    override var firstBaselineOffsetFromTop: CGFloat { -WordmarkArtwork.top * scale }

    override var lastBaselineOffsetFromBottom: CGFloat {
        (WordmarkArtwork.height + WordmarkArtwork.top) * scale
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Units to points, the baseline moved from y = 0 to 1100 units down so the box's top
        // lands at 0: x' = s·x, y' = s·y + 1100·s, written as the one matrix. `textColor` is
        // resolved here against this view's appearance.
        let transform = AffineTransform(
            m11: scale, m12: 0, m21: 0, m22: scale, tX: 0, tY: -WordmarkArtwork.top * scale)
        for (source, color) in [(artwork.letters, textColor), (artwork.motif, DS.coral)] {
            guard let path = source.copy() as? NSBezierPath else { continue }
            path.transform(using: transform)
            color.setFill()
            path.fill()
        }
    }
}
