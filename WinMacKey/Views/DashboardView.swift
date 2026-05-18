import SwiftUI

/// SCR-03: 메인 대시보드
/// 앱별 매핑 프로필 설정 및 'The Silencer' 활성화
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @State private var selectedTab = 0
    @AppStorage("eventViewerAlwaysOnTop") private var eventViewerAlwaysOnTop: Bool = false

    /// 키보드 바인딩 capture sheet 가 띄워질 대상 프로필.
    /// nil 이면 sheet 닫힘. 키보드 바인딩 UX 의 핵심 state.
    @State private var bindingTargetProfile: SavedKeyboardProfile?

    private var triggerShortcutDescription: String {
        "Right Command → Ctrl+Space (Mac) / F16 (VDI)"
    }
    
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
        // P2 / M3 — first-seen prompt (보조 — MenuBarView 가 주).
        // Settings 윈도우가 열려 있을 때 새 키보드 입력이 오면 여기서도 sheet 표시.
        .sheet(item: $appState.firstSeenKeyboardCandidate) { device in
            FirstSeenKeyboardPromptView(device: device)
                .environmentObject(appState)
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Input Source Card
                cardView(title: "Input Source", icon: "globe") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("전환 방식")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(triggerShortcutDescription)
                                .font(.system(.caption, design: .monospaced))
                        }

                        HStack {
                            Text("트리거 키")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Right Command")
                                .font(.system(.body, design: .monospaced))
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
                
                // Context Awareness Card
                cardView(title: "Context Awareness", icon: "app.badge.checkmark") {
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

                        Text("Profiles tab에서 앱별 프로필을 관리하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // General Settings Card
                cardView(title: "General Settings", icon: "gearshape") {
                    VStack(alignment: .leading, spacing: 12) {
                        // 시각적 키보드 레이아웃 설정
                        ModifierLayoutView()
                    }
                }

                // Startup Card
                cardView(title: "Startup", icon: "power.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("로그인 시 자동 실행")
                                    .font(.subheadline)
                                Text(appState.launchAtLoginService.statusDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { appState.launchAtLoginService.isEnabled },
                                set: { appState.launchAtLoginService.setEnabled($0) }
                            ))
                            .toggleStyle(.switch)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("앱 실행 후 엔진 자동 시작")
                                    .font(.subheadline)
                                Text("재부팅 후 바로 Right Command 전환을 쓰려면 함께 켜두세요. 손쉬운 사용 권한이 없으면 시작만 보류됩니다.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $appState.startEngineOnAppLaunch)
                                .toggleStyle(.switch)
                        }

                        if appState.launchAtLoginService.requiresApproval {
                            Button("로그인 항목 설정 열기") {
                                appState.launchAtLoginService.openLoginItemsSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if appState.launchAtLoginService.shouldShowSettingsButton {
                            Button("로그인 항목 설정 열기") {
                                appState.launchAtLoginService.openLoginItemsSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                
                // Permission Status
                if !appState.hasAccessibilityPermission {
                    cardView(title: "Permission Required", icon: "exclamationmark.triangle.fill") {
                        VStack(spacing: 12) {
                            Text("손쉬운 사용 권한이 필요합니다")
                                .foregroundStyle(.orange)
                             
                            Button("손쉬운 사용 설정 열기") {
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

            // Current keyboard device context
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastActiveKeyboard?.displayName ?? "-")
                        .font(.subheadline)
                }
                Spacer()
                if let device = appState.lastActiveKeyboard {
                    Text(device.matchingKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
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
        .sheet(item: $bindingTargetProfile) { target in
            // 같은 디바이스에 이미 바인딩된 다른 프로필이 있는지 검사 (충돌 경고용).
            // BindingCaptureView 가 캡처된 디바이스와 비교해 충돌 시 안내.
            // 여기서는 일단 default 로 nil 전달, view 가 캡처 시 실시간으로 다시 검사하지만
            // 정적으로 미리 알려주려면 candidate 가 정해진 후가 자연스러움. 그래서 view 내부 처리.
            KeyboardBindingCaptureView(
                appState: appState,
                profileName: target.name,
                existingBindingOnSameDevice: nil, // 동적으로 view 가 검사
                onConfirm: { identifier in
                    // 다른 프로필이 동일 디바이스 바인딩 중이면 해당 바인딩 제거 (이전).
                    for existing in appState.profileStore.profiles where existing.id != target.id {
                        if existing.deviceIdentifier == identifier {
                            var demoted = existing
                            demoted.deviceIdentifier = nil
                            appState.profileStore.update(demoted)
                        }
                    }
                    // 새 바인딩 적용.
                    var updated = target
                    updated.deviceIdentifier = identifier
                    appState.profileStore.update(updated)
                    bindingTargetProfile = nil
                },
                onCancel: {
                    bindingTargetProfile = nil
                }
            )
        }
    }

    private func savedProfileRow(_ profile: SavedKeyboardProfile) -> some View {
        let isActive = appState.activeMappingProfileId == profile.id.uuidString

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name)
                    .font(.headline)

                Text(profile.legendStyle.title)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

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
                .lineLimit(3)

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

            // Keyboard device assignment for per-device auto-switching
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let device = profile.deviceIdentifier {
                    Text(device.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.purple)

                    Button {
                        var updated = profile
                        updated.deviceIdentifier = nil
                        appState.profileStore.update(updated)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                } else {
                    Button {
                        // v1.3.6: Press-to-bind UX — sheet 열어 명시적으로 키 캡처.
                        // 기존 "직전 active device 자동 사용" 의 모호함 해소.
                        bindingTargetProfile = profile
                    } label: {
                        Label("Bind keyboard…", systemImage: "keyboard.badge.ellipsis")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
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
                    debugRow("활성 키보드", value: appState.lastActiveKeyboard?.displayName ?? "-")
                    debugRow("연결된 키보드", value: "\(appState.keyboardDeviceManager.connectedKeyboards.count)개")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("연결된 키보드 디바이스") {
                if appState.keyboardDeviceManager.connectedKeyboards.isEmpty {
                    Text("감지된 키보드 없음")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.keyboardDeviceManager.connectedKeyboards, id: \.matchingKey) { device in
                            HStack {
                                Image(systemName: device.isInternal ? "laptopcomputer" : "keyboard")
                                    .foregroundStyle(.secondary)
                                Text(device.displayName)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text(device.matchingKey)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if appState.lastActiveKeyboard == device {
                                    Text("Active")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.green.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

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
