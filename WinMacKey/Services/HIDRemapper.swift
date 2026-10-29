import Foundation
import os.log
import IOKit.hidsystem
import IOKit

struct HIDMappingDiagnosticSnapshot {
    enum Status { case notChecked, verified, failed }
    let status: Status
    let lastVerifiedAt: Date?
    let lastError: String?
    let pendingScopeCount: Int
}

protocol HIDMappingBackend {
    func resolve(matching: String?) throws -> [String]
    func read(matching: String?) throws -> [UInt64: UInt64]
    func write(_ mappings: [UInt64: UInt64], matching: String?) throws
}

extension HIDMappingBackend {
    func resolve(matching: String?) throws -> [String] { [matching ?? "global"] }
}

enum HIDMappingError: Error, LocalizedError {
    case invalidOutput, commandFailed(Int32), verificationMismatch, serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidOutput: return "HID 매핑 상태를 읽거나 해석할 수 없습니다."
        case .commandFailed(let status): return "HID 매핑 작업 실패 (상태 \(status))"
        case .verificationMismatch: return "HID 매핑을 다시 읽은 결과가 요청한 값과 다릅니다."
        case .serviceUnavailable: return "연결이 종료된 키보드 서비스입니다."
        }
    }
}

final class SystemHIDMappingBackend: HIDMappingBackend {
    private var client: IOHIDEventSystemClient?
    private var services: [String: IOHIDServiceClient] = [:]

    func resolve(matching: String?) throws -> [String] {
        let newClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let discovered = IOHIDEventSystemClientCopyServices(newClient) as? [IOHIDServiceClient] else {
            throw HIDMappingError.invalidOutput
        }
        services.removeAll()
        client = newClient
        let filter: [String: Any]
        if let matching {
            guard let data = matching.data(using: .utf8),
                  let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HIDMappingError.invalidOutput
            }
            filter = decoded
        } else { filter = [:] }
        var matches: [String] = []
        for service in discovered {
            guard let registryID = IOHIDServiceClientGetRegistryID(service) as? NSNumber else { continue }
            let token = "service:\(registryID.uint64Value)"
            services[token] = service
            let isKeyboard = IOHIDServiceClientConformsTo(service, 1, 6) != 0
            let usagePage = (IOHIDServiceClientCopyProperty(service, "PrimaryUsagePage" as CFString) as? NSNumber)?.uint32Value
            guard Self.isMappingTarget(isKeyboard: isKeyboard, primaryUsagePage: usagePage) else { continue }
            let selected = matching == nil
                ? isKeyboard
                : filter.allSatisfy { key, value in
                    guard let actual = IOHIDServiceClientCopyProperty(service, key as CFString) else { return false }
                    return (actual as AnyObject).isEqual(value)
                }
            if selected { matches.append(token) }
        }
        return matches.sorted()
    }

    /// A Product selector can include the trackpad alongside keyboard and Apple Fn
    /// services. Keep keyboard/vendor services, but don't verify keyboard maps on a pure digitizer.
    static func isMappingTarget(isKeyboard: Bool, primaryUsagePage: UInt32?) -> Bool {
        isKeyboard || primaryUsagePage != 0x0D
    }
    static func arguments(matching: String?, operation: String, value: String) -> [String] {
        var arguments = ["property"]
        if let matching { arguments += ["--matching", matching] }
        return arguments + [operation, value]
    }

    static func json(_ mappings: [UInt64: UInt64]) throws -> String {
        let entries = mappings.keys.sorted().map { source in
            ["HIDKeyboardModifierMappingSrc": source, "HIDKeyboardModifierMappingDst": mappings[source]!]
        }
        let data = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": entries], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ data: Data) throws -> [UInt64: UInt64] {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "(null)" { return [:] }
        let object = (try? PropertyListSerialization.propertyList(from: data, format: nil))
            ?? (try? JSONSerialization.jsonObject(with: data))
        guard let entries = object as? [[String: Any]] else { throw HIDMappingError.invalidOutput }
        var result: [UInt64: UInt64] = [:]
        for entry in entries {
            guard let source = usage(entry["HIDKeyboardModifierMappingSrc"]),
                  let destination = usage(entry["HIDKeyboardModifierMappingDst"]),
                  result[source] == nil else { throw HIDMappingError.invalidOutput }
            result[source] = destination
        }
        return result
    }

    private static func usage(_ value: Any?) -> UInt64? {
        if let string = value as? String {
            return string.hasPrefix("0x") ? UInt64(string.dropFirst(2), radix: 16) : UInt64(string)
        }
        if let number = value as? NSNumber, number.int64Value >= 0 { return number.uint64Value }
        return nil
    }

    func read(matching: String?) throws -> [UInt64: UInt64] {
        if let matching, matching.hasPrefix("service:") {
            guard let service = services[matching] else { throw HIDMappingError.serviceUnavailable }
            guard let value = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) else {
                // NULL can mean either unset or inaccessible. Accept unset only while
                // this local service is still live and another property remains readable.
                guard let registryID = IOHIDServiceClientGetRegistryID(service) as? NSNumber,
                      IOHIDServiceClientCopyProperty(service, "Product" as CFString) != nil else {
                    throw HIDMappingError.invalidOutput
                }
                let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID.uint64Value))
                guard entry != 0 else { throw HIDMappingError.invalidOutput }
                IOObjectRelease(entry)
                return [:]
            }
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            return try Self.parse(data)
        }
        return try Self.parse(run(Self.arguments(matching: matching, operation: "--get", value: "UserKeyMapping")))
    }
    func write(_ mappings: [UInt64: UInt64], matching: String?) throws {
        guard let matching, let service = services[matching] else { throw HIDMappingError.serviceUnavailable }
        let entries = mappings.keys.sorted().map { source in
            ["HIDKeyboardModifierMappingSrc": source, "HIDKeyboardModifierMappingDst": mappings[source]!]
        }
        guard IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, entries as CFArray) else {
            throw HIDMappingError.commandFailed(-1)
        }
    }
    private func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HIDMappingError.commandFailed(process.terminationStatus) }
        return data
    }
}

