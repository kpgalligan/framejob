import Foundation

/// Where the person's AssemblyAI key lives, behind a protocol with three
/// verbs — and the two conformers this build ships: a `0600` file, and a
/// value in memory that never touches disk.
///
/// **Why a file and not the Keychain.** The Keychain is the better place and
/// was the plan. Road map 6 §3 q7 MEASURED what an ad-hoc signature does to a
/// login-keychain item: the next build blocks on a `SecurityAgent` modal for
/// a full twenty seconds — even with `kSecUseAuthenticationUIFail`, which
/// does not turn that ACL confirmation into a refusal — and its delete
/// answers `errSecInvalidOwnerEdit`, so the item cannot even be cleaned up by
/// the build that finds it. Every `make app` is a new ad-hoc signature, and
/// an agent-driven instance has nobody to click the modal. The
/// data-protection keychain is not a way out either: `SecItemAdd` there
/// answered `errSecMissingEntitlement` from an unsandboxed ad-hoc-signed app
/// with no keychain access group. **The file is the weaker choice and this
/// paragraph is the record of it**: it is readable by anything running as the
/// person, where a Keychain item is readable by one signed identity after one
/// confirmation. The protocol is what lets a build signed with a stable
/// Developer ID identity add a `KeychainStore` conformer and a one-time
/// migration later without touching anything above it (R6-5, road map 6 §5d).
///
/// **No proof ever reads the person's file.** `MemoryStore` is what a probe
/// gets, and R6-9's `-RCSecretFolder` is what moves a launched app's folder
/// somewhere disposable — `AssemblyAIConfiguration.store` is the one place
/// either is decided.
protocol SecretStore {
    /// The secret, or nil when there is none. Never throws: "no key set" is a
    /// state the sheet names, not an error (road map 6 §5d).
    func read() -> String?
    /// Replaces whatever is there. Throws when it cannot be written, because
    /// a Save button that said nothing and saved nothing is the failure this
    /// is for.
    func write(_ secret: String) throws
    /// Leaves nothing behind. Removing what is not there succeeds.
    func remove() throws
}

/// Why a store could not be written, in a sentence the Settings window can
/// show unchanged.
enum SecretStoreError: LocalizedError, Equatable {
    case unwritable(String)

    var errorDescription: String? {
        switch self {
        case .unwritable(let reason):
            return "The API key could not be saved: \(reason)"
        }
    }
}

/// The shipping conformer: one file, mode `0600`, in a directory created at
/// `0700`.
///
/// **The permissions are on the file from the moment it exists.** It is
/// created with `O_CREAT|O_EXCL` at mode `0600` under a temporary name and
/// `rename(2)`d into place — never written first and `chmod`ed after, which
/// would leave a window in which the key was world-readable, and never
/// through `Data.write`, whose `POSIXPermissions` would be applied to a file
/// that already existed. The rename is also what makes a replacement atomic:
/// a reader sees the old key or the new one, never a half-written file.
///
/// An EXISTING directory's mode is left alone. A person who tightened
/// `~/Library/Application Support/Reelcut/` themselves should keep what they
/// chose, and a directory the app did not create is not the app's to relax.
final class FileStore: SecretStore {

    /// The one spelling of the file's name.
    static let fileName = "assemblyai-key"

    /// The folder the file sits in. `AssemblyAIConfiguration.store` resolves
    /// it — from `AppSupport.directory` for a person, from `-RCSecretFolder`
    /// for a proof — and nothing here reaches for a default of its own, so
    /// there is exactly one line in the tree that can name a person's real
    /// folder (R6-9).
    let directory: URL

    var fileURL: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    init(directory: URL) {
        self.directory = directory
    }

    /// The key, trimmed. An empty or whitespace-only file reads as NO key
    /// rather than as a key that is the empty string: a request with an empty
    /// `authorization` header would be refused by the service with the key
    /// sentence, and "no key is set" is the answer the person can act on.
    func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func write(_ secret: String) throws {
        try makeDirectory()
        let temporary = directory.appendingPathComponent(
            ".\(Self.fileName).\(UUID().uuidString)", isDirectory: false)
        let descriptor = temporary.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path = path else { return -1 }
            return open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        }
        guard descriptor >= 0 else {
            throw SecretStoreError.unwritable(String(cString: strerror(errno)))
        }
        if let reason = writeAll(descriptor, Array(secret.utf8)) {
            close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
            throw SecretStoreError.unwritable(reason)
        }
        close(descriptor)
        let moved = temporary.withUnsafeFileSystemRepresentation { from -> Int32 in
            guard let from = from else { return -1 }
            return fileURL.withUnsafeFileSystemRepresentation { to -> Int32 in
                guard let to = to else { return -1 }
                return rename(from, to)
            }
        }
        guard moved == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw SecretStoreError.unwritable(reason)
        }
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw SecretStoreError.unwritable(error.localizedDescription)
        }
    }

    /// `mkdir(2)` at `0700` when the directory is absent, and nothing at all
    /// when it is there — `FileManager.createDirectory`'s
    /// `withIntermediateDirectories: true` would silently succeed on an
    /// existing directory of any mode, which is the behaviour wanted, but it
    /// would also apply the attributes to the intermediates it makes. One
    /// call, one directory, one mode.
    private func makeDirectory() throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SecretStoreError.unwritable("\(directory.path) is not a folder")
            }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw SecretStoreError.unwritable(error.localizedDescription)
        }
        let made = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path = path else { return -1 }
            return mkdir(path, 0o700)
        }
        guard made == 0 || errno == EEXIST else {
            throw SecretStoreError.unwritable(String(cString: strerror(errno)))
        }
    }
}

/// Every byte of `bytes` to `descriptor`, or `strerror`'s sentence. A free
/// function because `write(2)` and `SecretStore.write(_:)` are the same name
/// and a method cannot call the system call without a module qualifier that
/// changes with the SDK.
private func writeAll(_ descriptor: Int32, _ bytes: [UInt8]) -> String? {
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return write(descriptor, base + offset, buffer.count - offset)
        }
        guard written > 0 else { return String(cString: strerror(errno)) }
        offset += written
    }
    return nil
}

/// The probe's store, and the empty store R6-9 hands an app that was pointed
/// at a stand-in server. Nothing here touches disk, so no run of any
/// instrument can read or write the person's own key.
final class MemoryStore: SecretStore {
    private let lock = NSLock()
    private var secret: String?

    init(_ secret: String? = nil) {
        self.secret = secret
    }

    func read() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return secret
    }

    func write(_ secret: String) throws {
        lock.lock()
        self.secret = secret
        lock.unlock()
    }

    func remove() throws {
        lock.lock()
        secret = nil
        lock.unlock()
    }
}
