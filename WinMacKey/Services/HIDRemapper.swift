import Foundation
import os.log

/// hidutil 기반 HID 레벨 키 리매핑 서비스
/// macOS의 IOHIDEventDriver 레벨에서 키를 변경합니다.
/// CGEventTap보다 낮은 레벨이므로 Fn/Globe 키도 리맵 가능합니다.
class HIDRemapper {

    static let shared = HIDRemapper()

    private let logger = Logger(subsystem: "com.winmackey.app", category: "HIDRemapper")
    /// hidutil 호출을 직렬화하여 빠른 연속 호출 시 순서를 보장
    private let queue = DispatchQueue(label: "com.winmackey.hidutil", qos: .userInitiated)

    /// 테스트 환경에서 hidutil Process spawn 을 skip.
    /// 카운터·ownership 게이트·snapshot capture 같은 in-memory state 는 정상 동작하지만
    /// 실제 /usr/bin/hidutil 호출은 no-op. 이걸로 smoke test 가 SIGKILL 없이 결정론적으로 동작.
    /// 프로덕션 빌드는 false 유지 (변경 금지).
    static var skipExternalHidutilCallsForTesting: Bool = false

    // MARK: - Operation Counters (lifecycle invariant verification)
    //
    // 이 카운터는 "엔진 OFF 시 HID 미터치" invariant를 검증하기 위한 것.
    // 어떤 path든 ownership 없이 HID 를 건드리면 DEBUG 빌드의 assertion 이 잡아낸다.
    private(set) var applyCallCount: Int = 0
    private(set) var clearCallCount: Int = 0
    /// ownership 가드 위반이 감지된 횟수 (DEBUG 검증용).
    private(set) var unauthorizedWriteAttempts: Int = 0

    func resetOperationCounters() {
        applyCallCount = 0
        clearCallCount = 0
        unauthorizedWriteAttempts = 0
    }

    // MARK: - Ownership Model
    //
    // hidutil 은 시스템 전역 단일 키 — 다른 도구(Karabiner 등)가 동시에 쓰고 있을 수 있다.
    // 따라서 본 앱은 "엔진 ON 동안만 HID 를 소유한다"는 명시적 lifecycle 을 가진다.
    //
    // 게이트 규칙:
    //   - 엔진 ON 진입 시 takeOwnership() 호출 → 이후 applyMappings* / clearMappings* 허용
    //   - 엔진 OFF 진입 시 releaseOwnership() 호출 → 이후 모든 HID write 거부
    //
    // 의도된 우회는 internalClearAllForTermination() 만 허용 (앱 종료/Reset/Doctor recovery
    // 같은 명시적 cleanup path 가 호출). 이 경로는 ownership 와 무관하게 항상 동작.

    private(set) var isOwnedByEngine: Bool = false

    /// 앱이 처음 HID 를 건드리기 전의 시스템 UserKeyMapping snapshot.
    /// hidutil --get 의 old-style plist 출력을 parse 해 [[String: Any]] 로 보관.
    /// 종료/Reset 시 이 snapshot 을 JSON 으로 재직렬화해 --set 으로 복원.
    private var preExistingMappings: [[String: Any]]?
    /// snapshot capture 가 성공했는지 (nil 도 valid — 빈 매핑 의미).
    private var snapshotCaptured: Bool = false
    /// 앱이 실제로 HID 매핑을 적용한 적 있는지.
    private var hasAppliedAnyMapping: Bool = false

    /// 앱 시작 시 1회 호출 — 현재 hidutil 상태를 snapshot 으로 저장.
    /// AppState.init body 의 updateIMETriggerRemap 전에 호출되어야 함.
    func captureSystemSnapshotIfNeeded() {
        guard !snapshotCaptured else { return }
        preExistingMappings = readCurrentUserKeyMapping()
        snapshotCaptured = true

        let count = preExistingMappings?.count ?? 0
        if count > 0 {
            logger.info("Pre-existing UserKeyMapping snapshot captured: \(count) entries (will be restored on cleanup)")
        } else {
            logger.info("Pre-existing UserKeyMapping snapshot: empty/clean state")
        }
    }

