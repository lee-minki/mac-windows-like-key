import Foundation
import os.log

/// 앱 초기화(Reset) 서비스
/// 앱이 변경한 모든 설정을 기본값으로 되돌립니다.
class ResetService {
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "ResetService")
    
    // 앱에서 사용하는 UserDefaults 키 목록
    private let userDefaultsKeys = [
        "WinMacKey.Profiles",
        "LastUpdateCheck",
        "AutoCheckUpdates",
        "CustomVirtualizationApps",
        "useVdiMode",
        "activeMappingProfileId",
        "visualCustomMappings",
        "eventViewerAlwaysOnTop",
        "savedKeyboardProfiles",
        "toggleTriggerKey"
    ]
    
    /// 모든 앱 설정을 초기화합니다.
    /// - Parameters:
    ///   - keyInterceptor: 엔진 정지를 위한 KeyInterceptor
    ///   - profileManager: 프로필 재로드를 위한 ProfileManager
    ///   - completion: 초기화 완료 후 콜백
    func resetAll(
        keyInterceptor: KeyInterceptor,
        profileManager: ProfileManager? = nil,
        completion: (() -> Void)? = nil
    ) {
        logger.info("🔄 Starting full reset...")
        
        // 1. 엔진 정지
        keyInterceptor.stop()
        logger.info("✅ Engine stopped")
        
        // 2. 이벤트 로그 클리어
        keyInterceptor.events.removeAll()
        logger.info("✅ Event logs cleared")
        
        // 3. UserDefaults 초기화
        clearUserDefaults()
        logger.info("✅ UserDefaults cleared")
        
        // 4. 프로필 매니저 재로드 (기본 프로필로 복원)
        profileManager?.loadProfiles()
        logger.info("✅ Profiles reloaded to defaults")
        
        // 5. HID 매핑 해제 (동기 — 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
        logger.info("✅ HID mappings cleared")
        
        logger.info("🎉 Full reset completed")
        
        completion?()
    }
    
    /// UserDefaults에서 앱 관련 키를 모두 삭제합니다.
    private func clearUserDefaults() {
        for key in userDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
