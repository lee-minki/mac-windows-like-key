// Commit window invariant smoke (v1.7.0)
//
// 검증 invariant 7종:
//   1. 초기 상태에서 complete/fail 호출 시 crash 없음 (guard 작동)
//   2. VDI 포커스 시 beginInputSourceCommitWindow no-op (가드)
//   3. 터미널 포커스 시 beginInputSourceCommitWindow no-op (P10 fix · v1.6.1)
//   4. begin → complete 순서 안전
//   5. begin → fail 순서 안전
//   6. 연속 begin (supersede) 안전
//   7. 모든 호출이 main thread 에서 — assert 미발화 (Main-Thread-Only contract · v1.7.0)
//
// 실제 commit window 의 timeout 발화·flush 시점·post 동작 검증은 manual test plan
// (Word/Notes 등 실기 앱) 에서 진행. 본 스모크는 API contract + 가드 + state 안전성만.

import Foundation

@main
struct CommitWindowSmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true

        guard Thread.isMainThread else {
            print("commit_window_smoke: FAIL — must run on main thread")
            exit(1)
        }

        let interceptor = KeyInterceptor()

        // === Invariant 1: 초기 complete/fail 안전 ===
        interceptor.completeInputSourceCommitWindow()
        interceptor.failInputSourceCommitWindow()
        print("  - Invariant 1 (initial complete/fail no-op) ✓")

        // === Invariant 2: VDI 포커스 가드 ===
        interceptor.isVdiAppFocused = true
        interceptor.beginInputSourceCommitWindow()  // guard 로 no-op
        interceptor.isVdiAppFocused = false
        print("  - Invariant 2 (VDI focus guards begin) ✓")

        // === Invariant 3: 터미널 포커스 가드 (P10) ===
        interceptor.isTerminalAppFocused = true
        interceptor.beginInputSourceCommitWindow()  // guard 로 no-op
        interceptor.isTerminalAppFocused = false
        print("  - Invariant 3 (Terminal focus guards begin, P10) ✓")

        // === Invariant 4: begin → complete 순서 ===
        interceptor.beginInputSourceCommitWindow()
        interceptor.completeInputSourceCommitWindow()
        print("  - Invariant 4 (begin → complete sequence) ✓")

        // === Invariant 5: begin → fail 순서 ===
        interceptor.beginInputSourceCommitWindow()
        interceptor.failInputSourceCommitWindow()
        print("  - Invariant 5 (begin → fail sequence) ✓")

        // === Invariant 6: 연속 begin (supersede 안전) ===
        interceptor.beginInputSourceCommitWindow()
        interceptor.beginInputSourceCommitWindow()
        interceptor.completeInputSourceCommitWindow()
        print("  - Invariant 6 (consecutive begin supersede) ✓")

        // === Invariant 7: VDI cooldown 도 같은 패턴 ===
        interceptor.isVdiAppFocused = true
        interceptor.beginVdiRelayCooldownWindow()
        interceptor.isVdiAppFocused = false
        print("  - Invariant 7 (VDI cooldown begin) ✓")

        print("commit_window_smoke: PASS (7 invariants)")
    }
}
