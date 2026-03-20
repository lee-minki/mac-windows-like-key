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
        
        // Function keys (IME relay용)
        0x6A: 0x70000006B, // kVK_F16             → F16 (IME toggle / VDI relay)
        0x4F: 0x70000006D, // kVK_F18             → F18
        
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
        0xFF00000003: "Fn/Globe"
    ]

    /// IME 전환 트리거 HID 리맵 (예: Right Cmd → F18)
    /// 모든 hidutil 호출 시 자동으로 포함됩니다.
    var imeTriggerMapping: (src: Int64, dst: Int64)? = nil
    
    // MARK: - Device Matching

    /// 내장 키보드 디바이스 매칭 (Apple Silicon Mac)
    /// hidutil --matching 파라미터로 사용
    static let internalKeyboardMatchJSON = "{\"Product\":\"Apple Internal Keyboard / Trackpad\"}"

    // MARK: - Device-Specific Mappings

    /// 내장 키보드에만 매핑 적용 (동기)
    /// IME 트리거 리맵이 설정되어 있으면 자동으로 포함됩니다.
    func applyMappingsForInternalKeyboardSync(_ mappings: [Int64: Int64]) {
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
        let result = runHidutil(arguments: ["property", "--matching", Self.internalKeyboardMatchJSON, "--set", "{\"UserKeyMapping\":[]}"])
        if result {
            logger.info("Internal keyboard mappings cleared (sync)")
        } else {
            logger.error("Failed to clear internal keyboard mappings")
        }
    }

    /// 모든 디바이스의 매핑을 완전히 해제 (앱 종료/리셋용)
    func clearAllMappingsSync() {
        // 글로벌 매핑 해제
        clearMappingsSync()
        // 내장 키보드 디바이스별 매핑도 해제
        clearMappingsForInternalKeyboardSync()
        logger.info("All mappings cleared (global + internal keyboard)")
    }

    // MARK: - Apply Mappings (Global)

    /// keycode 기반 매핑 딕셔너리를 hidutil로 적용 (전체 디바이스)
    /// IME 트리거 리맵이 설정되어 있으면 자동으로 포함됩니다.
    /// - Parameter mappings: [sourceKeyCode: destinationKeyCode] (macOS virtual keycode 사용)
    func applyMappings(_ mappings: [Int64: Int64]) {
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
        
        // IME 트리거 리맵 자동 주입 (Right Cmd/Opt → F18)
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
    
    /// 동기 버전 — 앱 종료, 리셋, 위저드 등에서 사용
    func clearMappingsSync() {
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
