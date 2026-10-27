import Foundation
import Darwin

@main
struct UpdateInstallerSmoke {
    enum Injected: Error { case validation, move, launch }

    static func main() async throws {
        if let mode = ProcessInfo.processInfo.environment["WINMACKEY_FIXTURE_MODE"] {
            if mode == "ordinary-relaunch" || mode == "inherited-relaunch" {
                let environment = ProcessInfo.processInfo.environment
                assert(String(getpid()) != environment["WINMACKEY_FIXTURE_PARENT_PID"])
                assert(environment["WINMACKEY_FIXTURE_PRESERVED"] == "keep")
                let managed = UpdateInstaller.isManagedLaunch
                assert(UpdateInstaller.acknowledgeLaunch())
                let accepted = await UpdateInstaller.waitForLaunchAcceptance(timeout: 0.05)
                assert(managed == (mode == "inherited-relaunch"))
                assert(accepted == (mode == "ordinary-relaunch"))
                let result = "\(mode): pid=\(getpid()) managed=\(managed) accepted=\(accepted)"
                try Data(result.utf8).write(to: URL(fileURLWithPath: environment["WINMACKEY_FIXTURE_RESULT"]!))
                return
            }
            if let path = ProcessInfo.processInfo.environment[UpdateInstaller.receiptEnvironment] {
                try Data(String(getpid()).utf8).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("child.pid"))
            }
            if mode == "ready" {
                assert(UpdateInstaller.acknowledgeLaunch())
                let accepted = await UpdateInstaller.waitForLaunchAcceptance(timeout: 2)
                assert(accepted, "Candidate must wait for helper acceptance before engine startup")
            }
            if mode == "wrongPID", let path = ProcessInfo.processInfo.environment[UpdateInstaller.receiptEnvironment] {
                let receipt = UpdateInstaller.Receipt(pid: getpid() + 100, token: ProcessInfo.processInfo.environment[UpdateInstaller.tokenEnvironment] ?? "")
                try JSONEncoder().encode(receipt).write(to: URL(fileURLWithPath: path))
            }
            if mode == "exit" { return }
            try await Task.sleep(nanoseconds: mode == "ready" ? 400_000_000 : 10_000_000_000)
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("WinMacKey-update-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func fixture(_ name: String) throws -> (URL, URL, URL) {
            let dir = root.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let old = dir.appendingPathComponent("WinMacKey.app")
            let staged = dir.appendingPathComponent("Candidate.app")
            let backup = dir.appendingPathComponent("backup.app")
            try Data("old".utf8).write(to: old)
            try Data("new".utf8).write(to: staged)
            return (old, staged, backup)
        }
        func content(_ url: URL) -> String { try! String(contentsOf: url, encoding: .utf8) }
        func expectFailure(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected failure") } catch { }
        }

        do {
            let (old, staged, backup) = try fixture("success")
            var launched = false
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { assert(content($0) == "new") }, launchAndWait: {
                    assert(content($0) == "new")
                    assert(content(backup) == "old")
                    launched = true
                })
            try transaction.perform()
            assert(launched && !fm.fileExists(atPath: backup.path))
            assert(content(old) == "new")
            print("PASS replacement: backup retained through readiness, removed only after success")
        }
        do {
            let (old, staged, backup) = try fixture("validation")
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { _ in throw Injected.validation }, launchAndWait: { _ in fatalError("Must not launch") })
            expectFailure { try transaction.perform() }
            assert(content(old) == "old")
            assert(!fm.fileExists(atPath: backup.path))
            print("PASS validation failure: installed app untouched")
        }
        do {
            let (old, staged, backup) = try fixture("move")
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { _ in }, launchAndWait: { _ in fatalError("Must not launch") }, move: { from, to in
                    if from == staged { throw Injected.move }
                    try fm.moveItem(at: from, to: to)
                })
            expectFailure { try transaction.perform() }
            assert(content(old) == "old")
            assert(content(staged) == "new")
            print("PASS replacement move failure: old app restored")
        }
        do {
            let (old, staged, backup) = try fixture("launch")
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { _ in }, launchAndWait: { _ in throw Injected.launch })
            expectFailure { try transaction.perform() }
            assert(content(old) == "old")
            assert(content(staged) == "new")
            print("PASS launch failure: old app restored, candidate retained")
        }
        do {
            let (old, staged, backup) = try fixture("live-child")
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { _ in }, launchAndWait: { _ in throw UpdateInstallFailure.candidateStillRunning })
            expectFailure { try transaction.perform() }
            assert(content(old) == "new")
            assert(content(backup) == "old")
            print("PASS unkillable candidate: no unsafe rollback; backup retained")
        }
        do {
            let (old, staged, backup) = try fixture("restore-failure")
            let transaction = UpdateReplacement(installed: old, staged: staged, backup: backup,
                validate: { _ in }, launchAndWait: { _ in throw Injected.launch }, move: { from, to in
                    if from == backup { throw Injected.move }
                    try fm.moveItem(at: from, to: to)
                })
            expectFailure { try transaction.perform() }
            assert(content(backup) == "old")
            print("PASS restore failure: previous app backup retained")
        }
        expectFailure { try UpdateInstaller.waitForParentExit(getpid(), timeout: 0.05) }
        print("PASS parent still running: replacement cannot start")

        let receiptURL = root.appendingPathComponent("receipt.json")
        try JSONEncoder().encode(UpdateInstaller.Receipt(pid: 123, token: "token")).write(to: receiptURL)
        assert(UpdateInstaller.receiptMatches(receiptURL, pid: 123, token: "token"))
        assert(!UpdateInstaller.receiptMatches(receiptURL, pid: 124, token: "token"))
        assert(!UpdateInstaller.receiptMatches(receiptURL, pid: 123, token: "other"))
        print("PASS receipt requires both launched PID and request token")

        assert(UpdateInstaller.acknowledgeLaunch(environment: [:]))
        assert(!UpdateInstaller.acknowledgeLaunch(environment: [UpdateInstaller.receiptEnvironment: receiptURL.path]))
        assert(!UpdateInstaller.acknowledgeLaunch(environment: [UpdateInstaller.tokenEnvironment: "token"]))
        assert(!UpdateInstaller.acknowledgeLaunch(environment: [UpdateInstaller.receiptEnvironment: "", UpdateInstaller.tokenEnvironment: "token"]))
        let missingParent = root.appendingPathComponent("missing-parent/ready.json")
        assert(!UpdateInstaller.acknowledgeLaunch(environment: [UpdateInstaller.receiptEnvironment: missingParent.path, UpdateInstaller.tokenEnvironment: "token"]))
        assert(UpdateInstaller.acknowledgeLaunch(environment: [UpdateInstaller.receiptEnvironment: receiptURL.path, UpdateInstaller.tokenEnvironment: "valid-token"]))
        assert(UpdateInstaller.receiptMatches(receiptURL, pid: getpid(), token: "valid-token"))
        print("PASS readiness acknowledgement reports incomplete environment and failed receipt writes")

        let normalAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: [:], timeout: 0.05)
        assert(normalAccepted)
        let partialAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: [UpdateInstaller.tokenEnvironment: "token"], timeout: 0.05)
        assert(!partialAccepted)
        let acceptanceEnvironment = [UpdateInstaller.receiptEnvironment: receiptURL.path, UpdateInstaller.tokenEnvironment: "acceptance-token"]
        let acceptanceURL = root.appendingPathComponent("accepted.json")
        let missingAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: acceptanceEnvironment, timeout: 0.05)
        assert(!missingAccepted)
        try JSONEncoder().encode(UpdateInstaller.Receipt(pid: getpid() + 100, token: "acceptance-token")).write(to: acceptanceURL)
        let wrongPIDAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: acceptanceEnvironment, timeout: 0.05)
        assert(!wrongPIDAccepted)
        try JSONEncoder().encode(UpdateInstaller.Receipt(pid: getpid(), token: "wrong-token")).write(to: acceptanceURL)
        let wrongTokenAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: acceptanceEnvironment, timeout: 0.05)
        assert(!wrongTokenAccepted)
        try JSONEncoder().encode(UpdateInstaller.Receipt(pid: getpid(), token: "acceptance-token")).write(to: acceptanceURL)
        let validAccepted = await UpdateInstaller.waitForLaunchAcceptance(environment: acceptanceEnvironment, timeout: 0.05)
        assert(validAccepted)
        print("PASS two-way acceptance: missing, wrong PID/token time out; matching helper acceptance succeeds")

        for mode in ["inherited-relaunch", "ordinary-relaunch"] {
            let output = root.appendingPathComponent("\(mode).txt")
            var environment = ProcessInfo.processInfo.environment
            environment.merge(acceptanceEnvironment) { _, new in new }
            environment["WINMACKEY_FIXTURE_MODE"] = mode
            environment["WINMACKEY_FIXTURE_PARENT_PID"] = String(getpid())
            environment["WINMACKEY_FIXTURE_PRESERVED"] = "keep"
            environment["WINMACKEY_FIXTURE_RESULT"] = output.path
            let beforeReceipt = try Data(contentsOf: receiptURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", #"exec "$0""#, URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path]
            process.environment = mode == "ordinary-relaunch"
                ? UpdateInstaller.ordinaryLaunchEnvironment(from: environment) : environment
            try process.run()
            process.waitUntilExit()
            assert(process.terminationStatus == 0)
            if mode == "ordinary-relaunch" {
                let afterReceipt = try Data(contentsOf: receiptURL)
                assert(beforeReceipt == afterReceipt, "Ordinary relaunch must not reuse or overwrite an update receipt")
            }
            print("PASS real shell/child environment: \(content(output))")
        }

        let app = root.appendingPathComponent("Executable.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("fixture")
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
        let plist: [String: String] = ["CFBundleExecutable": "fixture", "CFBundleIdentifier": "com.winmackey.app", "CFBundleShortVersionString": "9.9.9"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        for mode in ["ready", "wrongPID", "timeout", "exit"] {
            let dir = root.appendingPathComponent("process-\(mode)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            setenv("WINMACKEY_FIXTURE_MODE", mode, 1)
            defer { unsetenv("WINMACKEY_FIXTURE_MODE") }
            if mode == "ready" {
                try UpdateInstaller.launchAndWait(app, directory: dir, token: "process-token", timeout: 2)
                let pid = Int32(content(dir.appendingPathComponent("child.pid")))!
                assert(UpdateInstaller.receiptMatches(dir.appendingPathComponent("accepted.json"), pid: pid, token: "process-token"))
            } else {
                expectFailure { try UpdateInstaller.launchAndWait(app, directory: dir, token: "process-token", timeout: 0.15) }
                let pid = Int32(content(dir.appendingPathComponent("child.pid")))!
                assert(kill(pid, 0) == -1 && errno == ESRCH, "Failed child must be stopped and reaped before rollback")
            }
            print("PASS real child process: \(mode)")
        }
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", app.path]
        signer.standardError = FileHandle.nullDevice
        try signer.run()
        signer.waitUntilExit()
        assert(signer.terminationStatus == 0)
        try UpdateInstaller.validateBundle(app, version: "9.9.9")
        expectFailure { try UpdateInstaller.validateBundle(app, version: "9.9.8") }
        var alteredPlist = plist
        alteredPlist["CFBundleIdentifier"] = "other.app"
        try PropertyListSerialization.data(fromPropertyList: alteredPlist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        expectFailure { try UpdateInstaller.validateBundle(app, version: "9.9.9") }
        alteredPlist["CFBundleIdentifier"] = "com.winmackey.app"
        alteredPlist["UnsealedChange"] = "tampered"
        try PropertyListSerialization.data(fromPropertyList: alteredPlist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        expectFailure { try UpdateInstaller.validateBundle(app, version: "9.9.9") }
        print("PASS staged bundle identity/version/codesign validation (signed temporary fixture)")
        // The successful short-lived fixture exits by itself; no app or HID engine is launched.
        try await Task.sleep(nanoseconds: 500_000_000)
        print("update_installer_smoke: PASS (17 scenarios; temporary fixtures only)")
    }
}
