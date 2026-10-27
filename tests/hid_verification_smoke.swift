import Foundation

final class FakeHIDBackend: HIDMappingBackend {
    var maps: [String: [UInt64: UInt64]] = [:]
    var resolved: [String: [String]] = [:]
    var reads = 0
    var writes: [(String, [UInt64: UInt64])] = []
    var failReadNumbers: Set<Int> = []
    var failWrites = false
    var ignoreWrites = false
    var unavailableScopes: Set<String> = []

    func resolve(matching: String?) throws -> [String] {
        guard let matching else { return resolved["global"] ?? ["global"] }
        if let direct = resolved[matching] { return direct }
        if let object = try? JSONSerialization.jsonObject(with: Data(matching.utf8)) as? NSDictionary {
            for (key, scopes) in resolved {
                if let other = try? JSONSerialization.jsonObject(with: Data(key.utf8)) as? NSDictionary, object == other { return scopes }
            }
        }
        return [matching]
    }
    func read(matching: String?) throws -> [UInt64: UInt64] {
        reads += 1
        if unavailableScopes.contains(matching ?? "global") { throw HIDMappingError.serviceUnavailable }
        if failReadNumbers.contains(reads) { throw HIDMappingError.invalidOutput }
        return maps[matching ?? "global"] ?? [:]
    }
    func write(_ mappings: [UInt64: UInt64], matching: String?) throws {
        let scope = matching ?? "global"
        writes.append((scope, mappings))
        if failWrites { throw HIDMappingError.commandFailed(1) }
        if !ignoreWrites { maps[scope] = mappings }
    }
}

@main
struct HIDVerificationSmoke {
    static let command: UInt64 = 0x7000000E3
    static let control: UInt64 = 0x7000000E0
    static let option: UInt64 = 0x7000000E2
    static let rightCommand: UInt64 = 0x7000000E7
    static let f16: UInt64 = 0x70000006B
    static let foreign: UInt64 = 0x700000004
    static var scenarios = 0

    static func main() throws {
        HIDRemapper.skipExternalHidutilCallsForTesting = false
        try parser()
        serviceSelection()
        ownershipAndPreservation()
        readFailure()
        writeFailure()
        mismatch()
        pendingReadback()
        restoreFailureRetry()
        externalChanges()
        scopeIsolationAndLayout()
        reconnect()
        print("hid_verification_smoke: PASS (\(scenarios) scenarios; injected backend only, no system HID writes)")
    }
    static func make(_ backend: FakeHIDBackend) -> HIDRemapper {
        let remapper = HIDRemapper(backend: backend)
        remapper.takeOwnership()
        return remapper
    }
    static func require(_ condition: @autoclosure () -> Bool, _ text: String) {
        guard condition() else { fatalError("hid_verification_smoke: FAIL - \(text)") }
    }
    static func pass(_ name: String) { scenarios += 1; print("PASS: \(name)") }

    static func parser() throws {
        let plist = "({ HIDKeyboardModifierMappingDst = 30064771296; HIDKeyboardModifierMappingSrc = 30064771299; }, { HIDKeyboardModifierMappingDst = 30064771179; HIDKeyboardModifierMappingSrc = 30064771303; })"
        let reversed = "[{\"HIDKeyboardModifierMappingSrc\":30064771303,\"HIDKeyboardModifierMappingDst\":30064771179},{\"HIDKeyboardModifierMappingSrc\":30064771299,\"HIDKeyboardModifierMappingDst\":30064771296}]"
        require(tryParse(plist) == [command: control, rightCommand: f16], "old plist uses full 64-bit usages")
        require(tryParse(plist) == tryParse(reversed), "semantic equality ignores array order")
        require(tryParse("(null)") == [:], "explicit null is empty")
        require(tryParse("()") == [:], "empty plist is empty")
        require(tryParse("") == nil && tryParse("unexpected error") == nil, "failed/malformed output must not become empty")
        require(tryParse("({ HIDKeyboardModifierMappingSrc = nope; HIDKeyboardModifierMappingDst = 3; })") == nil, "invalid usage rejected")
        require(tryParse("[{\"HIDKeyboardModifierMappingSrc\":1,\"HIDKeyboardModifierMappingDst\":2},{\"HIDKeyboardModifierMappingSrc\":1,\"HIDKeyboardModifierMappingDst\":3}]") == nil, "ambiguous duplicate sources rejected")
        pass("plist/JSON parsing, 64-bit values, unordered comparison, malformed output")
    }
    static func tryParse(_ value: String) -> [UInt64: UInt64]? { try? SystemHIDMappingBackend.parse(Data(value.utf8)) }

