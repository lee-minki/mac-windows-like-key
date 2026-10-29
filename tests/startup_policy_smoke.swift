import Foundation

@main
struct StartupPolicySmoke {
    static func main() {
        let canonical = URL(fileURLWithPath: "/Applications/WinMacKey.app")
        let development = URL(fileURLWithPath: "/tmp/DerivedData/WinMacKey.app")

        guard InstanceLaunchPolicy.decision(
            currentBundleURL: canonical,
            canonicalBundleURL: canonical,
            canonicalBundleExists: true,
            acquiredInstanceLock: true
        ) == .run else {
            print("startup_policy_smoke: FAIL — canonical installed app should run when it owns the lock")
            exit(1)
        }

        guard InstanceLaunchPolicy.decision(
            currentBundleURL: development,
            canonicalBundleURL: canonical,
            canonicalBundleExists: true,
            acquiredInstanceLock: true
        ) == .yieldToCanonical else {
            print("startup_policy_smoke: FAIL — non-standard copy should yield to /Applications")
            exit(1)
        }

        guard InstanceLaunchPolicy.decision(
            currentBundleURL: canonical,
            canonicalBundleURL: canonical,
            canonicalBundleExists: true,
            acquiredInstanceLock: false
        ) == .yieldToExisting else {
            print("startup_policy_smoke: FAIL — second canonical process should yield to the lock owner")
            exit(1)
        }

        let suiteName = "WinMacKey.StartupPolicySmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("startup_policy_smoke: FAIL — could not create isolated defaults")
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard StartupDefaults.autoCheckUpdates(in: defaults) else {
            print("startup_policy_smoke: FAIL — update checks should default to enabled")
            exit(1)
        }
        defaults.set(false, forKey: StartupDefaults.autoCheckUpdatesKey)
        guard !StartupDefaults.autoCheckUpdates(in: defaults) else {
            print("startup_policy_smoke: FAIL — explicit opt-out should be preserved")
            exit(1)
        }
        defaults.set(true, forKey: StartupDefaults.autoCheckUpdatesKey)
        guard StartupDefaults.autoCheckUpdates(in: defaults) else {
            print("startup_policy_smoke: FAIL — explicit opt-in should be preserved")
            exit(1)
        }

        let normalLaunch = StartupReadiness(isManagedUpdate: false)
        assert(normalLaunch.canStartEngine)
        var updateLaunch = StartupReadiness(isManagedUpdate: true)
        assert(!updateLaunch.canStartEngine, "Update candidate must not remap before readiness")
        updateLaunch.acknowledge(false)
        assert(!updateLaunch.canStartEngine, "Failed acknowledgement must keep engine stopped")
        updateLaunch.acknowledge(true)
        assert(updateLaunch.canStartEngine, "Accepted candidate may start engine")

        print("startup_policy_smoke: PASS (10 invariants)")
    }
}
