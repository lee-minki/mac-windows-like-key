import Foundation
import AppKit
import Carbon.HIToolbox

/// CGEventTap 기반 키보드 이벤트 인터셉터
/// 실시간으로 키 입력을 캡처하고 변환합니다.
class KeyInterceptor: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    
    @Published var events: [KeyEvent] = []
    @Published var averageLatencyMs: Double = 0.0
    @Published var totalEventCount: Int = 0
    
    // 키 매핑 테이블 (CGKeyCode 기반)
    // macOS CGKeyCode: https://developer.apple.com/documentation/coregraphics/cgkeycode
    private var keyMappings: [Int64: Int64] = [:]
    
    // 이벤트 콜백
    var onKeyEvent: ((KeyEvent) -> Void)?
    
    // 최대 이벤트 로그 수 (메모리 관리)
    private let maxEventLogCount = 500
    
    // 싱글톤 참조 (C 콜백에서 사용)
    static var shared: KeyInterceptor?
    
    // Modifier Key Code to Flag Mapping
    private let modifierKeyToFlag: [Int64: CGEventFlags] = [
        Int64(kVK_Command): .maskCommand,
        Int64(kVK_RightCommand): .maskCommand,
        Int64(kVK_Control): .maskControl,
        Int64(kVK_RightControl): .maskControl,
        Int64(kVK_Shift): .maskShift,
        Int64(kVK_RightShift): .maskShift,
        Int64(kVK_Option): .maskAlternate,
        Int64(kVK_RightOption): .maskAlternate,
        Int64(kVK_Function): .maskSecondaryFn,
        Int64(kVK_CapsLock): .maskAlphaShift
    ]
    
    init() {
        KeyInterceptor.shared = self
        setupDefaultMappings()
    }
    
    // MARK: - Setup
    
    private func setupDefaultMappings() {
        // Windows 스타일 키 매핑
        // macOS Key Codes (Carbon.HIToolbox):
        // kVK_Function = 0x3F (63) - fn
        // kVK_Command = 0x37 (55) - left command
        // kVK_Control = 0x3B (59) - left control
        // kVK_RightCommand = 0x36 (54) - right command
        // kVK_CapsLock = 0x39 (57) - caps lock
        // kVK_F18 = 0x4F (79) - 한영 전환용
        
        // 1. fn → Left Command
        keyMappings[Int64(kVK_Function)] = Int64(kVK_Command)
        
        // 2. Left Control → fn
        keyMappings[Int64(kVK_Control)] = Int64(kVK_Function)
        
        // 3. Left Command → Left Control
        keyMappings[Int64(kVK_Command)] = Int64(kVK_Control)
        
        // 4. Right Command → F18 (한영전환 - 시스템 설정에서 F18을 입력소스 전환으로 설정 필요)
        keyMappings[Int64(kVK_RightCommand)] = Int64(kVK_F18)
        
        // 5. CapsLock → CapsLock (순수 캡스락, 한영전환 비활성화)
        // 참고: 시스템 설정에서 CapsLock 한영전환을 끄려면
        // 시스템 설정 > 키보드 > 입력 소스 > "Caps Lock으로 ABC 입력 소스 전환" 해제 필요
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
    }
    
    func updateMappings(from profile: Profile) {
        keyMappings.removeAll()
        for mapping in profile.mappings {
            keyMappings[Int64(mapping.fromKey)] = Int64(mapping.toKey)
        }
    }
    
    func addMapping(from: Int64, to: Int64) {
        keyMappings[from] = to
    }
    
    func removeMapping(from: Int64) {
        keyMappings.removeValue(forKey: from)
    }
    
    func clearMappings() {
        keyMappings.removeAll()
    }
    
    // MARK: - Engine Control
    
    func start() {
        guard !isRunning else { return }
        
        // 이벤트 마스크: keyDown, keyUp, flagsChanged (modifier keys)
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue)
        
        // CGEventTap 생성
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,          // 세션 레벨 탭
            place: .headInsertEventTap,       // 이벤트 체인 앞에 삽입
            options: .defaultTap,             // 이벤트 수정 가능
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                return KeyInterceptor.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: nil
        ) else {
            print("[KeyInterceptor] Failed to create event tap. Check Accessibility permissions.")
            return
        }
        
        eventTap = tap
        
        // RunLoopSource 생성 및 추가
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // 탭 활성화
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isRunning = true
        print("[KeyInterceptor] Engine started with CGEventTap")
    }
    
    func stop() {
        guard isRunning else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        print("[KeyInterceptor] Engine stopped")
    }
    
    // MARK: - Event Handling (Static callback for C interop)
    
    private static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        let startTime = DispatchTime.now()
        
        // 탭이 비활성화된 경우 재활성화
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = shared?.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard let interceptor = shared else {
            return Unmanaged.passUnretained(event)
        }
        
        // 키 코드 추출
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var mappedKeyCode = keyCode
        var finalEvent = event
        
        // 매핑 로직
        if let newKeyCode = interceptor.keyMappings[keyCode] {
            mappedKeyCode = newKeyCode
            
            let isSourceModifier = interceptor.modifierKeyToFlag[keyCode] != nil
            let isDestModifier = interceptor.modifierKeyToFlag[newKeyCode] != nil
            
            // Scenario 1: Modifier Key -> General Key (예: Right Command -> F18)
            // FlagsChanged 이벤트를 KeyDown/KeyUp으로 변환해야 함
            if isSourceModifier && !isDestModifier && type == .flagsChanged {
                if let srcFlag = interceptor.modifierKeyToFlag[keyCode] {
                    // 플래그 상태로 Down/Up 판단
                    let isDown = event.flags.contains(srcFlag)
                    
                    // 새 이벤트 생성
                    if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(newKeyCode), keyDown: isDown) {
                        // 기존 플래그 유지하되, 원본 Modifier 플래그는 제거
                        var newFlags = event.flags
                        newFlags.remove(srcFlag)
                        newEvent.flags = newFlags
                        
                        finalEvent = newEvent
                        // 중요: 여기서 리턴하지 않고 아래 로깅 로직을 타게 하거나,
                        // Unmanaged.passRetained(finalEvent)를 반환해야 함.
                        // 로깅을 위해 finalEvent 업데이트 후 진행.
                    }
                }
            }
            // Scenario 2: Modifier Key -> Modifier Key (예: Cmd -> Ctrl)
            else if isSourceModifier && isDestModifier {
                event.setIntegerValueField(.keyboardEventKeycode, value: newKeyCode)
                interceptor.updateModifierFlags(event: event, originalKey: keyCode, newKey: newKeyCode)
            }
            // Scenario 3: General Key -> General Key
            else if !isSourceModifier && !isDestModifier {
                event.setIntegerValueField(.keyboardEventKeycode, value: newKeyCode)
            }
            // Scenario 4: General -> Modifier (현재 미지원, 필요시 구현)
            else {
                // 단순 매핑 처리
                event.setIntegerValueField(.keyboardEventKeycode, value: newKeyCode)
            }
        }
        
        // 이벤트 타입 결정 (로깅용)
        let eventType: KeyEventType
        let currentType = finalEvent.type
        switch currentType {
        case .keyDown:
            eventType = .down
        case .keyUp:
            eventType = .up
        case .flagsChanged:
            let flags = finalEvent.flags
            eventType = flags.contains(.maskCommand) || flags.contains(.maskShift) ||
                       flags.contains(.maskAlternate) || flags.contains(.maskControl) ? .down : .up
        default:
            return Unmanaged.passUnretained(event)
        }
        
        // 지연 시간 계산
        let endTime = DispatchTime.now()
        let latencyNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let latencyMicros = UInt64(latencyNanos / 1000)
        
        // 이벤트 기록
        let keyEvent = KeyEvent(
            type: eventType,
            rawKey: UInt32(keyCode),
            mappedKey: UInt32(mappedKeyCode),
            latencyMicroseconds: latencyMicros,
            bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        
        DispatchQueue.main.async {
            interceptor.recordEvent(keyEvent)
        }
        
        // 새 이벤트가 생성되었다면 Retained로 반환, 아니면 Unretained
        if finalEvent !== event {
            return Unmanaged.passRetained(finalEvent)
        }
        
        return Unmanaged.passUnretained(finalEvent)
    }
    
    private func recordEvent(_ event: KeyEvent) {
        events.append(event)
        totalEventCount += 1
        
        // 메모리 관리: 오래된 이벤트 제거
        if events.count > maxEventLogCount {
            events.removeFirst(events.count - maxEventLogCount)
        }
        
        // 평균 지연 시간 계산
        let recentEvents = events.suffix(100)
        if !recentEvents.isEmpty {
            let totalLatency = recentEvents.reduce(0.0) { $0 + $1.latencyMs }
            averageLatencyMs = totalLatency / Double(recentEvents.count)
        }
        
        onKeyEvent?(event)
    }
    
    // MARK: - Utility
    
    func clearEvents() {
        events.removeAll()
        totalEventCount = 0
        averageLatencyMs = 0.0
    }
    
    func exportEventsAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(events) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// 현재 등록된 매핑 목록 반환
    func getCurrentMappings() -> [(from: Int64, to: Int64)] {
        return keyMappings.map { (from: $0.key, to: $0.value) }
    }
    
    // MARK: - Modifier Flag Processing
    
    private func updateModifierFlags(event: CGEvent, originalKey: Int64, newKey: Int64) {
        // 1. 해당 키가 Modifier Key인지 확인 (Original Key 기준)
        // 일반 키라면 굳이 플래그 처리를 할 필요 없거나, 복잡해짐.
        // 하지만 "Cmd -> A" 같은 매핑이라면 Cmd 플래그를 꺼줘야 한다.
        // 반대로 "A -> Cmd"라면 Cmd 플래그를 켜줘야 한다.
        // 따라서 Original 또는 New 중 하나라도 Modifier라면 처리가 필요함.
        
        // 원본 키의 플래그 (있다면)
        let originalFlag = modifierKeyToFlag[originalKey]
        
        // 새 키의 플래그 (있다면)
        let newFlag = modifierKeyToFlag[newKey]
        
        // 둘 다 일반 키라면 패스
        if originalFlag == nil && newFlag == nil { return }
        
        var currentFlags = event.flags
        
        // 키가 눌려있는지 판단하는 로직 개선
        // CGEventFlags는 "현재 상태"를 나타냄.
        
        // Case 1: Original Key가 Modifier인 경우 (예: Cmd -> Ctrl)
        if let srcFlag = originalFlag {
            if currentFlags.contains(srcFlag) {
                // 원본 플래그가 켜져 있음 -> 키가 눌린 상태 (Key Down)
                // 원본 플래그 제거
                currentFlags.remove(srcFlag)
                
                // 새 플래그 추가 (있다면)
                if let dstFlag = newFlag {
                    currentFlags.insert(dstFlag)
                }
            } else {
                // 원본 플래그가 꺼져 있음 -> 키가 떼진 상태 (Key Up)
                // 새 플래그도 제거
                if let dstFlag = newFlag {
                    currentFlags.remove(dstFlag)
                }
            }
        }
        // Case 2: Original Key는 일반 키인데, New Key가 Modifier인 경우 (예: A -> Cmd)
        // 일반 키 이벤트(KeyDown/Up)에 따라 플래그를 제어해야 함.
        else if let dstFlag = newFlag {
            // 이 경우 event.type을 봐야 함
            let type = event.type
            if type == .keyDown {
                currentFlags.insert(dstFlag)
            } else if type == .keyUp {
                currentFlags.remove(dstFlag)
            }
            // flagsChanged로 들어온 게 아니므로 별도 처리 필요
        }
        
        event.flags = currentFlags
    }
}