/// Transactions and cleanup share one lock. Cleanup restores only source keys whose
/// current value is still one we wrote, preserving unrelated or subsequently changed keys.
class HIDRemapper {
    static let shared = HIDRemapper()
    static var skipExternalHidutilCallsForTesting = false
    private let logger = Logger(subsystem: "com.winmackey.app", category: "HIDRemapper")
    private let lock = NSRecursiveLock()
    private let backend: HIDMappingBackend
    private var simulatedMappings: [String: [UInt64: UInt64]] = [:]
    private var records: [String: ScopeRecord] = [:]
    private var failures: [String: String] = [:]
    private var lastVerifiedAt: Date?
    private(set) var applyCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var unauthorizedWriteAttempts = 0
    private(set) var issuedCommandsForTesting: [[String]] = []
    private(set) var isOwnedByEngine = false
    var imeTriggerMapping: (src: Int64, dst: Int64)?

    private struct Entry {
        let original: UInt64?
        var targets: Set<UInt64>
    }
    private struct ScopeRecord {
        let matching: String?
        var owner: String
        var entries: [UInt64: Entry]
    }
    init(backend: HIDMappingBackend = SystemHIDMappingBackend()) { self.backend = backend }

    var diagnosticSnapshot: HIDMappingDiagnosticSnapshot {
        synchronized {
            HIDMappingDiagnosticSnapshot(
                status: !failures.isEmpty ? .failed : (lastVerifiedAt == nil ? .notChecked : .verified),
                lastVerifiedAt: lastVerifiedAt,
                lastError: failures.keys.sorted().first.flatMap { failures[$0] },
                pendingScopeCount: failures.count
            )
        }
    }
    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
    func resetOperationCounters() {
        synchronized {
            applyCallCount = 0
            clearCallCount = 0
            unauthorizedWriteAttempts = 0
            issuedCommandsForTesting.removeAll()
        }
    }
    /// Originals are captured immediately before each scope write, avoiding a stale startup snapshot.
    func captureSystemSnapshotIfNeeded() {}
    func takeOwnership() { synchronized { isOwnedByEngine = true } }
    func releaseOwnership() { synchronized { isOwnedByEngine = false } }
    private func checkOwnership(operation: String) -> Bool {
        guard isOwnedByEngine else {
            unauthorizedWriteAttempts += 1
            logger.error("HID write without engine ownership refused: \(operation)")
            return false
        }
        return true
    }

