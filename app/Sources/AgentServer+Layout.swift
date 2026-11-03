import Foundation

/// `switch_layout` (road map "creator-jobs" CO6, spec §11 CO-60…CO-66),
/// mirroring Clip ▸ Camera Layout ▸ (`switchCameraLayout` in
/// `EditorViewController+Layout.swift`, which sends this op at the playhead
/// with `duration` and `curve` left to the core): one op, one undo step
/// "Camera Layout", every refusal the core's sentence. Since CO7 (spec §11
/// CO-70) an omitted or null `focus` is filled from the camera clip's cached
/// person masks, as the menu and the Picture sub-tab's Layout section fill
/// it, and the answer carries the `focus` sent.
extension AgentServer {

    /// What the first main-thread hop resolves.
    private struct LayoutCall {
        let document: ProjectDocument
        let camera: UInt32
        let screen: UInt32?
        let layout: CameraLayoutKind
        let shape: CameraLayoutShape?
        let corner: CameraLayoutCorner?
        let at: Ticks
        let duration: Ticks?
        let curve: Curve?
        let focus: (Double, Double)?
        let nest: Bool?
        let through: Ticks?
        /// The masks to fill `focus` from, when the caller left it out.
        let inputs: CameraLayoutFocus.Inputs?
        let asked: ReelProject
        let scope: UInt32?

        func op(focus: (Double, Double)?) -> ReelOp {
            .switchLayout(
                camera: camera, screen: screen, layout: layout, shape: shape, corner: corner,
                at: at, duration: duration, curve: curve, focus: focus, nest: nest,
                through: through)
        }
    }

    /// **Runs on the SERVER thread** (`creatorOffMainTools`): one main hop resolves the
    /// arguments and the camera's cached masks, the centroid is read here, and a last main hop
    /// refuses when the project or the scope changed meanwhile and applies as one undo step.
    func switchLayout(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "switch_layout must run on the server thread — its name is missing "
                    + "from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveLayout(a) }
        let filled = call.inputs.flatMap { CameraLayoutFocus.focus($0) }
        return try onMain {
            let document = call.document
            guard document.project === call.asked, document.scope == call.scope else {
                throw ToolError(
                    message: "the project changed while switch_layout read the camera's person "
                        + "masks, so nothing was laid out. Call switch_layout again.")
            }
            var focus = call.focus ?? filled
            // A filled focus is in the camera media's pixels: never sent to the nest clip
            // that `nest: true` puts in the camera's place (CO-70).
            if call.focus == nil, filled != nil, call.nest == true,
                let nested = self.addressed([call.op(focus: filled)], document).first,
                !CameraLayoutCommand.keepsFocus(
                    nested: nested, camera: call.camera, document: document)
            {
                focus = nil
            }
            let answer: Any = focus.map { [$0.0, $0.1] } ?? NSNull()
            return try self.editResult(
                document, CameraLayoutCommand.actionName, [call.op(focus: focus)],
                ["focus": answer])
        }
    }

    /// The arguments in the op's order — every required one read before an id is looked up,
    /// so a missing one is named as missing whatever the others hold — and the camera's masks
    /// when `focus` is left out.
    private func resolveLayout(_ a: [String: Any]) throws -> LayoutCall {
        let document = try target(a)
        _ = try idArg(a, "camera")
        let layout = try requiredEnumArg(a, "layout", CameraLayoutKind.self)
        let at = try timeArg(a, "at", document)
        let camera = try clipArg(a, "camera", document)
        var screen: UInt32?
        if let raw = a["screen"], !(raw is NSNull) {
            screen = try clipArg(a, "screen", document).id
        }
        let focus = try pointArg(a, "focus")
        return LayoutCall(
            document: document, camera: camera.id, screen: screen, layout: layout,
            shape: try enumArg(a, "shape", CameraLayoutShape.self),
            corner: try enumArg(a, "corner", CameraLayoutCorner.self), at: at,
            duration: try optionalTimeArg(a, "duration", document),
            curve: try enumArg(a, "curve", Curve.self), focus: focus,
            nest: try boolArg(a, "nest"),
            through: try optionalTimeArg(a, "through", document),
            inputs: focus == nil ? CameraLayoutFocus.inputs(camera: camera.id, in: document) : nil,
            asked: document.project, scope: document.scope)
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
