// tools/proof/cloud_spike/keychain_probe.swift — road map 6, spike C0, row q7.
//
// The Keychain from an ad-hoc-signed bundle, one step per process so a modal
// nobody can click is a TIMEOUT of that step and not a lost run. It stores
// `spike-dummy` under service `com.reelcut.spike.q7`, account `spike`, and
// never touches `com.kgalligan.reelcut.assemblyai` — the service C1 would
// use — nor reads any other item.
//
//   keychain_probe <add|read|read-noui|attrs|delete> [--dp]
//     → {mode, dp, status, message, matched, ms, nonce}
//
// `read-noui` asks for the item with the interaction door shut
// (`kSecUseAuthenticationUIFail`), so "it would have prompted" is an answer
// rather than a hang. `--dp` puts the whole thing on the data-protection
// keychain instead of the file one. `nonce` is `buildNonce`, generated into
// a second file per build by the runner so builds A and B have two cdhashes.

import Foundation
import Security

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{\"status\":-99}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

let service = "com.reelcut.spike.q7"
let account = "spike"
let secret = "spike-dummy"

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { emit(["status": -98, "message": "usage: keychain_probe <mode> [--dp]"]) }
let mode = arguments[1]
let dataProtection = arguments.contains("--dp")

func base() -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
    ]
    if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
    return query
}

let started = Date()
var status: OSStatus = errSecSuccess
var matched: Any = NSNull()

switch mode {
case "add":
    var query = base()
    query[kSecValueData as String] = Data(secret.utf8)
    status = SecItemAdd(query as CFDictionary, nil)
case "read", "read-noui":
    var query = base()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if mode == "read-noui" {
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    }
    var item: CFTypeRef?
    status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
        matched = String(data: data, encoding: .utf8) == secret
    }
case "attrs":
    var query = base()
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if mode == "attrs" { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
    var item: CFTypeRef?
    status = SecItemCopyMatching(query as CFDictionary, &item)
    matched = status == errSecSuccess
case "delete":
    status = SecItemDelete(base() as CFDictionary)
default:
    emit(["status": -97, "message": "unknown mode \(mode)"])
}

emit([
    "mode": mode,
    "dp": dataProtection,
    "status": Int(status),
    "message": (SecCopyErrorMessageString(status, nil) as String?) ?? "",
    "matched": matched,
    "ms": Date().timeIntervalSince(started) * 1000,
    "nonce": buildNonce,
])