    static func serviceSelection() {
        require(SystemHIDMappingBackend.isMappingTarget(isKeyboard: true, primaryUsagePage: 1), "retain keyboard service")
        require(SystemHIDMappingBackend.isMappingTarget(isKeyboard: false, primaryUsagePage: 0xFF00), "retain Apple vendor Fn service")
        require(!SystemHIDMappingBackend.isMappingTarget(isKeyboard: false, primaryUsagePage: 13), "exclude pure trackpad under same Product selector")
        require(SystemHIDMappingBackend.isMappingTarget(isKeyboard: true, primaryUsagePage: 13), "mixed keyboard service must remain eligible")
        require(SystemHIDMappingBackend.isMappingTarget(isKeyboard: false, primaryUsagePage: nil), "unknown service cannot be assumed a digitizer")
        pass("observed keyboard/vendor/trackpad metadata selects keyboard and Fn, excludes pure digitizer")
    }

    static func ownershipAndPreservation() {
        let backend = FakeHIDBackend()
        backend.maps["global"] = [foreign: option, command: option]
        let remapper = HIDRemapper(backend: backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        require(backend.reads == 0 && backend.writes.isEmpty, "engine off cannot read or write")
        remapper.takeOwnership()
        remapper.applyMappingsSync([0x37: 0x3B])
        require(backend.maps["global"] == [foreign: option, command: control], "preserve foreign source during apply")
        require(remapper.diagnosticSnapshot.status == .verified, "readback verified")
        remapper.releaseOwnership()
        remapper.internalClearAllForTermination()
        require(backend.maps["global"] == [foreign: option, command: option], "restore original overwritten value")
        let count = backend.writes.count
        remapper.internalClearAllForTermination()
        require(backend.writes.count == count, "successful cleanup idempotent")
        pass("engine ownership, foreign entries, exact original restoration, idempotence")
    }
    static func readFailure() {
        let backend = FakeHIDBackend()
        backend.maps["global"] = [foreign: option]
        backend.failReadNumbers = [1]
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        require(backend.writes.isEmpty, "failed pre-read must never write")
        require(remapper.diagnosticSnapshot.status == .failed && remapper.diagnosticSnapshot.lastError != nil, "read failure visible")
        require(backend.maps["global"] == [foreign: option], "failed read preserves existing mappings")
        pass("failed initial read aborts without destructive fallback")
    }
    static func writeFailure() {
        let backend = FakeHIDBackend()
        backend.maps["global"] = [command: option]
        backend.failWrites = true
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        require(remapper.diagnosticSnapshot.status == .failed, "write failure visible")
        require(backend.maps["global"] == [command: option], "write failure leaves original")
        backend.failWrites = false
        remapper.internalClearAllForTermination()
        require(backend.maps["global"] == [command: option], "cleanup does not erase untouched original")
        pass("write failure preserves original and supports safe cleanup")
    }
    static func mismatch() {
        let backend = FakeHIDBackend()
        backend.ignoreWrites = true
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        require(remapper.diagnosticSnapshot.status == .failed, "exit success with no applied value is failure")
        require(remapper.diagnosticSnapshot.pendingScopeCount == 1, "mismatch remains diagnosable")
        backend.ignoreWrites = false
        remapper.applyMappingsSync([0x37: 0x3B])
        require(remapper.diagnosticSnapshot.status == .verified, "successful retry clears failure")
        pass("silent write mismatch detected; successful retry verified")
    }
    static func pendingReadback() {
        let backend = FakeHIDBackend()
        backend.maps["global"] = [command: option, foreign: option]
        backend.failReadNumbers = [2]
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        require(backend.maps["global"]?[command] == control, "write happened before failed readback")
        require(remapper.diagnosticSnapshot.status == .failed, "failed readback does not claim success")
        remapper.internalClearAllForTermination()
        require(backend.maps["global"] == [command: option, foreign: option], "pending ownership retained for cleanup")
        pass("write-success/readback-failure retains undo ownership")
    }
    static func restoreFailureRetry() {
        let backend = FakeHIDBackend()
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        backend.failReadNumbers = [backend.reads + 1]
        let before = backend.writes.count
        remapper.internalClearAllForTermination()
        require(backend.writes.count == before, "restore read failure never blindly clears")
        require(remapper.diagnosticSnapshot.status == .failed, "restore failure diagnosed")
        remapper.internalClearAllForTermination()
        require(backend.maps["global"] == [:], "retry preserves ownership and restores")
        pass("failed restoration retains ownership for retry without blanket clear")
    }
    static func externalChanges() {
        let backend = FakeHIDBackend()
        backend.maps["global"] = [command: option]
        let remapper = make(backend)
        remapper.applyMappingsSync([0x37: 0x3B])
        backend.maps["global"] = [command: f16, foreign: control]
        remapper.internalClearAllForTermination()
        require(backend.maps["global"] == [command: f16, foreign: control], "stop preserves intervening foreign edits")
        remapper.applyMappingsSync([0x37: 0x3B])
        remapper.internalClearAllForTermination()
        require(backend.maps["global"]?[command] == f16, "new lifecycle captures latest original")
        pass("foreign same-source and unrelated edits survive cleanup")
    }
    static func scopeIsolationAndLayout() {
        let backend = FakeHIDBackend()
        let device = KeyboardDeviceIdentifier(vendorId: 1133, productId: 45964, productName: "Keys-To-Go 2")
        backend.resolved["global"] = ["service:1", "service:2", "service:3"]
        backend.resolved[device.hidutilMatchingJSON!] = ["service:2", "service:3"]
        let baseline: [String: [UInt64: UInt64]] = ["service:1": [foreign: control], "service:2": [command: option], "service:3": [:]]
        backend.maps = baseline
        let remapper = make(backend)
        remapper.imeTriggerMapping = (src: 0x36, dst: 0x6A)
        remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, [0x3B: 0x37, 0x37: 0x3B])])
        require(backend.writes.count == 3, "one write per concrete service, no global overwrite")
        require(backend.maps["service:1"] == [foreign: control, rightCommand: f16], "unbound default layer keeps F16 and unrelated map")
        require(backend.maps["service:2"]?[command] == control && backend.maps["service:3"]?[command] == control, "same model services receive same target")
        let before = backend.writes.count
        remapper.reapplyMappingLayersSync(globalMappings: [:], deviceMappings: [(device, [0x3F: 0x37, 0x3A: 0x37, 0x37: 0x3A])])
        require(backend.writes.count == before + 2, "VDI transition updates only changed services, no empty gaps")
        require(backend.maps.values.allSatisfy { $0[rightCommand] == f16 }, "F16 present throughout all layers")
        require(backend.maps["service:2"]?[command] == option, "VDI Command-position to Alt unchanged")
        remapper.internalClearAllForTermination()
        require(backend.maps == baseline, "distinct originals of same-selector services restored separately")
        pass("global/device plan, multiple services, unchanged F16 and VDI layout, distinct baseline restoration")
    }
    static func reconnect() {
        let backend = FakeHIDBackend()
        backend.resolved["global"] = ["service:old"]
        backend.maps["service:old"] = [command: option]
        let remapper = make(backend)
        remapper.reapplyMappingLayersSync(globalMappings: [0x37: 0x3B], deviceMappings: [])
        backend.unavailableScopes.insert("service:old")
        backend.resolved["global"] = ["service:new"]
        backend.maps["service:new"] = [command: f16]
        remapper.reapplyMappingLayersSync(globalMappings: [0x37: 0x3B], deviceMappings: [])
        require(remapper.diagnosticSnapshot.status == .verified, "disconnected old registry must not remain a permanent failure")
        remapper.internalClearAllForTermination()
        require(backend.maps["service:new"] == [command: f16], "reconnected registry restores its own baseline")
        require(!backend.writes.dropFirst().contains { $0.0 == "service:old" }, "no stale writes to disconnected registry")
        pass("disconnect/reconnect new registry gets independent ownership, stale record discarded")
    }
}
