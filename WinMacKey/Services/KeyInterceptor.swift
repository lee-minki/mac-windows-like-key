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
    private var keyMappings: [Int64: Int64] = [:]

    // Right Cmd tap-only 감지 상태
    private var rightCmdPressed = false
    private var rightCmdUsedAsModifier = false

    // VDI 모드: 우측 Command → 우측 Option 변환
    var useVdiMode: Bool = false

    // 이벤트 로그 최대 개수
    private let maxEventLogCount = 1000

    // 로거
    private let logger = Logger(subsystem: "com.winmackey.app", category: "KeyInterceptor")

    // 한영전환 콜백
    var onInputSourceToggle: (() -> Void)?

    // 이벤트 콜백
    var onKeyEvent: ((KeyEvent) -> Void)?
    
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
    
    // MARK: - Setup
    
    private func setupDefaultMappings() {
        logger.info("Setting up default mappings...")
        // 1. fn (63) → Left Command (55)
        keyMappings[Int64(kVK_Function)] = Int64(kVK_Command)
        
        // 2. Left Command (55) → Left Control (59)
        keyMappings[Int64(kVK_Command)] = Int64(kVK_Control)
        
        // 3. Left Control (59) → fn (63)
        keyMappings[Int64(kVK_Control)] = Int64(kVK_Function)
        
        // Right Command는 handleEvent에서 VDI 모드에 따라 분기 처리
        
        // CapsLock (57) → 57 (순수 캡스락)
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
    }
    
    func updateMappings(from profile: Profile) {
        keyMappings.removeAll()
        for mapping in profile.mappings {
            keyMappings[Int64(mapping.fromKey)] = Int64(mapping.toKey)
        }
        // 기본 매핑 복구 필요 여부 체크 (현재 고정 매핑 우선)
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
        
        // ====== Right Cmd가 눌린 상태에서 다른 키 입력 시 modifier로 사용된 것으로 표시 ======
        if interceptor.rightCmdPressed && keyCode != rightCmdKeyCode && (type == .keyDown || type == .keyUp) {
            interceptor.rightCmdUsedAsModifier = true
        }
        
        // ====== Right Cmd 처리 (VDI 모드 분기) ======
        
        if keyCode == rightCmdKeyCode {
            if interceptor.useVdiMode {
                // VDI 모드: Right Cmd(54) -> Right Option(61) 로 순수 매핑
                let rightOptionKeyCode = Int64(kVK_RightOption)
                mappedKeyCode = rightOptionKeyCode
                
                if type == .flagsChanged {
                    event.setIntegerValueField(.keyboardEventKeycode, value: rightOptionKeyCode)
                    interceptor.updateModifierFlags(event: event, originalKey: rightCmdKeyCode, newKey: rightOptionKeyCode)
                }
                
            } else {
                // 기존 모드: Tap-Only 감지 (macOS TIS 한영 전환)
                if type == .flagsChanged {
                    let isDown = event.flags.contains(.maskCommand)
                    
                    if isDown {
                        interceptor.rightCmdPressed = true
                        interceptor.rightCmdUsedAsModifier = false
                    } else {
                        if interceptor.rightCmdPressed && !interceptor.rightCmdUsedAsModifier {
                            interceptor.logger.info("Right Cmd tap-only detected → toggling input source")
                            interceptor.onInputSourceToggle?()
                        }
                        interceptor.rightCmdPressed = false
                        interceptor.rightCmdUsedAsModifier = false
                    }
                    
                    interceptor.logEvent(event, startTime: startTime, originalKey: keyCode, mappedKey: keyCode)
                    return Unmanaged.passUnretained(event)
                }
            }
        }
        
        // ====== 일반 매핑 처리 ======
        
        if keyCode != rightCmdKeyCode, let newKeyCode = interceptor.keyMappings[keyCode] {
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
        
        let keyEvent = KeyEvent(
            type: eventType,
            rawKey: UInt32(originalKey),
            mappedKey: UInt32(mappedKey),
            latencyMicroseconds: latencyMicros,
            bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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
