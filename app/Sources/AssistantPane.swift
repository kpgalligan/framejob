import AppKit

/// The inspector's fourth tab (spec §11 AI-4, road map 12 A2): one
/// `AssistantView`, built ONCE in `init` and never in `makeSections()` —
/// `rebuild()` replaces what the sections hold, and a rebuild under the
/// composer would take the person's first responder and half-typed message
/// with it.
///
/// The pane holds only the view. The conversation is the editor's
/// (`EditorViewController+Assistant.swift`), which is handed the view through
/// `InspectorViewController.onAssistantView` the moment it exists, so a
/// later floating window is a second host for the same wiring.
///
/// **It is exactly the visible height.** The controller pins every pane at
/// least as tall as the scroll view shows; the `== 0` at priority 1 here
/// makes this one no taller, so the inspector's own scroll view never moves
/// and the transcript scrolls itself.
final class AssistantPane: InspectorPaneView {
    let assistantView = AssistantView()

    override var tab: InspectorTab { .assistant }
    override var emptyMessage: String? { nil }
    override var structureSignature: String { "assistant" }

    override init(inspector: InspectorViewController) {
        super.init(inspector: inspector)
        assistantView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(assistantView)
        let collapse = heightAnchor.constraint(equalToConstant: 0)
        collapse.priority = NSLayoutConstraint.Priority(1)
        NSLayoutConstraint.activate([
            assistantView.topAnchor.constraint(equalTo: topAnchor),
            assistantView.leadingAnchor.constraint(equalTo: leadingAnchor),
            assistantView.trailingAnchor.constraint(equalTo: trailingAnchor),
            assistantView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collapse,
        ])
        inspector.onAssistantView?(assistantView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantPane does not support NSCoder")
    }
}
