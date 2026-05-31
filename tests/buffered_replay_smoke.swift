// Buffered replay adaptive timeout smoke (v1.7.0)
//
// 검증 invariant 6종:
//   1. 기본값(IME-sensitive 아님): currentInputSourceCommitTimeout == 0.100 (100ms 일반)
//   2. IME-sensitive 활성: currentInputSourceCommitTimeout == 0.180 (180ms Word/Pages 등)
//   3. inputSourceCommitTimeoutDefault == 0.100 (상수)
//   4. inputSourceCommitTimeoutIMESensitive == 0.180 (상수)
//   5. flag 토글 시 timeout 값 즉시 반영 (computed property)
//   6. IME-sensitive 와 다른 가드 플래그(VDI/Terminal) 가 독립적 (조합 안전)
//
// 이 테스트는 v1.7.0 의 adaptive timeout (P13 후속 — Word for Mac 등 IME-sensitive 앱
// 호환성 강화) 의 핵심 invariant 를 lock-down 한다. 회귀 발생 시 즉시 감지.

import Foundation

@main
struct BufferedReplaySmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true

        let interceptor = KeyInterceptor()

        // === Invariant 1: 기본값 (IME-sensitive 아님) ===
        interceptor.isIMESensitiveAppFocused = false
        guard interceptor.currentInputSourceCommitTimeout == 0.100 else {
            print("buffered_replay_smoke: FAIL — default timeout should be 0.100, got \(interceptor.currentInputSourceCommitTimeout)")
            exit(1)
        }
        print("  - Invariant 1 (default timeout = 0.100s) ✓")

        // === Invariant 2: IME-sensitive 활성 ===
        interceptor.isIMESensitiveAppFocused = true
        guard interceptor.currentInputSourceCommitTimeout == 0.180 else {
            print("buffered_replay_smoke: FAIL — IME-sensitive timeout should be 0.180, got \(interceptor.currentInputSourceCommitTimeout)")
            exit(1)
        }
        print("  - Invariant 2 (IME-sensitive timeout = 0.180s) ✓")

        // === Invariant 3 & 4: 상수 값 확인 ===
        guard interceptor.inputSourceCommitTimeoutDefault == 0.100 else {
            print("buffered_replay_smoke: FAIL — inputSourceCommitTimeoutDefault should be 0.100")
            exit(1)
        }
        guard interceptor.inputSourceCommitTimeoutIMESensitive == 0.180 else {
            print("buffered_replay_smoke: FAIL — inputSourceCommitTimeoutIMESensitive should be 0.180")
            exit(1)
        }
        print("  - Invariant 3+4 (constants 0.100 / 0.180) ✓")

        // === Invariant 5: 토글 즉시 반영 ===
        interceptor.isIMESensitiveAppFocused = false
        let t1 = interceptor.currentInputSourceCommitTimeout
        interceptor.isIMESensitiveAppFocused = true
        let t2 = interceptor.currentInputSourceCommitTimeout
        interceptor.isIMESensitiveAppFocused = false
        let t3 = interceptor.currentInputSourceCommitTimeout
        guard t1 == 0.100, t2 == 0.180, t3 == 0.100 else {
            print("buffered_replay_smoke: FAIL — toggle didn't reflect immediately: \(t1) → \(t2) → \(t3)")
            exit(1)
        }
        print("  - Invariant 5 (toggle reflects immediately) ✓")

        // === Invariant 6: 가드 플래그 독립성 ===
        // IME-sensitive 와 VDI/Terminal 가드는 서로 독립적이어야 함 (조합 가능)
        interceptor.isIMESensitiveAppFocused = true
        interceptor.isVdiAppFocused = true
        guard interceptor.currentInputSourceCommitTimeout == 0.180 else {
            print("buffered_replay_smoke: FAIL — IME-sensitive timeout should still be 0.180 even with VDI flag")
            exit(1)
        }
        interceptor.isVdiAppFocused = false
        interceptor.isTerminalAppFocused = true
        guard interceptor.currentInputSourceCommitTimeout == 0.180 else {
            print("buffered_replay_smoke: FAIL — IME-sensitive timeout should still be 0.180 even with Terminal flag")
            exit(1)
        }
        interceptor.isTerminalAppFocused = false
        interceptor.isIMESensitiveAppFocused = false
        print("  - Invariant 6 (flag independence: IME-sensitive × VDI × Terminal) ✓")

        print("buffered_replay_smoke: PASS (6 invariants)")
    }
}
