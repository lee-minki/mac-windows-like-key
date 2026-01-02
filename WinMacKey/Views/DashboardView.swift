import SwiftUI

/// SCR-03: 메인 대시보드
/// 앱별 매핑 프로필 설정 및 'The Silencer' 활성화
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var profileManager = ProfileManager()
    @State private var selectedTab = 0
    @State private var showAddProfileSheet = false
    
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
                        
                        Divider()
                        
                        Toggle(isOn: .constant(true)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable \"The Silencer\"")
                                    .font(.headline)
                                Text("Pure Caps Lock - 즉각 반응, 지연 없음")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
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
                            Button(action: { showAddProfileSheet = true }) {
                                Label("Add New App", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
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
            }
            .padding(20)
        }
    }
    
    // MARK: - Profiles Tab
    
    private var profilesTab: some View {
        VStack(spacing: 0) {
            // Profile List
            List {
                ForEach(profileManager.profiles) { profile in
                    profileRow(profile)
                }
                .onDelete(perform: profileManager.removeProfile)
            }
            .listStyle(.inset)
            
            Divider()
            
            // Add Button
            HStack {
                Spacer()
                
                Button(action: { showAddProfileSheet = true }) {
                    Label("새 프로필 추가", systemImage: "plus")
                }
                .disabled(!appState.isPro)
            }
            .padding(12)
        }
        .sheet(isPresented: $showAddProfileSheet) {
            AddProfileSheet(profileManager: profileManager)
        }
    }
    
    private func profileRow(_ profile: Profile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.headline)
                    
                    if profile.bundleId == nil {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                if let bundleId = profile.bundleId {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Mappings
                ForEach(profile.mappings) { mapping in
                    Text(mapping.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { profile.isEnabled },
                set: { newValue in
                    var updated = profile
                    updated.isEnabled = newValue
                    profileManager.updateProfile(updated)
                }
            ))
            .toggleStyle(.switch)
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
                // Open Event Viewer window
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

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @ObservedObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    
    @State private var profileName = ""
    @State private var bundleId = ""
    @State private var selectedMapping = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("새 프로필 추가")
                .font(.headline)
            
            Form {
                TextField("프로필 이름", text: $profileName)
                TextField("Bundle ID (예: com.vmware.fusion)", text: $bundleId)
                
                Picker("키 매핑", selection: $selectedMapping) {
                    Text("CapsLock → Windows IME").tag(0)
                    Text("CapsLock → Pure CapsLock").tag(1)
                }
            }
            
            HStack {
                Button("취소") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("추가") {
                    let mapping = selectedMapping == 0
                        ? KeyMapping(fromKey: KeyEvent.capsLockKeyCode, toKey: KeyEvent.windowsIMEKeyCode, description: "CapsLock → Windows IME")
                        : KeyMapping(fromKey: KeyEvent.capsLockKeyCode, toKey: KeyEvent.capsLockKeyCode, description: "CapsLock → Pure CapsLock")
                    
                    let profile = Profile(
                        name: profileName,
                        bundleId: bundleId.isEmpty ? nil : bundleId,
                        mappings: [mapping]
                    )
                    profileManager.addProfile(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
}
