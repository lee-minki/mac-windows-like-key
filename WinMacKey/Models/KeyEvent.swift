import Foundation
import CryptoKit

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
    let keyboardType: Int64 // 키보드 하드웨어 타입 ID
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: KeyEventType,
        rawKey: UInt32,
        mappedKey: UInt32,
        latencyMicroseconds: UInt64,
        bundleId: String? = nil,
        keyboardType: Int64 = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.rawKey = rawKey
        self.mappedKey = mappedKey
        self.latencyMicroseconds = latencyMicroseconds
        self.bundleId = bundleId
        self.keyboardType = keyboardType
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
        Self.cachedFormatter.string(from: timestamp)
    }
    
    private static let cachedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
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

// MARK: - Privacy / Anonymization
//
// 로그·뷰어·export 에서 사용자 사용 패턴(어느 앱에서 어떤 키를 눌렀는지) 노출을 줄이기 위한 익명화.
// 기본 privacy mode (UserDefaults `loggingPrivacyMode`, default true) 에서는 다음으로 대체:
//   - bundleId → SHA-256 prefix hash (app-xxxxxxxx)
//   - keyCode  → 카테고리 ("modifier" / "function" / "letter" / "number" / "trigger" / "other")
// Verbose mode 에서만 raw 표시. Export 시점에 사용자 confirmation 으로 raw 포함 동의 받음.

extension KeyEvent {
    /// bundleId 의 SHA-256 prefix 를 사용한 안정적 익명 식별자.
    /// 같은 앱은 같은 hash 라 통계는 유지되지만 어떤 앱인지 모름.
    var bundleIdAnonymized: String? {
        guard let bid = bundleId, !bid.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(bid.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "app-\(hex)"
    }

    /// keyCode 를 거친 카테고리로 분류 — 실제 키는 노출하지 않되 패턴은 보여줌.
    var keyCodeCategory: String {
        switch rawKey {
        case 0x37, 0x36, 0x3A, 0x3D, 0x38, 0x3C, 0x3B, 0x3E, 0x3F: return "modifier"
        case 0x39: return "capslock"
        case 0x6A: return "trigger"  // F16
        case 0x60...0x6F, 0x7A, 0x78, 0x63, 0x76: return "function"
        case 0x12...0x1D, 0x53...0x5C: return "number"
        case 0x00...0x32: return "letter"
        default: return "other"
        }
    }

    /// 익명화된 표시용 row text. EventViewer 가 privacy mode ON 시 사용.
    func anonymizedSummary() -> String {
        let app = bundleIdAnonymized ?? "(no-app)"
        return "\(timestampFormatted) [\(type.rawValue)] \(keyCodeCategory) (\(latencyFormatted)) — \(app)"
    }
}
