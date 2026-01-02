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
            Image(systemName: appState.isEngineRunning ? "keyboard.fill" : "keyboard")
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
    
    let keyInterceptor = KeyInterceptor()
    let permissionService = PermissionService()
    let contextManager = ContextManager()
    let updateService = UpdateService()
    
    private var permissionObserver: NSObjectProtocol?
    
    init() {
        checkPermissions()
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
    }
    
    func checkPermissions() {
        hasAccessibilityPermission = permissionService.checkAccessibilityPermission()
    }
    
    private func setupPermissionObserver() {
        // 권한 변경 알림 수신
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hasAccessibilityPermission = true
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
    
    /// 앱 실행 시 업데이트 체크 (자동 체크가 활성화된 경우)
    private func checkForUpdatesOnLaunch() {
        if updateService.autoCheckEnabled {
            Task {
                await updateService.checkForUpdates()
            }
        }
    }
    
    deinit {
        if let observer = permissionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
