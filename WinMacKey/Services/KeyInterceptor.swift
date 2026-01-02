import Foundation
import AppKit
import IOKit
import IOKit.hid

/// IOKit 기반 키보드 이벤트 인터셉터
/// 실시간으로 키 입력을 캡처하고 변환합니다.
class KeyInterceptor: ObservableObject {
    private var hidManager: IOHIDManager?
    private var isRunning = false
    
    @Published var events: [KeyEvent] = []
    @Published var averageLatencyMs: Double = 0.0
    @Published var totalEventCount: Int = 0
    
    // 키 매핑 테이블
    private var keyMappings: [UInt32: UInt32] = [:]
    
    // 이벤트 콜백
    var onKeyEvent: ((KeyEvent) -> Void)?
    
    // 최대 이벤트 로그 수 (메모리 관리)
    private let maxEventLogCount = 1000
    
    init() {
        setupDefaultMappings()
    }
    
    // MARK: - Setup
    
    private func setupDefaultMappings() {
        // 기본 매핑: CapsLock을 순수 CapsLock으로 (즉시 반응)
        keyMappings[KeyEvent.capsLockKeyCode] = KeyEvent.capsLockKeyCode
    }
    
    func updateMappings(from profile: Profile) {
        keyMappings.removeAll()
        for mapping in profile.mappings {
            keyMappings[mapping.fromKey] = mapping.toKey
        }
    }
    
    // MARK: - Engine Control
    
    func start() {
        guard !isRunning else { return }
        
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("[KeyInterceptor] Failed to create HID Manager")
            return
        }
        
        // 키보드 디바이스만 필터링
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        
        // 입력 값 콜백 설정
        let inputCallback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(context).takeUnretainedValue()
            interceptor.handleHIDValue(value)
        }
        
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, inputCallback, contextPtr)
        
        // Run Loop에 스케줄링
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        // 매니저 열기
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[KeyInterceptor] Failed to open HID Manager: \(result)")
            return
        }
        
        isRunning = true
        print("[KeyInterceptor] Engine started")
    }
    
    func stop() {
        guard isRunning, let manager = hidManager else { return }
        
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        hidManager = nil
        isRunning = false
        print("[KeyInterceptor] Engine stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleHIDValue(_ value: IOHIDValue) {
        let startTime = DispatchTime.now()
        
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        
        // 키보드 키 이벤트만 처리
        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }
        
        let rawKey = UInt32(usage)
        let mappedKey = keyMappings[rawKey] ?? rawKey
        let eventType: KeyEventType = intValue == 1 ? .down : .up
        
        let endTime = DispatchTime.now()
        let latencyNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let latencyMicros = UInt64(latencyNanos / 1000)
        
        let event = KeyEvent(
            type: eventType,
            rawKey: rawKey,
            mappedKey: mappedKey,
            latencyMicroseconds: latencyMicros,
            bundleId: getCurrentAppBundleId()
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.recordEvent(event)
        }
        
        // 키 변환 수행 (TODO: CGEvent 생성으로 실제 키 주입)
        if rawKey != mappedKey {
            // 실제 키 리매핑 로직은 여기에 구현
            // CGEvent를 사용하여 새 키 이벤트 생성
        }
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
    
    private func getCurrentAppBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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
}
