import Foundation
import IOKit
import IOKit.hid
import os.log

/// 연결된 키보드 디바이스를 식별하는 구조체
struct KeyboardDeviceIdentifier: Codable, Equatable, Hashable, Identifiable {
    let vendorId: Int
    let productId: Int
    let productName: String

    var isInternal: Bool {
        // Apple Internal Keyboard / Trackpad: vendorId=0x05AC (Apple), productName contains "Internal"
        productName.contains("Internal")
    }

    var displayName: String {
        if isInternal { return "Internal Keyboard" }
        if !productName.isEmpty { return productName }
        return "Unknown (\(String(format: "0x%04X", vendorId)):\(String(format: "0x%04X", productId)))"
    }

    /// 매칭 키: 같은 모델 = 같은 레이아웃
    var matchingKey: String {
        "\(vendorId):\(productId)"
    }

    /// SwiftUI Identifiable 용 — VID:PID 가 stable unique id (P2 first-seen sheet 등에서 사용).
    var id: String { matchingKey }
}

/// IOHIDManager 기반 키보드 디바이스 열거/모니터링 서비스
/// - 연결된 키보드 목록 관리
/// - 키보드 연결/해제 이벤트 감지
/// - 마지막으로 사용된 키보드 추적 (InputValue 콜백)
class KeyboardDeviceManager: ObservableObject {

    private var hidManager: IOHIDManager?
    private let logger = Logger(subsystem: "com.winmackey.app", category: "KeyboardDevice")

    /// 현재 연결된 키보드 목록
    @Published var connectedKeyboards: [KeyboardDeviceIdentifier] = []

    /// 마지막으로 키 입력이 감지된 키보드
    @Published var lastActiveDevice: KeyboardDeviceIdentifier?

    /// 키보드 전환 콜백 (AppState가 등록)
    var onActiveDeviceChanged: ((KeyboardDeviceIdentifier) -> Void)?

    /// 키보드 연결/해제 콜백
    var onDeviceConnected: ((KeyboardDeviceIdentifier) -> Void)?
    var onDeviceDisconnected: ((KeyboardDeviceIdentifier) -> Void)?

    // MARK: - Capture Mode
    //
    // "Press-to-bind" UX 를 위한 일회성 capture.
    // UI 가 startCapture 호출 → 다음 키 입력이 들어오면 콜백으로 디바이스 정보 전달 후 자동 종료.
    // capture 활성 동안에도 lastActiveDevice / onActiveDeviceChanged 는 정상 동작 (캡처와 무관).

    @Published private(set) var isCapturing: Bool = false
    private var captureCallback: ((KeyboardDeviceIdentifier) -> Void)?
    private var captureTimeoutCallback: (() -> Void)?
    private var captureTimer: Timer?

