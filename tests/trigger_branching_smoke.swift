// Trigger branching invariant smoke test
//
// 검증 대상: KeyInterceptor 의 isVdiAppFocused / isRemoteMacAppFocused / isTerminalApp
// 같은 flag 들이 외부 (AppState) 에서 설정 가능하고 서로 독립적인지.
//
// 이 smoke 는 v1.3.4 와 v1.3.5 둘 다에서 통과해야 한다 (flag 자체의 존재·독립성은 invariant).
// v1.3.5 hotfix 는 KeyInterceptor 내부에서 그 flag 를 어떻게 "사용" 하는지를 바꾸는 거지,
// flag 자체의 의미는 그대로.
//
// 실제 패스스루/suppress 결정 path 는 CGEvent 가 필요해 단위 테스트 불가 — manual test plan
// 의 [2] VDI 와 [3] Mac 원격 카테고리가 그 역할.

import Foundation

@main
struct TriggerBranchingSmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true

        let interceptor = KeyInterceptor()

        // === Invariant 1: 모든 mode flag default = false ===
        precondition(interceptor.isVdiAppFocused == false,
                     "default isVdiAppFocused must be false")
        precondition(interceptor.isRemoteMacAppFocused == false,
                     "default isRemoteMacAppFocused must be false")

        // === Invariant 2: VDI flag 외부 설정 가능 ===
        interceptor.isVdiAppFocused = true
        precondition(interceptor.isVdiAppFocused == true)
        interceptor.isVdiAppFocused = false

        // === Invariant 3: Remote Mac flag 외부 설정 가능 ===
        interceptor.isRemoteMacAppFocused = true
        precondition(interceptor.isRemoteMacAppFocused == true)
        interceptor.isRemoteMacAppFocused = false

        // === Invariant 4: 두 flag 가 서로 독립 (한 쪽 set 이 다른 쪽에 영향 없음) ===
        interceptor.isVdiAppFocused = true
        precondition(interceptor.isRemoteMacAppFocused == false,
                     "setting VDI must not affect Remote Mac")
        interceptor.isRemoteMacAppFocused = true
        precondition(interceptor.isVdiAppFocused == true,
                     "setting Remote Mac must not affect VDI")
        interceptor.isVdiAppFocused = false
        interceptor.isRemoteMacAppFocused = false

        // === Invariant 5: triggerKeyCode 가 F16 (kVK_F16 = 0x6A = 106) ===
        precondition(interceptor.triggerKeyCode == 0x6A,
                     "trigger key must remain F16 (0x6A). 다른 값이면 hidutil 매핑과 불일치.")

        print("trigger_branching_smoke: PASS (5 invariants)")
        print("   - flag default = false ✓")
        print("   - VDI flag 외부 설정 가능 ✓")
        print("   - Remote Mac flag 외부 설정 가능 ✓")
        print("   - 두 flag 서로 독립 ✓")
        print("   - triggerKeyCode = F16 (0x6A) ✓")
        exit(0)
    }
}
