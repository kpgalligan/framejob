import Foundation

/// An Objective-C exception `ObjCException` caught (spec §11 #525).
struct ObjCRaised: Error, @unchecked Sendable {
    let exception: NSException
    var name: String { exception.name.rawValue }
    var reason: String { exception.reason ?? "no reason given" }
}

/// Swift's door to `framejob_catch_objc` (`app/Bridging/FrameJobObjCCatch.h`,
/// spec §11 #525). Swift cannot catch an Objective-C exception, and one that
/// leaves a tool call ends the app, so `AgentLane` runs each call inside this.
///
/// **Accepted:** a raise skips the `defer`s and releases of every Swift frame
/// between it and the catch, so a handler's own lock or half-made state is not
/// restored; the catch therefore sits inside the lane's own lock and `defer`.
enum ObjCException {
    /// `body` on THIS thread, inside `@try`: its value, or what it raised.
    static func catching<T>(_ body: () -> T) -> Result<T, ObjCRaised> {
        var value: T?
        if let raised = framejob_catch_objc({ value = body() }) {
            return .failure(ObjCRaised(exception: raised))
        }
        guard let value else { preconditionFailure("framejob_catch_objc returned without running") }
        return .success(value)
    }

    /// `body` inside `@try`, its Swift error thrown on as it was: nil with
    /// `raised` set when it raised instead. `AgentLane.onMainWhenIdle` runs it
    /// on main and raises `raised` again on the thread that waited. Typed
    /// throws so a `rethrows` caller may pass its own closure.
    static func shielding<T, E: Error>(
        _ body: () throws(E) -> T, raised: inout NSException?
    ) throws(E) -> T? {
        var value: T?
        var thrown: E?
        raised = framejob_catch_objc {
            do throws(E) { value = try body() } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return value
    }

    /// The call's answer: "<tool> failed on an internal exception (<name>:
    /// <reason>). Frame Job is still running, but part of the call may have
    /// happened."
    static func toolSentence(_ tool: String, _ raised: ObjCRaised) -> String {
        "\(tool) failed on an internal exception (\(raised.name): \(raised.reason)). "
            + "Frame Job is still running, but part of the call may have happened."
    }

    /// The log line, never under the `Frame Job: ` prefix the parity check owns.
    static func log(_ tool: String, _ raised: ObjCRaised) {
        NSLog("framejob agent: %@ raised %@: %@", tool, raised.name, raised.reason)
    }
}
