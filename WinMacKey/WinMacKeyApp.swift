import SwiftUI

@main
struct WinMacKeyApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        // Menu Bar Extra - 메뉴바에 상주
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // 현재 입력 소스에 따라 아이콘 변경
            if appState.isEngineRunning {
                Image(systemName: appState.stateManager.currentInputSource == .korean
                      ? "character.textbox"
                      : "a.square")
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
    
    // VDI (VMware Horizon 등) 호환 모드: 우측 Command를 우측 Option(Alt)으로 변환
    @AppStorage("useVdiMode") var useVdiMode: Bool = false {
        didSet {
            // 값이 변경될 때 KeyInterceptor 등에 바로 반영되로록 할 수 있음
            keyInterceptor.useVdiMode = useVdiMode
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
        // Right Cmd tap-only → 한영전환 연결
        keyInterceptor.onInputSourceToggle = { [weak self] in
            self?.stateManager.handleTrigger()
        }
        // 초기화 시 저장된 속성을 Interceptor에 전달
        keyInterceptor.useVdiMode = useVdiMode
        
        checkPermissions()
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
        contextManager.startMonitoring()
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
            }
        }
    }
    
    func toggleEngine() {
        if isEngineRunning {
            keyInterceptor.stop()
        } else {
            keyInterceptor.start()
        }
        isEngineRunning.toggle()
    }
    
    /// 모든 설정을 초기화하고 기본 상태로 되돌립니다.
    func resetAll() {
        resetService.resetAll(keyInterceptor: keyInterceptor) { [weak self] in
            DispatchQueue.main.async {
                self?.isEngineRunning = false
                self?.currentLatencyMs = 0.0
                self?.stateManager.switchCount = 0
                self?.stateManager.refreshCurrentSource()
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
