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

    // Right Cmd/Opt toggle 상태 (연속 토글 방지용)
    private var triggerKeyPressed = false
    private var previousFlags: CGEventFlags = []
    private var awaitingInputSourceCommit = false
    private var bufferedKeyEvents: [CGEvent] = []
    private var bufferedFlushWorkItem: DispatchWorkItem?

    private let inputSourceCommitTimeout: TimeInterval = 0.040
    private let maxBufferedEventCount = 8

    /// 합성 이벤트 식별자 — 재진입 방지용 (탭이 자신이 주입한 이벤트를 재처리하지 않도록)
    private static let syntheticEventMarker: Int64 = 0x57494E4B  // "WINK"

    // 한영 전환 트리거 키 (기본: Right Command)
    var triggerKeyCode: Int64 = Int64(kVK_RightCommand)

    // VDI 앱 포커스 여부 (ContextManager가 자동 갱신)
    var isVdiAppFocused: Bool = false
    
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

    // ContextManager가 앱 전환 시 갱신 — 콜백 내 NSWorkspace 동기 호출 제거용
    var cachedBundleId: String? = nil
    
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
        
        // 이름 기반 매칭 (기본 프로파일)
        let selectedProfile: MappingProfile?
        switch activeProfileID {
        case "standardMac":      selectedProfile = .standardMac
        case "windowsBluetooth": selectedProfile = .windowsBluetooth
        case "winMacKeyOriginal": selectedProfile = .winMacKeyOriginal
        default:                 selectedProfile = nil
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
        HIDRemapper.shared.applyMappings(keyMappings)
    }
    
    /// 동기 버전 — 위저드 Step 3 등 완료 보장이 필요할 때
    func applyCustomMappingsSync(_ mappings: [Int64: Int64]) {
        keyMappings.removeAll()
        for (src, dst) in mappings {
            keyMappings[src] = dst
        }
        keyMappings[Int64(kVK_CapsLock)] = Int64(kVK_CapsLock)
        
        HIDRemapper.shared.applyMappingsSync(keyMappings)
    }
    
    func updateMappings(from profileId: String) {
        self.activeProfileID = profileId
        setupDefaultMappings()
    }
    
    // MARK: - Engine Control
    
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        
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
            return false
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
        return true
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
        cancelPendingInputSourceCommit(dropBufferedEvents: true)
        
        // HID 매핑도 해제 (동기 — 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
        
        logger.info("Engine stopped.")
    }

    func beginInputSourceCommitWindow() {
        guard !isVdiAppFocused else { return }

        if awaitingInputSourceCommit {
            flushBufferedKeyEvents(reason: "superseded")
        }
        cancelPendingInputSourceCommit(dropBufferedEvents: true)
        awaitingInputSourceCommit = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushBufferedKeyEvents(reason: "timeout")
        }
        bufferedFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + inputSourceCommitTimeout, execute: workItem)
    }

    func completeInputSourceCommitWindow() {
        flushBufferedKeyEvents(reason: "input-source-changed")
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
        
        // 합성 이벤트(자신이 주입한 이벤트)는 재처리 없이 통과
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
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
        
        // ====== 트리거 키가 눌린 상태에서의 후속 이벤트 처리 ======
        if interceptor.triggerKeyPressed && keyCode != triggerKey {
            // (1) 핵심 수정: flags에서 트리거 modifier를 제거
            // 이유: Right Cmd는 suppress되어 시스템에 전달되지 않지만,
            //       하드웨어 modifier 상태가 후속 이벤트의 event.flags에 그대로 남음.
            //       제거하지 않으면 앱이 "b keyDown"을 "Cmd+b" 로 해석 → 씹힘 발생.
            let triggerFlag: CGEventFlags = triggerKey == rightCmdKeyCode ? .maskCommand : .maskAlternate
            if event.flags.contains(triggerFlag) {
                var strippedFlags = event.flags
                strippedFlags.remove(triggerFlag)
                event.flags = strippedFlags
            }
        }
        
        // ====== 트리거 키 처리 (한영 전환 / VDI 릴레이) ======
        // 핵심 원칙: 트리거 키 이벤트를 시스템에 그대로 전달하지 않음 (suppress).
        // → 우발적인 Cmd+Space(Spotlight) 등 단축키 발동 원천 차단.
        // → AppState/StateManager가 현재 컨텍스트에 따라
        //    macOS 입력소스 전환(Control+Space) 또는 VDI 릴레이 키(F16)를 선택.

        if keyCode == triggerKey && type == .flagsChanged {

            // ── isDown 판별: device-specific 플래그 (L+R 동시 홀드 엣지케이스 완전 해결) ──
            // .maskCommand/.maskAlternate는 Left/Right 구분 불가 → NX device 비트 사용
            // NX_DEVICERCMDKEYMASK=0x10, NX_DEVICERALTKEYMASK=0x40 (CGEventFlags.rawValue 하위 비트)
            let deviceRightFlag: UInt64 = triggerKey == rightCmdKeyCode ? 0x10 : 0x40
            let isDown = event.flags.rawValue & deviceRightFlag != 0
            let wasDown = interceptor.previousFlags.rawValue & deviceRightFlag != 0
            interceptor.previousFlags = event.flags

            // 상태 갱신 (반복 토글 방지)
            interceptor.triggerKeyPressed = isDown

            if isDown && !wasDown {
                interceptor.logger.info("⚡️ Trigger key detected (VDI=\(interceptor.isVdiAppFocused))")
                interceptor.onInputSourceToggle?()
            }
            interceptor.logEvent(event, startTime: startTime, originalKey: keyCode, mappedKey: keyCode)
            return nil  // suppress: 트리거 키 이벤트를 시스템에 전달하지 않음
        }
        
        // ====== 일반 매핑 처리 ======
        // 이중 매핑 방지: modifier-to-modifier 매핑은 HIDRemapper(hidutil)가 이미 처리하므로
        // CGEventTap에서는 HID가 처리할 수 없는 매핑만 수행합니다.

        if keyCode != triggerKey, let newKeyCode = interceptor.keyMappings[keyCode] {
            let isSourceModifier = interceptor.modifierKeyToFlag[keyCode] != nil
            let isDestModifier = interceptor.modifierKeyToFlag[newKeyCode] != nil

            // HID가 이미 처리한 modifier→modifier 매핑은 스킵 (이중 변환 방지)
            let hidCanHandle = isSourceModifier && isDestModifier
                && HIDRemapper.keycodeToHIDUsage[keyCode] != nil
                && HIDRemapper.keycodeToHIDUsage[newKeyCode] != nil

            if !hidCanHandle {
                mappedKeyCode = newKeyCode

                if type == .flagsChanged {
                    if isSourceModifier && !isDestModifier {
                        // Modifier → General Key
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
                    // modifier→modifier는 HID가 처리, 여기서는 패스
                } else {
                    // keyDown / keyUp: 일반 키코드 교체
                    event.setIntegerValueField(.keyboardEventKeycode, value: newKeyCode)
                }
            }
        }
        
        // 로깅
        interceptor.logEvent(finalEvent, startTime: startTime, originalKey: keyCode, mappedKey: mappedKeyCode)

        if interceptor.awaitingInputSourceCommit && keyCode != triggerKey {
            interceptor.bufferKeyEvent(finalEvent)
            return nil
        }
        
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

    private func bufferKeyEvent(_ event: CGEvent) {
        bufferedKeyEvents.append(event)
        if bufferedKeyEvents.count >= maxBufferedEventCount {
            flushBufferedKeyEvents(reason: "buffer-limit")
        }
    }

    private func flushBufferedKeyEvents(reason: String) {
        bufferedFlushWorkItem?.cancel()
        bufferedFlushWorkItem = nil

        guard awaitingInputSourceCommit else { return }
        awaitingInputSourceCommit = false

        guard !bufferedKeyEvents.isEmpty else { return }
        let events = bufferedKeyEvents
        bufferedKeyEvents.removeAll()

        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            event.post(tap: .cgSessionEventTap)
        }

        logger.info("Replayed \(events.count) buffered key events (\(reason))")
    }

    private func cancelPendingInputSourceCommit(dropBufferedEvents: Bool = false) {
        bufferedFlushWorkItem?.cancel()
        bufferedFlushWorkItem = nil
        awaitingInputSourceCommit = false
        if dropBufferedEvents {
            bufferedKeyEvents.removeAll()
        }
    }
    
    // MARK: - Synthetic Event Injection (reserved for future use)

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
            bundleId: self.cachedBundleId,
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
