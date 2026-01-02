import Foundation

/// 키 이벤트 타입
enum KeyEventType: String, Codable {
    case down = "Down"
    case up = "Up"
}

/// 실시간 키 이벤트 로그 항목
struct KeyEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: KeyEventType
    let rawKey: UInt32      // 원본 키코드
    let mappedKey: UInt32   // 매핑된 키코드
    let latencyMicroseconds: UInt64  // 지연 시간 (마이크로초)
    let bundleId: String?   // 현재 앱 Bundle ID
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: KeyEventType,
        rawKey: UInt32,
        mappedKey: UInt32,
        latencyMicroseconds: UInt64,
        bundleId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.rawKey = rawKey
        self.mappedKey = mappedKey
        self.latencyMicroseconds = latencyMicroseconds
        self.bundleId = bundleId
    }
    
    /// 지연 시간을 밀리초로 변환
    var latencyMs: Double {
        Double(latencyMicroseconds) / 1000.0
    }
    
    /// 지연 시간 포맷된 문자열
    var latencyFormatted: String {
        String(format: "%.2fms", latencyMs)
    }
    
    /// 타임스탬프 포맷된 문자열
    var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    /// 키코드를 16진수 문자열로 변환
    static func keyCodeHex(_ keyCode: UInt32) -> String {
        String(format: "0x%02X", keyCode)
    }
}

// MARK: - 주요 키코드 상수
extension KeyEvent {
    static let capsLockKeyCode: UInt32 = 0x39      // macOS CapsLock
    static let windowsIMEKeyCode: UInt32 = 0x15   // Windows 한/영 전환 (스캔코드)
}
