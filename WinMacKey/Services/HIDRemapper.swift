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
        0xFF00000003: "Fn/Globe"
    ]
    
    // MARK: - Apply Mappings
    
    /// keycode 기반 매핑 딕셔너리를 hidutil로 적용
    /// - Parameter mappings: [sourceKeyCode: destinationKeyCode] (macOS virtual keycode 사용)
    func applyMappings(_ mappings: [Int64: Int64]) {
        var userKeyMapping: [[String: UInt64]] = []
        
        for (src, dst) in mappings {
            // 자기 자신으로의 매핑은 무의미하므로 스킵
            guard src != dst else { continue }
            
            guard let srcHID = Self.keycodeToHIDUsage[src],
                  let dstHID = Self.keycodeToHIDUsage[dst] else {
                // HID 테이블에 없는 키코드는 스킵 (일반 키는 CGEventTap이 처리)
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
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(null)"
        } catch {
            return "(error: \(error.localizedDescription))"
        }
    }
    
    // MARK: - Private
    
    @discardableResult
    private func runHidutil(arguments: [String]) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = arguments
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            logger.error("hidutil execution failed: \(error.localizedDescription)")
            return false
        }
    }
}
