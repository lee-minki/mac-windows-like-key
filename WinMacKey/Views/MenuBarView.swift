import SwiftUI

/// SCR-02: 메뉴바 Popover
/// 현재 상태 확인 및 빠른 모드 전환을 제공합니다.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) private var openSettings

    private var triggerShortcutDescription: String {
        let trigger = appState.toggleTriggerKey == "rightOpt" ? "Right Option" : "Right Command"
        return "\(trigger) → Control+Space (Mac) / F16 (VDI)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 - 앱 상태
            headerSection
            
            Divider()
            
            // 권한이 없으면 권한 가이드 표시
            if !appState.hasAccessibilityPermission {
                permissionWarningSection
            } else {
                // 입력 소스 상태
                inputSourceSection
                
                Divider()
                
                // 엔진 상태 및 컨트롤
                engineSection
                
                Divider()
                
                // 빠른 액션
                quickActionsSection
            }
            
            Divider()
            
            // 앱 메뉴
            appMenuSection
        }
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WinMac Key")
                    .font(.headline)
                
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 지연 시간 표시
            if appState.isEngineRunning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", appState.keyInterceptor.averageLatencyMs))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
    
    private var inputSourceSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("입력 소스 전환")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(triggerShortcutDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.isEngineRunning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(appState.stateManager.switchCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("전환")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
    
    private var permissionWarningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("권한이 필요합니다", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            
            Text("손쉬운 사용 권한을 허용해주세요")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("설정 열기") {
                appState.permissionService.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
    }
    
    private var engineSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("엔진 상태")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isEngineRunning ? .green : .gray)
                        .frame(width: 8, height: 8)
                    
                    Text(appState.isEngineRunning ? "실행 중" : "중지됨")
                        .font(.callout)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { appState.isEngineRunning },
                set: { _ in appState.toggleEngine() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "event-viewer")
            }) {
                Label("Event Viewer 열기", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.clear)
            .contentShape(Rectangle())
            
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "log-window")
            }) {
                Label("로그 뷰어", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
    
    private var appMenuSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }) {
                Label("설정...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .keyboardShortcut(",", modifiers: .command)
            
            // 업데이트 확인 버튼
            Button(action: { openWindow(id: "update-window") }) {
                HStack {
                    Label("업데이트 확인...", systemImage: "arrow.triangle.2.circlepath")
                    
                    Spacer()
                    
                    if appState.updateService.updateAvailable {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // 도움말 버튼
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "help-window")
            }) {
                Label("도움말", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // Doctor 버튼
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "doctor-window")
            }) {
                Label("Doctor (진단/복구)", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            // 설정 초기화 버튼
            Button(action: {
                appState.showResetConfirmation = true
            }) {
                Label("설정 초기화...", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            Divider()
                .padding(.horizontal, 8)
            
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("WinMac Key 종료", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .confirmationDialog(
            "정말 초기화하시겠습니까?",
            isPresented: $appState.showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("초기화", role: .destructive) {
                appState.resetAll()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("엔진이 정지되고 모든 프로필이 기본값으로 복원됩니다.")
        }
    }

}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
