import Foundation
import AppKit
import Carbon.HIToolbox
import os.log

/// CGEventTap 기반 키보드 이벤트 인터셉터
/// Right Cmd tap-only 감지 + 기존 키 리매핑 + EventTap 자동 재활성화
class KeyInterceptor: ObservableObject {
    static weak var shared: KeyInterceptor?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var reactivationTimer: Timer?

    @Published var events: [KeyEvent] = []
    @Published var averageLatencyMs: Double = 0.0
    @Published var totalEventCount: Int = 0

    // 키 매핑 테이블 (fn↔Cmd↔Ctrl 등 기존 매핑)
    private(set) var keyMappings: [Int64: Int64] = [:]

    // Right Cmd/Opt tap-only 감지 상태
    private var triggerKeyPressed = false
    private var triggerKeyUsedAsModifier = false
    private var triggerKeyDownTime: UInt64 = 0  // 누르는 순간의 타임스탬프 (ns)
    private var previousFlags: CGEventFlags = []
    
    /// Tap-only 타이밍 임계값 (ns)
    /// 이 시간 이내에 떄 경우, 다른 키가 눌렸어도 tap으로 간주
    private let tapThresholdNs: UInt64 = 300_000_000  // 300ms

    // 한영 전환 트리거 키 (기본: Right Cmd, 옵션: Right Opt)
    var triggerKeyCode: Int64 = Int64(kVK_RightCommand)

    // VDI 모드: 우측 Command → 우측 Option 변환
    @Published var useVdiMode: Bool = false

    // 이벤트 로그 최대 개수
    private let maxEventLogCount = 1000

    // 로거
    private let logger = Logger(subsystem: "com.winmackey.app", category: "KeyInterceptor")

    // 한영전환 콜백
    var onInputSourceToggle: (() -> Void)?

    // 이벤트 콜백
    var onKeyEvent: ((KeyEvent) -> Void)?
    
    // 키 감지/검증 콜백 (ModifierLayoutView 마법사용)
    // (originalKeyCode, mappedKeyCode, isDown)
    var onVerifyKeyEvent: ((Int64, Int64, Bool) -> Void)?
    
    // Modifier Flags Mapping
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
    
    // 활성화된 프로파일 ID (AppStorage와 동기화)
    // NOTE: didSet에서 setupDefaultMappings를 호출하지 않음.
    // applyCustomMappings가 HID 매핑을 설정한 후 didSet이 async로 setupDefaultMappings를
    // 호출하여 HID 매핑을 덮어쓰는 레이스 컨디션을 방지합니다.
    var activeProfileID: String = "standardMac"
    
    // MARK: - Setup
    
    func setupDefaultMappings() {
        logger.info("Setting up mappings for profile: \(self.activeProfileID)")
        
        keyMappings.removeAll()
        
        // 선택된 프로파일 찾기
        var selectedProfile = MappingProfile.defaultProfiles.first { $0.id.uuidString == activeProfileID }
        
        // UUID 매칭 실패시 하드코딩된 이름으로 폴백 매칭 시도
        if selectedProfile == nil {
            if activeProfileID == "standardMac" { selectedProfile = .standardMac }
            else if activeProfileID == "windowsBluetooth" { selectedProfile = .windowsBluetooth }
            else if activeProfileID == "winMacKeyOriginal" { selectedProfile = .winMacKeyOriginal }
        }
        
        if let profile = selectedProfile {
            for (src, dst) in profile.mappings {
                keyMappings[src] = dst
            }
        } else {
            // 저장된 프로필 UUID 또는 visualCustomProfile — UserDefaults에서 매핑 로드
            if let data = UserDefaults.standard.data(forKey: "visualCustomMappings"),
               let dict = try? JSONDecoder().decode([String: Int64].self, from: data) {
                for (key, value) in dict {
                    if let k = Int64(key) {
                        keyMappings[k] = value
                    }
                }
                logger.info("Loaded custom mappings from UserDefaults for profile: \(self.activeProfileID)")
            } else {
                logger.warning("No saved mappings found for profile: \(self.activeProfileID)")
            }
        }
        
        // CapsLock (57) → 57 (순수 캡스락) - 프로파일 상관없이 유지
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
        
        // HID 레벨 리매핑 적용 (Fn/Globe 포함)
        HIDRemapper.shared.applyMappings(keyMappings)
    }
    
