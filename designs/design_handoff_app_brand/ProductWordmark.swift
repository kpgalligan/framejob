import AppKit

// REFERENCE IMPLEMENTATION — not compiled where it was written (no Swift toolchain there).
// Adapt it to the repository's rules (file placement, DS tokens, the per-side CLAUDE.md),
// then build and drive it. The README beside this file is the spec; this is one way to meet it.

/// An app's wordmark: the name in outlined Geist 650 at −0.04em with the coral piece of the
/// app's icon, drawn from the path data in `<app>-wordmark.json` (a bundle resource).
///
/// The data is in the artwork's own units: 1000 per em, y growing downward, the baseline at
/// y = 0 (so letters sit at negative y), and a viewBox 1140 units tall whose top is y = −1100.
/// Every wordmark shares that box, so at one font size their caps match Geist's and each other's.
struct WordmarkArtwork {
    /// The viewBox's width, in units.
    let width: CGFloat
    /// The letters, one compound path. Filled with the text colour, so they follow the appearance.
    let letters: NSBezierPath
    /// The motif (the playhead, the pulse, the horns). Always brand coral.
    let motif: NSBezierPath
    /// Non-nil when the motif is a stroke (Doctored's pulse), nil when it is filled.
    let motifLineWidth: CGFloat?

    static let top: CGFloat = -1100
    static let height: CGFloat = 1140
    static let unitsPerEm: CGFloat = 1000

    /// Loads `<resource>.json` from the main bundle; nil when it is missing or malformed, in
    /// which case callers fall back to the name in text.
    static func load(resource: String) -> WordmarkArtwork? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let box = json["viewBox"] as? [String: Any],
              let width = (box["width"] as? NSNumber)?.doubleValue,
              let lettersData = json["letters"] as? String,
              let motifJSON = json["motif"] as? [String: Any],
              let motifData = motifJSON["d"] as? String,
              let letters = path(lettersData),
              let motif = path(motifData)
        else { return nil }
        var lineWidth: CGFloat?
        if (motifJSON["mode"] as? String) == "stroke",
           let value = (motifJSON["lineWidth"] as? NSNumber)?.doubleValue {
            lineWidth = CGFloat(value)
            motif.lineWidth = CGFloat(value)
            motif.lineCapStyle = .round
            motif.lineJoinStyle = .round
        }
        return WordmarkArtwork(
            width: CGFloat(width), letters: letters, motif: motif, motifLineWidth: lineWidth)
    }

    /// Parses the absolute M, L, C and Z commands the files use (and nothing else: a file
    /// with any other command is malformed here, by design).
    private static func path(_ data: String) -> NSBezierPath? {
        var tokens: [String] = []
        var number = ""
        for character in data {
            if character.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
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
                      let x = next(), let y = next() else { return nil }
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
        return path
    }
}

/// The wordmark as a view, sized by a font size the way text is: its caps are as tall as Geist's
/// at `fontSize`, and its first baseline is reported, so an `NSStackView` aligned by baseline
/// lines it up with text.
final class ProductWordmarkView: NSView {
    private let artwork: WordmarkArtwork
    private let fontSize: CGFloat
    private let textColor: NSColor

    init(artwork: WordmarkArtwork, name: String, fontSize: CGFloat, textColor: NSColor) {
        self.artwork = artwork
        self.fontSize = fontSize
        self.textColor = textColor
        super.init(frame: NSRect(origin: .zero, size: .zero))
        // A title, read once: the name, not "image".
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(name)
        setAccessibilityValue(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ProductWordmarkView does not support NSCoder")
    }

    private var scale: CGFloat { fontSize / WordmarkArtwork.unitsPerEm }

    /// The data is y-down, as the SVG writes it.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: artwork.width * scale, height: WordmarkArtwork.height * scale)
    }

    /// The baseline sits 1100 units below the box's top.
    override var firstBaselineOffsetFromTop: CGFloat { -WordmarkArtwork.top * scale }
    override var lastBaselineOffsetFromBottom: CGFloat {
        (WordmarkArtwork.height + WordmarkArtwork.top) * scale
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit resolves dynamic colours against this view's appearance inside draw(_:).
        // Units to points, with the baseline moved from y = 0 to 1100 units down so the box's
        // top lands at 0: x' = s·x, y' = s·y + 1100·s. Written as the matrix, so there is no
        // question of which way round two transforms compose.
        let transform = AffineTransform(
            m11: scale, m12: 0, m21: 0, m22: scale,
            tX: 0, tY: -WordmarkArtwork.top * scale)
        let letters = artwork.letters.copy() as? NSBezierPath ?? artwork.letters
        letters.transform(using: transform)
        textColor.setFill()
        letters.fill()

        let motif = artwork.motif.copy() as? NSBezierPath ?? artwork.motif
        motif.transform(using: transform)
        if let lineWidth = artwork.motifLineWidth {
            motif.lineWidth = lineWidth * scale
            DS.coral.setStroke()
            motif.stroke()
        } else {
            DS.coral.setFill()
            motif.fill()
        }
    }
}
