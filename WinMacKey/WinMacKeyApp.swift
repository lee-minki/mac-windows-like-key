import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 앱 종료 시 모든 HID 매핑 해제 — 글로벌 + 내장 키보드 디바이스별 (동기)
        HIDRemapper.shared.clearAllMappingsSync()
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
            if appState.isEngineRunning {
                Text("WM")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } else {
                Text("wm")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
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
                .environmentObject(appState)
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
    @Published var isVdiMode: Bool = false  // VDI 앱 포커스 여부
    
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
    let profileStore = KeyboardProfileStore()

    @Published var showResetConfirmation: Bool = false

    private var permissionObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// The user's default profile ID (before auto-switching overrides)
    private var defaultMappingProfileId: String?

    // MARK: - VDI Internal Keyboard Mapping
    // VDI 포커스 시 내장 키보드만 Windows 감각의 좌측 modifier 레이아웃으로 교체
    // 외장 키보드는 글로벌 매핑 그대로 유지
    private static let vdiInternalKeyboardMappings: [Int64: Int64] = [
        Int64(kVK_Function): Int64(kVK_Control),   // Fn → Ctrl
        Int64(kVK_Control): Int64(kVK_Function),   // Control → Fn
        Int64(kVK_Option): Int64(kVK_Command),     // Option → Windows key
        Int64(kVK_Command): Int64(kVK_Option),     // Command → Alt
    ]
    
    init() {
        // Forward child ObservableObject changes so views observing AppState re-render
        profileStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        stateManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        updateService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        stateManager.onSystemInputSourceChanged = { [weak self] in
            self?.keyInterceptor.completeInputSourceCommitWindow()
        }

        // Right Cmd/Opt 즉시 전환 → 한영전환 연결
        // EventTap은 메인 RunLoop에서 실행되므로 assumeIsolated 안전
        keyInterceptor.onInputSourceToggle = { [weak self] in
            MainActor.assumeIsolated {
                let isVdiMode = self?.isVdiMode == true
                if !isVdiMode {
                    self?.keyInterceptor.beginInputSourceCommitWindow()
                }
                self?.stateManager.handleTrigger(isVdiMode: isVdiMode)
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
        contextManager.onAppChanged = { [weak self] bundleId, appName in
            guard let self = self else { return }
            self.keyInterceptor.cachedBundleId = bundleId.isEmpty ? nil : bundleId

            let wasVdi = self.isVdiMode
            let isNowVdi = self.contextManager.isVirtualizationApp
            self.keyInterceptor.isVdiAppFocused = isNowVdi
            self.isVdiMode = isNowVdi

            // VDI 모드 전환: 내장 키보드 매핑 교체
            if isNowVdi && !wasVdi {
                self.switchToVdiMapping()
                LogService.shared.info("VDI mode: internal keyboard → Fn=Ctrl, Option=Win, Command=Alt (\(appName))", category: "VDI")
            } else if !isNowVdi && wasVdi {
                self.switchToMacMapping()
                LogService.shared.info("Mac mode: internal keyboard override cleared (\(appName))", category: "VDI")
            }

            // Auto-switch profile if a matching per-app profile exists
            if let appProfile = self.profileStore.profile(forBundleId: bundleId) {
                if self.defaultMappingProfileId == nil {
                    self.defaultMappingProfileId = self.activeMappingProfileId
                }
                self.applyProfile(appProfile)
            } else if let defaultId = self.defaultMappingProfileId {
                self.defaultMappingProfileId = nil
                self.activeMappingProfileId = defaultId
                self.keyInterceptor.setupDefaultMappings()
            }
        }

        checkPermissions()
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
        contextManager.startMonitoring()

        LogService.shared.info("AppState initialized (accessibility: \(hasAccessibilityPermission))", category: "App")
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

    // MARK: - VDI / Mac Mapping Switch

    /// VDI 모드: 내장 키보드만 Windows 감각 레이아웃으로 교체 (외장 키보드는 글로벌 매핑 유지)
    func switchToVdiMapping() {
        HIDRemapper.shared.applyMappingsForInternalKeyboardSync(Self.vdiInternalKeyboardMappings)
    }

    /// Mac 모드: 내장 키보드의 VDI 오버라이드를 해제하고 글로벌 매핑을 재적용
    func switchToMacMapping() {
        HIDRemapper.shared.clearMappingsForInternalKeyboardSync()
        // 글로벌 매핑 재적용 (프로필 기반)
        keyInterceptor.setupDefaultMappings()
    }

    func toggleEngine() {
        if isEngineRunning {
            keyInterceptor.stop()
            isEngineRunning = false
            LogService.shared.info("Engine stopped", category: "Engine")
        } else {
            let started = keyInterceptor.start()
            isEngineRunning = started
            if started {
                LogService.shared.info("Engine started", category: "Engine")
            } else {
                LogService.shared.error("Engine failed to start", category: "Engine")
            }
        }
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
