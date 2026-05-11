// Lifecycle invariant smoke test
//
// 검증 invariant: KeyInterceptor.init() 은 HID 시스템 상태를 절대 건드리지 않아야 한다.
// "엔진 OFF = 시스템 영향 없음" 안전 경계의 가장 중요한 게이트.
//
// 회귀: 누군가 KeyInterceptor.init() 안에서 HIDRemapper.apply/clear* 를 호출하면
// 이 테스트가 즉시 FAIL 한다.

import Foundation

@main
struct HIDLifecycleSmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true
        let initialApply = HIDRemapper.shared.applyCallCount
        let initialClear = HIDRemapper.shared.clearCallCount

        // Subject under test: KeyInterceptor 인스턴스 생성
        _ = KeyInterceptor()

        let deltaApply = HIDRemapper.shared.applyCallCount - initialApply
        let deltaClear = HIDRemapper.shared.clearCallCount - initialClear

        if deltaApply == 0 && deltaClear == 0 {
            print("hid_lifecycle_smoke: PASS (KeyInterceptor.init() touched HID 0 times)")
            exit(0)
        } else {
            print("hid_lifecycle_smoke: FAIL")
            print("   apply call delta: \(deltaApply) (expected 0)")
            print("   clear call delta: \(deltaClear) (expected 0)")
            print("   → init path가 hidutil 시스템 상태를 건드림. 회귀 발생.")
            exit(1)
        }
    }
}
