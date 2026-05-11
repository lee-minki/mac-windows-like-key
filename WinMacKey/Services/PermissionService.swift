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
        startAccessibilityPolling()
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
        startAccessibilityPolling()
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
        startInputMonitoringPolling()
    }

    /// 시스템 설정 열기 (일반) — 어느 권한을 위한 동선인지 모호하므로 Accessibility 폴링만 시작.
    /// 사용자가 Input Monitoring 설정을 위해 따로 도착하면 그 진입점에서 별도 polling.
    func openSystemPreferences() {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
        startAccessibilityPolling()
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

    /// Terminal.app 을 열고 tccutil 명령을 자동 실행.
    /// ⚠️ 위험: TCC 권한 entry 를 즉시 변경하는 명령 — 사용자 confirmation 후에만 호출되어야 한다.
    /// caller (예: MenuBarView 의 stale grant 안내) 는 반드시 NSAlert 등으로 명시 동의를 받은 뒤 호출.
    ///
    /// AppleScript `do script` 는 명령을 새 Terminal 창에서 자동 입력 + Enter 실행 (사용자 추가 입력 불필요).
    /// 즉 "사용자는 Enter만" 이 아니라 "즉시 실행" 이다 — UI 측에서 confirmation 가드 필수.
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

    /// 사용자에게 confirmation dialog 띄우고 동의하면 runTccutilResetInTerminal 호출.
    /// 이 메서드를 통해서만 자동 실행이 가능하도록 UI 가 호출해야 한다.
    @MainActor
    func confirmAndRunTccutilReset() {
        let alert = NSAlert()
        alert.messageText = "TCC 권한 등록을 초기화하시겠습니까?"
        alert.informativeText = """
            다음 명령이 Terminal.app 에서 즉시 실행됩니다:

            \(tccutilResetCommand)

            이 명령은 WinMac Key 의 손쉬운 사용 권한 등록을 제거합니다.
            실행 후 앱을 다시 실행하면 권한 요청 다이얼로그가 나타납니다.

            계속하시려면 '실행'을 누르세요.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "실행")
        alert.addButton(withTitle: "취소")

        if alert.runModal() == .alertFirstButtonReturn {
            runTccutilResetInTerminal()
        }
    }

    // MARK: - Permission Polling
    //
    // Accessibility 와 Input Monitoring 은 사용자 동선·문서상 별개로 다룬다.
    // - Accessibility: 엔진 동작에 필수 (CGEventTap 권한). 부여 즉시 자동 엔진 시작 트리거.
    // - Input Monitoring: 일부 macOS 버전에서만 보조적으로 요구되며 UI 흐름은 분리됨.
    //
    // 과거에는 두 권한 polling 종료 조건이 AND 결합이라 Accessibility 만 허용한
    // 사용자는 timer 가 계속 돌고 accessibilityPermissionGranted 알림이 발화되지 않았다.
    // 두 polling 을 완전히 분리해 각자의 동선을 가짐.

    private var accessibilityPollingTimer: Timer?
    private var inputMonitoringPollingTimer: Timer?
    private let pollingTimeout: TimeInterval = 300  // 5분 후 자동 종료 (배터리 보호)
    private var accessibilityPollingStartedAt: Date?
    private var inputMonitoringPollingStartedAt: Date?

    private func startAccessibilityPolling() {
        accessibilityPollingTimer?.invalidate()
        accessibilityPollingStartedAt = Date()
        accessibilityPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // Timeout
            if let start = self.accessibilityPollingStartedAt,
               Date().timeIntervalSince(start) > self.pollingTimeout {
                timer.invalidate()
                self.accessibilityPollingTimer = nil
                self.accessibilityPollingStartedAt = nil
                return
            }

            if self.checkAccessibilityPermission() {
                timer.invalidate()
                self.accessibilityPollingTimer = nil
                self.accessibilityPollingStartedAt = nil

                // 권한 허용 직후 자동 엔진 시작 흐름의 트리거.
                NotificationCenter.default.post(
                    name: .accessibilityPermissionGranted,
                    object: nil
                )
            }
        }
    }

    private func startInputMonitoringPolling() {
        inputMonitoringPollingTimer?.invalidate()
        inputMonitoringPollingStartedAt = Date()
        inputMonitoringPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if let start = self.inputMonitoringPollingStartedAt,
               Date().timeIntervalSince(start) > self.pollingTimeout {
                timer.invalidate()
                self.inputMonitoringPollingTimer = nil
                self.inputMonitoringPollingStartedAt = nil
                return
            }

            if self.checkInputMonitoringPermission() {
                timer.invalidate()
                self.inputMonitoringPollingTimer = nil
                self.inputMonitoringPollingStartedAt = nil
            }
        }
    }

    func stopPolling() {
        accessibilityPollingTimer?.invalidate()
        accessibilityPollingTimer = nil
        accessibilityPollingStartedAt = nil
        inputMonitoringPollingTimer?.invalidate()
        inputMonitoringPollingTimer = nil
        inputMonitoringPollingStartedAt = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}
