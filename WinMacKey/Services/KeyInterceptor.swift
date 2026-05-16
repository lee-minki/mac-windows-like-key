import Foundation
import AppKit
import Carbon.HIToolbox
import os.log

/// CGEventTap 기반 키보드 이벤트 인터셉터
/// Right Cmd tap-only 감지 + 기존 키 리매핑 + EventTap 자동 재활성화
class KeyInterceptor: ObservableObject {
    static weak var shared: KeyInterceptor?

    private enum BufferedReplayWindow: String {
        case none
        case inputSourceCommit
        case vdiRelayCooldown
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var tapIncludesFlagsChanged = false
    private var reactivationTimer: Timer?

    @Published var events: [KeyEvent] = []
    @Published var averageLatencyMs: Double = 0.0
    @Published var totalEventCount: Int = 0

    // 키 매핑 테이블 (fn↔Cmd↔Ctrl 등 기존 매핑)
    private(set) var keyMappings: [Int64: Int64] = [:]

    /// 현재 매핑에 modifier→비modifier 변환이 있는지 여부
    /// true일 때만 flagsChanged 이벤트를 처리합니다.
    /// false이면 flagsChanged를 즉시 패스스루하여 Caps Lock 등 시스템 동작 간섭을 방지합니다.
    private(set) var needsFlagsChangedProcessing: Bool = false

    private var triggerKeyPressed = false
    private var bufferedReplayWindow: BufferedReplayWindow = .none
    private var bufferedReplayStartedAt: UInt64 = 0

    /// 트리거 키 릴리즈 후 버퍼링된 키 이벤트 (VDI 릴레이 쿨다운 / 입력소스 commit 윈도우 동안 보관)
    private var bufferedKeyEvents: [CGEvent] = []
    private var bufferedFlushWorkItem: DispatchWorkItem?

    private static let inputSourceCommitMinimumHoldNanos: UInt64 = 20_000_000  // 20ms
    private let inputSourceCommitTimeout: TimeInterval = 0.220
    private let vdiRelayCooldownTimeout: TimeInterval = 0.030
    private let maxBufferedEventCount = 8

    /// 합성 이벤트 식별자 — 재진입 방지용 (탭이 자신이 주입한 이벤트를 재처리하지 않도록)
    private static let syntheticEventMarker: Int64 = 0x57494E4B  // "WINK"

    // 한영 전환 트리거 키 (HID remap 후 CGEventTap에 도달하는 키: F16)
    // VDI에서는 F16이 패스스루되어 Horizon이 Right Alt로 직접 변환
    var triggerKeyCode: Int64 = Int64(kVK_F16)

    // VDI 앱 포커스 여부 (ContextManager가 자동 갱신)
    var isVdiAppFocused: Bool = false

    // Mac 원격접속 앱 포커스 여부 (Screen Sharing, ARD, Jump Desktop 등).
    // true 면 F16 패스스루 — 원격 Mac 의 WinMacKey 가 자체적으로 한영전환 처리.
    // 로컬에서는 입력소스 합성 안 함 (로컬 입력소스 변경 부작용 방지).
    var isRemoteMacAppFocused: Bool = false
    
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
    //
    // 콜백이 nil → non-nil 로 바뀌면 flagsChanged 구독을 강제로 켠다.
    // 위자드는 빈 매핑으로 진입하기 때문에 keyMappings 기반 최적화만으로는
    // modifier 키 이벤트가 tap 에 들어오지 않는다. nil 로 돌아오면 다시
    // 매핑 기반 최적화 결과로 복귀.
    var onVerifyKeyEvent: ((Int64, Int64, Bool) -> Void)? {
        didSet { updateNeedsFlagsChangedProcessing() }
    }

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
        // CapsLock은 의도적으로 제외 — 앱이 Caps Lock을 절대 건드리지 않음
        // Int64(kVK_CapsLock): .maskAlphaShift
    ]
    
    init() {
        KeyInterceptor.shared = self
        // Lifecycle invariant: init에서는 HID 시스템 상태를 절대 건드리지 않음.
        // keyMappings는 내부 메모리에만 계산해 두고, 실제 hidutil 적용은
        // engine ON path (toggleEngine → refreshActiveProfileForCurrentContext) 에서만 수행.
        computeKeyMappings()
    }
    
