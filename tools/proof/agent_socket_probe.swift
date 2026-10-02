// tools/proof/agent_socket_probe.swift — `agent_socket_proof.py`'s P1
// instrument (road map 14's MC2). Built as `main.swift` over every other file
// in app/Sources on harness/build.sh's swiftc line, it asks the app's own
// `AgentServer.socketPlan` — the pure half of `bindSocket` — for each case
// below and prints one JSON line per case, then one line with
// `AgentServer.defaultSocketPath` (a path only; it creates nothing). Nothing
// here binds, connects or writes a file.

import Foundation

let fixedDefault = "/probe/Reelcut/Agent/agent.sock"
let scratchSocket = "/probe/scratch/agent.sock"

let cases: [(name: String, environment: [String: String], defaultPath: String?)] = [
    ("empty", [:], fixedDefault),
    ("socket", ["RC_AGENT_SOCKET": scratchSocket], fixedDefault),
    ("empty-socket", ["RC_AGENT_SOCKET": ""], fixedDefault),
    ("nil-default", [:], nil),
]

func line(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else {
        print("{\"error\":\"unencodable\"}")
        return
    }
    print(String(decoding: data, as: UTF8.self))
}

for (name, environment, defaultPath) in cases {
    switch AgentServer.socketPlan(environment: environment, defaultPath: defaultPath) {
    case .bind(let path):
        line(["case": name, "plan": "bind", "path": path])
    case .skip(let reason):
        line(["case": name, "plan": "skip", "reason": reason])
    }
}
line([
    "case": "default-path",
    "path": AgentServer.defaultSocketPath.map { $0 as Any } ?? NSNull(),
    "fixed_default": fixedDefault,
    "scratch_socket": scratchSocket,
])