    /// 다음 키 입력의 디바이스를 캡처.
    /// - Parameter timeout: 무입력 시 자동 cancel (default 10초)
    /// - Parameter onCapture: 디바이스 식별자 전달 (메인 스레드에서 호출됨)
    /// - Parameter onTimeout: timeout 시 호출 (메인 스레드)
    @MainActor
    func startCapture(
        timeout: TimeInterval = 10.0,
        onCapture: @escaping (KeyboardDeviceIdentifier) -> Void,
        onTimeout: @escaping () -> Void
    ) {
        // 이전 capture 있으면 cancel
        cancelCapture()

        captureCallback = onCapture
        captureTimeoutCallback = onTimeout
        isCapturing = true

        captureTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isCapturing else { return }
                self.cancelCapture()
                onTimeout()
            }
        }

        logger.info("KeyboardDeviceManager: capture started (timeout=\(timeout)s)")
    }

    /// 진행 중인 capture 취소 (사용자 취소 또는 timeout).
    @MainActor
    func cancelCapture() {
        captureCallback = nil
        captureTimeoutCallback = nil
        captureTimer?.invalidate()
        captureTimer = nil
        if isCapturing {
            isCapturing = false
            logger.info("KeyboardDeviceManager: capture cancelled")
        }
    }

    /// IOHIDDevice → Identifier 캐시 (포인터 비교로 빠른 룩업)
    private var deviceCache: [IOHIDDevice: KeyboardDeviceIdentifier] = [:]

    /// 마지막 활성 디바이스의 포인터 — 빠른 비교용 (매 키 이벤트마다 호출되므로 성능 중요)
    private var lastActiveDeviceRef: IOHIDDevice?

    // MARK: - Lifecycle

    func startMonitoring() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        // 키보드 디바이스만 매칭 (HID Usage Page 1 = Generic Desktop, Usage 6 = Keyboard)
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // 콜백 등록
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceConnectedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueCallback, context)

        // 메인 RunLoop에 스케줄 (CGEventTap과 같은 스레드)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            logger.error("Failed to open IOHIDManager: \(result)")
            return
        }

        // 초기 열거
        refreshConnectedDevices()
        logger.info("KeyboardDeviceManager started — \(self.connectedKeyboards.count) keyboards detected")
    }

    func stopMonitoring() {
        guard let manager = hidManager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        hidManager = nil
        deviceCache.removeAll()
        lastActiveDeviceRef = nil
        logger.info("KeyboardDeviceManager stopped")
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Device Enumeration

    private func refreshConnectedDevices() {
        guard let manager = hidManager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        var keyboards: [KeyboardDeviceIdentifier] = []
        deviceCache.removeAll()

        for device in deviceSet {
            let identifier = Self.extractIdentifier(from: device)
            deviceCache[device] = identifier
            // 중복 모델 제거 (같은 vendorId+productId)
            if !keyboards.contains(where: { $0.matchingKey == identifier.matchingKey }) {
                keyboards.append(identifier)
            }
        }

        connectedKeyboards = keyboards.sorted { a, b in
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.displayName < b.displayName
        }
    }

    // MARK: - C Callback Trampolines

    private static let deviceConnectedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()
        manager.handleDeviceConnected(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()
        manager.handleDeviceRemoved(device)
    }

    /// Apple Vendor Top Case 페이지의 Fn/Globe 키 (hidutil 표기로 0xFF00000003).

    private static let inputValueCallback: IOHIDValueCallback = { context, result, sender, value in
        guard let context = context else { return }
        let manager = Unmanaged<KeyboardDeviceManager>.fromOpaque(context).takeUnretainedValue()

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let device = IOHIDElementGetDevice(element)

        // 캡처 모드(press-to-bind): 디바이스 식별만 필요하므로 usage page 무관하게 허용.
        if manager.isCapturing {
            manager.handleInputValue(from: device)
            return
        }

        // 일반 활성-키보드 추적: 표준 키보드 키(0x07)만 — 미디어/밝기 키 오탐 방지.
        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }
        manager.handleInputValue(from: device)
    }

    // MARK: - Event Handlers

    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let identifier = Self.extractIdentifier(from: device)
        deviceCache[device] = identifier

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.connectedKeyboards.contains(where: { $0.matchingKey == identifier.matchingKey }) {
                self.connectedKeyboards.append(identifier)
                self.connectedKeyboards.sort { a, b in
                    if a.isInternal != b.isInternal { return a.isInternal }
                    return a.displayName < b.displayName
                }
            }
            self.onDeviceConnected?(identifier)
            LogService.shared.info("Keyboard connected: \(identifier.displayName) (\(identifier.matchingKey))", category: "Device")
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard let identifier = deviceCache.removeValue(forKey: device) else { return }

        // 같은 모델의 다른 인스턴스가 아직 연결되어 있는지 확인
        let stillConnected = deviceCache.values.contains { $0.matchingKey == identifier.matchingKey }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !stillConnected {
                self.connectedKeyboards.removeAll { $0.matchingKey == identifier.matchingKey }
            }
            // 해제된 디바이스가 마지막 활성 디바이스였으면 리셋
            if self.lastActiveDeviceRef === device {
                self.lastActiveDeviceRef = nil
                // lastActiveDevice는 유지 — 다음 키 이벤트가 올 때까지
            }
            self.onDeviceDisconnected?(identifier)
            LogService.shared.info("Keyboard disconnected: \(identifier.displayName)", category: "Device")
        }
    }

    /// 키 입력 감지 — 마지막 사용 키보드 추적 + capture mode 처리.
    /// IOHIDManager 콜백은 메인 RunLoop에서 실행되어 main-thread context.
    private func handleInputValue(from device: IOHIDDevice) {
        let identifier = deviceCache[device] ?? Self.extractIdentifier(from: device)

        // === Capture mode 처리 ===
        // 활성이면 일회성 콜백 호출 후 자동 종료. lastActiveDevice 갱신과 무관.
        if isCapturing, let callback = captureCallback {
            captureCallback = nil
            captureTimeoutCallback = nil
            captureTimer?.invalidate()
            captureTimer = nil
            isCapturing = false
            logger.info("KeyboardDeviceManager: capture fired (\(identifier.displayName))")
            // Main thread (current context) 에서 즉시 호출
            callback(identifier)
            // Note: capture 활성 동안에도 lastActiveDevice 는 동시 갱신 — 자연스러운 동작
        }

        // === 일반 lastActiveDevice 추적 (capture 와 독립) ===
        if device === lastActiveDeviceRef { return }
        lastActiveDeviceRef = device

        let changed = self.lastActiveDevice != identifier
        self.lastActiveDevice = identifier
        if changed {
            self.onActiveDeviceChanged?(identifier)
        }
    }

    // MARK: - Helpers

    static func extractIdentifier(from device: IOHIDDevice) -> KeyboardDeviceIdentifier {
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""

        return KeyboardDeviceIdentifier(
            vendorId: vendorId,
            productId: productId,
            productName: productName
        )
    }
}
