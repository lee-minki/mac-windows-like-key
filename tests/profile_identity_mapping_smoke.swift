import Foundation
import Carbon.HIToolbox

// A profile-owned slot must honor its identity target across contexts, while
// always-identity slots retain external mappings. No physical keyboard is used.
private final class IdentityMappingBackend: HIDMappingBackend {
    var mappings: [UInt64: UInt64]
    init(_ mappings: [UInt64: UInt64]) { self.mappings = mappings }
    func resolve(matching: String?) throws -> [String] { ["service:identity-test"] }
    func read(matching: String?) throws -> [UInt64: UInt64] { mappings }
    func write(_ mappings: [UInt64: UInt64], matching: String?) throws { self.mappings = mappings }
}

@main
struct ProfileIdentityMappingSmoke {
    private static let control: UInt64 = 0x7000000E0
    private static let option: UInt64 = 0x7000000E2
    private static let command: UInt64 = 0x7000000E3
    private static let rightCommand: UInt64 = 0x7000000E7
    private static let f16: UInt64 = 0x70000006B
    private static let foreign: UInt64 = 0x700000004
    private static var failures = 0

    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = false
        let device = KeyboardDeviceIdentifier(vendorId: 8137, productId: 59591, productName: "Gaming Keyboard")
        let profile = SavedKeyboardProfile(
            name: "explicit VDI identity regression",
            legendStyle: .windows,
            keyboardLayout: .win3key,
            physicalKeys: [59, 58, 55],
            localDesiredKeys: [55, 58, 59],
            vdiDesiredKeys: [59, 55, 58],
            deviceIdentifier: device
        )

        for startsInLocal in [false, true] {
            for staleBaseline in [false, true] {
                var baseline = [foreign: option]
                if staleBaseline { baseline[control] = command }
                let backend = IdentityMappingBackend(baseline)
                let remapper = HIDRemapper(backend: backend)
                remapper.takeOwnership()
                remapper.imeTriggerMapping = (src: Int64(kVK_RightCommand), dst: Int64(kVK_F16))
                if startsInLocal {
                    remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, profile.mappings(for: .localMac))])
                    check(backend.mappings[control] == command, "local profile maps Control to Command")
                }
                remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, profile.mappings(for: .vdi))])
                let label = "\(startsInLocal ? "local-to-VDI" : "direct VDI"), \(staleBaseline ? "stale baseline" : "clean baseline")"
                let actualControl = backend.mappings[control] ?? control
                check(actualControl == control, "\(label): saved Control identity must override baseline; actual=0x\(String(actualControl, radix: 16))")
                check(backend.mappings[option] == command && backend.mappings[command] == option, "\(label): other VDI targets maintained")
                check(backend.mappings[rightCommand] == f16, "\(label): F16 relay maintained")
                check(backend.mappings[foreign] == option, "\(label): unrelated mapping preserved")
                remapper.internalClearAllForTermination()
                check(backend.mappings == baseline, "\(label): exact pre-activation mappings restored")
            }
        }

        let backend = IdentityMappingBackend([control: command, foreign: option])
        let remapper = HIDRemapper(backend: backend)
        remapper.takeOwnership()
        remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, profile.mappings(for: .vdi))])
        backend.mappings[control] = option // Another tool changes this source after apply.
        backend.mappings[foreign] = command
        remapper.internalClearAllForTermination()
        check(backend.mappings[control] == option && backend.mappings[foreign] == command, "cleanup preserves intervening same-source and unrelated external changes")

        koreanOnlyPreservesModifiers(device)
        localIdentityAndUnownedSlot(device)

        if failures > 0 {
            fputs("profile_identity_mapping_smoke: FAIL (\(failures) expectations; injected backend only, no system HID writes)\n", stderr)
            exit(1)
        }
        print("profile_identity_mapping_smoke: PASS (injected backend only, no system HID writes)")
    }

    private static func koreanOnlyPreservesModifiers(_ device: KeyboardDeviceIdentifier) {
        let identity: [Int64] = [59, 58, 55]
        let profile = SavedKeyboardProfile(
            name: "Korean/English only",
            physicalKeys: identity,
            localDesiredKeys: identity,
            vdiDesiredKeys: identity,
            deviceIdentifier: device
        )
        check(profile.mappings(for: .localMac).isEmpty && profile.mappings(for: .vdi).isEmpty,
              "Korean/English-only profile owns no modifier slots")
        let baseline = [control: command, option: control, foreign: option]
        let backend = IdentityMappingBackend(baseline)
        let remapper = HIDRemapper(backend: backend)
        remapper.takeOwnership()
        remapper.imeTriggerMapping = (src: Int64(kVK_RightCommand), dst: Int64(kVK_F16))
        for context in [KeyboardUsageContext.localMac, .vdi] {
            remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, profile.mappings(for: context))])
            var expected = baseline
            expected[rightCommand] = f16
            check(backend.mappings == expected, "Korean/English-only \(context) preserves foreign modifiers and only adds F16")
        }
        remapper.internalClearAllForTermination()
        check(backend.mappings == baseline, "Korean/English-only stop restores exact baseline")
    }

    private static func localIdentityAndUnownedSlot(_ device: KeyboardDeviceIdentifier) {
        let profile = SavedKeyboardProfile(
            name: "VDI-only Control remap",
            physicalKeys: [59, 58],
            localDesiredKeys: [59, 58],
            vdiDesiredKeys: [55, 58],
            deviceIdentifier: device
        )
        check(profile.mappings(for: .localMac) == [59: 59], "local context explicitly owns identity only for the VDI-remapped slot")
        check(profile.mappings(for: .vdi) == [59: 55], "always-identity Option slot is excluded in both contexts")
        let baseline = [control: command, option: command]
        let backend = IdentityMappingBackend(baseline)
        let remapper = HIDRemapper(backend: backend)
        remapper.takeOwnership()
        for context in [KeyboardUsageContext.localMac, .vdi, .localMac] {
            remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, profile.mappings(for: context))])
            let expectedControl = context == .localMac ? control : command
            check(backend.mappings[control] == expectedControl, "opposite-context mapping honors \(context) target over stale baseline")
            check(backend.mappings[option] == command, "always-identity Option retains foreign mapping in \(context)")
        }
        remapper.internalClearAllForTermination()
        check(backend.mappings == baseline, "opposite-context identity restores exact baseline on stop")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { print("PASS: \(message)") }
        else { failures += 1; fputs("FAIL: \(message)\n", stderr) }
    }
}
