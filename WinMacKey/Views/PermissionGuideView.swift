import SwiftUI
import AppKit

// MARK: - Setup Check (v1.4.1)
//
// 신규 맥 / 첫 실행에서 막히기 쉬운 환경 설정을 한곳에서 점검·안내한다.
// - 손쉬운 사용 / 입력 모니터링 권한 (없으면 핵심 기능 동작 안 함)
// - Caps Lock → ABC 입력 소스 전환 (SymbolicHotKey 162) 켜짐 → 대소문자 토글 막힘
// - "이전 입력 소스 선택" ⌃Space (SymbolicHotKey 60) 꺼짐 → 한/영 합성 실패 가능
//
// 직접 끄지 못하는 시스템 설정(Caps Lock·단축키)은 감지 후 안내 + 설정 열기 버튼만 제공한다.

struct SetupIssue: Identifiable {
    enum Kind { case accessibility, inputMonitoring, capsLockSwitch, inputSourceShortcut }
    enum Severity { case critical, warning }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let actionTitle: String
    let severity: Severity
}

enum SetupCheckService {
    /// 현재 환경의 미해결 설정 이슈. 비어 있으면 모두 정상.
    @MainActor
    static func detectIssues(using permissions: PermissionService) -> [SetupIssue] {
        var issues: [SetupIssue] = []

        if !permissions.checkAccessibilityPermission() {
            issues.append(SetupIssue(
                kind: .accessibility,
                title: "손쉬운 사용 권한 필요",
                detail: "키 입력을 가로채 한/영 전환·매핑을 적용하려면 손쉬운 사용 권한이 필요합니다. 이 권한이 없으면 프로필 위자드에서 Ctrl/Opt/Cmd 도 인식되지 않습니다.",
                actionTitle: "권한 요청 / 설정 열기",
                severity: .critical
            ))
        }

        if !permissions.checkInputMonitoringPermission() {
            issues.append(SetupIssue(
                kind: .inputMonitoring,
                title: "입력 모니터링 권한 필요",
                detail: "연결된 키보드와 Fn(🌐) 키를 감지하려면 입력 모니터링 권한이 필요합니다.",
                actionTitle: "설정 열기",
                severity: .critical
            ))
        }

        if isSymbolicHotKeyEnabled(162) {
            issues.append(SetupIssue(
                kind: .capsLockSwitch,
                title: "Caps Lock 이 한/영 전환으로 설정됨",
                detail: "macOS 설정상 Caps Lock 이 입력 소스 전환으로 동작해 대소문자 토글이 안 됩니다. 시스템 설정 → 키보드 → 입력 소스 → ‘모든 입력 소스’ 에서 ‘Caps Lock 키로 ABC 입력 소스 전환’ 을 끄세요. (한/영 전환은 Right Command 가 담당합니다.)",
                actionTitle: "키보드 설정 열기",
                severity: .warning
            ))
        }

        if isSymbolicHotKeyExplicitlyDisabled(60) {
            issues.append(SetupIssue(
                kind: .inputSourceShortcut,
                title: "‘이전 입력 소스 선택’ 단축키 꺼짐",
                detail: "WinMac Key 는 Right Command 한/영 전환을 ⌃Space(‘이전 입력 소스 선택’) 단축키로 합성합니다. 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스 에서 이 항목을 켜 주세요.",
                actionTitle: "키보드 설정 열기",
                severity: .warning
            ))
        }

        return issues
    }

    private static func symbolicHotKeys() -> [String: Any]? {
        UserDefaults.standard
            .persistentDomain(forName: "com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"] as? [String: Any]
    }

    /// enabled == true 인지 (키 부재 시 false).
    private static func isSymbolicHotKeyEnabled(_ id: Int) -> Bool {
        guard let entry = symbolicHotKeys()?[String(id)] as? [String: Any],
              let enabled = entry["enabled"] as? Bool else { return false }
        return enabled
    }

    /// 명시적으로 enabled == false 인지 (키 부재/true 면 false — 기본값은 켜짐으로 간주).
    private static func isSymbolicHotKeyExplicitlyDisabled(_ id: Int) -> Bool {
        guard let entry = symbolicHotKeys()?[String(id)] as? [String: Any],
              let enabled = entry["enabled"] as? Bool else { return false }
        return !enabled
    }
}

// MARK: - Setup Check Panel (첫 실행 점검 패널)