    /// hidutil property --get UserKeyMapping → parsed array of mapping dicts.
    /// 빈 매핑 / 파싱 실패 시 빈 array 반환 (nil 아님 — capture 자체는 성공으로 본다).
    private func readCurrentUserKeyMapping() -> [[String: Any]]? {
        if Self.skipExternalHidutilCallsForTesting {
            return []  // 빈 baseline 으로 가정
        }

        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = ["property", "--get", "UserKeyMapping"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }

            // hidutil --get 출력은 OpenStep (old-style) plist text.
            // 빈 경우: "(\n)" → 빈 array. 파싱 실패 시 빈 array 로 fallback (caller 가 clear 처리).
            if let array = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] {
                return array
            }
            return []
        } catch {
            return []
        }
    }

    func takeOwnership() {
        isOwnedByEngine = true
        logger.info("HID ownership acquired by engine")
    }

    func releaseOwnership() {
        isOwnedByEngine = false
        logger.info("HID ownership released by engine")
    }

    /// ownership 가드 — write 메서드 진입 시 호출.
    /// 거부되면 false 반환 + 카운터 증가 + DEBUG 빌드에서는 assertion.
    private func checkOwnership(operation: String) -> Bool {
        if isOwnedByEngine { return true }

        unauthorizedWriteAttempts += 1
        logger.error("HID write attempted without ownership: \(operation) — refused")
        #if DEBUG
        assertionFailure("HID \(operation) attempted without engine ownership")
        #endif
        return false
    }
    
    // MARK: - HID Usage ID Table
    // https://developer.apple.com/library/archive/technotes/tn2450/_index.html
    
    /// macOS keycode → HID Usage ID 변환 테이블
    static let keycodeToHIDUsage: [Int64: UInt64] = [
        // Standard modifier keys (HID Usage Page 0x07)
        0x3B: 0x7000000E0, // kVK_Control       → Left Control
        0x3E: 0x7000000E4, // kVK_RightControl   → Right Control
        0x3A: 0x7000000E2, // kVK_Option          → Left Alt
        0x3D: 0x7000000E6, // kVK_RightOption     → Right Alt
        0x37: 0x7000000E3, // kVK_Command         → Left GUI
        0x36: 0x7000000E7, // kVK_RightCommand    → Right GUI
        0x38: 0x7000000E1, // kVK_Shift           → Left Shift
        0x3C: 0x7000000E5, // kVK_RightShift      → Right Shift
        0x39: 0x700000039, // kVK_CapsLock        → Caps Lock
        
        // Function keys
        0x6A: 0x70000006B, // kVK_F16 → F16 (active IME trigger / VDI relay)
        // F18/F19는 v1.3 이전 릴레이 실험의 historical 매핑. 현재 트리거 경로에서는 사용하지 않으나
        // 외부 프로필이 참조할 가능성을 대비해 변환 테이블에 유지.
        0x4F: 0x70000006D, // kVK_F18 → F18 (historical, unused after v1.3)
        0x50: 0x70000006E, // kVK_F19 → F19 (historical, unused after v1.3)
        
        // Fn/Globe key (Apple 전용)
        0x3F: 0xFF00000003 // kVK_Function        → Fn (Apple vendor-specific)
    ]
    
    /// HID Usage ID → 사용자 표시용 이름
    static let hidUsageToName: [UInt64: String] = [
        0x7000000E0: "Control",
        0x7000000E4: "Right Control",
        0x7000000E2: "Option",
        0x7000000E6: "Right Option",
        0x7000000E3: "Command",
        0x7000000E7: "Right Command",
        0x7000000E1: "Shift",
        0x7000000E5: "Right Shift",
        0x700000039: "Caps Lock",
        0x70000006B: "F16",
        0x70000006D: "F18",
        0x70000006E: "F19",
        0xFF00000003: "Fn/Globe"
    ]

    var imeTriggerMapping: (src: Int64, dst: Int64)? = nil
    
    // MARK: - Device Matching

    /// 내장 키보드 디바이스 매칭 (Apple Silicon Mac)
    /// hidutil --matching 파라미터로 사용
    static let internalKeyboardMatchJSON = "{\"Product\":\"Apple Internal Keyboard / Trackpad\"}"

    // MARK: - Device-Specific Mappings

    /// 내장 키보드에만 매핑 적용 (동기)
    /// IME 트리거 리맵이 설정되어 있으면 자동으로 포함됩니다.
    func applyMappingsForInternalKeyboardSync(_ mappings: [Int64: Int64]) {
        guard checkOwnership(operation: "applyMappingsForInternalKeyboardSync") else { return }
        applyCallCount += 1
        hasAppliedAnyMapping = true
        var combined = mappings
        if let trigger = imeTriggerMapping, trigger.src != trigger.dst {
            combined[trigger.src] = trigger.dst
        }
        let json = buildUserKeyMappingJSON(combined)
        guard let json = json else {
            clearMappingsForInternalKeyboardSync()
            return
        }
        let result = runHidutil(arguments: ["property", "--matching", Self.internalKeyboardMatchJSON, "--set", json])
        if result {
            logger.info("Internal keyboard mappings applied (sync, \(combined.count) mappings)")
        } else {
            logger.error("Failed to apply internal keyboard mappings")
        }
    }

    /// 내장 키보드의 매핑만 해제 (동기)
    func clearMappingsForInternalKeyboardSync() {
        guard checkOwnership(operation: "clearMappingsForInternalKeyboardSync") else { return }
        clearCallCount += 1
        let result = runHidutil(arguments: ["property", "--matching", Self.internalKeyboardMatchJSON, "--set", "{\"UserKeyMapping\":[]}"])
        if result {
            logger.info("Internal keyboard mappings cleared (sync)")
        } else {
            logger.error("Failed to clear internal keyboard mappings")
        }
    }

    /// 모든 디바이스의 매핑을 완전히 해제 (앱 종료/리셋용)
    /// ⚠️ ownership 가드 적용 — 엔진이 hidutil 소유 중일 때만 동작.
    /// 종료/Reset/Recovery 등 명시적 cleanup path 는 internalClearAllForTermination() 사용.
    func clearAllMappingsSync() {
        guard checkOwnership(operation: "clearAllMappingsSync") else { return }
        // 글로벌 매핑 해제
        clearMappingsSyncNoGuard()
        // 내장 키보드 디바이스별 매핑도 해제
        clearMappingsForInternalKeyboardSyncNoGuard()
        logger.info("All mappings cleared (global + internal keyboard)")
    }

    /// 종료/Reset/Recovery 시 호출되는 명시적 cleanup path.
    /// 앱이 HID 매핑을 적용한 적 있으면 pre-existing snapshot 으로 복원.
    /// 적용 안 했으면 no-op — 다른 hidutil 도구의 매핑을 건드리지 않음.
    func internalClearAllForTermination() {
        performSnapshotRestoreAndInternalCleanup()
    }

    /// 엔진 OFF / Doctor stop / Reset 모두 공용 — pre-existing snapshot 복원 + internal cleanup.
    /// ownership 무관 (caller 가 책임지고 호출). hasAppliedAnyMapping=false 면 no-op.
    /// HIGH 1·2 fix — toggleEngine OFF, Doctor stopEngine 도 이 메서드 사용해야 함.
    func restorePreExistingMappingsAndClearInternal() {
        performSnapshotRestoreAndInternalCleanup()
    }

    /// 두 진입점이 공유하는 실제 cleanup 로직.
    private func performSnapshotRestoreAndInternalCleanup() {
        guard hasAppliedAnyMapping else {
            logger.info("Cleanup: no app mappings were applied — preserving system state")
            return
        }

        // Snapshot 으로 복원 (없거나 비어있으면 결과적으로 clear 와 동일).
        let restored = restorePreExistingSnapshot()
        if !restored {
            // 복원 실패 — 안전 fallback 으로 clear (사용자의 다른 hidutil 매핑이 사라질 수 있음, 로그로 알림).
            logger.error("Snapshot restore failed — falling back to clearMappings (other hidutil tools' mappings will be lost)")
            clearMappingsSyncNoGuard()
        }

        // 내장 키보드 디바이스별 매핑은 앱이 추가한 것이므로 항상 clear
        clearMappingsForInternalKeyboardSyncNoGuard()

        // 한 번 cleanup 후엔 동일 lifecycle 에서 또 복원하지 않도록 reset
        hasAppliedAnyMapping = false
    }

    /// preExistingMappings 를 hidutil 에 다시 적용. 성공 시 true.
    private func restorePreExistingSnapshot() -> Bool {
        let entries = preExistingMappings ?? []
        let config: [String: Any] = ["UserKeyMapping": entries]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        let result = runHidutil(arguments: ["property", "--set", json])
        clearCallCount += 1
        if result {
            if entries.isEmpty {
                logger.info("Restored to empty UserKeyMapping (no pre-existing mappings)")
            } else {
                logger.info("Restored pre-existing UserKeyMapping (\(entries.count) entries — preserved other hidutil tools)")
            }
        }
        return result
    }

    /// ownership 가드 없는 내부 동기 clear — guarded wrapper 에서만 호출.
    private func clearMappingsSyncNoGuard() {
        clearCallCount += 1
        let emptyConfig = "{\"UserKeyMapping\":[]}"
        let result = runHidutil(arguments: ["property", "--set", emptyConfig])
        if result {
            logger.info("HID mappings cleared (sync, no-guard)")
        } else {
            logger.error("Failed to clear HID mappings (sync, no-guard)")
        }
    }

    /// ownership 가드 없는 내장 키보드 clear — guarded wrapper 에서만 호출.
    private func clearMappingsForInternalKeyboardSyncNoGuard() {
        clearCallCount += 1
        let result = runHidutil(arguments: ["property", "--matching", Self.internalKeyboardMatchJSON, "--set", "{\"UserKeyMapping\":[]}"])
        if result {
            logger.info("Internal keyboard mappings cleared (no-guard)")
        } else {
            logger.error("Failed to clear internal keyboard mappings (no-guard)")
        }
    }

    // MARK: - Apply Mappings (Global)

    /// keycode 기반 매핑 딕셔너리를 hidutil로 적용 (전체 디바이스)
    /// IME 트리거 리맵이 설정되어 있으면 자동으로 포함됩니다.
    /// - Parameter mappings: [sourceKeyCode: destinationKeyCode] (macOS virtual keycode 사용)
    func applyMappings(_ mappings: [Int64: Int64]) {
        guard checkOwnership(operation: "applyMappings") else { return }
        applyCallCount += 1
        hasAppliedAnyMapping = true
        var userKeyMapping: [[String: UInt64]] = []
        
        for (src, dst) in mappings {
            guard src != dst else { continue }
            
            guard let srcHID = Self.keycodeToHIDUsage[src],
                  let dstHID = Self.keycodeToHIDUsage[dst] else {
                continue
            }
            
            userKeyMapping.append([
                "HIDKeyboardModifierMappingSrc": srcHID,
                "HIDKeyboardModifierMappingDst": dstHID
            ])
            
            let srcName = Self.hidUsageToName[srcHID] ?? "\(srcHID)"
            let dstName = Self.hidUsageToName[dstHID] ?? "\(dstHID)"
            logger.info("HID mapping: \(srcName) → \(dstName)")
        }
        
        injectIMETriggerMapping(into: &userKeyMapping)
        
        if userKeyMapping.isEmpty {
            clearMappings()
            return
        }
        
        let config: [String: Any] = ["UserKeyMapping": userKeyMapping]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to serialize UserKeyMapping to JSON")
            return
        }
        
        let count = userKeyMapping.count
        queue.async { [self] in
            let result = runHidutil(arguments: ["property", "--set", jsonString])
            if result {
                logger.info("HID mappings applied successfully (\(count) mappings)")
            } else {
                logger.error("Failed to apply HID mappings")
            }
        }
    }
    
    /// 동기 버전 — 위저드, 리셋 등 완료를 보장해야 할 때 사용
    func applyMappingsSync(_ mappings: [Int64: Int64]) {
        guard checkOwnership(operation: "applyMappingsSync") else { return }
        applyCallCount += 1
        hasAppliedAnyMapping = true
        var userKeyMapping: [[String: UInt64]] = []
        
        for (src, dst) in mappings {
            guard src != dst else { continue }
            guard let srcHID = Self.keycodeToHIDUsage[src],
                  let dstHID = Self.keycodeToHIDUsage[dst] else { continue }
            userKeyMapping.append([
                "HIDKeyboardModifierMappingSrc": srcHID,
                "HIDKeyboardModifierMappingDst": dstHID
            ])
        }
        
        // IME 트리거 리맵 자동 주입
        injectIMETriggerMapping(into: &userKeyMapping)
        
        if userKeyMapping.isEmpty {
            clearMappingsSync()
            return
        }
        
        let config: [String: Any] = ["UserKeyMapping": userKeyMapping]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        let result = runHidutil(arguments: ["property", "--set", jsonString])
        if result {
            logger.info("HID mappings applied (sync, \(userKeyMapping.count) mappings)")
        } else {
            logger.error("Failed to apply HID mappings (sync)")
        }
    }
    
    /// 모든 HID 매핑 해제
    func clearMappings() {
        guard checkOwnership(operation: "clearMappings") else { return }
        clearCallCount += 1
        let emptyConfig = "{\"UserKeyMapping\":[]}"
        queue.async { [self] in
            let result = runHidutil(arguments: ["property", "--set", emptyConfig])
            if result {
                logger.info("HID mappings cleared")
            } else {
                logger.error("Failed to clear HID mappings")
            }
        }
    }
    
    /// 동기 버전 — 엔진 stop, 위저드 등에서 사용
    /// 종료/Reset path 는 internalClearAllForTermination() 을 거쳐 ownership bypass 함.
    func clearMappingsSync() {
        guard checkOwnership(operation: "clearMappingsSync") else { return }
        clearCallCount += 1
        let emptyConfig = "{\"UserKeyMapping\":[]}"
        let result = runHidutil(arguments: ["property", "--set", emptyConfig])
        if result {
            logger.info("HID mappings cleared (sync)")
        } else {
            logger.error("Failed to clear HID mappings (sync)")
        }
    }
    
    /// 현재 HID 매핑 상태 조회
    func getCurrentMappings() -> String {
        if Self.skipExternalHidutilCallsForTesting {
            return "(test mode — hidutil skipped)"
        }

        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = ["property", "--get", "UserKeyMapping"]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(null)"
        } catch {
            return "(error: \(error.localizedDescription))"
        }
    }
    
    // MARK: - Private

    /// IME 트리거 매핑을 HID 매핑 배열에 주입 (중복 방지)
    private func injectIMETriggerMapping(into userKeyMapping: inout [[String: UInt64]]) {
        guard let trigger = imeTriggerMapping, trigger.src != trigger.dst,
              let srcHID = Self.keycodeToHIDUsage[trigger.src],
              let dstHID = Self.keycodeToHIDUsage[trigger.dst] else { return }
        let entry: [String: UInt64] = [
            "HIDKeyboardModifierMappingSrc": srcHID,
            "HIDKeyboardModifierMappingDst": dstHID
        ]
        // 이미 동일한 소스의 매핑이 있으면 교체, 없으면 추가
        if let idx = userKeyMapping.firstIndex(where: { $0["HIDKeyboardModifierMappingSrc"] == srcHID }) {
            userKeyMapping[idx] = entry
        } else {
            userKeyMapping.append(entry)
        }
        let srcName = Self.hidUsageToName[srcHID] ?? "\(srcHID)"
        let dstName = Self.hidUsageToName[dstHID] ?? "\(dstHID)"
        logger.info("IME trigger HID mapping: \(srcName) → \(dstName)")
    }

    /// 매핑 딕셔너리를 hidutil JSON 문자열로 변환. 유효한 매핑이 없으면 nil 반환.
    private func buildUserKeyMappingJSON(_ mappings: [Int64: Int64]) -> String? {
        var userKeyMapping: [[String: UInt64]] = []
        for (src, dst) in mappings {
            guard src != dst else { continue }
            guard let srcHID = Self.keycodeToHIDUsage[src],
                  let dstHID = Self.keycodeToHIDUsage[dst] else { continue }
            userKeyMapping.append([
                "HIDKeyboardModifierMappingSrc": srcHID,
                "HIDKeyboardModifierMappingDst": dstHID
            ])
        }
        // IME 트리거 매핑도 포함
        injectIMETriggerMapping(into: &userKeyMapping)
        guard !userKeyMapping.isEmpty else { return nil }
        let config: [String: Any] = ["UserKeyMapping": userKeyMapping]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        return jsonString
    }

    @discardableResult
    private func runHidutil(arguments: [String]) -> Bool {
        // 테스트 환경: hidutil Process spawn 자체를 skip.
        // 카운터/상태 머신 검증은 정상 동작하지만 실제 시스템 hidutil 안 건드림.
        if Self.skipExternalHidutilCallsForTesting {
            logger.info("hidutil call skipped (testing mode): \(arguments.joined(separator: " "))")
            return true
        }

        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            // 데드락 방지: pipe 버퍼를 먼저 소비한 후 waitUntilExit 호출
            _ = outPipe.fileHandleForReading.readDataToEndOfFile()
            _ = errPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            logger.error("hidutil execution failed: \(error.localizedDescription)")
            return false
        }
    }
}
