// Runs under Desk Undo's own entitlements (see Tests/sandbox-probe.sh) and checks the
// sandbox does what the README promises: the config folder works, every other folder
// in the home folder is closed, and network connections are refused.
import Darwin
import Foundation

var failed = false
func expect(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failed = true }
}

let args = CommandLine.arguments
guard args.count == 2, let port = UInt16(args[1]) else {
    print("usage: SandboxProbe <port on this Mac>")
    exit(2)
}
let home = ConfigLocation.realHomeDirectory
let fm = FileManager.default

expect(NSHomeDirectory().contains("/Library/Containers/"), "running inside the App Sandbox container")
expect(ConfigLocation.file.path == home.path + "/.config/desk-undo/config.toml",
       "config path is in the real home folder, not the container")

// Config folder: create it if needed, write, read back, remove the probe file.
let probe = ConfigLocation.directory.appendingPathComponent(".sandbox-probe")
do {
    try fm.createDirectory(at: ConfigLocation.directory, withIntermediateDirectories: true)
    try "probe".write(to: probe, atomically: false, encoding: .utf8)
    let back = try String(contentsOf: probe, encoding: .utf8)
    try fm.removeItem(at: probe)
    expect(back == "probe", "config folder can be created, written and read")
} catch {
    expect(false, "config folder can be created, written and read (\(error.localizedDescription))")
}

// Anywhere else in the home folder is closed.
let outside = home.appendingPathComponent(".config/desk-undo-sandbox-probe-outside")
let wroteOutside = (try? "x".write(to: outside, atomically: false, encoding: .utf8)) != nil
if wroteOutside { try? fm.removeItem(at: outside) }
expect(!wroteOutside, "writing beside the config folder is refused")
expect((try? fm.contentsOfDirectory(atPath: home.path)) == nil, "listing the home folder is refused")

// Network: connect to a port on this Mac, so a failed sandbox sends nothing outside.
let fd = socket(AF_INET, SOCK_STREAM, 0)
var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = port.bigEndian
addr.sin_addr.s_addr = inet_addr("127.0.0.1")
let rc = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
let err = errno
close(fd)
expect(rc != 0 && err == EPERM, "network connection is refused (errno \(rc == 0 ? 0 : err), EPERM expected)")

exit(failed ? 1 : 0)