    // 활성화된 프로파일 ID (AppStorage와 동기화)
    // NOTE: didSet에서 setupDefaultMappings를 호출하지 않음.
    // applyCustomMappings가 HID 매핑을 설정한 후 didSet이 async로 setupDefaultMappings를
    // 호출하여 HID 매핑을 덮어쓰는 레이스 컨디션을 방지합니다.
    var activeProfileID: String = "standardMac"
    
    // MARK: - Setup
    
    /// 활성 프로필을 keyMappings dictionary에 로드만 한다. HID 시스템 상태는 건드리지 않음.
    /// init 시점·UI 갱신 시점처럼 engine OFF에서도 호출 가능한 안전 경로.
    func computeKeyMappings() {
        logger.info("Computing mappings for profile: \(self.activeProfileID)")

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
        ensureCapsLockUntouched()
        updateNeedsFlagsChangedProcessing()
    }

    /// keyMappings를 계산하고 HID 시스템에 적용.
    /// engine OFF 면 HID 적용 skip (dictionary 만 갱신) — ownership 모델과 일관.
    func setupDefaultMappings() {
        computeKeyMappings()
        guard HIDRemapper.shared.isOwnedByEngine else {
            logger.info("setupDefaultMappings: engine OFF, skipping HID apply")
            return
        }
        // HID 레벨 리매핑 적용 (Fn/Globe 포함)
        HIDRemapper.shared.applyMappings(keyMappings)
    }
    
    /// 매핑 dictionary 갱신 + HID 적용. ownership 없으면 dictionary 만 갱신하고 HID 호출 skip.
    /// 위저드가 엔진 OFF 상태에서 부르면 시스템 상태는 안 바뀌지만 다음 engine ON 시 정확한 매핑 사용.
    func applyCustomMappings(_ mappings: [Int64: Int64]) {
        keyMappings.removeAll()
        for (src, dst) in mappings {
            keyMappings[src] = dst
        }
        ensureCapsLockUntouched()
        updateNeedsFlagsChangedProcessing()

        guard HIDRemapper.shared.isOwnedByEngine else {
            logger.info("applyCustomMappings: engine OFF, skipping HID apply (dictionary updated)")
            return
        }
        HIDRemapper.shared.applyMappings(keyMappings)
    }

    /// 동기 버전 — 위저드 Step 3 등 완료 보장이 필요할 때.
    /// engine OFF 면 동일하게 dictionary 만 갱신.
    func applyCustomMappingsSync(_ mappings: [Int64: Int64]) {
        keyMappings.removeAll()
        for (src, dst) in mappings {
            keyMappings[src] = dst
        }
        ensureCapsLockUntouched()
        updateNeedsFlagsChangedProcessing()

        guard HIDRemapper.shared.isOwnedByEngine else {
            logger.info("applyCustomMappingsSync: engine OFF, skipping HID apply (dictionary updated)")
            return
        }
        HIDRemapper.shared.applyMappingsSync(keyMappings)
    }
    
    func updateMappings(from profileId: String) {
        self.activeProfileID = profileId
        setupDefaultMappings()
    }

    /// Caps Lock은 앱이 절대 건드리지 않습니다.
    /// 프로필에 Caps Lock 매핑이 포함되어 있더라도 제거합니다.
    private func ensureCapsLockUntouched() {
        keyMappings.removeValue(forKey: Int64(kVK_CapsLock))
    }

