import SwiftUI

/// SCR-02: 메뉴바 Popover
/// 현재 상태 확인 및 빠른 모드 전환을 제공합니다.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) private var openSettings

    private var triggerShortcutDescription: String {
        "Right Command → Control+Space (Mac) / F16 (VDI)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 - 앱 상태
            headerSection

            Divider()

            // 중복 설치 경고 (있을 때만)
            if !appState.duplicateInstallations.isEmpty {
                duplicateInstallSection
                Divider()
            }

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
        // popover 가 열릴 때마다 중복 설치를 재탐지한다. 탐지는 시작 시 1회만
        // 수행돼서, 그 사이 중복본을 지워도 경고가 stale 하게 남아 있었다
        // (mdfind background queue 라 비용 작음). 이제 매 popover open 마다 갱신 →
        // 중복이 사라지면 경고도 자동으로 사라진다.
        .onAppear {
            appState.checkForDuplicateInstallations()
        }
        // P2 / M3 — 미등록 외장 키보드 first-seen prompt.
        // appState.firstSeenKeyboardCandidate 가 non-nil 이면 sheet 표시.
        // DashboardView 도 동일 binding 으로 sheet attach (보조 — Settings 윈도우 열려 있을 때 노출).
        .sheet(item: $appState.firstSeenKeyboardCandidate) { device in
            FirstSeenKeyboardPromptView(device: device)
                .environmentObject(appState)
        }
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
            let isStale = appState.permissionService.isStaleGrantDetected

            Label(isStale ? "권한 등록이 무효화되었습니다" : "권한이 필요합니다",
                  systemImage: isStale ? "exclamationmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)

            if !appState.hasAccessibilityPermission {
                Text(isStale
                     ? "이전 버전의 권한 등록(csreq)이 남아 동작하지 않을 수 있습니다. 아래 명령으로 초기화 후 다시 허용해주세요."
                     : "손쉬운 사용 권한을 허용해주세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isStale {
                    HStack(spacing: 6) {
                        // Primary: 클립보드 복사 (안전, side effect 없음)
                        Button("명령 복사") {
                            appState.permissionService.copyTccutilCommandToClipboard()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        // Secondary: 자동 실행 — confirmation dialog 후에만 동작
                        Button("터미널에서 실행…") {
                            appState.permissionService.confirmAndRunTccutilReset()
                        }
                        .controlSize(.small)
                    }

                    Text(appState.permissionService.tccutilResetCommand)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                Group {
                    if isStale {
                        Button("손쉬운 사용 설정 열기") {
                            appState.permissionService.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("손쉬운 사용 설정 열기") {
                            appState.permissionService.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var duplicateInstallSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("WinMac Key가 \(appState.duplicateInstallations.count + 1)곳에 설치됨",
                  systemImage: "square.on.square.dashed")
                .font(.subheadline)
                .foregroundStyle(.orange)

            Text("권한·업데이트가 꼬일 수 있어 한 곳에서만 사용을 권장합니다. 다른 위치의 앱을 휴지통으로 옮기세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Finder에서 다른 위치 보기") {
                // activateFileViewerSelecting 은 파일 선택 + Finder 활성화(전면)를
                // 한 번에 보장한다. 이전 selectFile(_:inFileViewerRootedAtPath:) 는
                // LSUIElement 앱에서 Finder 를 전면으로 가져오지 못해 "반응 없음" 으로
                // 보였다 (다른 메뉴 버튼은 NSApp.activate 로 우회).
                // 탐지 후 삭제됐을 수 있어 클릭 시점에 존재 경로만 다시 거른다.
                let existing = appState.duplicateInstallations.filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                guard !existing.isEmpty else {
                    // 전부 stale → 경고 자체가 false positive. 재탐지로 정리.
                    appState.checkForDuplicateInstallations()
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting(existing)
            }
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
            // LSUIElement 앱이라 NSApp.activate 없으면 윈도우가 뒤에 숨음 (v1.3.7 fix).
            // 다른 메뉴 버튼들과 일관성 맞춤.
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "update-window")
            }) {
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

            Toggle(isOn: Binding(
                get: { appState.launchAtLoginService.isEnabled },
                set: { appState.launchAtLoginService.setEnabled($0) }
            )) {
                Label("로그인 시 자동 실행", systemImage: "power.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.checkbox)
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

// SwiftUI #Preview 는 swiftc CLI 컴파일에서 macro 확장 컨텍스트 부족으로 깨질 수 있어
// MenuBarView+Preview.swift 로 분리됨. smoke test 가 View 파일을 컴파일해도 영향 없음.
