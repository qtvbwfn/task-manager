import AppKit

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}
if CommandLine.arguments.contains("--benchall") {
    exit(SelfTest.benchAll())
}
if CommandLine.arguments.contains("--bench") {
    exit(SelfTest.bench())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()