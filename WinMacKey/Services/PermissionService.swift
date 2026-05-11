import Foundation
import AppKit
import ApplicationServices

/// 권한 관리 서비스
/// 손쉬운 사용(Accessibility) 권한 체크 및 요청을 담당합니다.
class PermissionService: ObservableObject {
    @Published var isAccessibilityGranted: Bool = false
    @Published var isInputMonitoringGranted: Bool = false
    /// 이전에는 권한이 부여되었으나 현재는 거부 상태 — 보통 코드 서명 csreq 변경으로
    /// TCC 데이터베이스의 등록 항목이 무효화되었을 때 발생.
    @Published var isStaleGrantDetected: Bool = false

    private let wasEverGrantedKey = "WinMacKey.AccessibilityWasEverGranted"

    init() {
        checkAccessibilityPermission()
        checkInputMonitoringPermission()
    }

    // MARK: - Accessibility Permission

    /// 손쉬운 사용 권한 확인
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        let wasGranted = UserDefaults.standard.bool(forKey: wasEverGrantedKey)
        let stale = wasGranted && !trusted

        if trusted && !wasGranted {
            UserDefaults.standard.set(true, forKey: wasEverGrantedKey)
        }

        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
            self.isStaleGrantDetected = stale
        }
        return trusted
    }

    @discardableResult
    func checkInputMonitoringPermission() -> Bool {
        let trusted = CGPreflightListenEventAccess()
        DispatchQueue.main.async {
            self.isInputMonitoringGranted = trusted
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

    func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
        openInputMonitoringSettings()
    }

    /// 시스템 설정의 손쉬운 사용 패널 열기
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)

        // 설정 열때도 폴링 시작
        startPermissionPolling()
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
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

    // MARK: - Stale TCC Grant Mitigation

    /// `tccutil reset Accessibility <bundle_id>` 명령 문자열
    /// 같은 bundle ID의 모든 TCC 항목을 제거하여 다음 권한 요청 시 새로 등록됩니다.
    /// sudo 불필요 — 자기 자신의 csreq에 대한 reset이므로 user-level 권한으로 충분.
    var tccutilResetCommand: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.winmackey.app"
        return "tccutil reset Accessibility \(bundleID)"
    }

    /// tccutil 명령을 클립보드에 복사
    func copyTccutilCommandToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tccutilResetCommand, forType: .string)
    }

    /// Terminal.app을 열어 tccutil 명령을 자동 입력
    /// 사용자는 Enter만 눌러 실행
    func runTccutilResetInTerminal() {
        let cmd = tccutilResetCommand
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
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

            if self.checkAccessibilityPermission() && self.checkInputMonitoringPermission() {
                timer.invalidate()
                self.pollingTimer = nil

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
