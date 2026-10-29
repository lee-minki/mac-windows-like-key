import Foundation
import Carbon.HIToolbox

@main
struct ProfileStoreBindingSmoke {
    private enum Failure: Error { case assertion(String) }

    static func main() {
        do {
            try run()
            print("profile_store_binding_smoke: PASS (13 scenarios; isolated defaults, no HID)")
        } catch {
            fputs("profile_store_binding_smoke: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let suiteName = "WinMacKey.ProfileStoreBindingSmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure.assertion("could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([SavedKeyboardProfile]()), forKey: "savedKeyboardProfiles")
        defaults.set(try JSONEncoder().encode(IgnoredDevices.empty), forKey: "ignoredKeyboardDevices")
        defaults.set("untouched", forKey: "unrelatedPreference")

        let internalDevice = KeyboardDeviceIdentifier(vendorId: 0, productId: 0,
                                                      productName: "Apple Internal Keyboard / Trackpad")
        let external = KeyboardDeviceIdentifier(vendorId: 1133, productId: 45890, productName: "Keyboard K380")
        let renamedExternal = KeyboardDeviceIdentifier(vendorId: 1133, productId: 45890, productName: "K380")
        let otherDevice = KeyboardDeviceIdentifier(vendorId: 1133, productId: 45964, productName: "Keys-To-Go 2")
        let internalProfile = makeProfile("internal", device: internalDevice)
        let old = makeProfile("old", device: external)
        let other = makeProfile("other", device: otherDevice)
        let store = KeyboardProfileStore(defaults: defaults)
        store.add(internalProfile)
        store.add(old)
        store.add(other)

        var callbackSnapshots: [[SavedKeyboardProfile]] = []
        var persistedSnapshots: [[SavedKeyboardProfile]] = []
        store.onMappingConfigurationChanged = { [weak store] _ in
            guard let store else { return }
            callbackSnapshots.append(store.profiles)
            let data = defaults.data(forKey: "savedKeyboardProfiles") ?? Data()
            persistedSnapshots.append((try? JSONDecoder().decode([SavedKeyboardProfile].self, from: data)) ?? [])
        }

        // 1. Creating a new profile for an already-bound model selects the new
        // profile even if the reported product name differs (same VID:PID).
        var replacement = makeProfile("replacement", device: renamedExternal)
        replacement.localDesiredKeys = replacement.physicalKeys
        store.add(replacement)
        try require(store.profile(forDevice: external)?.id == replacement.id,
                    "new profile must replace the old VID:PID binding")
        var unboundOld = old
        unboundOld.deviceIdentifier = nil
        try require(store.profile(idString: old.id.uuidString) == unboundOld,
                    "transfer must retain every old profile field except its binding")
        try require(callbackSnapshots.count == 1 && callbackSnapshots.last == store.profiles,
                    "add must notify once with final binding state")

        // 2. Unrelated devices retain both local and VDI mappings and all data.
        try require(store.profile(idString: internalProfile.id.uuidString) == internalProfile,
                    "internal profile changed during external transfer")
        try require(store.profile(idString: other.id.uuidString) == other,
                    "unrelated external profile changed during transfer")
        try require(store.profile(forDevice: external)?.mappings(for: .localMac) == replacement.mappings(for: .localMac)
                    && store.profile(forDevice: external)?.mappings(for: .vdi) == replacement.mappings(for: .vdi),
                    "selected device must use the replacement's distinct context mappings")

        // 3. An existing unbound profile can claim this device via update.
        var rebound = unboundOld
        rebound.deviceIdentifier = external
        let callbacksBeforeUpdate = callbackSnapshots.count
        store.update(rebound)
        try require(store.profile(forDevice: renamedExternal)?.id == rebound.id,
                    "update must transfer equivalent-name device binding")
        try require(store.profile(idString: replacement.id.uuidString)?.deviceIdentifier == nil,
                    "update left the previous owner bound")
        try require(callbackSnapshots.count == callbacksBeforeUpdate + 1,
                    "update must notify only once")

        // 4. Editing the same bound profile keeps ownership and other devices.
        rebound.name = "edited"
        rebound.localDesiredKeys = rebound.physicalKeys
        store.update(rebound)
        try require(store.profile(forDevice: external) == rebound,
                    "editing a bound profile lost its device or edited layout")
        try require(store.profile(forDevice: internalDevice) == internalProfile,
                    "bound edit changed internal keyboard")

        // 5. Rebinding to another device releases the old model and transfers
        // only the newly selected model's ownership.
        rebound.deviceIdentifier = otherDevice
        store.update(rebound)
        try require(store.profile(forDevice: external) == nil,
                    "rebind left the old model attached")
        try require(store.profile(forDevice: otherDevice) == rebound,
                    "rebind did not select the target model")
        var unboundOther = other
        unboundOther.deviceIdentifier = nil
        try require(store.profile(idString: other.id.uuidString) == unboundOther,
                    "rebind discarded old owner's layout or metadata")

        // 6. Adding or editing a global (nil binding) profile never claims a device.
        var global = makeProfile("global", device: nil)
        store.add(global)
        global.name = "global edited"
        store.update(global)
        try require(store.profile(forDevice: internalDevice) == internalProfile
                    && store.profile(forDevice: otherDevice) == rebound,
                    "nil binding disturbed device owners")

        // 7. Removing a binding and updating a missing ID are safe operations.
        rebound.deviceIdentifier = nil
        store.update(rebound)
        try require(store.profile(forDevice: otherDevice) == nil,
                    "explicit unbind did not release the device")
        let beforeMissing = store.profiles
        let beforeMissingCallbacks = callbackSnapshots.count
        store.update(makeProfile("not saved", device: internalDevice))
        try require(store.profiles == beforeMissing && callbackSnapshots.count == beforeMissingCallbacks,
                    "unknown profile update changed persisted state or emitted callback")

        // 8. Every callback saw the final persisted state; loading is read-only.
        try require(callbackSnapshots == persistedSnapshots,
                    "callback ran before normalized profiles were persisted")
        try require(callbackSnapshots.allSatisfy(uniqueBindings),
                    "callback exposed duplicate bindings")
        let storedData = defaults.data(forKey: "savedKeyboardProfiles")
        let reloaded = KeyboardProfileStore(defaults: defaults)
        try require(reloaded.profiles == store.profiles && defaults.data(forKey: "savedKeyboardProfiles") == storedData,
                    "reload changed profile data or persistence")
        try require(defaults.string(forKey: "unrelatedPreference") == "untouched",
                    "store changed an unrelated preference")

        // 9. Legacy duplicates retain their current first-match behavior until
        // an explicit save. Loading must not silently migrate or unbind them.
        let legacy = [internalProfile, old, replacement, other]
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "savedKeyboardProfiles")
        let legacyStore = KeyboardProfileStore(defaults: defaults)
        try require(legacyStore.profiles == legacy && legacyStore.profile(forDevice: external)?.id == old.id,
                    "legacy load changed the first-applied profile")
        try require(defaults.data(forKey: "savedKeyboardProfiles") == legacyData,
                    "legacy load rewrote existing preferences")
        var legacySelection = old.id.uuidString
        var displacedCallbacks: [Set<UUID>] = []
        legacyStore.onMappingConfigurationChanged = { displaced in
            displacedCallbacks.append(displaced)
            legacySelection = ProfileActivationPolicy.preservingGlobalSelection(
                legacySelection, displacedDeviceProfiles: displaced
            )
        }
        legacyStore.update(replacement)
        try require(legacyStore.profile(forDevice: external)?.id == replacement.id
                    && legacyStore.profile(idString: old.id.uuidString) == unboundOld,
                    "explicit save failed to resolve legacy duplicates")
        try require(KeyboardProfileStore(defaults: defaults).profiles == legacyStore.profiles,
                    "resolved legacy binding did not survive reload")
        try require(displacedCallbacks == [Set([old.id])] && legacySelection == "standardMac",
                    "legacy bound selection became a global layout during transfer")
        try require(ProfileActivationPolicy.globalSelection(
            applying: replacement, current: legacySelection,
            currentProfile: legacyStore.profile(idString: legacySelection)
        ) == "standardMac", "applying the replacement changed the effective global fallback")

        // 10. Dependency injection also covers ignored-device persistence.
        legacyStore.ignore(otherDevice)
        try require(KeyboardProfileStore(defaults: defaults).isIgnored(otherDevice),
                    "ignored device was not saved to the injected defaults")
        legacyStore.unignore(otherDevice)
        try require(!KeyboardProfileStore(defaults: defaults).isIgnored(otherDevice),
                    "unignore did not update the injected defaults")

        // 11. Unedited portable defaults are resolved identically for preview
        // and persistence; Ctrl/Cmd follow the recommendation, not identity.
        let layout = KeyboardLayout.portableMac4key
        let preview = KeyboardMappingResolution.targets(
            physicalKeys: layout.physicalKeys, defaults: layout.localDefaults, overrides: [:]
        )
        try require(preview == layout.localDefaults && preview != layout.physicalKeys,
                    "portable preview does not show the values that will be saved")

        // 12. Explicit identity choices survive edit/preview/save even when
        // recommended defaults would swap Ctrl and Cmd. VDI stays independent.
        let identityOverrides: [Int64: Int64] = [Int64(kVK_Control): Int64(kVK_Control),
                                                Int64(kVK_Command): Int64(kVK_Command)]
        let savedLocal = KeyboardMappingResolution.targets(
            physicalKeys: layout.physicalKeys, defaults: layout.localDefaults, overrides: identityOverrides
        )
        let restoredOverrides = KeyboardMappingResolution.overrides(
            physicalKeys: layout.physicalKeys, defaults: layout.localDefaults, desiredKeys: savedLocal
        )
        try require(restoredOverrides == identityOverrides, "editing discarded explicit identity overrides")
        try require(KeyboardMappingResolution.targets(
            physicalKeys: layout.physicalKeys, defaults: layout.localDefaults, overrides: restoredOverrides
        ) == savedLocal, "edit/save changed the saved portable local layout")
        let restoredVdi = KeyboardMappingResolution.overrides(
            physicalKeys: layout.physicalKeys, defaults: layout.vdiDefaults, desiredKeys: layout.vdiDefaults
        )
        try require(KeyboardMappingResolution.targets(
            physicalKeys: layout.physicalKeys, defaults: layout.vdiDefaults, overrides: restoredVdi
        ) == layout.vdiDefaults, "local identity editing changed VDI defaults")

        // 13. Applying a device profile keeps a genuine custom global profile
        // (or built-in preset) for keyboards without a binding.
        try require(ProfileActivationPolicy.globalSelection(
            applying: replacement, current: global.id.uuidString, currentProfile: global
        ) == global.id.uuidString, "device save replaced the custom global profile")
        try require(ProfileActivationPolicy.preservingGlobalSelection(
            global.id.uuidString, displacedDeviceProfiles: Set([old.id])
        ) == global.id.uuidString, "transfer reset an unrelated global profile")
        try require(ProfileActivationPolicy.globalSelection(
            applying: replacement, current: "windowsBluetooth", currentProfile: nil
        ) == "windowsBluetooth", "device save replaced the built-in global preset")
        try require(ProfileActivationPolicy.globalSelection(
            applying: replacement, current: old.id.uuidString, currentProfile: old
        ) == "standardMac", "legacy bound selection lost its standard global fallback")
        try require(ProfileActivationPolicy.globalSelection(
            applying: global, current: "standardMac", currentProfile: nil
        ) == global.id.uuidString, "explicit global application was blocked")
    }

    private static func makeProfile(_ name: String, device: KeyboardDeviceIdentifier?) -> SavedKeyboardProfile {
        SavedKeyboardProfile(
            name: name,
            keyboardLayout: .portableMac4key,
            physicalKeys: [Int64(kVK_Control), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Command)],
            localDesiredKeys: [Int64(kVK_Command), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Control)],
            vdiDesiredKeys: [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)],
            auxiliaryFnKey: Int64(kVK_RightControl),
            bundleId: "example.profile.\(name)",
            deviceIdentifier: device
        )
    }

    private static func uniqueBindings(_ profiles: [SavedKeyboardProfile]) -> Bool {
        let keys = profiles.compactMap { $0.deviceIdentifier?.matchingKey }
        return Set(keys).count == keys.count
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.assertion(message) }
    }
}
