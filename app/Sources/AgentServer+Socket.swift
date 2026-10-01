import Foundation

/// The agent server's Unix socket (road map 14's MC2, spec §11 MC-1, MC-2,
/// MC-6): where it is bound, whether this instance may bind it, the bind,
/// and its release at quit. The core's listener is the second server object
/// beside `start()`'s TCP one (`ReelAgentSocket`), serving the same prepared
/// catalog through the same trampoline, so a call from either listener goes
/// through `AgentLane.serve`'s one lock (AI-2) and ordering is unchanged.
///
/// **Bound at every launch, and never an alert.** No person asked for it,
/// so a launch that cannot bind logs one line, `Reelcut agent socket not
/// bound: <reason>`, and carries on; a bound one logs `Reelcut agent socket
/// listening at <path>`. Neither line carries the `Reelcut: ` prefix, which
/// is the parity check's alone.
///
/// **The path** (`socketPlan`) is `RC_AGENT_SOCKET` when it is set and not
/// empty, else `AppSupport`'s folder plus `Agent/agent.sock`. Until MC4, a
/// launch that sets `RC_AGENT_PORT` and not `RC_AGENT_SOCKET` binds no
/// socket: every proof of the era launches that way, and MC-6 says no proof
/// binds the person's socket. MC4 deletes that arm with `RC_AGENT_PORT`.
///
/// **MC-2's policy** (`socketRefusal`), in order: the folder is made by
/// `AppSupport.ensureDirectory` (`0700` at each level it makes) and must
/// then be a real folder — not a symlink — owned by this user with no group
/// or world bits, because its mode is the socket's whole access control and
/// a wrong one is reported, not worked around. A file at the path is asked
/// first: a socket that ACCEPTS a connection belongs to another instance and
/// is left alone; one that REFUSES is a crash's leftover and is unlinked;
/// anything that is not a socket is left alone too (MC-2 sanctions unlinking
/// only a refused socket). The core then binds without unlinking anything
/// and makes the file `0600`.
///
/// **The quit** (`unbindSocket`) is a release, not a stop: the core unlinks
/// the file only while it is still the one this listener bound (MC1's S7)
/// and abandons the listener without a join, so a call in flight that waits
/// on main cannot hold the quit. `AgentServer.shared` is the context and
/// lives for the process, which the release's contract needs.
extension AgentServer {
    enum SocketPlan: Equatable {
        case bind(path: String)
        case skip(reason: String)
    }

    static let socketEnvironmentKey = "RC_AGENT_SOCKET"

    /// The interim rule's reason (MC2..MC3; MC4 deletes it with the port).
    static let portOnlyReason =
        "RC_AGENT_PORT is set and RC_AGENT_SOCKET is not; "
        + "a port-only launch binds no socket until MC4"

    /// The bundle's short version, or "0.0" — what both listeners report as
    /// `serverInfo.version`.
    static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// `~/Library/Application Support/Reelcut/Agent/agent.sock` — the path
    /// only; creates nothing.
    static var defaultSocketPath: String? {
        AppSupport.subdirectory("Agent")?.appendingPathComponent("agent.sock").path
    }

    /// Where this launch binds, or why it binds nothing. Pure.
    static func socketPlan(environment: [String: String], defaultPath: String?) -> SocketPlan {
        if let path = environment[socketEnvironmentKey], !path.isEmpty {
            return .bind(path: path)
        }
        if environment["RC_AGENT_PORT"] != nil { return .skip(reason: portOnlyReason) }
        guard let defaultPath else { return .skip(reason: "no Application Support folder") }
        return .bind(path: defaultPath)
    }

    /// Binds the socket under MC-2's rules, or logs why not. Main only,
    /// from `applicationDidFinishLaunching`; never throws, never alerts.
    func bindSocket() {
        assert(Thread.isMainThread)
        let plan = Self.socketPlan(
            environment: ProcessInfo.processInfo.environment, defaultPath: Self.defaultSocketPath)
        let path: String
        switch plan {
        case .skip(let reason):
            Self.logSocketNotBound(reason)
            return
        case .bind(let planned):
            path = planned
        }
        if let reason = Self.socketRefusal(at: path) {
            Self.logSocketNotBound(reason)
            return
        }
        do {
            let catalog = try prepareCatalog()
            try ReelAgentSocket.start(
                path: path, serverName: "reelcut", version: Self.serverVersion,
                toolsJSON: catalog, handler: agentToolTrampoline,
                context: Unmanaged.passUnretained(self).toOpaque())
        } catch {
            Self.logSocketNotBound(error.localizedDescription)
            return
        }
        NSLog("Reelcut agent socket listening at %@", path)
    }

    /// For `applicationWillTerminate`: unlinks the socket only if it is
    /// still this instance's, with no join. Safe when none is bound.
    func unbindSocket() {
        ReelAgentSocket.release()
    }

    private static func logSocketNotBound(_ reason: String) {
        NSLog("Reelcut agent socket not bound: %@", reason)
    }

    /// MC-2 before the bind: the folder made and checked, then whatever is
    /// at the path asked and, only when it is a refusing socket, unlinked.
    /// Nil means bind; otherwise the reason nothing is bound.
    static func socketRefusal(at path: String) -> String? {
        let socketURL = URL(fileURLWithPath: path)
        let folder = socketURL.deletingLastPathComponent().path
        do {
            try AppSupport.ensureDirectory(URL(fileURLWithPath: folder, isDirectory: true))
        } catch {
            return "could not make the folder \(folder): \(error.localizedDescription)"
        }

        var folderInfo = stat()
        guard lstat(folder, &folderInfo) == 0 else {
            return "could not read the folder \(folder): \(errnoSentence(errno))"
        }
        guard folderInfo.st_mode & S_IFMT == S_IFDIR else {
            return "\(folder) is not a folder (a symlink is refused)"
        }
        guard folderInfo.st_uid == getuid() else {
            return "\(folder) is owned by uid \(folderInfo.st_uid), not this user (\(getuid()))"
        }
        if folderInfo.st_mode & 0o077 != 0 { return modeSentence(folder, folderInfo.st_mode) }

        var fileInfo = stat()
        guard lstat(path, &fileInfo) == 0 else {
            let code = errno
            return code == ENOENT ? nil : "could not read \(path): \(errnoSentence(code))"
        }
        guard fileInfo.st_mode & S_IFMT == S_IFSOCK else {
            return "\(path) exists and is not a socket; it is left alone"
        }
        let answer = connectErrno(toSocketAt: path)
        if answer == 0 { return "another instance answers at \(path); this one binds none" }
        guard answer == ECONNREFUSED else {
            return "could not reach the socket at \(path): \(errnoSentence(answer))"
        }
        guard unlink(path) == 0 || errno == ENOENT else {
            return "could not remove the leftover socket \(path): \(errnoSentence(errno))"
        }
        return nil
    }

    private static func modeSentence(_ folder: String, _ mode: mode_t) -> String {
        let octal = String(format: "%04o", UInt32(mode) & 0o7777)
        return "\(folder) is mode \(octal); the socket's folder must be its owner's alone (0700)"
    }

    private static func errnoSentence(_ code: Int32) -> String {
        String(cString: strerror(code))
    }

    /// `connect(2)` to the socket at `path`: 0 when something accepts,
    /// else the errno (ECONNREFUSED for a crash's leftover).
    static func connectErrno(toSocketAt path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return errno }
        defer { close(fd) }
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return ENAMETOOLONG }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0 ? 0 : errno
    }
}