    func applyCustomMappings(_ mappings: [Int64: Int64]) {
        keyMappings.removeAll()
        for (src, dst) in mappings {
            keyMappings[src] = dst
        }
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
        
        // HID 레벨 리매핑 적용 (Fn/Globe 포함)
        HIDRemapper.shared.applyMappings(mappings)
    }
    
    /// 동기 버전 — 위저드 Step 3 등 완료 보장이 필요할 때
    func applyCustomMappingsSync(_ mappings: [Int64: Int64]) {
        keyMappings.removeAll()
        for (src, dst) in mappings {
            keyMappings[src] = dst
        }
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
        
        HIDRemapper.shared.applyMappingsSync(mappings)
    }
    
    func updateMappings(from profileId: String) {
        self.activeProfileID = profileId
        setupDefaultMappings()
    }
    
    // MARK: - Engine Control
    
    func start() {
        guard !isRunning else { return }
        
        logger.info("Attempting to start engine...")
        
        // 이벤트 마스크: keyDown, keyUp, flagsChanged
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                return KeyInterceptor.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: nil
        ) else {
            logger.error("Failed to create event tap. Check Accessibility permissions.")
            return
        }
        
        eventTap = tap
        
        // RunLoopSource 생성
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isRunning = true
        logger.info("Engine started successfully.")
        
