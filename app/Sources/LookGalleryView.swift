import AppKit

/// The Look section's gallery (spec §11 GR-7 [b]): a 3×3 grid of tiles —
/// None, then the eight looks in `LookGallery.tiles` order — each a thumbnail
/// with its name beneath, the kind every target shares outlined in the accent.
///
/// An `OptionControl`, so the section's `refresh()` reaches it like any row:
/// each refresh hands the model the selection and whether the gallery is OPEN —
/// in a window and not hidden, which a collapsed section's content is. Open
/// and closed are read here, from `isHiddenOrHasHiddenAncestor`, and the three
/// moments they change (`viewDidHide`, `viewDidUnhide`, `viewDidMoveToWindow`)
/// refresh too; never from `InspectorSection.didToggle`, which `KeyedReveal`
/// overwrites on every build.
final class LookGalleryView: NSView, OptionControl {
    let tiles: [LookTileButton]
    private let gallery: LookGallery
    private let binding: InspectorBinding
    private let onPick: (LookKind?) -> Void

    init(gallery: LookGallery, binding: InspectorBinding, onPick: @escaping (LookKind?) -> Void) {
        self.gallery = gallery
        self.binding = binding
        self.onPick = onPick
        tiles = LookGallery.tiles.map { LookTileButton(kind: $0) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for start in stride(from: 0, to: tiles.count, by: 3) {
            let row = NSStackView(views: Array(tiles[start..<min(start + 3, tiles.count)]))
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = 6
            grid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }
        for tile in tiles {
            tile.target = self
            tile.action = #selector(tilePicked(_:))
        }
        gallery.view = self
        showThumbnails()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LookGalleryView does not support NSCoder")
    }

    /// Whether this gallery is the attached one and owes renders — what
    /// `select_inspector_tab` answers as `look_thumbnails_pending`.
    var isPending: Bool { gallery.view === self && gallery.isPending }

    func refresh() {
        let targets = LookGallery.targets(binding.clips, in: binding.snapshot)
        gallery.update(
            from: self, document: binding.document, targets: targets,
            open: window != nil && !isHiddenOrHasHiddenAncestor)
        // The outline reads the clips' OWN looks, which is what a tile writes
        // (GR-7 [b] (1)), as Clip ▸ Look ▸'s checkmarks do.
        let shared = LookGallery.shared(targets.map { $0.videoProps.look })
        for tile in tiles {
            tile.isOutlined = shared.map { $0 == tile.kind } ?? false
        }
    }

    /// The model's thumbnails, onto the tiles.
    func showThumbnails() {
        guard gallery.view === self else { return }
        for (tile, image) in zip(tiles, gallery.thumbnails) { tile.thumbnail = image }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func viewDidHide() {
        super.viewDidHide()
        refresh()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refresh()
    }

    @objc private func tilePicked(_ sender: LookTileButton) {
        onPick(sender.kind)
    }
}

/// One tile: a well holding the thumbnail, aspect-fit, and the look's name
/// beneath; outlined in the accent when every target carries its kind.
final class LookTileButton: NSButton {
    let kind: LookKind?
    var isOutlined = false {
        didSet { if isOutlined != oldValue { needsDisplay = true } }
    }
    var thumbnail: CGImage? {
        didSet { if thumbnail !== oldValue { needsDisplay = true } }
    }
    private let well = NSView()
    private let name: NSTextField

    init(kind: LookKind?) {
        self.kind = kind
        let title = kind?.displayName ?? "None"
        name = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(title)
        toolTip = kind == nil ? "Remove the look" : "Apply \(title)"

        well.translatesAutoresizingMaskIntoConstraints = false
        addSubview(well)
        name.font = DS.sans(10)
        name.textColor = DS.textMuted
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(name)
        NSLayoutConstraint.activate([
            well.topAnchor.constraint(equalTo: topAnchor),
            well.leadingAnchor.constraint(equalTo: leadingAnchor),
            well.trailingAnchor.constraint(equalTo: trailingAnchor),
            well.heightAnchor.constraint(equalTo: well.widthAnchor, multiplier: 9.0 / 16.0),
            name.topAnchor.constraint(equalTo: well.bottomAnchor, constant: 3),
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.trailingAnchor.constraint(equalTo: trailingAnchor),
            name.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LookTileButton does not support NSCoder")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = well.frame
        DS.canvasVoid.setFill()
        frame.fill()
        if let thumbnail, thumbnail.width > 0, thumbnail.height > 0,
           let context = NSGraphicsContext.current?.cgContext
        {
            let scale = min(
                frame.width / CGFloat(thumbnail.width), frame.height / CGFloat(thumbnail.height))
            let size = CGSize(
                width: CGFloat(thumbnail.width) * scale, height: CGFloat(thumbnail.height) * scale)
            let rect = CGRect(
                x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                width: size.width, height: size.height)
            context.saveGState()
            context.interpolationQuality = .high
            if isFlipped {
                context.translateBy(x: 0, y: rect.maxY + rect.minY)
                context.scaleBy(x: 1, y: -1)
            }
            context.draw(thumbnail, in: rect)
            context.restoreGState()
        }
        let outline = isOutlined ? DS.accent : DS.border
        let width: CGFloat = isOutlined ? 2 : 1
        outline.setStroke()
        let path = NSBezierPath(rect: frame.insetBy(dx: width / 2, dy: width / 2))
        path.lineWidth = width
        path.stroke()
    }
}
