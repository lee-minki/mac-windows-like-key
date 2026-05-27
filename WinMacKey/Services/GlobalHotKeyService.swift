import Foundation
import AppKit
import Carbon.HIToolbox
import os.log

/// 메뉴바 popover 가 SwiftUI 버그/장기가동 등으로 응답하지 않을 때를 대비한
/// 우회 진입 경로. Carbon RegisterEventHotKey 를 사용해 시스템 글로벌 단축키를
/// 등록하고, 사전 정의된 콜백을 호출한다.
///
/// 현재 등록: Cmd+Shift+Opt+D → onTriggered() (Doctor 윈도우 진입용)
///
/// Carbon Event Manager 는 메인 run loop 에 디스패치되며, 콜백에서 다시
/// DispatchQueue.main.async 로 래핑하므로 actor 격리 없이도 안전.
final class GlobalHotKeyService: ObservableObject {

    private let logger = Logger(subsystem: "com.winmackey.app", category: "GlobalHotKey")

    /// 단축키 fire 시 호출되는 콜백. AppState 가 SwiftUI 의 openWindow 와 연결한다.
    var onTriggered: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// 단축키 식별용 4-char OSType. 동일 앱 내에서 unique 하기만 하면 된다.
    private static let hotKeySignature: OSType = {
        let chars: [Character] = ["W", "M", "K", "1"]
        var value: OSType = 0
        for ch in chars {
            value = (value << 8) | OSType(ch.asciiValue ?? 0)
        }
        return value
    }()
    private static let hotKeyId: UInt32 = 1

    /// Cmd+Shift+Opt+D
    private static let keyCode: UInt32 = UInt32(kVK_ANSI_D)
    private static let modifiers: UInt32 =
        UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey)

    func register() {
        guard hotKeyRef == nil else { return }

        // 이벤트 핸들러 먼저 설치 (Carbon Event Manager)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData,
                      let eventRef = eventRef else { return noErr }
                let service = Unmanaged<GlobalHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hkId = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkId
                )
                if status == noErr && hkId.id == GlobalHotKeyService.hotKeyId {
                    DispatchQueue.main.async {
                        service.handleTrigger()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            logger.error("InstallEventHandler failed: status=\(installStatus)")
            return
        }

        // 단축키 등록
        let hotKeyId = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyId)
        let registerStatus = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            logger.info("Global hotkey registered: Cmd+Shift+Opt+D")
        } else {
            logger.error("RegisterEventHotKey failed: status=\(registerStatus)")
            if let handler = eventHandlerRef {
                RemoveEventHandler(handler)
                eventHandlerRef = nil
            }
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    private func handleTrigger() {
        logger.info("Global hotkey fired (Cmd+Shift+Opt+D)")
        // LSUIElement 앱은 명시 활성화 없으면 윈도우가 background 에 열림.
        // 부수효과로 stuck 된 MenuBarExtra hosting NSPanel 도 깨워질 가능성.
        NSApp.activate(ignoringOtherApps: true)
        onTriggered?()
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
