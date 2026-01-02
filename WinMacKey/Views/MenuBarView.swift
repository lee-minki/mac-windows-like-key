import SwiftUI

/// SCR-02: 메뉴바 Popover
/// 현재 상태 확인 및 빠른 모드 전환을 제공합니다.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 - 앱 상태
            headerSection
            
            Divider()
            
            // 권한이 없으면 권한 가이드 표시
            if !appState.hasAccessibilityPermission {
                permissionWarningSection
            } else {
                // 엔진 상태 및 컨트롤
                engineSection
                
                Divider()
                
                // 현재 컨텍스트
                contextSection
                
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
                
                Text(appState.isPro ? "Pro Edition" : "Free Edition")
                    .font(.caption)
                    .foregroundStyle(appState.isPro ? .orange : .secondary)
            }
            
            Spacer()
            
            // 지연 시간 표시
            if appState.isEngineRunning {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f", appState.currentLatencyMs))
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
    
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("현재 컨텍스트")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: appState.contextManager.isVirtualizationApp ? "desktopcomputer" : "app.fill")
                    .foregroundStyle(appState.contextManager.isVirtualizationApp ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.contextManager.currentAppName.isEmpty ? "알 수 없음" : appState.contextManager.currentAppName)
                        .font(.callout)
                        .lineLimit(1)
                    
                    if appState.contextManager.isVirtualizationApp {
                        Text("Windows Mode 활성화")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
            }
        }
        .padding(12)
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { openWindow(id: "event-viewer") }) {
                Label("Event Viewer 열기", systemImage: "list.bullet.rectangle")
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
            Button(action: { openSettings() }) {
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
                    
                    // 업데이트 가능 시 배지 표시
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
            
            if !appState.isPro {
                Divider()
                    .padding(.horizontal, 8)
                
                Button(action: openDonationLink) {
                    Label("Pro 버전 후원하기 ♥", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            
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
    }
    
    private func openDonationLink() {
        if let url = URL(string: "https://github.com/sponsors/lee-minki") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
