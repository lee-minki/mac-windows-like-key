// Engine-OFF UI invariant smoke test
//
// 검증 invariant: 엔진이 켜져 있지 않은 상태에서 KeyInterceptor 의 외부 메서드를 호출해도
// HIDRemapper 의 ownership 가드가 작동해 hidutil 시스템 상태를 건드리지 않아야 한다.
//
// 회귀 시나리오: 위저드(ModifierLayoutView)가 engine OFF 에서 applyCustomMappingsSync 를 호출
// 또는 어떤 path 가 setupDefaultMappings 를 호출 → ownership 가드가 막아야 함.

import Foundation

@main
struct EngineOffUISmoke {
    static func main() {
        // 초기 상태 — ownership 없음
        HIDRemapper.shared.resetOperationCounters()
        precondition(!HIDRemapper.shared.isOwnedByEngine,
                     "test precondition: ownership must start as false")

        let interceptor = KeyInterceptor()

        // 1. applyCustomMappings (Engine OFF) → HID 호출 안 됨
        let dummyMappings: [Int64: Int64] = [0x37: 0x3B]  // Cmd → Ctrl
        interceptor.applyCustomMappings(dummyMappings)

        // 2. applyCustomMappingsSync (Engine OFF) → HID 호출 안 됨
        interceptor.applyCustomMappingsSync(dummyMappings)

        // 3. setupDefaultMappings (Engine OFF) → HID 호출 안 됨
        interceptor.setupDefaultMappings()

        let apply = HIDRemapper.shared.applyCallCount
        let clear = HIDRemapper.shared.clearCallCount
        let unauthorized = HIDRemapper.shared.unauthorizedWriteAttempts

        if apply == 0 && clear == 0 {
            print("engine_off_ui_smoke: PASS (engine OFF UI 메서드 3종 모두 HID 미호출)")
            print("   (unauthorized write attempts: \(unauthorized) — guard 동작 확인)")
            exit(0)
        } else {
            print("engine_off_ui_smoke: FAIL")
            print("   apply: \(apply) (expected 0)")
            print("   clear: \(clear) (expected 0)")
            print("   unauthorized: \(unauthorized)")
            print("   → ownership 가드가 우회됨. 회귀 발생.")
            exit(1)
        }
    }
}
