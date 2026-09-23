import AppKit

/// The object-carrying door into `OptionPopupControl` (app/CLAUDE.md,
/// Popups): the caller hands titled VALUES and reads and writes values,
/// never an index. It maps onto the index init — `OptionControls.swift` is
/// carried from Rasterize and not forked — so a value not in `choices` reads
/// as row 0 and a row outside them writes nothing.
extension OptionPopupControl {
    convenience init<Value: Equatable>(
        width: CGFloat, choices: [(title: String, value: Value)],
        read: @escaping () -> Value, write: @escaping (Value) -> Void,
        enabled: @escaping () -> Bool, onEdit: @escaping () -> Void
    ) {
        let values = choices.map { $0.value }
        self.init(
            width: width, items: choices.map { $0.title },
            read: { values.firstIndex(of: read()) ?? 0 },
            write: { index in
                guard values.indices.contains(index) else { return }
                write(values[index])
            },
            enabled: enabled, onEdit: onEdit)
    }
}