struct SetupCheckView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var issues: [SetupIssue] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if issues.isEmpty {
                allClear
            } else {
                VStack(spacing: 10) {
                    ForEach(issues) { issueRow($0) }
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issues.isEmpty ? .green : .orange)
                Text("설정 점검")
                    .font(.title2).bold()
            }
            Text(issues.isEmpty
                 ? "필요한 권한과 macOS 설정이 모두 준비됐습니다."
                 : "WinMac Key 가 제대로 동작하려면 아래 항목을 정리해 주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func issueRow(_ issue: SetupIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.severity == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .critical ? .red : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).font(.headline)
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(issue.actionTitle) { perform(issue) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var allClear: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("모두 정상입니다").font(.headline)
            Text("이제 프로필을 만들어 키보드 배치를 설정할 수 있어요.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        HStack {
            Button { refresh() } label: { Label("다시 점검", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
            Button { appState.relaunch() } label: { Label("앱 다시 시작", systemImage: "arrow.clockwise.circle") }
                .buttonStyle(.bordered)
                .help("권한을 바꾼 뒤 적용이 안 되면 누르세요. macOS '종료하고 다시 열기'가 메뉴바 앱을 재실행 못 하는 문제를 우회합니다.")
            Spacer()
            if issues.isEmpty {
                if appState.profileStore.profiles.isEmpty {
                    // 엔진은 프로필 ≥1 이어야 켜진다. 두 가지 시작 경로 제공.
                    SettingsLink {
                        Label("직접 프로필 만들기", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        appState.createKoreanOnlyProfile()
                        appState.toggleEngine()
                        dismiss()
                    } label: {
                        Label("한/영 전환만 시작", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    SettingsLink {
                        Label("프로필 / 설정 열기", systemImage: "person.crop.rectangle.stack")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func refresh() {
        appState.checkPermissions()
        issues = SetupCheckService.detectIssues(using: appState.permissionService)
        // 입력 모니터링이 부여됐으면 그때 키보드 감지 시작 (init 에서 미리 안 열어 프롬프트 순서 보호)
        appState.beginKeyboardMonitoringIfPermitted()
    }

    private func perform(_ issue: SetupIssue) {
        switch issue.kind {
        case .accessibility:
            appState.permissionService.requestAccessibilityPermission()
            appState.permissionService.openAccessibilitySettings()
        case .inputMonitoring:
            appState.permissionService.requestInputMonitoringPermission()
        case .capsLockSwitch, .inputSourceShortcut:
            openKeyboardSettings()
        }
    }

    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - First Run (첫 실행 환영 + 라이선스 1회 동의)

struct FirstRunView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "command.square.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("WinMac Key 에 오신 걸 환영합니다").font(.title2).bold()
                }
                Text("Windows 키보드 습관을 Mac 에서 그대로 — Right Command 로 한/영 전환, VDI·터미널 자동 대응.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                introRow("command", "Right Command 로 한/영 전환 (modifier 오염 없는 F16 HID 방식)")
                introRow("display", "Windows VDI(Omnissa Horizon)·터미널·Mac 원격을 자동 감지해 전환 방식을 바꿈")
                introRow("keyboard", "키보드별 프로필 + 자동 전환")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("라이선스").font(.headline)
                Text("WinMac Key 는 MIT 라이선스로 제공됩니다. 계속하면 라이선스 및 이용 안내에 동의하는 것으로 간주됩니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: "https://github.com/lee-minki/mac-windows-like-key/blob/main/LICENSE") {
                    Link("MIT License 전문 보기", destination: url).font(.caption)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("나중에") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("동의하고 시작") {
                    appState.hasCompletedFirstRun = true
                    dismiss()
                    // 이어서 권한·환경 점검 안내
                    let issues = SetupCheckService.detectIssues(using: appState.permissionService)
                    if !issues.isEmpty {
                        openWindow(id: "setup-window")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func introRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.green).frame(width: 20)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Move to Applications (설치 콤보, v1.5.0)
//
// DMG/다운로드/데스크탑처럼 /Applications 밖에서 처음 실행되면 응용 프로그램 폴더로
// 옮기도록 제안한다 (LetsMove 패턴). 비파괴적: 원본은 자동 삭제하지 않고, 어떤 실패에도
// 조용히 무시하고 기존 위치에서 계속 동작한다.
enum ApplicationMover {
    @MainActor
    static func offerMoveToApplicationsIfNeeded() {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundleURL.path

        // 이미 응용 프로그램 폴더면 종료
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/") { return }

        // 정확히 'DMG/다운로드/데스크탑에서 실행' 경우에만 제안 (개발/임시 빌드 false-positive 방지)
        let downloads = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        let desktop = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let shouldOffer = path.hasPrefix("/Volumes/")
            || path.hasPrefix(downloads + "/")
            || path.hasPrefix(desktop + "/")
        guard shouldOffer else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "응용 프로그램 폴더로 이동할까요?"
        alert.informativeText = "WinMac Key 가 응용 프로그램 폴더 밖에서 실행되고 있습니다. /Applications 로 옮기면 권한·자동 시작·업데이트가 안정적으로 동작합니다."
        alert.addButton(withTitle: "응용 프로그램으로 이동")
        alert.addButton(withTitle: "나중에")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let destURL = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(bundleURL.lastPathComponent)
        do {
            if fm.fileExists(atPath: destURL.path) {
                try? fm.trashItem(at: destURL, resultingItemURL: nil)  // 이전 설치본 정리
            }
            try fm.copyItem(at: bundleURL, to: destURL)

            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destURL, configuration: config) { _, error in
                if let error {
                    LogService.shared.warning("Relaunch from /Applications failed: \(error.localizedDescription)", category: "App")
                    return
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            LogService.shared.info("Moved app to /Applications and relaunched", category: "App")
        } catch {
            LogService.shared.warning("Move to /Applications failed: \(error.localizedDescription)", category: "App")
        }
    }
}

#Preview("Setup Check") {
    SetupCheckView()
        .environmentObject(AppState())
}

#Preview("First Run") {
    FirstRunView()
        .environmentObject(AppState())
}
