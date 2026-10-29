import Foundation
import Darwin

enum UpdateInstallFailure: LocalizedError {
    case invalidRequest
    case parentStillRunning
    case candidateNotReady
    case candidateStillRunning
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "업데이트 설치 요청을 검증하지 못했습니다."
        case .parentStillRunning: return "기존 앱이 종료되지 않아 업데이트를 취소했습니다."
        case .candidateNotReady: return "새 앱의 시작을 확인하지 못해 이전 앱을 복원했습니다."
        case .candidateStillRunning: return "새 앱을 종료하지 못했습니다. 이전 앱 백업을 보존했습니다."
        case .recoveryFailed(let detail): return "업데이트 복원 실패: \(detail)"
        }
    }
}

/// A failed launch may be rolled back only after the launched process is gone.
struct UpdateReplacement {
    let installed: URL
    let staged: URL
    let backup: URL
    var validate: (URL) throws -> Void
    var launchAndWait: (URL) throws -> Void
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    func perform() throws {
        try validate(staged)
        try move(installed, backup)
        do {
            try move(staged, installed)
            try launchAndWait(installed)
        } catch UpdateInstallFailure.candidateStillRunning {
            // Replacing files underneath a live candidate is unsafe. Keep both copies.
            throw UpdateInstallFailure.candidateStillRunning
        } catch {
            let originalError = error
            do {
                if FileManager.default.fileExists(atPath: installed.path) {
                    try FileManager.default.moveItem(at: installed, to: staged)
                }
                try move(backup, installed)
            } catch {
                throw UpdateInstallFailure.recoveryFailed("\(error.localizedDescription); backup: \(backup.path)")
            }
            throw originalError
        }
        // Cleanup failure must not roll back a healthy, running app.
        try? FileManager.default.removeItem(at: backup)
    }
}

enum UpdateInstaller {
    static let helperArgument = "--winmackey-install-update"
    static let receiptEnvironment = "WINMACKEY_UPDATE_RECEIPT"
    static let tokenEnvironment = "WINMACKEY_UPDATE_TOKEN"

