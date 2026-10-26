import Foundation
import os.log

/// 앱 초기화(Reset) 서비스
/// 앱이 변경한 모든 설정을 기본값으로 되돌립니다.
class ResetService {
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "ResetService")
    
    // 앱에서 사용하는 UserDefaults 키 목록 — 단일 정의(AppManagedDefaultsKeys)를 공유.
    // ResetService 와 DoctorService.emergencyRecovery 가 같은 목록을 쓰도록 일원화해
    // 키 추가 시 한쪽만 누락되는 drift 를 방지한다.
    private let userDefaultsKeys = AppManagedDefaultsKeys.all
    
    /// 모든 앱 설정을 초기화합니다.
    /// - Parameters:
    ///   - keyInterceptor: 엔진 정지를 위한 KeyInterceptor
    ///   - completion: 초기화 완료 후 콜백
    func resetAll(
        keyInterceptor: KeyInterceptor,
        keyboardDeviceManager: KeyboardDeviceManager? = nil,
        completion: (() -> Void)? = nil
    ) {
        logger.info("Starting full reset...")

        // 1. 엔진 정지 — keyInterceptor.stop() 이 ownership 있는 동안 clearMappingsSync 호출.
        //    toggleEngine 과 다르게 명시적 release 는 stop 후 즉시 (이후 추가 cleanup 이 hidutil 안 건드림).
        keyInterceptor.stop()
        if HIDRemapper.shared.isOwnedByEngine {
            HIDRemapper.shared.releaseOwnership()
        }
        logger.info("Engine stopped, HID ownership released")

        // 1b. 키보드 디바이스 모니터링 정지
        keyboardDeviceManager?.stopMonitoring()
        logger.info("Keyboard device monitoring stopped")

        // 2. 이벤트 로그 클리어
        keyInterceptor.events.removeAll()
        logger.info("Event logs cleared")

        // 3. UserDefaults 초기화
        clearUserDefaults()
        logger.info("UserDefaults cleared")

        // 4. 모든 HID 매핑 해제 — ownership 우회 (이미 release 됨, Reset 은 명시적 cleanup path).
        HIDRemapper.shared.internalClearAllForTermination()
        logger.info("All HID mappings cleared (via termination path)")

        logger.info("Full reset completed")

        completion?()
    }
    
    /// UserDefaults에서 앱 관련 키를 모두 삭제합니다.
    private func clearUserDefaults() {
        for key in userDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// 앱이 관리하는 모든 UserDefaults 키의 단일 정의.
/// Reset(`ResetService`)·Emergency Recovery(`DoctorService`)가 공유해, 신규 키 추가 시
/// 한쪽 목록만 갱신되어 초기화가 불완전해지는 drift 를 구조적으로 차단한다.
enum AppManagedDefaultsKeys {
    static let all: [String] = [
        "WinMacKey.Profiles",
        "LastUpdateCheck",
        "AutoCheckUpdates",
        "CustomVirtualizationApps",
        "CustomTerminalApps",
        "CustomRemoteMacApps",            // v1.8.2: ContextManager 가 쓰지만 누락돼 있던 키
        "activeMappingProfileId",
        "visualCustomMappings",
        "eventViewerAlwaysOnTop",
        "savedKeyboardProfiles",
        "languagePairSource1",
        "languagePairSource2",
        "startEngineOnAppLaunch",
        "hasCompletedFirstRunOnboarding", // v1.8.2: 초기화 후 첫 실행 온보딩 재노출
        "WinMacKey.AccessibilityWasEverGranted" // v1.8.2: stale-grant 판정 상태도 초기화
    ]
}
