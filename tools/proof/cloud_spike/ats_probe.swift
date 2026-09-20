// tools/proof/cloud_spike/ats_probe.swift — road map 6, spike C0, row q3.
//
// One plain-HTTP GET, one JSON object on stdout. App Transport Security is a
// property of the BUNDLE the process runs from, so the runner builds this one
// file three ways — a bare Mach-O with no plist at all, an ad-hoc-signed
// `RCSpikeQ3.app` with no ATS key, and the same bundle with
// `NSAllowsLocalNetworking` — and puts the same two URLs to each.
//
//   ats_probe <url>   → {"status": 200, "body": "ok"}
//                     | {"error_domain": …, "error_code": …, "description": …}

import Foundation

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{\"error_domain\":\"probe\",\"error_code\":-2,\"description\":\"unserialisable\"}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2, let url = URL(string: arguments[1]) else {
    emit(["error_domain": "probe", "error_code": -1, "description": "usage: ats_probe <url>"])
}

var answer: [String: Any] = ["error_domain": "probe", "error_code": -3,
                             "description": "the handler never ran"]
let waiting = DispatchSemaphore(value: 0)
let configuration = URLSessionConfiguration.ephemeral
configuration.timeoutIntervalForRequest = 10
configuration.timeoutIntervalForResource = 10
let task = URLSession(configuration: configuration).dataTask(with: url) { data, response, error in
    if let error = error as NSError? {
        answer = ["error_domain": error.domain, "error_code": error.code,
                  "description": error.localizedDescription]
    } else {
        answer = ["status": (response as? HTTPURLResponse)?.statusCode ?? -1,
                  "body": String(data: data ?? Data(), encoding: .utf8) ?? ""]
    }
    waiting.signal()
}
task.resume()
if waiting.wait(timeout: .now() + 10) == .timedOut {
    answer = ["error_domain": "probe", "error_code": -4,
              "description": "no answer and no error in 10 s"]
}
emit(answer)