    static var isManagedLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[receiptEnvironment] != nil || environment[tokenEnvironment] != nil
    }

    /// Readiness belongs to one launched PID, never to a later ordinary relaunch.
    static func ordinaryLaunchEnvironment(from environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var result = environment
        result.removeValue(forKey: receiptEnvironment)
        result.removeValue(forKey: tokenEnvironment)
        return result
    }

    struct Request: Codable {
        let installed: URL
        let staged: URL
        let backup: URL
        let expectedVersion: String
        let parentPID: Int32
        let token: String
    }

    struct Receipt: Codable {
        let pid: Int32
        let token: String
    }

    /// Copy the helper outside the bundle before the old process terminates.
    static func prepareHandoff(installed: URL, candidate: URL, version: String) throws -> URL {
        guard let executable = Bundle.main.executableURL, !version.isEmpty else {
            throw UpdateInstallFailure.invalidRequest
        }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("WinMacKey-install-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        let staged = directory.appendingPathComponent("Candidate.app")
        let helper = directory.appendingPathComponent("installer")
        do {
            try fm.copyItem(at: candidate, to: staged)
            try fm.copyItem(at: executable, to: helper)
            let request = Request(installed: installed, staged: staged,
                                  backup: installed.deletingLastPathComponent().appendingPathComponent(".WinMacKey-backup-\(UUID().uuidString).app"),
                                  expectedVersion: version, parentPID: getpid(), token: UUID().uuidString)
            let requestURL = directory.appendingPathComponent("request.json")
            try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
            let process = Process()
            process.executableURL = helper
            process.arguments = [helperArgument, requestURL.path]
            process.environment = ordinaryLaunchEnvironment()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let armed = directory.appendingPathComponent("armed")
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                if let data = try? Data(contentsOf: armed), String(data: data, encoding: .utf8) == request.token { return directory }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
            throw UpdateInstallFailure.invalidRequest
        } catch {
            // No installed app has been touched; parent remains alive on handoff failure.
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    /// Called before SingleInstanceGuard and AppState are constructed.
    static func runHelperIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.dropFirst().first == helperArgument else { return nil }
        guard arguments.count == 3 else { return 1 }
        let requestURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let directory = requestURL.deletingLastPathComponent()
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
            guard request.parentPID > 1, request.parentPID != getpid(),
                  request.installed.deletingLastPathComponent().path == "/Applications",
                  request.installed.pathExtension == "app",
                  request.staged == directory.appendingPathComponent("Candidate.app"),
                  request.backup.deletingLastPathComponent() == request.installed.deletingLastPathComponent(),
                  request.backup.lastPathComponent.hasPrefix(".WinMacKey-backup-"),
                  !FileManager.default.fileExists(atPath: request.backup.path),
                  URL(fileURLWithPath: arguments[0]).standardizedFileURL == directory.appendingPathComponent("installer")
            else { throw UpdateInstallFailure.invalidRequest }
            try validateBundle(request.staged, version: request.expectedVersion)
            try Data(request.token.utf8).write(to: directory.appendingPathComponent("armed"), options: .atomic)
            try waitForParentExit(request.parentPID)
            let replacement = UpdateReplacement(installed: request.installed, staged: request.staged,
                                                backup: request.backup,
                                                validate: { try validateBundle($0, version: request.expectedVersion) },
                                                launchAndWait: { try launchAndWait($0, directory: directory, token: request.token) })
            do {
                try replacement.perform()
            } catch {
                if case UpdateInstallFailure.candidateStillRunning = error { throw error }
                if !FileManager.default.fileExists(atPath: request.backup.path) {
                    // A restored old app receives no readiness environment.
                    let old = Process()
                    old.executableURL = try executableURL(in: request.installed)
                    old.environment = ordinaryLaunchEnvironment()
                    try? old.run()
                }
                throw error
            }
            // The candidate still needs to consume accepted.json before starting its engine.
            // Retain the private handoff directory instead of racing that acknowledgement.
            return 0
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("failure.txt"), options: .atomic)
            return 1
        }
    }

    static func waitForParentExit(_ pid: Int32, timeout: TimeInterval = 60) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while kill(pid, 0) == 0 || errno == EPERM {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw UpdateInstallFailure.parentStillRunning }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard errno == ESRCH else { throw UpdateInstallFailure.parentStillRunning }
    }

    @discardableResult
    static func acknowledgeLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment[receiptEnvironment] == nil && environment[tokenEnvironment] == nil { return true }
        guard let path = environment[receiptEnvironment], !path.isEmpty,
              let token = environment[tokenEnvironment], !token.isEmpty else { return false }
        let receipt = Receipt(pid: getpid(), token: token)
        do {
            try JSONEncoder().encode(receipt).write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func receiptMatches(_ url: URL, pid: Int32, token: String) -> Bool {
        guard let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else { return false }
        return receipt.pid == pid && receipt.token == token
    }

    static func waitForLaunchAcceptance(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 25
    ) async -> Bool {
        if environment[receiptEnvironment] == nil && environment[tokenEnvironment] == nil { return true }
        guard let path = environment[receiptEnvironment], !path.isEmpty,
              let token = environment[tokenEnvironment], !token.isEmpty else { return false }
        let accepted = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("accepted.json")
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !Task.isCancelled && ProcessInfo.processInfo.systemUptime < deadline {
            if receiptMatches(accepted, pid: getpid(), token: token) { return true }
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return false }
        }
        return false
    }

    static func launchAndWait(_ app: URL, directory: URL, token: String, timeout: TimeInterval = 20) throws {
        let child = Process()
        child.executableURL = try executableURL(in: app)
        let receipt = directory.appendingPathComponent("ready.json")
        var environment = ProcessInfo.processInfo.environment
        environment[receiptEnvironment] = receipt.path
        environment[tokenEnvironment] = token
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            if receiptMatches(receipt, pid: child.processIdentifier, token: token), child.isRunning {
                let accepted = Receipt(pid: child.processIdentifier, token: token)
                do {
                    try JSONEncoder().encode(accepted).write(to: directory.appendingPathComponent("accepted.json"), options: .atomic)
                    // From this point the candidate may own HID state. Never terminate or roll back it.
                    return
                } catch {
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if child.isRunning { child.terminate() }
        var stopDeadline = ProcessInfo.processInfo.systemUptime + 2
        while child.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
        if child.isRunning {
            kill(child.processIdentifier, SIGKILL)
            stopDeadline = ProcessInfo.processInfo.systemUptime + 2
            while child.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
        }
        guard !child.isRunning else { throw UpdateInstallFailure.candidateStillRunning }
        child.waitUntilExit()
        throw UpdateInstallFailure.candidateNotReady
    }

    static func executableURL(in app: URL) throws -> URL {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["CFBundleExecutable"] as? String, !name.isEmpty,
              name == URL(fileURLWithPath: name).lastPathComponent else { throw UpdateInstallFailure.invalidRequest }
        return app.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
    }

    static func validateBundle(_ app: URL, version: String) throws {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "com.winmackey.app",
              plist["CFBundleShortVersionString"] as? String == version,
              FileManager.default.isExecutableFile(atPath: try executableURL(in: app).path)
        else { throw UpdateInstallFailure.invalidRequest }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--no-strict", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateInstallFailure.invalidRequest }
    }
}
