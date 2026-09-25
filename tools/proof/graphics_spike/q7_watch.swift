// q7(c) (road map 10 G0): what a DispatchSource on a DIRECTORY raises when
// files inside it are moved in, replaced by rename, overwritten in place or
// removed. One JSON line per event, `t` in seconds since 1970 so the caller
// can line events up with its own actions; exits at the bound.
//
//   q7_watch <dir> <seconds>

import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count == 3, let seconds = Double(arguments[2]) else {
    print("{\"error\":\"usage: q7_watch <dir> <seconds>\"}")
    exit(2)
}
let fd = open(arguments[1], O_EVTONLY)
guard fd >= 0 else {
    print("{\"error\":\"open failed: \(errno)\"}")
    exit(1)
}
let queue = DispatchQueue(label: "q7.watch")
let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .all, queue: queue)
let names: [(DispatchSource.FileSystemEvent, String)] = [
    (.delete, "delete"), (.write, "write"), (.extend, "extend"), (.attrib, "attrib"),
    (.link, "link"), (.rename, "rename"), (.revoke, "revoke"), (.funlock, "funlock"),
]
source.setEventHandler {
    let mask = source.data
    let raised = names.filter { mask.contains($0.0) }.map { "\"\($0.1)\"" }.joined(separator: ",")
    print("{\"t\":\(Date().timeIntervalSince1970),\"mask\":[\(raised)]}")
}
source.resume()
print("{\"t\":\(Date().timeIntervalSince1970),\"ready\":true}")
queue.asyncAfter(deadline: .now() + seconds) {
    source.cancel()
    close(fd)
    exit(0)
}
dispatchMain()