    /// 현재 매핑 테이블에서 modifier→비modifier 변환이 있는지 계산합니다.
    /// 이런 매핑이 없으면 CGEventTap에서 flagsChanged를 이벤트 마스크에서 제외하여
    /// Caps Lock 등 시스템 modifier 동작 간섭을 원천 방지합니다.
    ///
    /// 단, 위저드 검증 모드(onVerifyKeyEvent != nil)일 때는 빈 매핑이라도
    /// modifier 키 이벤트를 받아야 하므로 강제로 켭니다.
    private func updateNeedsFlagsChangedProcessing() {
        var needed = (onVerifyKeyEvent != nil)
        if needed {
            logger.info("flagsChanged processing ENABLED (verify mode active)")
        } else {
            for (src, dst) in keyMappings {
                guard src != dst else { continue }
                let srcIsModifier = modifierKeyToFlag[src] != nil
                let dstIsModifier = modifierKeyToFlag[dst] != nil
                if srcIsModifier && !dstIsModifier {
                    needed = true
                    logger.info("flagsChanged processing ENABLED (modifier→key mapping found: \(src)→\(dst))")
                    break
                }
            }
        }
        if !needed {
            logger.info("flagsChanged processing DISABLED (no modifier→key mappings, Caps Lock safe)")
        }
        let changed = (needsFlagsChangedProcessing != needed)
        needsFlagsChangedProcessing = needed
        if changed {
            restartTapIfNeeded()
        }
    }

    /// flagsChanged 포함 여부가 바뀌면 EventTap을 재생성합니다.
    /// HID 매핑은 보존 — EventTap 만 재생성하므로 RightCmd→F16 같은 트리거 매핑이 풀리지 않음.
    /// 재시작 윈도우(수십 ms) 동안 한영전환 침묵 가능성 차단.
    private func restartTapIfNeeded() {
        guard isRunning else { return }
        guard self.tapIncludesFlagsChanged != self.needsFlagsChangedProcessing else { return }
        logger.info("Restarting event tap (flagsChanged mask changed: \(self.tapIncludesFlagsChanged) → \(self.needsFlagsChangedProcessing))")
        stop(clearHIDMappings: false)
        start()
    }
    
    // MARK: - Engine Control
    
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        
        logger.info("Attempting to start engine...")
        