    static let keycodeToHIDUsage: [Int64: UInt64] = [
        0x3B: 0x7000000E0, 0x3E: 0x7000000E4,
        0x3A: 0x7000000E2, 0x3D: 0x7000000E6,
        0x37: 0x7000000E3, 0x36: 0x7000000E7,
        0x38: 0x7000000E1, 0x3C: 0x7000000E5,
        0x39: 0x700000039,
        0x6A: 0x70000006B, // F16: active local trigger / VDI relay
        0x4F: 0x70000006D, 0x50: 0x70000006E, // Historical F18/F19 profile compatibility
        0x3F: 0xFF00000003
    ]
    static let hidUsageToName: [UInt64: String] = [
        0x7000000E0: "Control", 0x7000000E4: "Right Control",
        0x7000000E2: "Option", 0x7000000E6: "Right Option",
        0x7000000E3: "Command", 0x7000000E7: "Right Command",
        0x7000000E1: "Shift", 0x7000000E5: "Right Shift",
        0x700000039: "Caps Lock", 0x70000006B: "F16",
        0x70000006D: "F18", 0x70000006E: "F19", 0xFF00000003: "Fn/Globe"
    ]
    static let internalKeyboardMatchJSON = "{\"Product\":\"Apple Internal Keyboard / Trackpad\"}"
    private static let internalKeyboardIdentifier = KeyboardDeviceIdentifier(
        vendorId: 0, productId: 0, productName: "Apple Internal Keyboard / Trackpad"
    )

    func applyMappingsForInternalKeyboardSync(_ mappings: [Int64: Int64]) {
        applyDeviceMappingsSync(mappings, matching: Self.internalKeyboardIdentifier)
    }
    func clearMappingsForInternalKeyboardSync() { clearDeviceMappingsSync(matching: Self.internalKeyboardIdentifier) }
    func reapplyMappingLayersSync(
        globalMappings: [Int64: Int64],
        deviceMappings: [(device: KeyboardDeviceIdentifier, mappings: [Int64: Int64])]
    ) {
        synchronized {
            guard checkOwnership(operation: "reapplyMappingLayersSync") else { return }
            do {
                // Resolve all layers before the first write, so device originals are never
                // captured after a global write has overwritten them.
                var plan: [String: (owner: String, mappings: [Int64: Int64])] = [:]
                for key in try resolve(matching: nil) { plan[key] = ("global", globalMappings) }
                for assignment in deviceMappings.sorted(by: { $0.device.matchingKey < $1.device.matchingKey }) {
                    guard let matching = assignment.device.hidutilMatchingJSON else { continue }
                    for key in try resolve(matching: matching) { plan[key] = (assignment.device.matchingKey, assignment.mappings) }
                }
                guard !plan.isEmpty else { throw HIDMappingError.invalidOutput }
                for key in records.keys.sorted() where plan[key] == nil { restore(key: key) }
                for key in plan.keys.sorted(by: { lhs, rhs in
                    if lhs == "global" { return rhs != "global" }
                    if rhs == "global" { return false }
                    return lhs < rhs
                }) {
                    let assignment = plan[key]!
                    apply(assignment.mappings, key: key, matching: key == "global" ? nil : key, owner: assignment.owner)
                }
                failures.removeValue(forKey: "discovery")
            } catch { failed(key: "discovery", error: error) }
        }
    }
    func applyDeviceMappingsSync(_ mappings: [Int64: Int64], matching device: KeyboardDeviceIdentifier) {
        synchronized {
            guard checkOwnership(operation: "applyDeviceMappingsSync"), let matching = device.hidutilMatchingJSON else { return }
            applyResolved(mappings, matching: matching, owner: device.matchingKey)
        }
    }
    func clearDeviceMappingsSync(matching device: KeyboardDeviceIdentifier) {
        synchronized {
            guard checkOwnership(operation: "clearDeviceMappingsSync") else { return }
            for key in records.keys.sorted() where records[key]?.owner == device.matchingKey { restore(key: key) }
        }
    }
    func applyMappings(_ mappings: [Int64: Int64]) { applyMappingsSync(mappings) }
    func applyMappingsSync(_ mappings: [Int64: Int64]) {
        synchronized {
            guard checkOwnership(operation: "applyMappingsSync") else { return }
            applyResolved(mappings, matching: nil, owner: "global")
        }
    }
    func clearMappings() { clearMappingsSync() }
    func clearMappingsSync() {
        synchronized {
            guard checkOwnership(operation: "clearMappingsSync") else { return }
            for key in records.keys.sorted() where records[key]?.owner == "global" { restore(key: key) }
        }
    }
    func clearAllMappingsSync() {
        synchronized {
            guard checkOwnership(operation: "clearAllMappingsSync") else { return }
            restoreAll()
        }
    }
    func internalClearAllForTermination() { synchronized { restoreAll() } }
    func restorePreExistingMappingsAndClearInternal() { synchronized { restoreAll() } }
    private func restoreAll() {
        guard !records.isEmpty else { return }
        do {
            _ = try resolve(matching: nil)
            for key in records.keys.sorted() { restore(key: key) }
            failures.removeValue(forKey: "discovery")
        } catch { failed(key: "discovery", error: error) }
    }

