import Foundation
import AppKit

/// 권한 관리 서비스
/// 손쉬운 사용(Accessibility) 권한 체크 및 요청을 담당합니다.
class PermissionService: ObservableObject {
    @Published var isAccessibilityGranted: Bool = false
    
    init() {
        checkAccessibilityPermission()
    }
    
    // MARK: - Accessibility Permission
    
    /// 손쉬운 사용 권한 확인
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
        return trusted
    }
    
    /// 권한 요청 프롬프트 표시 (시스템 다이얼로그)
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // 권한 변경 후 상태 업데이트를 위해 폴링
        startPermissionPolling()
    }
    
    /// 시스템 설정의 손쉬운 사용 패널 열기
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        
        // 설정 열때도 폴링 시작
        startPermissionPolling()
    }
    
    /// 시스템 설정 열기 (일반)
    func openSystemPreferences() {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
        startPermissionPolling()
    }
    
    /// 키보드 단축키 설정 열기 (입력 소스)
    func openInputSourceSettings() {
        // macOS Ventura 이상: 키보드 단축키 설정
        // 이전 버전 호환성을 위해 일반 키보드 설정으로 이동
        let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!
        
        // 시도: 키보드 단축키 > 입력 소스 섹션 (OS 버전에 따라 동작 상이할 수 있음)
        // x-apple.systempreferences:com.apple.keyboardservices?TextInput_Shortcuts (Ventura+)
        // x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts (Monterey-)
        
        let shortcutsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") ?? fallbackUrl
        
        NSWorkspace.shared.open(shortcutsUrl)
    }
    
    // MARK: - Permission Polling
    
    private var pollingTimer: Timer?
    
    private func startPermissionPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.checkAccessibilityPermission() {
                timer.invalidate()
                self.pollingTimer = nil
                
                // 권한 획득 성공 알림
                NotificationCenter.default.post(
                    name: .accessibilityPermissionGranted,
                    object: nil
                )
            }
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}
