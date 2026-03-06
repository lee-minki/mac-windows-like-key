import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 앱 종료 시 HID 매핑 해제 (동기 — 프로세스 종료 전 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
        // 가상 HID 헬퍼 종료
        VirtualHIDManager.appShared?.stop()
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
            // WM 브랜드 아이콘
            // VDI 모드: W/한, W/A  |  Mac 모드: M/한, M/A  |  OFF: WM
            if appState.isEngineRunning {
                let prefix = appState.isVdiMode ? "W" : "M"
                let lang = appState.stateManager.isSource1Active ? "A" : "한"
                Text("\(prefix)/\(lang)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } else {
                Text("WM")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
    @Published var currentProfileId: String?
    @Published var hasAccessibilityPermission: Bool = false
    @Published var isPro: Bool = false  // Pro 버전 활성화 여부
    @Published var isVdiMode: Bool = false  // VDI 앱 포커스 여부 (메뉴바 아이콘용)
    
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
    let virtualHIDManager = VirtualHIDManager()
    let profileStore = KeyboardProfileStore()

    @Published var showResetConfirmation: Bool = false

    private var permissionObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// The user's default profile ID (before auto-switching overrides)
    private var defaultMappingProfileId: String?
    
    init() {
        // Forward profileStore changes so views observing AppState re-render
        profileStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Right Cmd/Opt 즉시 전환 → 한영전환 연결
        // EventTap은 메인 RunLoop에서 실행되므로 assumeIsolated 안전
        keyInterceptor.onInputSourceToggle = { [weak self] in
            MainActor.assumeIsolated {
                self?.stateManager.handleTrigger()
            }
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

        // 앱 전환 시: (1) bundleId 캐시 갱신 (2) VDI 앱 자동 감지 (3) 프로필 자동 전환
        keyInterceptor.cachedBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        contextManager.onAppChanged = { [weak self] bundleId, _ in
            guard let self = self else { return }
            self.keyInterceptor.cachedBundleId = bundleId.isEmpty ? nil : bundleId
            self.keyInterceptor.isVdiAppFocused = self.contextManager.isVirtualizationApp
            self.isVdiMode = self.contextManager.isVirtualizationApp

            // Auto-switch profile if a matching per-app profile exists
            if let appProfile = self.profileStore.profile(forBundleId: bundleId) {
                if self.defaultMappingProfileId == nil {
                    self.defaultMappingProfileId = self.activeMappingProfileId
                }
                self.applyProfile(appProfile)
            } else if let defaultId = self.defaultMappingProfileId {
                // Revert to user's default profile
                self.defaultMappingProfileId = nil
                self.activeMappingProfileId = defaultId
                self.keyInterceptor.setupDefaultMappings()
            }
        }

        // VirtualHIDManager ↔ KeyInterceptor 연결
        keyInterceptor.virtualHIDManager = virtualHIDManager
        VirtualHIDManager.appShared = virtualHIDManager

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
    
    /// Apply a keyboard layout profile's mappings
    func applyProfile(_ profile: SavedKeyboardProfile) {
        let mappings = profile.mappings
        let stringKeyDict = Dictionary(uniqueKeysWithValues: mappings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: "visualCustomMappings")
        }
        activeMappingProfileId = profile.id.uuidString
        keyInterceptor.applyCustomMappings(mappings)
    }

    func toggleEngine() {
        if isEngineRunning {
            keyInterceptor.stop()
            virtualHIDManager.stop()
            LogService.shared.info("Engine stopped", category: "Engine")
        } else {
            keyInterceptor.start()
            // Karabiner 드라이버가 설치되어 있으면 VirtualHID도 시작
            if VirtualHIDManager.isDriverInstalled() {
                virtualHIDManager.start()
            } else {
                LogService.shared.info("Karabiner driver not installed, virtual HID skipped", category: "Engine")
            }
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
