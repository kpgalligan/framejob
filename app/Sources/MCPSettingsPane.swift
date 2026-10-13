import AppKit

/// Settings' MCP pane (issue batch B74, spec §11 MC-7): the first of
/// `SettingsWindowController`'s panes. It says how an MCP client reaches
/// Frame Job — through the bundled `framejob-mcp` (MC-1, MC-3), which opens
/// Frame Job in the background on the first tool call (MC-4) — shows that
/// helper's path, and holds Copy MCP Command, which puts MC-3's line on the
/// pasteboard.
///
/// **The blurb is visible, not behind an ⓘ** (MC-7): the owner asked for it
/// above the button, so the heading has no `SettingsInfoButton`.
///
/// **One spelling of the path and the line.** The helper's URL arrives from
/// `AgentServer.mcpHelperURL` through `SettingsWindowController`'s defaulted
/// parameter, and the line is `AgentServer.mcpCommand(helperPath:)`; the pane
/// builds neither itself. The pasteboard is a parameter too, so a probe hands
/// it a private one and never writes the general pasteboard.
///
/// **The button is enabled exactly while the helper is executable.** A copy
/// of Frame Job without it says so in the status line. The press is not an
/// edit, so it has no MCP mirror (spec §7.9).
final class MCPSettingsPane: NSStackView {
    static let paneTitle = "MCP"
    static let blurb = [
        "An MCP client such as Claude Code uses Frame Job's tools through framejob-mcp, a helper "
            + "inside this app. It reaches Frame Job over a local socket that only programs you "
            + "run can open.",
        "If Frame Job isn't running, the first tool call opens it in the background. To add "
            + "Frame Job to Claude Code, copy the command and run it in Terminal.",
    ]
    static let copyTitle = "Copy MCP Command"
    static let copiedStatus = "Copied. Paste it into Terminal and press Return."
    static let missingStatus = "framejob-mcp is missing from this copy of Frame Job."
    /// The Settings window's width less its two insets.
    private static let textWidth: CGFloat = 420

    let helperURL: URL
    let pasteboard: NSPasteboard

    let headingLabel = NSTextField(labelWithString: MCPSettingsPane.paneTitle)
    let blurbLabels: [NSTextField] = MCPSettingsPane.blurb.map {
        NSTextField(wrappingLabelWithString: $0)
    }
    let helperLabel = NSTextField(wrappingLabelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var copyButton: NSButton!

    /// MC-3's line for this pane's helper.
    var command: String { AgentServer.mcpCommand(helperPath: helperURL.path) }

    init(helperURL: URL, pasteboard: NSPasteboard) {
        self.helperURL = helperURL
        self.pasteboard = pasteboard
        super.init(frame: .zero)
        build()
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MCPSettingsPane does not support NSCoder")
    }

    private func build() {
        headingLabel.font = DS.sans(15, weight: .bold)
        headingLabel.textColor = DS.textStrong
        headingLabel.setAccessibilityIdentifier("settings.mcp.heading")

        for (index, label) in blurbLabels.enumerated() {
            label.font = DS.sans(13)
            label.textColor = DS.textStrong
            label.preferredMaxLayoutWidth = Self.textWidth
            label.setAccessibilityIdentifier("settings.mcp.blurb.\(index + 1)")
        }

        helperLabel.stringValue = helperURL.path
        helperLabel.font = DS.mono(12)
        helperLabel.textColor = DS.textStrong
        helperLabel.isSelectable = true
        helperLabel.lineBreakMode = .byCharWrapping
        helperLabel.preferredMaxLayoutWidth = Self.textWidth
        helperLabel.setAccessibilityIdentifier("settings.mcp.helper")

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = Self.textWidth
        statusLabel.setAccessibilityIdentifier("settings.mcp.status")

        copyButton = StickerButton(
            title: Self.copyTitle, style: .secondary, target: self,
            action: #selector(copyClicked(_:)))
        copyButton.setAccessibilityIdentifier("settings.mcp.copy")

        orientation = .vertical
        alignment = .leading
        spacing = 12
        let views: [NSView] = [headingLabel] + blurbLabels + [helperLabel, copyButton, statusLabel]
        for view in views { addArrangedSubview(view) }
        for label in blurbLabels.dropLast() { setCustomSpacing(8, after: label) }
    }

    /// Whether the button can do anything, and the status that goes with it:
    /// empty while the helper is executable, `missingStatus` while it is not.
    func sync() {
        let present = FileManager.default.isExecutableFile(atPath: helperURL.path)
        copyButton.isEnabled = present
        statusLabel.stringValue = present ? "" : Self.missingStatus
    }

    /// Puts MC-3's line on the pane's pasteboard. A helper that went missing
    /// since the last sync writes nothing and shows why.
    @objc func copyClicked(_ sender: Any?) {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            sync()
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        statusLabel.stringValue = Self.copiedStatus
    }
}
