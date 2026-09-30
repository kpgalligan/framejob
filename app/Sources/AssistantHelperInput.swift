import Foundation

/// The helper's stdin. Touched only on the session's write queue, so a write
/// after the close, or a second close, does nothing.
final class HelperInput {
    private let handle: FileHandle
    private var closed = false

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("HelperInput does not support NSCoder")
    }

    func write(_ data: Data) {
        guard !closed else { return }
        try? handle.write(contentsOf: data)
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? handle.close()
    }
}
