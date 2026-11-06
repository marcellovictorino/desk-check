// Runs under Desk Check's own entitlements (see Tests/sandbox-probe.sh) and checks the
// sandbox does what the README promises: current settings are writable, legacy settings
// are readable but not writable, other home folders are closed, and network is refused.
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
expect(ConfigLocation.file.path == home.path + "/.config/desk-check/config.toml",
       "config path is in the real home folder, not the container")

// Config folder: create it if needed, write, read back, remove the probe file.
let probe = ConfigLocation.directory.appendingPathComponent(".sandbox-probe-\(UUID().uuidString)")
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
let outside = home.appendingPathComponent(".config/desk-check-sandbox-probe-outside-\(UUID().uuidString)")
let wroteOutside = (try? "x".write(to: outside, atomically: false, encoding: .utf8)) != nil
if wroteOutside { try? fm.removeItem(at: outside) }
expect(!wroteOutside, "writing beside the config folder is refused")
expect((try? fm.contentsOfDirectory(atPath: home.path)) == nil, "listing the home folder is refused")

let legacyConfig = ConfigLocation.legacyDirectory.appendingPathComponent("config.toml")
do {
    _ = try Data(contentsOf: legacyConfig)
    expect(true, "legacy settings can be read for migration")
} catch {
    let nsError = error as NSError
    let missing = (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue)
        || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    if missing {
        expect(true, "legacy settings file may be absent on a clean install")
    } else {
        expect(false, "legacy settings can be read for migration (\(error.localizedDescription))")
    }
}
let legacyWriteProbe = ConfigLocation.legacyDirectory.appendingPathComponent(".sandbox-probe-\(UUID().uuidString)")
do {
    try Data("probe".utf8).write(to: legacyWriteProbe)
    try fm.removeItem(at: legacyWriteProbe)
    expect(false, "writing to the legacy folder is refused")
} catch {
    expect(true, "writing to the legacy folder is refused")
}

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
