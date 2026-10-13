// q9 (road map 10 G0): Swift calls the throwaway `rc_graphic_spike_render`
// linked from libframejob_core.a. Built with `-D CONTROL`, it calls only
// `rc_op_names`, so the two binaries' sizes differ by what the engine costs
// once the linker keeps it. Prints ONE JSON object.
//
//   q9_probe <module.js> <frame> <width> <height> <font.ttf>
//   q9_probe (CONTROL build: no arguments)

import Foundation

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

#if CONTROL
let names = rc_op_names()
let text = names.map { String(cString: $0) } ?? ""
rc_string_free(names)
emit(["control": true, "op_names_bytes": text.utf8.count])
#else
let arguments = CommandLine.arguments
guard arguments.count == 6,
      let source = try? String(contentsOfFile: arguments[1], encoding: .utf8),
      let frame = Int64(arguments[2]), let width = UInt32(arguments[3]), let height = UInt32(arguments[4]),
      let font = FileManager.default.contents(atPath: arguments[5])
else {
    emit(["error": "usage: q9_probe <module.js> <frame> <width> <height> <font.ttf>"])
    exit(2)
}
var error: UnsafeMutablePointer<CChar>? = nil
let answer = font.withUnsafeBytes { raw -> UnsafeMutablePointer<CChar>? in
    let bytes = raw.bindMemory(to: UInt8.self)
    return rc_graphic_spike_render(source, frame, width, height, bytes.baseAddress, bytes.count, &error)
}
if let answer {
    let text = String(cString: answer)
    rc_string_free(answer)
    let timed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? text
    emit(["control": false, "timed": timed])
} else {
    let message = error.map { String(cString: $0) } ?? "NULL with no err_out"
    rc_string_free(error)
    emit(["control": false, "error": message])
    exit(1)
}
#endif
