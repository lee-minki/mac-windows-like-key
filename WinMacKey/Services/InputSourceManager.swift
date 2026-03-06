import Foundation
import Carbon.HIToolbox
import os.log

/// 시스템에 설치된 입력 소스 정보
struct InputSourceInfo: Identifiable, Codable, Equatable, Hashable {
    let id: String        // "com.apple.inputmethod.Korean.2SetKorean"
    let localizedName: String  // "한국어 (2-Set Korean)"
    
    static func == (lhs: InputSourceInfo, rhs: InputSourceInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// TIS (Text Input Sources) API 래퍼
/// 범용 언어 페어 토글을 지원합니다 (한/영, 日/英, 中/英 등 모든 조합).
class InputSourceManager {
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "InputSourceManager")
    
    /// 사용자가 설정한 언어 페어 (Source 1 ↔ Source 2 토글)
    /// UserDefaults에서 로드되며, 비어있으면 자동 감지합니다.
    var source1ID: String = ""
    var source2ID: String = ""
    
    // MARK: - 시스템 입력 소스 조회
    
    /// 시스템에 설치된 모든 키보드 입력 소스 목록
    func getAvailableSources() -> [InputSourceInfo] {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        
        return sourceList.compactMap { source -> InputSourceInfo? in
            let id = getSourceID(source)
            let name = getSourceName(source)
            let category = getSourceCategory(source)
            
            // 키보드 입력 소스만 필터 (키보드 레이아웃 + 입력기)
            guard category == kTISCategoryKeyboardInputSource as String else { return nil }
            guard !id.isEmpty else { return nil }
            
            return InputSourceInfo(id: id, localizedName: name)
        }
    }
    
    /// 현재 활성화된 입력 소스 ID
    func currentSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return getSourceID(source)
    }
    
    /// 현재 입력 소스가 source1인지 source2인지 판별
    func currentSourceIndex() -> Int {
        let current = currentSourceID()
        if current == source1ID { return 1 }
        if current == source2ID { return 2 }
        // 패턴 매칭 폴백 — 한국어 등 입력기(inputmethod)는 하위 소스 ID가 달라질 수 있음
        if matchesSource(current, target: source1ID) { return 1 }
        if matchesSource(current, target: source2ID) { return 2 }
        
        logger.warning("Unknown source: '\(current)' (pair: '\(self.source1ID)' / '\(self.source2ID)')")
        return 0  // 알 수 없음
    }
    
    /// 현재 입력 소스의 표시 이름
    func currentSourceName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "?"
        }
        return getSourceName(source)
    }
    
    /// 현재 입력 소스의 짧은 표시 이름 (메뉴바용)
    func currentSourceShortName() -> String {
        let id = currentSourceID()
        // 알려진 패턴에서 짧은 이름 추출
        if id.contains("Korean") { return "한" }
        if id.contains("Japanese") || id.contains("Kotoeri") { return "あ" }
        if id.contains("Chinese") || id.contains("Pinyin") { return "中" }
        if id.contains("ABC") || id.contains(".US") { return "EN" }
        // 범용: 로컬라이즈된 이름의 첫 2글자
        let name = currentSourceName()
        return String(name.prefix(2))
    }
    
    // MARK: - 전환

    /// Control+Space CGEvent를 합성하여 시스템 입력소스 전환을 트리거합니다.
    /// TISSelectInputSource 대신 시스템 단축키를 사용하여:
    /// - CJKV 입력기의 조합 버퍼를 macOS가 자동 commit
    /// - 메뉴바 아이콘을 macOS가 자동 갱신
    /// - VDI 앱에서도 Control+Space 이벤트가 전달됨
    func toggleViaKeyboardShortcut() {
        // Control+Space keyDown
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: true) else {
            logger.error("Failed to create Control+Space keyDown event")
            return
        }
        keyDown.flags = .maskControl

        // Control+Space keyUp
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: false) else {
            logger.error("Failed to create Control+Space keyUp event")
            return
        }
        keyUp.flags = .maskControl

        // 합성 이벤트 마커 설정 (CGEventTap 재진입 방지)
        keyDown.setIntegerValueField(.eventSourceUserData, value: 0x57494E4B)
        keyUp.setIntegerValueField(.eventSourceUserData, value: 0x57494E4B)

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        logger.info("Toggle: posted Control+Space shortcut")
    }
    
    // MARK: - 자동 감지
    
    /// 시스템에 설치된 입력 소스에서 자동으로 언어 페어를 추론
    func autoDetectPair() -> (source1: String, source2: String)? {
        let sources = getAvailableSources()
        
        // 영어 계열 찾기 (source1 후보)
        let english = sources.first { $0.id.contains("ABC") || $0.id.contains(".US") }
        
        // 비영어 입력기 찾기 (source2 후보) — 우선순위: Korean > Japanese > Chinese > 기타
        let nonEnglish = sources.first { $0.id.contains("Korean") }
            ?? sources.first { $0.id.contains("Japanese") || $0.id.contains("Kotoeri") }
            ?? sources.first { $0.id.contains("Chinese") || $0.id.contains("Pinyin") }
            ?? sources.first { src in
                !src.id.contains("ABC") && !src.id.contains(".US") && !src.id.contains("keylayout.Unicode")
            }
        
        guard let eng = english, let other = nonEnglish else { return nil }
        return (source1: eng.id, source2: other.id)
    }
    
    // MARK: - Private Helpers
    
    private func getSourceID(_ source: TISInputSource) -> String {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }
    
    private func getSourceName(_ source: TISInputSource) -> String {
        guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return "" }
        return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }
    
    private func getSourceCategory(_ source: TISInputSource) -> String {
        guard let catPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { return "" }
        return Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
    }
    
    /// 부분 매칭 — 한국어 입력기는 하위 모드에 따라 ID가 달라질 수 있음
    /// 예: "com.apple.inputmethod.Korean.2SetKorean" vs "com.apple.inputmethod.Korean"
    private func matchesSource(_ sourceID: String, target: String) -> Bool {
        if sourceID == target { return true }
        // 한쪽이 다른 쪽의 prefix인 경우 (Korean 입력기 하위 모드)
        if sourceID.hasPrefix(target) || target.hasPrefix(sourceID) { return true }
        // 같은 패밀리인지 확인 (예: Korean.2Set vs Korean.3Set)
        let sourceParts = sourceID.split(separator: ".")
        let targetParts = target.split(separator: ".")
        if sourceParts.count >= 3 && targetParts.count >= 3 {
            return sourceParts.prefix(3).joined(separator: ".") == targetParts.prefix(3).joined(separator: ".")
        }
        return false
    }
}