        // EventTap 자동 재활성화 타이머 시작
        startReactivationTimer()
    }
    
    func stop() {
        guard isRunning else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        reactivationTimer?.invalidate()
        reactivationTimer = nil
        
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        
        // HID 매핑도 해제 (동기 — 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
        
        logger.info("Engine stopped.")
    }
    
    // MARK: - EventTap Reactivation
    
    /// macOS는 CGEventTap 콜백이 ~3초 이상 응답하지 않으면 자동으로 비활성화합니다.
    /// 5초 간격으로 모니터링하여 자동 재활성화합니다.
    private func startReactivationTimer() {
        reactivationTimer?.invalidate()
        reactivationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                self.logger.warning("EventTap was disabled, re-enabled by timer.")
            }
        }
    }
    
    // MARK: - Event Handling
    
    private static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        let startTime = DispatchTime.now()
        
        // 탭 재활성화 (콜백 내 즉시 처리)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = shared?.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                shared?.logger.warning("Tap re-enabled in callback.")
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard let interceptor = shared else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rightCmdKeyCode = Int64(kVK_RightCommand)
        var mappedKeyCode = keyCode
        var finalEvent = event
        
        let triggerKey = interceptor.triggerKeyCode
        
        // ====== 트리거 키가 눌린 상태에서 다른 키 keyDown 시 modifier로 사용된 것으로 표시 ======
        // ⚠️ keyUp은 제외: 빠른 타이핑 중 이전 키의 keyUp이 트리거 구간에 발생해도 tap 무효화하지 않음
        if interceptor.triggerKeyPressed && keyCode != triggerKey && type == .keyDown {
            interceptor.triggerKeyUsedAsModifier = true
        }
        
        // ====== 트리거 키 처리 (한영 전환 / VDI 모드) ======
        
        if keyCode == triggerKey {
            // VDI 모드: Right Cmd → Right Option 순수 매핑 (트리거가 Right Cmd일 때만)
            if interceptor.useVdiMode && triggerKey == rightCmdKeyCode {
                let rightOptionKeyCode = Int64(kVK_RightOption)
                mappedKeyCode = rightOptionKeyCode
                
                if type == .flagsChanged {
                    event.setIntegerValueField(.keyboardEventKeycode, value: rightOptionKeyCode)
                    interceptor.updateModifierFlags(event: event, originalKey: rightCmdKeyCode, newKey: rightOptionKeyCode)
                }
                
            } else {
                // Tap-Only 감지 (macOS TIS 한영 전환)
                if type == .flagsChanged {
                    // 트리거 키에 맞는 modifier flag로 isDown 판별
                    // Left+Right 동시 홀드 엣지케이스 대응: flags 델타로 판단
                    let triggerFlag: CGEventFlags
                    if triggerKey == rightCmdKeyCode {
                        triggerFlag = .maskCommand
                    } else {
                        triggerFlag = .maskAlternate
                    }
                    
                    // 이전 flags와 비교하여 변화 방향으로 isDown 판단
                    let flagsNow = event.flags.contains(triggerFlag)
                    let flagsBefore = interceptor.previousFlags.contains(triggerFlag)
                    let isDown: Bool
                    if flagsNow && !flagsBefore {
                        isDown = true   // flag가 새로 켜짐 → 누름
                    } else if !flagsNow && flagsBefore {
                        isDown = false  // flag가 꺼짐 → 뗌
                    } else {
                        // flag 변화 없음 (다른 쪽이 눌린/떼 경우) → keyCode로 판단
                        isDown = flagsNow
                    }
                    interceptor.previousFlags = event.flags
                    
                    if isDown {
                        if !interceptor.triggerKeyPressed {
                            // keyDown: 상태만 기록, 전환하지 않음
                            interceptor.triggerKeyPressed = true
                            interceptor.triggerKeyUsedAsModifier = false
                            interceptor.triggerKeyDownTime = DispatchTime.now().uptimeNanoseconds
                        }
                    } else {
                        // keyUp: tap-only 판단
                        if interceptor.triggerKeyPressed {
                            let elapsed = DispatchTime.now().uptimeNanoseconds - interceptor.triggerKeyDownTime
                            
                            // Tap 판정: (1) modifier로 안 쓴 경우, 또는
                            //          (2) 쓴 경우라도 임계값 이내면 빠른 타이핑 중 오탐으로 간주
                            let isTap = !interceptor.triggerKeyUsedAsModifier || elapsed < interceptor.tapThresholdNs
                            
                            if isTap {
                                interceptor.logger.info("Trigger key tap-only detected (\(elapsed / 1_000_000)ms) → toggling input source")
                                interceptor.onInputSourceToggle?()
                            }
                        }
                        interceptor.triggerKeyPressed = false
                        interceptor.triggerKeyUsedAsModifier = false
                    }
                    
                    // 트리거 키 이벤트도 수집기(EventViewer)에 찍히도록 로깅
                    interceptor.logEvent(event, startTime: startTime, originalKey: keyCode, mappedKey: keyCode)
                    return Unmanaged.passUnretained(event)
                }
            }
        }
        
        // ====== 일반 매핑 처리 ======
        
        if keyCode != triggerKey, let newKeyCode = interceptor.keyMappings[keyCode] {
            mappedKeyCode = newKeyCode
            
            let isSourceModifier = interceptor.modifierKeyToFlag[keyCode] != nil
            let isDestModifier = interceptor.modifierKeyToFlag[newKeyCode] != nil
            
            if type == .flagsChanged {
                // ── flagsChanged 이벤트에서의 매핑 ──
                
                if isSourceModifier && isDestModifier {
                    // Modifier → Modifier (예: fn→Cmd, Cmd→Ctrl, Ctrl→fn)
                    // 새 이벤트를 생성하여 시스템의 기본 modifier 처리를 우회
                    if let srcFlag = interceptor.modifierKeyToFlag[keyCode] {
                        let isDown = event.flags.contains(srcFlag)
                        
                        // flagsChanged 이벤트를 새로 생성
                        if let newEvent = CGEvent(keyboardEventSource: CGEventSource(event: event),
                                                   virtualKey: CGKeyCode(newKeyCode),
                                                   keyDown: isDown) {
                            // 이벤트 타입을 flagsChanged로 설정
                            newEvent.type = .flagsChanged
                            
                            // 플래그 구성: 원본 플래그에서 소스 플래그를 제거하고 대상 플래그를 추가
                            var newFlags = event.flags
                            newFlags.remove(srcFlag)
                            if isDown, let dstFlag = interceptor.modifierKeyToFlag[newKeyCode] {
                                newFlags.insert(dstFlag)
                            } else if !isDown, let dstFlag = interceptor.modifierKeyToFlag[newKeyCode] {
                                newFlags.remove(dstFlag)
                            }
                            newEvent.flags = newFlags
                            
                            finalEvent = newEvent
                        }
                    }
                }
                else if isSourceModifier && !isDestModifier {
                    // Modifier → General Key (예: 특수 시나리오)
                    if let srcFlag = interceptor.modifierKeyToFlag[keyCode] {
                        let isDown = event.flags.contains(srcFlag)
                        if let newEvent = CGEvent(keyboardEventSource: CGEventSource(event: event),
                                                   virtualKey: CGKeyCode(newKeyCode),
                                                   keyDown: isDown) {
                            var newFlags = event.flags
                            newFlags.remove(srcFlag)
                            newEvent.flags = newFlags
                            finalEvent = newEvent
                        }
                    }
                }
                // General → Modifier in flagsChanged: 거의 발생하지 않으므로 패스
            }
            else {
                // ── keyDown / keyUp 이벤트에서의 매핑 ──
                // 단순히 keyCode만 교체 (General→General, 또는 Modifier keyCode가 keyDown/keyUp으로 오는 경우)
                event.setIntegerValueField(.keyboardEventKeycode, value: newKeyCode)
            }
        }
        
        // 로깅
        interceptor.logEvent(finalEvent, startTime: startTime, originalKey: keyCode, mappedKey: mappedKeyCode)
        
        // 검증 콜백 호출 (Step 1 키 감지 / Step 3 실시간 확인용)
        if let verify = interceptor.onVerifyKeyEvent {
            let isDown: Bool
            if type == .flagsChanged {
                if let flag = interceptor.modifierKeyToFlag[keyCode] {
                    isDown = event.flags.contains(flag)
                } else {
                    isDown = true
                }
            } else {
                isDown = (type == .keyDown)
            }
            if isDown {
                DispatchQueue.main.async {
                    verify(keyCode, mappedKeyCode, true)
                }
            }
        }
        
        if finalEvent !== event {
            return Unmanaged.passRetained(finalEvent)
        }
        return Unmanaged.passUnretained(finalEvent)
    }
    
    private func updateModifierFlags(event: CGEvent, originalKey: Int64, newKey: Int64) {
        let originalFlag = modifierKeyToFlag[originalKey]
        let newFlag = modifierKeyToFlag[newKey]
        
        guard let srcFlag = originalFlag, let dstFlag = newFlag else { return }
        
        var currentFlags = event.flags
        
        if currentFlags.contains(srcFlag) {
            // Key Down
            currentFlags.remove(srcFlag)
            currentFlags.insert(dstFlag)
        } else {
            // Key Up
            currentFlags.remove(srcFlag)
            currentFlags.remove(dstFlag)
        }
        
        event.flags = currentFlags
    }
    
    // MARK: - Logging
    
    private func logEvent(_ event: CGEvent, startTime: DispatchTime, originalKey: Int64, mappedKey: Int64) {
        let endTime = DispatchTime.now()
        let latencyMicros = UInt64((endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1000)
        
        // 이벤트 타입 판별
        let eventType: KeyEventType
        switch event.type {
        case .keyDown:
            eventType = .down
        case .keyUp:
            eventType = .up
        case .flagsChanged:
            // flagsChanged에서는 매핑된 키의 플래그를 확인하여 down/up 판별
            if let flag = modifierKeyToFlag[mappedKey] {
                eventType = event.flags.contains(flag) ? .down : .up
            } else {
                // 매핑 대상이 일반 키인 경우 (Modifier→General 매핑)
                // 새 이벤트가 keyDown/keyUp으로 변환되었을 수 있으므로 event.type으로 판단
                eventType = .down
            }
        default:
            eventType = .up
        }
        
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        
        let keyEvent = KeyEvent(
            type: eventType,
            rawKey: UInt32(originalKey),
            mappedKey: UInt32(mappedKey),
            latencyMicroseconds: latencyMicros,
            bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            keyboardType: keyboardType
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.recordEvent(keyEvent)
        }
    }
    
    private func recordEvent(_ event: KeyEvent) {
        events.append(event)
        totalEventCount += 1
        if events.count > maxEventLogCount {
            events.removeFirst(events.count - maxEventLogCount)
        }
        
        let recentEvents = events.suffix(100)
        if !recentEvents.isEmpty {
            let totalLatency = recentEvents.reduce(0.0) { $0 + $1.latencyMs }
            averageLatencyMs = totalLatency / Double(recentEvents.count)
        }
        
        onKeyEvent?(event)
    }
    
    func clearEvents() {
        events.removeAll()
        totalEventCount = 0
        averageLatencyMs = 0.0
    }
    
    func exportEventsAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
