import Foundation
import AppKit

/// 앱 컨텍스트 매니저
/// 현재 포커스된 앱을 감지하고 적절한 프로필을 자동 전환합니다.
class ContextManager: ObservableObject {
    @Published var currentAppName: String = ""
    @Published var currentBundleId: String = ""
    @Published var isVirtualizationApp: Bool = false
    @Published var isTerminalApp: Bool = false
    @Published var isRemoteMacApp: Bool = false
    /// v1.7.0 — IME-sensitive 앱 포커스 여부 (Word/Pages/Keynote/PowerPoint 등).
    /// true 면 `KeyInterceptor` 의 `currentInputSourceCommitTimeout` 이 180ms 로 길어진다 (기본 100ms).
    /// 이런 앱들은 TIS notification 을 느리게 발화해 짧은 타임아웃에선 매번 풀 대기 + replay burst 가
    /// IME 처리 속도 초과 → 글자 drop. 카테고리 분리로 일반 앱은 더 빠르게(100ms), 느린 앱은 안정적(180ms).
    @Published var isIMESensitiveApp: Bool = false

    // 알려진 가상화 앱 Bundle ID 목록 (VDI — Windows 데스크탑)
    private let virtualizationApps: Set<String> = [
        "com.vmware.horizon",           // VMware Horizon (legacy)
        "com.vmware.fusion",            // VMware Fusion
        "com.omnissa.horizon.client.mac", // Omnissa Horizon Client (VMware 리브랜딩)
        "com.omnissa.horizon.protocol",   // Omnissa Horizon Protocol
        "com.parallels.desktop.console", // Parallels Desktop
        "com.microsoft.rdc.macos",      // Microsoft Remote Desktop
        "org.virtualbox.app.VirtualBoxVM" // VirtualBox
    ]

    // 알려진 Mac 원격접속 앱 Bundle ID 목록 (Mac → Mac)
    // 이 앱이 포커스면 F16 트리거를 패스스루 — 원격 Mac 의 WinMacKey 가 처리.
    // 즉 양쪽 Mac 모두 WinMacKey 설치 + 동일 self-signed cert 필요.
    private let remoteMacApps: Set<String> = [
        "com.apple.ScreenSharing",      // macOS 기본 화면 공유 / VNC
        "com.apple.RemoteDesktop",      // Apple Remote Desktop (ARD)
        "com.jumpdesktop.viewer",       // Jump Desktop
        "net.sf.cord",                  // CoRD (Mac VNC client)
        "com.realvnc.vncviewer",        // RealVNC Viewer
        "com.teamviewer.TeamViewer",
        "com.anydesk.anydesk",
        "com.parsecgaming.parsec",
    ]

    private let terminalApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.anthropic.claudefordesktop",
        "com.mitchellh.ghostty",
        "ai.warp.Warp-Stable",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty"
    ]

    // IME-sensitive 앱 (v1.7.0 · P13 후속) — TIS notification 을 느리게 발화해 commit window 가
    // 매번 풀 타임아웃까지 대기하는 경향이 있는 앱들. `KeyInterceptor.currentInputSourceCommitTimeout`
    // 이 180ms 로 길어져 첫 글자 mis-route 방지 + replay 안정성 확보.
    private let imeSensitiveApps: Set<String> = [
        // Microsoft 365
        "com.microsoft.Word",
        "com.microsoft.Powerpoint",
        "com.microsoft.Excel",
        "com.microsoft.onenote.mac",
        "com.microsoft.Outlook",
        // Apple iWork
        "com.apple.iWork.Pages",
        "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers",
        // Adobe (PDF 폼 입력)
        "com.adobe.Acrobat.Pro",
        "com.adobe.Reader"
    ]
    
    private var workspaceObserver: NSObjectProtocol?
    
    var onAppChanged: ((String, String) -> Void)?  // (bundleId, appName)
    
    init() {
        updateCurrentApp()
    }
    
    // MARK: - App Detection
    
    func startMonitoring() {
        // 현재 앱 상태 업데이트
        updateCurrentApp()
        
        // 앱 전환 감지
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
    }
    
    func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }
    
    private func handleAppActivation(_ notification: Notification) {
        updateCurrentApp()
    }
    
    private func updateCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""

        currentBundleId = bundleId
        currentAppName = appName
        isVirtualizationApp = allVirtualizationApps.contains(bundleId)
        isTerminalApp = allTerminalApps.contains(bundleId)
        isRemoteMacApp = allRemoteMacApps.contains(bundleId)
        isIMESensitiveApp = imeSensitiveApps.contains(bundleId)  // v1.7.0

        onAppChanged?(bundleId, appName)
    }

    // MARK: - Virtualization Detection

    /// 기본 앱 + UserDefaults 커스텀 앱을 합친 전체 목록
    private var allVirtualizationApps: Set<String> {
        let customApps = UserDefaults.standard.stringArray(forKey: "CustomVirtualizationApps") ?? []
        return virtualizationApps.union(customApps)
    }

    private var allTerminalApps: Set<String> {
        let customApps = UserDefaults.standard.stringArray(forKey: "CustomTerminalApps") ?? []
        return terminalApps.union(customApps)
    }

    private var allRemoteMacApps: Set<String> {
        let customApps = UserDefaults.standard.stringArray(forKey: "CustomRemoteMacApps") ?? []
        return remoteMacApps.union(customApps)
    }

    /// 현재 앱이 가상화 앱인지 확인
    func isCurrentAppVirtualization() -> Bool {
        return allVirtualizationApps.contains(currentBundleId)
    }

    func isCurrentAppTerminal() -> Bool {
        return allTerminalApps.contains(currentBundleId)
    }

    func isCurrentAppRemoteMac() -> Bool {
        return allRemoteMacApps.contains(currentBundleId)
    }
    
    /// 가상화 앱 목록에 새 앱 추가
    func addVirtualizationApp(_ bundleId: String) {
        // 런타임에는 Set이 immutable하므로 UserDefaults로 관리
        var customApps = UserDefaults.standard.stringArray(forKey: "CustomVirtualizationApps") ?? []
        if !customApps.contains(bundleId) {
            customApps.append(bundleId)
            UserDefaults.standard.set(customApps, forKey: "CustomVirtualizationApps")
        }
    }

    func addTerminalApp(_ bundleId: String) {
        var customApps = UserDefaults.standard.stringArray(forKey: "CustomTerminalApps") ?? []
        if !customApps.contains(bundleId) {
            customApps.append(bundleId)
            UserDefaults.standard.set(customApps, forKey: "CustomTerminalApps")
        }
    }

    func addRemoteMacApp(_ bundleId: String) {
        var customApps = UserDefaults.standard.stringArray(forKey: "CustomRemoteMacApps") ?? []
        if !customApps.contains(bundleId) {
            customApps.append(bundleId)
            UserDefaults.standard.set(customApps, forKey: "CustomRemoteMacApps")
        }
    }
    
    /// 모든 가상화 앱 Bundle ID 반환
    func getAllVirtualizationApps() -> [String] {
        let customApps = UserDefaults.standard.stringArray(forKey: "CustomVirtualizationApps") ?? []
        return Array(virtualizationApps) + customApps
    }
    
    deinit {
        stopMonitoring()
    }
}
