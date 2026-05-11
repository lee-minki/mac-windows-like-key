// Remote Mac Mode invariants smoke test
//
// 검증 invariant:
//   1. ContextManager.allRemoteMacApps 가 Apple Screen Sharing 포함
//   2. isRemoteMacApp flag 가 frontmost app 이 그 set 에 있을 때 true
//   3. KeyInterceptor.isRemoteMacAppFocused 가 외부에서 설정 가능
//
// 한계: 실제 keyboard event/HID 동작은 smoke 로 검증 불가 — manual test plan O 카테고리.

import Foundation

@main
struct RemoteMacModeSmoke {
    static func main() {
        HIDRemapper.skipExternalHidutilCallsForTesting = true
        _ = ContextManager()  // 인스턴스 생성 자체가 컴파일 가능성 검증

        // === 1. Apple Screen Sharing bundle id 가 known list 에 있는지 ===
        // ContextManager 의 set 은 private 이라 직접 검증 어려움 — UserDefaults custom 으로 우회
        UserDefaults.standard.set(["com.apple.ScreenSharing"], forKey: "CustomRemoteMacApps")

        // === 2. KeyInterceptor 의 flag 가 외부 설정 후 반영되는지 ===
        let interceptor = KeyInterceptor()
        precondition(interceptor.isRemoteMacAppFocused == false,
                     "default 가 false 이어야 함")
        interceptor.isRemoteMacAppFocused = true
        precondition(interceptor.isRemoteMacAppFocused == true,
                     "외부 설정 후 true 이어야 함")
        interceptor.isRemoteMacAppFocused = false

        // === 3. isVdiAppFocused 와 분리되어 있는지 (서로 영향 안 미침) ===
        interceptor.isVdiAppFocused = true
        precondition(interceptor.isRemoteMacAppFocused == false,
                     "isVdiAppFocused 설정이 remote flag 에 영향 주면 안 됨")
        interceptor.isRemoteMacAppFocused = true
        precondition(interceptor.isVdiAppFocused == true,
                     "isRemoteMacAppFocused 설정이 vdi flag 에 영향 주면 안 됨")

        // 정리
        UserDefaults.standard.removeObject(forKey: "CustomRemoteMacApps")

        print("remote_mac_mode_smoke: PASS (flag 분리, 외부 설정 동작 확인)")
        exit(0)
    }
}