    private func desiredMappings(_ mappings: [Int64: Int64]) -> [UInt64: UInt64] {
        var desired: [UInt64: UInt64] = [:]
        for (source, destination) in mappings where source != destination {
            if let sourceUsage = Self.keycodeToHIDUsage[source], let destinationUsage = Self.keycodeToHIDUsage[destination] {
                desired[sourceUsage] = destinationUsage
            }
        }
        if let trigger = imeTriggerMapping, trigger.src != trigger.dst,
           let source = Self.keycodeToHIDUsage[trigger.src], let destination = Self.keycodeToHIDUsage[trigger.dst] {
            desired[source] = destination
        }
        return desired
    }
    private func resolve(matching: String?) throws -> [String] {
        if Self.skipExternalHidutilCallsForTesting {
            guard let matching else { return ["global"] }
            let object = try JSONSerialization.jsonObject(with: Data(matching.utf8))
            return [String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)]
        }
        return try backend.resolve(matching: matching)
    }
    private func applyResolved(_ mappings: [Int64: Int64], matching: String?, owner: String) {
        do {
            let scopes = try resolve(matching: matching)
            guard !scopes.isEmpty else { throw HIDMappingError.invalidOutput }
            for scope in scopes { apply(mappings, key: scope, matching: scope == "global" ? nil : scope, owner: owner) }
            failures.removeValue(forKey: "discovery")
        } catch { failed(key: "discovery", error: error) }
    }
    private func apply(_ mappings: [Int64: Int64], key: String, matching: String?, owner: String) {
        applyCallCount += 1
        do {
            let current = try read(matching: matching)
            let desired = desiredMappings(mappings)
            var updated = current
            var record = records[key] ?? ScopeRecord(matching: matching, owner: owner, entries: [:])
            record.owner = owner
            for (source, entry) in record.entries where desired[source] == nil {
                if let value = current[source], entry.targets.contains(value) { updated[source] = entry.original }
            }
            for (source, target) in desired {
                if var entry = record.entries[source], let value = current[source], entry.targets.contains(value) {
                    entry.targets.insert(target)
                    record.entries[source] = entry
                } else {
                    record.entries[source] = Entry(original: current[source], targets: [target])
                }
                updated[source] = target
            }
            // Record before writing: a failed readback must not lose the ability to undo our write.
            records[key] = record
            try setVerified(updated, matching: matching, current: current)
            record.entries = record.entries.filter { desired[$0.key] != nil }
            for (source, target) in desired { record.entries[source]?.targets = [target] }
            if record.entries.isEmpty { records.removeValue(forKey: key) } else { records[key] = record }
            verified(key: key)
        } catch { failed(key: key, error: error) }
    }
    private func restore(key: String) {
        guard let record = records[key] else { return }
        clearCallCount += 1
        do {
            let current = try read(matching: record.matching)
            var restored = current
            for (source, entry) in record.entries {
                if let value = current[source], entry.targets.contains(value) { restored[source] = entry.original }
            }
            try setVerified(restored, matching: record.matching, current: current)
            records.removeValue(forKey: key)
            verified(key: key)
        } catch HIDMappingError.serviceUnavailable {
            // Fresh discovery no longer contains this registry ID; a replacement
            // device has its own baseline and must never inherit this undo record.
            records.removeValue(forKey: key)
            failures.removeValue(forKey: key)
        } catch { failed(key: key, error: error) }
    }
    private func setVerified(_ mappings: [UInt64: UInt64], matching: String?, current: [UInt64: UInt64]) throws {
        if mappings != current {
            if Self.skipExternalHidutilCallsForTesting {
                issuedCommandsForTesting.append(SystemHIDMappingBackend.arguments(
                    matching: matching, operation: "--set", value: try SystemHIDMappingBackend.json(mappings)
                ))
                simulatedMappings[matching ?? "global"] = mappings
            } else { try backend.write(mappings, matching: matching) }
        }
        guard try read(matching: matching) == mappings else { throw HIDMappingError.verificationMismatch }
    }
    private func read(matching: String?) throws -> [UInt64: UInt64] {
        if Self.skipExternalHidutilCallsForTesting { return simulatedMappings[matching ?? "global"] ?? [:] }
        return try backend.read(matching: matching)
    }
    private func verified(key: String) {
        failures.removeValue(forKey: key)
        lastVerifiedAt = Date()
    }
    private func failed(key: String, error: Error) {
        let message = "\(key): \(error.localizedDescription)"
        failures[key] = message
        logger.error("HID mapping verification failed: \(message)")
    }
    func getCurrentMappings() -> String {
        synchronized {
            do { return try SystemHIDMappingBackend.json(read(matching: nil)) }
            catch { return "(error: \(error.localizedDescription))" }
        }
    }
}