        let eventMask: CGEventMask = {
            var mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue)
            if needsFlagsChangedProcessing {
                mask |= (1 << CGEventType.flagsChanged.rawValue)
            }
            return mask
        }()

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            KeyInterceptor.handleEvent(proxy: proxy, type: type, event: event, refcon: refcon)
        }

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        guard let tap else {
            logger.error("Failed to create HID and session event taps. Check Accessibility permissions.")
            return false
        }

        eventTap = tap
        tapIncludesFlagsChanged = needsFlagsChangedProcessing

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)
        
        isRunning = true
        logger.info("Engine started successfully (CGEventTap).")
        DispatchQueue.main.async {
            LogService.shared.info(
                "Engine started (CGEventTap trigger suppression active)",
                category: "Engine"
            )
        }
        startReactivationTimer()
        
        return true
    }
    
    /// EventTap 정지. 기본 동작은 HID 매핑도 함께 해제하지만,
    /// 내부 restart (`restartTapIfNeeded`) 처럼 매핑 보존이 필요한 경우 `clearHIDMappings: false`.
    func stop(clearHIDMappings: Bool = true) {
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
        cancelPendingBufferedReplay(dropBufferedEvents: true)

        if clearHIDMappings {
            // HID 매핑 해제 (동기 — 완료 보장)
            HIDRemapper.shared.clearMappingsSync()
            logger.info("Engine stopped (HID mappings cleared).")
        } else {
            logger.info("Engine stopped (HID mappings preserved for restart).")
        }
    }

    func beginInputSourceCommitWindow() {
        guard !isVdiAppFocused else { return }
        startBufferedReplayWindow(.inputSourceCommit, timeout: inputSourceCommitTimeout, timeoutReason: "timeout")
    }

    func beginVdiRelayCooldownWindow() {
        guard isVdiAppFocused else { return }
        startBufferedReplayWindow(.vdiRelayCooldown, timeout: vdiRelayCooldownTimeout, timeoutReason: "vdi-relay-settle")
    }

    func completeInputSourceCommitWindow() {
        guard bufferedReplayWindow == .inputSourceCommit else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now - bufferedReplayStartedAt
        if elapsed >= Self.inputSourceCommitMinimumHoldNanos {
            flushBufferedKeyEvents(reason: "input-source-changed")
            return
        }

        let remainingNanos = Self.inputSourceCommitMinimumHoldNanos - elapsed
        scheduleBufferedReplayFlush(
            after: TimeInterval(remainingNanos) / 1_000_000_000,
            reason: "input-source-min-hold"
        )
    }

    func failInputSourceCommitWindow() {
        guard bufferedReplayWindow == .inputSourceCommit else { return }
        scheduleBufferedReplayFlush(after: 0.100, reason: "verification-failed-grace")
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
    
    /// C-style CGEventTap 콜백.
    /// 탭/합성-이벤트 admin만 처리하고, 실제 로직은 interceptor 인스턴스 메서드에 위임한다.
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

        // 트리거 키(F16)는 매핑/버퍼링과 무관한 별도 경로
        if keyCode == interceptor.triggerKeyCode && (type == .keyDown || type == .keyUp) {
            return interceptor.handleTriggerKey(event: event, type: type, startTime: startTime, keyCode: keyCode)
        }

        return interceptor.handleMappedKey(event: event, type: type, startTime: startTime, keyCode: keyCode)
    }

    // MARK: - Event Handling Pipeline (split from handleEvent)

    /// F16 트리거 키 처리.
    /// 두 가지 분기:
    ///   - VDI 모드: 패스스루 → Horizon 이 F16 → Right Alt 변환 (Windows VDI 처리)
    ///   - 그 외 (로컬 Mac · Mac 원격접속 · Terminal 등):
    ///     F16 suppress → AppState 의 onInputSourceToggle 콜백에서 로컬 macOS 의
    ///     입력소스 전환. Mac 원격 (Screen Sharing) 의 경우 character forwarding 모델이라
    ///     로컬 입력소스 토글만으로 원격 화면에 올바른 문자가 들어감.
    private func handleTriggerKey(
        event: CGEvent,
        type: CGEventType,
        startTime: DispatchTime,
        keyCode: Int64
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat && !triggerKeyPressed {
                triggerKeyPressed = true
                logger.info("⚡️ Trigger key (F16) detected (VDI=\(self.isVdiAppFocused), Remote=\(self.isRemoteMacAppFocused))")
                onInputSourceToggle?()
            }
        } else {
            // keyUp
            triggerKeyPressed = false
        }

        logEvent(event, startTime: startTime, originalKey: keyCode, mappedKey: keyCode)

        if isVdiAppFocused {
            // VDI: F16 패스스루
            return Unmanaged.passUnretained(event)
        } else {
            // 로컬 Mac / Mac 원격 / 그 외: F16 suppress
            // (Mac 원격 — Screen Sharing 이 character 단위로 forward 하므로 로컬 토글이면 충분)
            return nil
        }
    }

    /// 일반 키 매핑 + 버퍼링 + 검증 콜백 디스패치.
    private func handleMappedKey(
        event: CGEvent,
        type: CGEventType,
        startTime: DispatchTime,
        keyCode: Int64
    ) -> Unmanaged<CGEvent>? {
        var mappedKeyCode = keyCode
        var finalEvent = event

        if let newKeyCode = keyMappings[keyCode] {
            let (translated, newMapped) = translateMapping(
                event: event,
                type: type,
                sourceKey: keyCode,
                destKey: newKeyCode
            )
            if let translated {
                finalEvent = translated
            }
            mappedKeyCode = newMapped
        }

        logEvent(finalEvent, startTime: startTime, originalKey: keyCode, mappedKey: mappedKeyCode)

        if bufferedReplayWindow != .none {
            bufferKeyEvent(finalEvent)
            return nil
        }

        dispatchVerificationCallback(
            event: finalEvent,
            type: type,
            originalKey: keyCode,
            mappedKey: mappedKeyCode
        )

        if finalEvent !== event {
            return Unmanaged.passRetained(finalEvent)
        }
        return Unmanaged.passUnretained(finalEvent)
    }

    /// HID가 처리할 수 없는 매핑만 CGEventTap 레벨에서 변환.
    /// - Returns: (재구성된 이벤트 or nil, 매핑된 키코드).
    ///   nil이면 원본 이벤트를 그대로 사용해야 한다.
    private func translateMapping(
        event: CGEvent,
        type: CGEventType,
        sourceKey: Int64,
        destKey: Int64
    ) -> (event: CGEvent?, mappedKeyCode: Int64) {
        let isSourceModifier = modifierKeyToFlag[sourceKey] != nil
        let isDestModifier = modifierKeyToFlag[destKey] != nil

        // HID가 이미 처리한 modifier→modifier 매핑은 스킵 (이중 변환 방지)
        let hidCanHandle = isSourceModifier && isDestModifier
            && HIDRemapper.keycodeToHIDUsage[sourceKey] != nil
            && HIDRemapper.keycodeToHIDUsage[destKey] != nil

        guard !hidCanHandle else {
            return (nil, sourceKey)
        }

        if type == .flagsChanged {
            // Modifier → General Key: 새 keyDown/keyUp 이벤트로 변환
            if isSourceModifier && !isDestModifier,
               let srcFlag = modifierKeyToFlag[sourceKey],
               let newEvent = CGEvent(
                    keyboardEventSource: CGEventSource(event: event),
                    virtualKey: CGKeyCode(destKey),
                    keyDown: event.flags.contains(srcFlag)
               )
            {
                var newFlags = event.flags
                newFlags.remove(srcFlag)
                newEvent.flags = newFlags
                return (newEvent, destKey)
            }
            // modifier→modifier는 HID가 처리, 여기서는 패스
            return (nil, sourceKey)
        }

        // keyDown / keyUp: 원본 이벤트의 키코드 in-place 교체
        event.setIntegerValueField(.keyboardEventKeycode, value: destKey)
        return (nil, destKey)
    }

    /// 위저드 Step 1/Step 3에서 사용하는 검증 콜백 디스패치.
    private func dispatchVerificationCallback(
        event: CGEvent,
        type: CGEventType,
        originalKey: Int64,
        mappedKey: Int64
    ) {
        guard let verify = onVerifyKeyEvent else { return }

        let isDown: Bool
        if type == .flagsChanged {
            if let flag = modifierKeyToFlag[originalKey] {
                isDown = event.flags.contains(flag)
            } else {
                isDown = true
            }
        } else {
            isDown = (type == .keyDown)
        }

        if isDown {
            DispatchQueue.main.async {
                verify(originalKey, mappedKey, true)
            }
        }
    }

    private func bufferKeyEvent(_ event: CGEvent) {
        bufferedKeyEvents.append(event)
        if bufferedKeyEvents.count >= maxBufferedEventCount {
            flushBufferedKeyEvents(reason: "buffer-limit")
        }
    }

    private func startBufferedReplayWindow(
        _ window: BufferedReplayWindow,
        timeout: TimeInterval,
        timeoutReason: String
    ) {
        if bufferedReplayWindow != .none {
            flushBufferedKeyEvents(reason: "superseded")
        }
        cancelPendingBufferedReplay(dropBufferedEvents: true)
        bufferedReplayWindow = window
        bufferedReplayStartedAt = DispatchTime.now().uptimeNanoseconds
        scheduleBufferedReplayFlush(after: timeout, reason: timeoutReason)
    }

    private func scheduleBufferedReplayFlush(after timeout: TimeInterval, reason: String) {
        bufferedFlushWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushBufferedKeyEvents(reason: reason)
        }
        bufferedFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func flushBufferedKeyEvents(reason: String) {
        bufferedFlushWorkItem?.cancel()
        bufferedFlushWorkItem = nil

        let activeWindow = bufferedReplayWindow
        guard activeWindow != .none else { return }
        bufferedReplayWindow = .none
        bufferedReplayStartedAt = 0

        guard !bufferedKeyEvents.isEmpty else { return }
        let events = bufferedKeyEvents
        bufferedKeyEvents.removeAll()

        for (i, event) in events.enumerated() {
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            event.post(tap: .cgSessionEventTap)
            // IME가 각 이벤트를 안정적으로 처리할 수 있도록 키 사이에 짧은 딜레이 삽입
            if i < events.count - 1 {
                usleep(500)  // 0.5ms
            }
        }

        logger.info("Replayed \(events.count) buffered key events (\(activeWindow.rawValue), \(reason))")
    }

    private func cancelPendingBufferedReplay(dropBufferedEvents: Bool = false) {
        bufferedFlushWorkItem?.cancel()
        bufferedFlushWorkItem = nil
        bufferedReplayWindow = .none
        bufferedReplayStartedAt = 0
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
