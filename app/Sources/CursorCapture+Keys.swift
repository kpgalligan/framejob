import AppKit
import Carbon.HIToolbox

/// A listen-only session event tap for key-downs (road map creator-jobs CU6, spec §11 CU-60;
/// CU-S1 `keys=tap`): it needs Input Monitoring, never Accessibility, and never changes or
/// posts an event. Made and enabled on MAIN; its run-loop source is on main's run loop in
/// `.commonModes`, so an open status-item menu (event tracking) still delivers. The tap holds
/// this object unretained in its `userInfo`, so `invalidate()` — idempotent, and run by the
/// owner's `stop` and `deinit` — must come before the last release. The system disables a tap
/// that answers too slowly or under user input; this one re-enables itself on either.
final class CursorKeyTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let onKeyDown: (CGEvent) -> Void

    /// MAIN. Nil when `CGEvent.tapCreate` makes no tap (Input Monitoring absent, or refused).
    init?(onKeyDown: @escaping (CGEvent) -> Void) {
        self.onKeyDown = onKeyDown
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            if let info {
                Unmanaged<CursorKeyTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return nil }
        self.port = port
    }

    deinit { invalidate() }

    /// MAIN. The tap's source onto main's run loop and the tap on; a second call does nothing.
    func enable() {
        guard let port, source == nil else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// MAIN. The tap off, its source removed and its port invalidated; idempotent.
    func invalidate() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    /// MAIN, from the run-loop source: a key-down to the owner; a disabled tap back on.
    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown:
            onKeyDown(event)
        default:
            break
        }
    }
}

extension CursorCapture {
    /// MAIN. The key tap made and stored (enabled by `start`); false when no tap could be made.
    func makeKeyTap() -> Bool {
        guard keyTap == nil else { return true }
        guard let tap = CursorKeyTap(onKeyDown: { [weak self] event in self?.takeKey(event) })
        else { return false }
        keyTap = tap
        return true
    }

    /// A key-down as the filter sees it, its character NIL: only `takeKey` fills it, and only
    /// for a shortcut (spec §11 CU-60).
    static func keyEvent(from event: CGEvent) -> CursorKeyEvent {
        CursorKeyEvent(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: CursorKeyModifiers(flags: event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            character: nil)
    }

    /// MAIN, from the tap: secure input read at delivery, the character read only for a
    /// shortcut, and the entry recorded at the event's host time; `.none` records nothing.
    func takeKey(_ event: CGEvent) {
        let arrival = Self.hostNow()
        var key = Self.keyEvent(from: event)
        let secure = IsSecureEventInputEnabled()
        if !secure, CursorKeyFilter.isShortcut(key) {
            key.character = NSEvent(cgEvent: event)?.characters(byApplyingModifiers: [])
        }
        let entry = CursorKeyFilter.entry(for: key, secure: secure)
        guard entry != .none else { return }
        record(entry, host: Self.host(of: event, arrival))
    }
}
