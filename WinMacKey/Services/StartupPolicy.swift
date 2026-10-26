import Foundation
import AppKit
import Darwin

enum InstanceLaunchDecision: Equatable {
    case run
    case yieldToCanonical
    case yieldToExisting
}

enum InstanceLaunchPolicy {
    static func decision(
        currentBundleURL: URL,
        canonicalBundleURL: URL,
        canonicalBundleExists: Bool,
        acquiredInstanceLock: Bool
    ) -> InstanceLaunchDecision {
        let current = currentBundleURL.resolvingSymlinksInPath().standardizedFileURL
        let canonical = canonicalBundleURL.resolvingSymlinksInPath().standardizedFileURL

        if canonicalBundleExists && current != canonical {
            return .yieldToCanonical
        }
        return acquiredInstanceLock ? .run : .yieldToExisting
    }
}

enum StartupDefaults {
    static let autoCheckUpdatesKey = "AutoCheckUpdates"

    static func autoCheckUpdates(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: autoCheckUpdatesKey) != nil else { return true }
        return defaults.bool(forKey: autoCheckUpdatesKey)
    }
}

final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    static let canonicalBundleURL = URL(fileURLWithPath: "/Applications/WinMacKey.app", isDirectory: true)
    static let developmentOverrideEnvironmentKey = "WINMACKEY_ALLOW_NONSTANDARD_INSTANCE"

    private(set) var decision: InstanceLaunchDecision = .run
    private var lockFileDescriptor: Int32 = -1
    private var didPrepare = false

    private init() {}

    deinit {
        releaseLock()
    }

    @discardableResult
    func prepareForLaunch(
        currentBundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard !didPrepare else { return decision == .run }
        didPrepare = true

        let allowsNonstandardInstance = environment[Self.developmentOverrideEnvironmentKey] == "1"
        let canonicalExists = !allowsNonstandardInstance
            && fileManager.fileExists(atPath: Self.canonicalBundleURL.path)

        if InstanceLaunchPolicy.decision(
            currentBundleURL: currentBundleURL,
            canonicalBundleURL: Self.canonicalBundleURL,
            canonicalBundleExists: canonicalExists,
            acquiredInstanceLock: true
        ) == .yieldToCanonical {
            decision = .yieldToCanonical
            return false
        }

        guard acquireLock(fileManager: fileManager) else {
            decision = .yieldToExisting
            return false
        }

        decision = .run
        return true
    }

    func activatePreferredInstance() {
        switch decision {
        case .run:
            return
        case .yieldToCanonical:
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(
                at: Self.canonicalBundleURL,
                configuration: configuration,
                completionHandler: nil
            )
        case .yieldToExisting:
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first { $0.processIdentifier != getpid() }?
                .activate(options: [.activateAllWindows])
        }
    }

    private func acquireLock(fileManager: FileManager) -> Bool {
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return false }

        let directoryURL = appSupportURL.appendingPathComponent("WinMacKey", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let lockURL = directoryURL.appendingPathComponent("instance.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
        return true
    }

    private func releaseLock() {
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }
}
