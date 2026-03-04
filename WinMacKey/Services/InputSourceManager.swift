import Foundation
import Carbon.HIToolbox

/// 입력 소스 타입
enum InputSource: String, Codable {
    case english = "English"
    case korean = "Korean"
    
    var displayName: String {
        switch self {
        case .english: return "EN"
        case .korean: return "한"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .english: return "a.square"
        case .korean: return "character.textbox"
        }
    }
}

/// TIS (Text Input Sources) API 래퍼
/// 캐시 없이 실시간으로 현재 입력 소스를 조회하고 전환합니다.
class InputSourceManager {
    
    // 알려진 한글 입력 소스 ID 패턴
    private static let koreanPatterns = [
        "com.apple.inputmethod.Korean",
        "Korean"
    ]
    
    // 선호하는 입력 소스 ID
    private static let preferredKoreanID = "com.apple.inputmethod.Korean.2SetKorean"
    private static let preferredEnglishID = "com.apple.keylayout.ABC"
    
    /// 현재 입력 소스를 실시간 조회 (캐시 없음)
    /// Telegram 등이 입력 소스를 건드려도 항상 정확한 상태 반영
    func currentSource() -> InputSource {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .english
        }
        
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return .english
        }
        
        let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        
        // 한글 입력 소스인지 확인
        for pattern in Self.koreanPatterns {
            if sourceID.contains(pattern) {
                return .korean
            }
        }
        
        return .english
    }
    
    /// 특정 입력 소스로 전환 (동기 처리 + 완료 확인 폴링)
    func switchTo(_ target: InputSource) {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            print("[InputSourceManager] ERROR: Failed to get input source list")
            return
        }
        
        let targetID: String
        
        if target == .korean {
            targetID = Self.preferredKoreanID
        } else {
            targetID = Self.preferredEnglishID
        }
        
        // 정확한 ID로 먼저 찾기
        if let source = sourceList.first(where: { getSourceID($0) == targetID }) {
            let status = TISSelectInputSource(source)
            if status != noErr {
                print("[InputSourceManager] ERROR: TISSelectInputSource failed with status \(status)")
            }
        } else {
            // 대체: 패턴 매칭으로 찾기
            let source: TISInputSource?
            if target == .korean {
                source = sourceList.first { src in
                    let id = getSourceID(src)
                    return Self.koreanPatterns.contains(where: { id.contains($0) })
                }
            } else {
                source = sourceList.first { src in
                    let id = getSourceID(src)
                    return id.contains("ABC") || id.contains("US") || (id.contains("keylayout") && !Self.koreanPatterns.contains(where: { id.contains($0) }))
                }
            }
            
            if let source = source {
                let status = TISSelectInputSource(source)
                if status != noErr {
                    print("[InputSourceManager] ERROR: TISSelectInputSource fallback failed with status \(status)")
                }
            } else {
                print("[InputSourceManager] ERROR: Could not find input source for \(target)")
            }
        }
        
        // 전환 완료 확인 (동기 확인 1회만, 블로킹 없이)
        let actual = currentSource()
        if actual != target {
            print("[InputSourceManager] WARNING: Input source switch may not have completed: expected \(target), got \(actual)")
        }
    }
    
    /// 토글 (현재 상태의 반대로 전환)
    func toggle() {
        let current = currentSource()
        let target: InputSource = current == .korean ? .english : .korean
        switchTo(target)
    }
    
    // MARK: - Private Helpers
    
    private func getSourceID(_ source: TISInputSource) -> String {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }
}
