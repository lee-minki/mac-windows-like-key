import Foundation
import Carbon.HIToolbox

@main
struct DeviceScopedMappingSmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true
        let remapper = HIDRemapper.shared
        remapper.resetOperationCounters()
        remapper.takeOwnership()
        remapper.imeTriggerMapping = (src: Int64(kVK_RightCommand), dst: Int64(kVK_F16))

        let internalKeyboard = KeyboardDeviceIdentifier(
            vendorId: 0,
            productId: 0,
            productName: "Apple Internal Keyboard / Trackpad"
        )
        let keysToGo = KeyboardDeviceIdentifier(
            vendorId: 1133,
            productId: 45964,
            productName: "Keys-To-Go 2"
        )

        require(
            KeyboardBindingResolver.resolve(lastActive: nil, connected: [internalKeyboard]) == internalKeyboard,
            "single connected keyboard must be available for Save and Apply without a prior key press"
        )
        require(
            KeyboardBindingResolver.resolve(lastActive: nil, connected: [internalKeyboard, keysToGo]) == nil,
            "multiple connected keyboards must require an explicit last-active device"
        )
        require(
            KeyboardBindingResolver.resolve(lastActive: keysToGo, connected: [internalKeyboard, keysToGo]) == keysToGo,
            "last-active keyboard must win when multiple keyboards are connected"
        )

        let internalProfile = SavedKeyboardProfile(
            name: "맥로컬키보드",
            physicalKeys: [Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)],
            localDesiredKeys: [Int64(kVK_Command), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Control)],
            vdiDesiredKeys: [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)],
            deviceIdentifier: internalKeyboard
        )
        let portableProfile = SavedKeyboardProfile(
            name: "키투고",
            physicalKeys: [Int64(kVK_Control), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Command)],
            localDesiredKeys: [Int64(kVK_Command), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Control)],
            vdiDesiredKeys: [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)],
            deviceIdentifier: keysToGo
        )

        remapper.reapplyMappingLayersSync(
            globalMappings: [:],
            deviceMappings: [
                (device: internalKeyboard, mappings: internalProfile.mappings(for: .localMac)),
                (device: keysToGo, mappings: portableProfile.mappings(for: .localMac))
            ]
        )

        let localCommands = remapper.issuedCommandsForTesting
        require(localCommands.count == 3, "local apply must write one global and two device layers")
        require(!localCommands[0].contains("--matching"), "global layer must be first")
        require(command(for: internalKeyboard, in: localCommands) != nil, "internal device layer missing")
        require(command(for: keysToGo, in: localCommands) != nil, "Keys-To-Go device layer missing")
        require(mappingPairs(in: localCommands[0]).contains(pair(kVK_RightCommand, kVK_F16)), "global F16 relay missing")

        let internalLocal = command(for: internalKeyboard, in: localCommands)!
        let portableLocal = command(for: keysToGo, in: localCommands)!
        require(mappingPairs(in: internalLocal).contains(pair(kVK_Function, kVK_Command)), "internal local Fn to Command missing")
        require(mappingPairs(in: portableLocal).contains(pair(kVK_Control, kVK_Command)), "portable local Control to Command missing")
        require(mappingPairs(in: internalLocal).contains(pair(kVK_RightCommand, kVK_F16)), "internal F16 relay missing")
        require(mappingPairs(in: portableLocal).contains(pair(kVK_RightCommand, kVK_F16)), "portable F16 relay missing")

        let commandCountBeforeVdi = remapper.issuedCommandsForTesting.count
        remapper.reapplyMappingLayersSync(
            globalMappings: [:],
            deviceMappings: [
                (device: internalKeyboard, mappings: internalProfile.mappings(for: .vdi)),
                (device: keysToGo, mappings: portableProfile.mappings(for: .vdi))
            ]
        )

        let vdiCommands = Array(remapper.issuedCommandsForTesting.dropFirst(commandCountBeforeVdi))
        require(vdiCommands.count == 2, "VDI transition must update two changed devices; unchanged global F16 needs no write")
        require(!vdiCommands.contains(where: isEmptyMappingCommand), "VDI transition must not temporarily clear device mappings")

        let internalVdi = command(for: internalKeyboard, in: vdiCommands)!
        let portableVdi = command(for: keysToGo, in: vdiCommands)!
        require(mappingPairs(in: internalVdi).contains(pair(kVK_Function, kVK_Control)), "internal VDI must use Windows Control position")
        require(mappingPairs(in: portableVdi).contains(pair(kVK_Command, kVK_Option)), "portable VDI must use Windows Alt position")
        require(mappingPairs(in: internalVdi).contains(pair(kVK_RightCommand, kVK_F16)), "internal VDI F16 relay missing")
        require(mappingPairs(in: portableVdi).contains(pair(kVK_RightCommand, kVK_F16)), "portable VDI F16 relay missing")

        remapper.restorePreExistingMappingsAndClearInternal()
        remapper.releaseOwnership()
        print("device_scoped_mapping_smoke: PASS")
    }

    private static func command(
        for device: KeyboardDeviceIdentifier,
        in commands: [[String]]
    ) -> [String]? {
        guard let expected = device.hidutilMatchingJSON else { return nil }
        return commands.last { command in
            guard let index = command.firstIndex(of: "--matching"), index + 1 < command.count else {
                return false
            }
            return matchingEquals(command[index + 1], expected) && !isEmptyMappingCommand(command)
        }
    }

    private static func mappingPairs(in command: [String]) -> Set<String> {
        guard let index = command.firstIndex(of: "--set"), index + 1 < command.count,
              let object = jsonObject(command[index + 1]),
              let mappings = object["UserKeyMapping"] as? [[String: Any]] else {
            return []
        }
        return Set(mappings.compactMap { mapping in
            guard let source = mapping["HIDKeyboardModifierMappingSrc"] as? NSNumber,
                  let destination = mapping["HIDKeyboardModifierMappingDst"] as? NSNumber else {
                return nil
            }
            return "\(source.uint64Value)->\(destination.uint64Value)"
        })
    }

    private static func isEmptyMappingCommand(_ command: [String]) -> Bool {
        guard let index = command.firstIndex(of: "--set"), index + 1 < command.count,
              let object = jsonObject(command[index + 1]),
              let mappings = object["UserKeyMapping"] as? [Any] else {
            return false
        }
        return mappings.isEmpty
    }

    private static func jsonObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func matchingEquals(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsObject = jsonObject(lhs), let rhsObject = jsonObject(rhs) else { return false }
        return NSDictionary(dictionary: lhsObject).isEqual(to: rhsObject)
    }

    private static func pair(_ source: Int, _ destination: Int) -> String {
        let sourceUsage = HIDRemapper.keycodeToHIDUsage[Int64(source)]!
        let destinationUsage = HIDRemapper.keycodeToHIDUsage[Int64(destination)]!
        return "\(sourceUsage)->\(destinationUsage)"
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("device_scoped_mapping_smoke: FAIL - \(message)\n", stderr)
            exit(1)
        }
    }
}
