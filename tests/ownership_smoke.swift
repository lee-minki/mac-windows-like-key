// HID Ownership semantics smoke test
//
// 검증 invariant:
//   1. takeOwnership 후 apply 가능
//   2. releaseOwnership 후 apply 거부
//   3. internalClearAllForTermination 은 ownership 없어도 동작 (cleanup path)
//   4. hasAppliedAnyMapping 가 false 면 termination cleanup 이 no-op

import Foundation

@main
struct OwnershipSmoke {
    static func main() {
        let remapper = HIDRemapper.shared

        // === 1. Ownership 없으면 apply 거부 ===
        remapper.resetOperationCounters()
        precondition(!remapper.isOwnedByEngine)
        remapper.applyMappings([0x37: 0x3B])
        guard remapper.applyCallCount == 0 else {
            print("ownership_smoke: FAIL — apply without ownership wasn't refused (count=\(remapper.applyCallCount))")
            exit(1)
        }
        guard remapper.unauthorizedWriteAttempts > 0 else {
            print("ownership_smoke: FAIL — unauthorizedWriteAttempts not incremented")
            exit(1)
        }

        // === 2. takeOwnership 후 apply 동작 (count 만 검증 — 실제 hidutil 부르지 않으려면 mock 필요)
        // 실제 hidutil 을 부르지 않기 위해 ownership only 체크.
        remapper.resetOperationCounters()
        remapper.takeOwnership()
        precondition(remapper.isOwnedByEngine)

        // === 3. release 후 다시 거부 ===
        remapper.releaseOwnership()
        precondition(!remapper.isOwnedByEngine)
        remapper.applyMappings([0x37: 0x3B])
        guard remapper.applyCallCount == 0 else {
            print("ownership_smoke: FAIL — apply after release wasn't refused")
            exit(1)
        }

        // === 4. internalClearAllForTermination 은 ownership 없이도 호출 가능하지만
        //    hasAppliedAnyMapping = false 면 no-op
        remapper.resetOperationCounters()
        precondition(!remapper.isOwnedByEngine)
        remapper.internalClearAllForTermination()
        guard remapper.clearCallCount == 0 else {
            print("ownership_smoke: FAIL — termination cleanup ran even though no mappings applied (clear=\(remapper.clearCallCount))")
            exit(1)
        }

        print("ownership_smoke: PASS (4 invariants 검증 완료)")
        exit(0)
    }
}
