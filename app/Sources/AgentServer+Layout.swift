import Foundation

/// `switch_layout` (road map "creator-jobs" CO6, spec §11 CO-60…CO-66),
/// mirroring Clip ▸ Camera Layout ▸ (`switchCameraLayout` in
/// `EditorViewController+Layout.swift`, which sends this op at the playhead
/// with `duration` and `curve` left to the core): one op, one undo step
/// "Camera Layout", every refusal the core's sentence.
extension AgentServer {

    func switchLayout(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        // Every required argument is read before an id is looked up, so a
        // missing one is named as missing whatever the others hold.
        _ = try idArg(a, "camera")
        let layout = try requiredEnumArg(a, "layout", CameraLayoutKind.self)
        _ = try timeArg(a, "at", document)
        let camera = try clipArg(a, "camera", document)
        var screen: UInt32?
        if let raw = a["screen"], !(raw is NSNull) {
            screen = try clipArg(a, "screen", document).id
        }
        let shape = try enumArg(a, "shape", CameraLayoutShape.self)
        let corner = try enumArg(a, "corner", CameraLayoutCorner.self)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let curve = try enumArg(a, "curve", Curve.self)
        let focus = try pointArg(a, "focus")
        let nest = try boolArg(a, "nest")
        let through = try optionalTimeArg(a, "through", document)
        let op = ReelOp.switchLayout(
            camera: camera.id, screen: screen, layout: layout, shape: shape, corner: corner,
            at: at, duration: duration, curve: curve, focus: focus, nest: nest, through: through)
        return try editResult(document, "Camera Layout", [op], [:])
    }

    /// Two finite numbers, `[x, y]`, or nil when absent or null.
    private func pointArg(_ a: [String: Any], _ key: String) throws -> (Double, Double)? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        let numbers = (raw as? [Any])?.compactMap { value -> Double? in
            guard let number = value as? NSNumber,
                CFGetTypeID(number) != CFBooleanGetTypeID()
            else { return nil }
            return number.doubleValue
        }
        guard let numbers, numbers.count == 2, (raw as? [Any])?.count == 2,
            numbers.allSatisfy(\.isFinite)
        else {
            throw ToolError(message: "\(key) must be two numbers, [x, y].")
        }
        return (numbers[0], numbers[1])
    }
}
