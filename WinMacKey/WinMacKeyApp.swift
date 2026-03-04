import SwiftUI
import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 앱 종료 시 HID 매핑 해제 (동기 — 프로세스 종료 전 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
    }
}

@main
struct WinMacKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        // Menu Bar Extra - 메뉴바에 상주
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // 현재 입력 소스에 따라 아이콘 변경
            if appState.isEngineRunning {
                Image(systemName: appState.stateManager.isSource1Active
                      ? "a.square"
                      : "character.textbox")
            } else {
                Image(systemName: "keyboard")
            }
        }
        .menuBarExtraStyle(.window)
        
        // Settings Window
        Settings {
            DashboardView()
                .environmentObject(appState)
        }
        
        // Event Viewer Window
        Window("Event Viewer", id: "event-viewer") {
            EventViewerView()
                .environmentObject(appState)
        }
        .defaultSize(width: 700, height: 500)
        
        // Update Window
        Window("소프트웨어 업데이트", id: "update-window") {
            UpdateView()
        }
        .defaultSize(width: 400, height: 350)
        .windowResizability(.contentSize)
        
        // Help Window
        Window("도움말", id: "help-window") {
            HelpView()
        }
        .defaultSize(width: 620, height: 520)
        
        // Doctor Window
        Window("Doctor", id: "doctor-window") {
            DoctorView()
                .environmentObject(appState)
        }
        .defaultSize(width: 560, height: 480)
        
        // Log Viewer Window
        Window("로그 뷰어", id: "log-window") {
            LogView()
        }
        .defaultSize(width: 700, height: 450)
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isEngineRunning: Bool = false
    @Published var currentLatencyMs: Double = 0.0
    @Published var currentAppBundleId: String = ""
    @Published var currentProfile: Profile?
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isPro: Bool = false  // Pro 버전 활성화 여부
    
    // VDI 앱 자동 감지 모드 (수동 토글 대신 ContextManager가 자동 처리)
    // 레거시 호환을 위해 AppStorage 키는 유지하되, 실제로는 ContextManager가 자동 갱신
    @AppStorage("useVdiMode") var useVdiMode: Bool = false
    
    // 한영 전환 트리거 키 선택: "rightCmd" 또는 "rightOpt"
    @AppStorage("toggleTriggerKey") var toggleTriggerKey: String = "rightCmd" {
        didSet {
            keyInterceptor.triggerKeyCode = (toggleTriggerKey == "rightOpt")
                ? Int64(kVK_RightOption)
                : Int64(kVK_RightCommand)
        }
    }
    
    // 언어 페어 설정 (Source 1 ↔ Source 2 토글)
    @AppStorage("languagePairSource1") var languagePairSource1: String = "" {
        didSet { stateManager.configurePair(source1: languagePairSource1, source2: languagePairSource2) }
    }
    @AppStorage("languagePairSource2") var languagePairSource2: String = "" {
        didSet { stateManager.configurePair(source1: languagePairSource1, source2: languagePairSource2) }
    }
    
    // 키보드 매핑 프로파일 ID
    @AppStorage("activeMappingProfileId") var activeMappingProfileId: String = "standardMac" {
        didSet {
            keyInterceptor.activeProfileID = activeMappingProfileId
            keyInterceptor.setupDefaultMappings()
        }
    }
    
    let keyInterceptor = KeyInterceptor()
    let permissionService = PermissionService()
    let contextManager = ContextManager()
    let updateService = UpdateService()
    let stateManager = StateManager()
    let resetService = ResetService()
    
    @Published var showResetConfirmation: Bool = false
    
    private var permissionObserver: NSObjectProtocol?
    
    init() {
        // Right Cmd/Opt 즉시 전환 → 한영전환 연결
        keyInterceptor.onInputSourceToggle = { [weak self] in
            self?.stateManager.handleTrigger()
        }
        
        // 언어 페어 초기화: 저장된 값이 없으면 자동 감지
        if languagePairSource1.isEmpty || languagePairSource2.isEmpty {
            if let detected = stateManager.inputSourceManager.autoDetectPair() {
                languagePairSource1 = detected.source1
                languagePairSource2 = detected.source2
            }
        }
        stateManager.configurePair(source1: languagePairSource1, source2: languagePairSource2)
        
        // 트리거 키 설정
        keyInterceptor.triggerKeyCode = (toggleTriggerKey == "rightOpt")
            ? Int64(kVK_RightOption)
            : Int64(kVK_RightCommand)
        keyInterceptor.activeProfileID = activeMappingProfileId
        keyInterceptor.setupDefaultMappings()
        
        // 앱 전환 시: (1) bundleId 캐시 갱신 (2) VDI 앱 자동 감지
        keyInterceptor.cachedBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        contextManager.onAppChanged = { [weak self] bundleId, _ in
            self?.keyInterceptor.cachedBundleId = bundleId.isEmpty ? nil : bundleId
            // VDI 앱 포커스 여부 자동 갱신
            self?.keyInterceptor.isVdiAppFocused = self?.contextManager.isVirtualizationApp ?? false
        }

        checkPermissions()
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
        contextManager.startMonitoring()
        
        LogService.shared.info("AppState initialized", category: "App")
        LogService.shared.info("Accessibility: \(hasAccessibilityPermission)", category: "App")
    }
    
    func checkPermissions() {
        hasAccessibilityPermission = permissionService.checkAccessibilityPermission()
    }
    
    private func setupPermissionObserver() {
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hasAccessibilityPermission = true
                if self?.isEngineRunning == false {
                    self?.toggleEngine()
                }
            }
        }
    }
    
    func toggleEngine() {
        if isEngineRunning {
            keyInterceptor.stop()
            LogService.shared.info("Engine stopped", category: "Engine")
        } else {
            keyInterceptor.start()
            LogService.shared.info("Engine started", category: "Engine")
        }
        isEngineRunning.toggle()
    }
    
    /// 모든 설정을 초기화하고 기본 상태로 되돌립니다.
    func resetAll() {
        LogService.shared.warning("Reset all triggered", category: "App")
        resetService.resetAll(keyInterceptor: keyInterceptor) { [weak self] in
            DispatchQueue.main.async {
                self?.isEngineRunning = false
                self?.currentLatencyMs = 0.0
                self?.stateManager.switchCount = 0
                self?.stateManager.refreshCurrentSource()
                LogService.shared.info("Reset completed", category: "App")
            }
        }
    }
    
    private func checkForUpdatesOnLaunch() {
        if updateService.autoCheckEnabled {
            Task {
                await updateService.checkForUpdates()
            }
        }
    }
    
    deinit {
        contextManager.stopMonitoring()
        if let observer = permissionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
