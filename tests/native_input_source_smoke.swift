import Carbon.HIToolbox
import CoreGraphics
import Foundation

@main
struct NativeInputSourceSmoke {
    static func verifySetupRouting(_ interceptor: KeyInterceptor) {
        let settings = "com.apple.systempreferences"
        let codex = "com.openai.codex"
        func hotKey(_ enabled: Bool, _ parameters: [Int]) -> [String: Any] {
            ["enabled": enabled, "value": ["parameters": parameters]]
        }
        let functionKeyFlag = 0x800000 // Observed in the macOS symbolic hotkey for bare F17.
        let configured = NativeInputSourceShortcut.isConfigured(hotKey(true, [65535, kVK_F17, functionKeyFlag]))
        precondition(configured, "bare F17 with the intrinsic function-key flag should be recognized")
        precondition(NativeInputSourceShortcut.isConfigured(hotKey(true, [65535, kVK_F17, 0])))
        let unusableEntries: [[String: Any]?] = [
            nil, [:], hotKey(false, [65535, kVK_F17, 0]), hotKey(true, [65535, kVK_F16, 0]),
            hotKey(true, [65535, kVK_F17, 262144]), hotKey(true, [65535, kVK_F17]),
            hotKey(false, [65535, kVK_F17, functionKeyFlag]), hotKey(true, [65535, kVK_F16, functionKeyFlag])
        ]
        precondition(unusableEntries.allSatisfy { !NativeInputSourceShortcut.isConfigured($0) })
        for modifier: CGEventFlags in [.maskShift, .maskControl, .maskAlternate, .maskCommand] {
            let parameters = [65535, kVK_F17, functionKeyFlag | Int(modifier.rawValue)]
            precondition(!NativeInputSourceShortcut.isConfigured(hotKey(true, parameters)), "modified F17 must be rejected")
        }
        let scenarios: [(Bool, String?, Bool, Int)] = [
            (false, settings, configured, kVK_F16), (false, codex, configured, kVK_F16),
            (true, settings, false, kVK_F17), (true, codex, false, kVK_F16),
            (true, codex, configured, kVK_F17), (true, nil, configured, kVK_F16), (true, "", false, kVK_F16)
        ]
        for (requested, frontmost, enabled, expectedKey) in scenarios {
            interceptor.nativeLocalInputSourceKey = KeyInterceptor.shouldEnableNativeLocalKey(
                requested: requested, frontmostBundleId: frontmost, shortcutConfigured: enabled
            )
            precondition(interceptor.inputSourceHIDKeyCode == Int64(expectedKey), "unexpected route for \(frontmost ?? "unknown")")
        }
    }

    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true
        let interceptor = KeyInterceptor()
        var triggers = 0
        interceptor.onInputSourceToggle = { triggers += 1 }

        // Exercise the tap's keyboard handler in process. No event is posted.
        func deliver(_ key: Int, _ type: CGEventType, forwarded: Bool, isRepeat: Bool = false) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: type == .keyDown)!
            event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
            let result = interceptor.handleKeyboardEvent(type: type, event: event)
            precondition((result != nil) == forwarded, "unexpected delivery for key \(key), type \(type)")
            if let result {
                precondition(result.takeUnretainedValue() === event, "must forward the original event")
                precondition(event.getIntegerValueField(.keyboardEventKeycode) == Int64(key), "key changed in transit")
            }
        }
        func press(_ key: Int, forwarded: Bool, triggersOnce: Bool) {
            let previousTriggers = triggers
            for (type, isRepeat) in [(CGEventType.keyDown, false), (.keyDown, true), (.keyUp, false)] {
                deliver(key, type, forwarded: forwarded, isRepeat: isRepeat)
                precondition(triggers - previousTriggers == (triggersOnce ? 1 : 0), "incorrect toggle count")
            }
        }

        precondition(!interceptor.nativeLocalInputSourceKey && interceptor.inputSourceHIDKeyCode == Int64(kVK_F16))
        verifySetupRouting(interceptor)
        press(kVK_F16, forwarded: false, triggersOnce: true)
        press(kVK_F17, forwarded: true, triggersOnce: false)
        interceptor.isTerminalAppFocused = true
        press(kVK_F16, forwarded: false, triggersOnce: true)
        interceptor.isTerminalAppFocused = false
        let beforeGap = triggers
        deliver(kVK_F16, .keyDown, forwarded: false)
        deliver(kVK_F16, .keyDown, forwarded: false) // A fresh physical press after the previous release was missed.
        deliver(kVK_F16, .keyDown, forwarded: false, isRepeat: true)
        deliver(kVK_F16, .keyUp, forwarded: false)
        precondition(triggers == beforeGap + 2, "a missed release must not swallow the next press")

        interceptor.nativeLocalInputSourceKey = true
        precondition(interceptor.inputSourceHIDKeyCode == Int64(kVK_F17))
        interceptor.loadCustomMappings([Int64(kVK_F17): Int64(kVK_ANSI_A)])
        for isTerminal in [false, true] {
            interceptor.isTerminalAppFocused = isTerminal
            press(kVK_F17, forwarded: true, triggersOnce: false)
            press(kVK_F16, forwarded: true, triggersOnce: false)
            precondition(interceptor.activeBufferedReplayWindowForTesting == "none", "native keys must not start a replay")
        }
        interceptor.isTerminalAppFocused = false
        interceptor.loadCustomMappings([:])

        interceptor.isRemoteMacAppFocused = true
        precondition(interceptor.inputSourceHIDKeyCode == Int64(kVK_F16))
        press(kVK_F16, forwarded: false, triggersOnce: true)
        deliver(kVK_F16, .keyDown, forwarded: false)
        interceptor.isRemoteMacAppFocused = false
        interceptor.finishBufferedReplayForRouteChange()
        deliver(kVK_F16, .keyUp, forwarded: false) // Pair with the suppressed press from Screen Sharing.
        press(kVK_F16, forwarded: true, triggersOnce: false)

        interceptor.isVdiAppFocused = true
        precondition(interceptor.inputSourceHIDKeyCode == Int64(kVK_F16))
        press(kVK_F16, forwarded: true, triggersOnce: true)
        interceptor.beginVdiRelayCooldownWindow()
        interceptor.isVdiAppFocused = false
        precondition(interceptor.inputSourceHIDKeyCode == Int64(kVK_F17))
        press(kVK_F17, forwarded: true, triggersOnce: false)  // Even with a pending VDI cooldown.

        interceptor.nativeLocalInputSourceKey = false
        precondition(interceptor.inputSourceHIDKeyCode == Int64(kVK_F16))
        press(kVK_F16, forwarded: false, triggersOnce: true)
        print("native_input_source_smoke: PASS (in-process events only)")
    }
}
