import AVFoundation
import AppKit

/// The recorder panel's camera preview (camera-recording CR2b, spec §11
/// CAM-7 (1)): a 200 × 150 pt well, `DS.canvasVoid` with a 1 pt `DS.border`,
/// that HOSTS a capture's `AVCaptureVideoPreviewLayer` as a sublayer filling
/// its bounds, aspect-fit — or shows one faint sentence, or nothing. It owns
/// no session and never sets a layer's `session`: the layer belongs to the
/// capture that made it (`CameraCapture(…, preview: true)`), so hosting one
/// is a sublayer swap and never reconfigures a running session. Which layer
/// or sentence it shows is `RecorderPanelController+CameraPreview.swift`'s
/// step.
final class CameraPreviewWell: NSView {
    static let size = NSSize(width: 200, height: 150)

    /// The layer shown, if any.
    private(set) var hostedLayer: AVCaptureVideoPreviewLayer?
    private let label = NSTextField(wrappingLabelWithString: "")

    /// The sentence shown, while it is; nil while a layer or nothing is.
    var message: String? { label.isHidden ? nil : label.stringValue }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.borderWidth = 1
        label.font = DS.sans(11)
        label.textColor = DS.textFaint
        label.alignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: Self.size.width - 24),
        ])
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CameraPreviewWell does not support NSCoder")
    }

    /// Hosts `preview`, filling the bounds and aspect-fit, in place of any
    /// other layer, and hides the sentence; nothing for the layer already
    /// hosted.
    func show(_ preview: AVCaptureVideoPreviewLayer) {
        guard preview !== hostedLayer else { return }
        hostedLayer?.removeFromSuperlayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.videoGravity = .resizeAspect
        preview.frame = bounds
        layer?.addSublayer(preview)
        CATransaction.commit()
        hostedLayer = preview
        label.isHidden = true
    }

    /// Lets any hosted layer go and shows `text`; nil is a blank well.
    func showMessage(_ text: String?) {
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = nil
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }

    /// The layer follows the bounds; `CATransaction` off, or every layout
    /// animates the picture into place.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    /// The well's fill and border, resolved in the current appearance.
    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = DS.canvasVoid.cgColor
            layer?.borderColor = DS.border.cgColor
        }
    }
}
