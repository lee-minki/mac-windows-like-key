import SwiftUI

/// SCR-03: 메인 대시보드
/// 앱별 매핑 프로필 설정 및 'The Silencer' 활성화
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @State private var selectedTab = 0
    @AppStorage("eventViewerAlwaysOnTop") private var eventViewerAlwaysOnTop: Bool = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            profilesTab
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }
                .tag(1)
            
            debugTab
                .tabItem {
                    Label("Debug", systemImage: "ant")
                }
                .tag(2)
        }
        .frame(width: 550, height: 450)
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Input Source Card
                cardView(title: "Input Source", icon: "globe") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("현재 입력 소스")
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: appState.stateManager.isSource1Active ? "a.square" : "character.textbox")
                                    .foregroundStyle(appState.stateManager.isSource1Active ? .green : .blue)
                                Text(appState.stateManager.currentSourceShortName)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(appState.stateManager.isSource1Active ? .green : .blue)
                            }
                        }
                        
                        HStack {
                            Text("트리거 키")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $appState.toggleTriggerKey) {
                                Text("Right Command").tag("rightCmd")
                                Text("Right Option").tag("rightOpt")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }
                        
                        HStack {
                            Text("전환 횟수")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(appState.stateManager.switchCount)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                
                // Core Status Card
                cardView(title: "Core Status", icon: "cpu") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Engine")
                                .foregroundStyle(.secondary)
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(appState.isEngineRunning ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(appState.isEngineRunning ? "RUNNING" : "STOPPED")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(appState.isEngineRunning ? .green : .secondary)
                            }
                            
                            Toggle("", isOn: Binding(
                                get: { appState.isEngineRunning },
                                set: { _ in appState.toggleEngine() }
                            ))
                            .toggleStyle(.switch)
                        }
                        
                        HStack {
                            Text("Latency")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f ms", appState.keyInterceptor.averageLatencyMs))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                // Context Awareness Card (Pro Feature)
                cardView(title: "Context Awareness", icon: "app.badge.checkmark", isPro: true) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Current App")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(appState.contextManager.currentAppName.isEmpty ? "—" : appState.contextManager.currentAppName)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        HStack {
                            Text("Auto-Profile")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(appState.contextManager.isVirtualizationApp ? "Windows Mode" : "Mac Mode")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(appState.contextManager.isVirtualizationApp ? .blue.opacity(0.2) : .gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if appState.isPro {
                            Text("Profiles tab에서 앱별 프로필을 관리하세요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(action: {}) {
                                Label("Pro 버전에서 사용 가능", systemImage: "lock.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(true)
                        }
                    }
                }

                // General Settings Card
                cardView(title: "General Settings", icon: "gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 시각적 키보드 레이아웃 설정
                        ModifierLayoutView()
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Toggle("이벤트 뷰어 항상 위", isOn: $eventViewerAlwaysOnTop)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VMware 한/영 전환")
                                if VirtualHIDManager.isDriverInstalled() {
                                    Text("Karabiner 드라이버 설치됨. VMware 등 가상화 앱에서 자동으로 Right Alt 키를 전송합니다.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Karabiner 드라이버 미설치. VMware 호환이 필요하면 Karabiner-DriverKit-VirtualHIDDevice를 설치하세요.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if VirtualHIDManager.isDriverInstalled() {
                                Text(appState.contextManager.isVirtualizationApp ? "활성" : "대기")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(appState.contextManager.isVirtualizationApp ? .green.opacity(0.2) : .gray.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text("미설치")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
                
                // Permission Status
                if !appState.hasAccessibilityPermission {
                    cardView(title: "Permission Required", icon: "exclamationmark.triangle.fill") {
                        VStack(spacing: 12) {
                            Text("손쉬운 사용 권한이 필요합니다")
                                .foregroundStyle(.orange)
                            
                            Button("시스템 설정 열기") {
                                appState.permissionService.openAccessibilitySettings()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                // Reset Card
                cardView(title: "초기화", icon: "arrow.counterclockwise") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("모든 설정을 기본값으로 되돌립니다.\n엔진이 정지되고, 저장된 프로필이 삭제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Accessibility 권한은 시스템 설정에서 직접 해제해야 합니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(role: .destructive) {
                            appState.showResetConfirmation = true
                        } label: {
                            Label("설정 초기화", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
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
            Text("엔진이 정지되고 모든 프로필이 기본값으로 복원됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }
    
    // MARK: - Profiles Tab

    private var profilesTab: some View {
        VStack(spacing: 0) {
            // Current foreground app context
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.contextManager.currentAppName.isEmpty
                         ? "-" : appState.contextManager.currentAppName)
                        .font(.subheadline)
                }
                Spacer()
                Text(appState.contextManager.currentBundleId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if appState.profileStore.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No saved profiles")
                        .font(.headline)
                    Text("General > Keyboard Layout > New Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.profileStore.profiles) { profile in
                        savedProfileRow(profile)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func savedProfileRow(_ profile: SavedKeyboardProfile) -> some View {
        let isActive = appState.activeMappingProfileId == profile.id.uuidString

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name)
                    .font(.headline)

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Button(isActive ? "Active" : "Apply") {
                    appState.applyProfile(profile)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isActive)

                Button {
                    appState.profileStore.delete(id: profile.id)
                    if isActive {
                        appState.activeMappingProfileId = "standardMac"
                        appState.keyInterceptor.applyCustomMappings([:])
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Text(profile.summary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            // Bundle ID assignment for per-app auto-switching
            HStack(spacing: 8) {
                Image(systemName: "app.badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let bundleId = profile.bundleId {
                    Text(bundleId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)

                    Button {
                        var updated = profile
                        updated.bundleId = nil
                        appState.profileStore.update(updated)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                } else {
                    Button {
                        var updated = profile
                        updated.bundleId = appState.contextManager.currentBundleId
                        appState.profileStore.update(updated)
                    } label: {
                        Label("Assign current app", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(appState.contextManager.currentBundleId.isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Debug Tab
    
    private var debugTab: some View {
        VStack(spacing: 16) {
            Text("디버그 정보")
                .font(.headline)
            
            GroupBox("시스템 상태") {
                VStack(alignment: .leading, spacing: 8) {
                    debugRow("Accessibility 권한", value: appState.hasAccessibilityPermission ? "✅ 허용됨" : "❌ 거부됨")
                    debugRow("Engine 상태", value: appState.isEngineRunning ? "🟢 실행 중" : "⚪ 중지됨")
                    debugRow("총 이벤트 수", value: "\(appState.keyInterceptor.totalEventCount)")
                    debugRow("평균 지연 시간", value: String(format: "%.3f ms", appState.keyInterceptor.averageLatencyMs))
                    debugRow("현재 앱", value: appState.contextManager.currentBundleId)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            Button("Event Viewer 열기") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "event-viewer")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }
    
    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
    
    // MARK: - Card View Helper
    
    private func cardView<Content: View>(
        title: String,
        icon: String,
        isPro: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                
                if isPro {
                    Text("PRO")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
