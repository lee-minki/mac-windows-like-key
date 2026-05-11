import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 앱 종료 시 cleanup — ownership 우회 path 사용.
        // Phase D 에서 pre-existing snapshot 복원 로직 추가 예정.
        HIDRemapper.shared.internalClearAllForTermination()
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
        .defaultSize(width: 550, height: 450)
        
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
    @Published var isVdiMode: Bool = false  // VDI 앱 포커스 여부
    @Published var isTerminalMode: Bool = false
    
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
            refreshActiveProfileForCurrentContext()
        }
    }
    
    let keyInterceptor = KeyInterceptor()
    let permissionService = PermissionService()
    let contextManager = ContextManager()
    let updateService = UpdateService()
    let launchAtLoginService = LaunchAtLoginService()
    let stateManager = StateManager()
    let resetService = ResetService()
    let profileStore = KeyboardProfileStore()
    let keyboardDeviceManager = KeyboardDeviceManager()

    @Published var showResetConfirmation: Bool = false
    @Published var lastActiveKeyboard: KeyboardDeviceIdentifier?
    @Published var duplicateInstallations: [URL] = []

    @AppStorage("startEngineOnAppLaunch") var startEngineOnAppLaunch: Bool = false

    private var permissionObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// The user's default profile ID (before auto-switching overrides)
    private var defaultMappingProfileId: String?

    // MARK: - VDI Internal Keyboard Mapping
    // VDI 포커스 시 내장 키보드는 디바이스별 오버라이드로 Windows 감각 레이아웃 적용
    // 외장 키보드는 저장된 프로필이 있다면 현재 컨텍스트(Local/VDI)에 맞는 매핑으로 재적용
    private static let vdiInternalKeyboardMappings: [Int64: Int64] = [
        Int64(kVK_Function): Int64(kVK_Control),   // Fn → Ctrl
        Int64(kVK_Control): Int64(kVK_Function),   // Control → Fn
    ]
    
    init() {
        Self.sanitizeSavedWindowFrame(forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window")

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
        launchAtLoginService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        keyboardDeviceManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        stateManager.onSystemInputSourceChanged = { [weak self] in
            self?.keyInterceptor.completeInputSourceCommitWindow()
        }
        stateManager.onInputSourceToggleVerificationFailed = { [weak self] in
            self?.keyInterceptor.failInputSourceCommitWindow()
        }

        // EventTap은 메인 RunLoop에서 실행되므로 assumeIsolated 안전
        keyInterceptor.onInputSourceToggle = { [weak self] in
            MainActor.assumeIsolated {
                let isVdiMode = self?.isVdiMode == true
                let isTerminalMode = self?.isTerminalMode == true
                if isVdiMode {
                    // VDI: F16이 패스스루되어 Horizon이 직접 처리
                    // 릴레이 키 발행 불필요, 버퍼링만 시작
                    self?.keyInterceptor.beginVdiRelayCooldownWindow()
                    self?.stateManager.switchCount += 1
                } else if isTerminalMode {
                    self?.stateManager.handleTerminalTrigger()
                } else {
                    // 로컬 Mac: F16 suppress 후 Control+Space 합성
                    self?.keyInterceptor.beginInputSourceCommitWindow()
                    self?.stateManager.handleTrigger(isVdiMode: false)
                }
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

        // 다른 hidutil 도구 (Karabiner 등) 의 매핑을 보존하기 위해 앱이 HID 를 건드리기 전 snapshot 저장.
        // applicationWillTerminate / Reset / Recovery 에서 이 snapshot 으로 복원된다.
        HIDRemapper.shared.captureSystemSnapshotIfNeeded()

        updateIMETriggerRemap()
        keyInterceptor.activeProfileID = activeMappingProfileId
        refreshActiveProfileForCurrentContext()

        // 앱 전환 시: (1) bundleId 캐시 갱신 (2) VDI 앱 자동 감지 (3) 프로필 자동 전환
        keyInterceptor.cachedBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        contextManager.onAppChanged = { [weak self] bundleId, appName in
            guard let self = self else { return }
            self.keyInterceptor.cachedBundleId = bundleId.isEmpty ? nil : bundleId

            let wasVdi = self.isVdiMode
            let isNowVdi = self.contextManager.isVirtualizationApp
            let wasTerminal = self.isTerminalMode
            let isNowTerminal = self.contextManager.isTerminalApp
            self.keyInterceptor.isVdiAppFocused = isNowVdi
            self.isVdiMode = isNowVdi
            self.isTerminalMode = isNowTerminal

            if wasTerminal != isNowTerminal {
                LogService.shared.info("Terminal mode: \(isNowTerminal ? "enabled" : "disabled") (\(appName))", category: "Terminal")
            }

            // VDI 모드 전환: 내장 키보드 매핑 교체
            // 실제 매핑은 vdiInternalKeyboardMappings 정의 (Fn↔Ctrl swap) 와 일치해야 함.
            if isNowVdi && !wasVdi {
                self.switchToVdiMapping()
                LogService.shared.info("VDI mode: internal keyboard Fn↔Ctrl swap applied (\(appName))", category: "VDI")
            } else if !isNowVdi && wasVdi {
                self.switchToMacMapping()
                LogService.shared.info("Mac mode: internal keyboard override cleared (\(appName))", category: "VDI")
            }

            self.resolveActiveProfile()
        }

        // 키보드 디바이스 전환 시 프로필 자동 전환
        keyboardDeviceManager.onActiveDeviceChanged = { [weak self] device in
            guard let self = self else { return }
            self.lastActiveKeyboard = device
            self.resolveActiveProfile()
            LogService.shared.info("Active keyboard: \(device.displayName)", category: "Device")
        }

        checkPermissions()
        bootstrapPermissionPromptsIfNeeded()
        startEngineOnLaunchIfNeeded()
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
        contextManager.startMonitoring()
        keyboardDeviceManager.startMonitoring()
        checkForDuplicateInstallations()

        setupActivationObserver()

        LogService.shared.info(
            "AppState initialized (accessibility: \(hasAccessibilityPermission))",
            category: "App"
        )

        // Invariant: 앱 초기화는 절대 hidutil 시스템 상태를 건드려서는 안 됨.
        // 엔진이 명시적으로 켜질 때만 (toggleEngine → refreshActiveProfileForCurrentContext) HID 적용.
        // 이 assertion이 firing 하면 init path 어딘가에서 HIDRemapper.apply*/clear* 가 불린 것.
        #if DEBUG
        let applyCount = HIDRemapper.shared.applyCallCount
        let clearCount = HIDRemapper.shared.clearCallCount
        assert(applyCount == 0,
               "Invariant violated: HIDRemapper.applyMappings was called \(applyCount) time(s) during init")
        assert(clearCount == 0,
               "Invariant violated: HIDRemapper.clearMappings was called \(clearCount) time(s) during init")
        if applyCount > 0 || clearCount > 0 {
            LogService.shared.error(
                "Lifecycle invariant violation — init touched HID: apply=\(applyCount), clear=\(clearCount)",
                category: "App"
            )
        }
        #endif
    }
    
    func checkPermissions() {
        hasAccessibilityPermission = permissionService.checkAccessibilityPermission()
    }

    private func bootstrapPermissionPromptsIfNeeded() {
        if !hasAccessibilityPermission {
            permissionService.requestAccessibilityPermission()
            LogService.shared.warning("Bootstrap: requested Accessibility permission", category: "App")
        }
    }

    private func startEngineOnLaunchIfNeeded() {
        guard startEngineOnAppLaunch else { return }

        if hasAccessibilityPermission {
            toggleEngine()
            LogService.shared.info("Bootstrap: started engine from launch preference", category: "App")
        } else {
            LogService.shared.warning("Bootstrap: launch engine preference blocked by missing Accessibility permission", category: "App")
        }
    }
    
    private func setupPermissionObserver() {
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkPermissions()
                if self.startEngineOnAppLaunch && self.hasAccessibilityPermission && !self.isEngineRunning {
                    self.toggleEngine()
                }
            }
        }
    }

    private func setupActivationObserver() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissions()
                self?.launchAtLoginService.refreshStatus()
            }
        }
    }
    
    /// Apply a keyboard layout profile's mappings
    func applyProfile(_ profile: SavedKeyboardProfile) {
        activeMappingProfileId = profile.id.uuidString
    }

    func persistCustomMappings(_ mappings: [Int64: Int64]) {
        let stringKeyDict = Dictionary(uniqueKeysWithValues: mappings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: "visualCustomMappings")
        }
    }

    // MARK: - Unified Profile Resolution
    // 모든 키보드: 디바이스 프로필 > 앱 프로필 > 기본 프로필

    private func resolveActiveProfile() {
        // 1. 키보드 디바이스 기반 프로필 (최우선)
        if let device = lastActiveKeyboard,
           let deviceProfile = profileStore.profile(forDevice: device) {
            if defaultMappingProfileId == nil {
                defaultMappingProfileId = activeMappingProfileId
            }
            applyProfile(deviceProfile)
            refreshActiveProfileForCurrentContext()
            return
        }

        // 2. 앱 기반 프로필
        let bundleId = contextManager.currentBundleId
        if let appProfile = profileStore.profile(forBundleId: bundleId) {
            if defaultMappingProfileId == nil {
                defaultMappingProfileId = activeMappingProfileId
            }
            applyProfile(appProfile)
            refreshActiveProfileForCurrentContext()
            return
        }

        // 3. 기본 프로필 복원 (내장 키보드로 돌아왔거나 매칭 없음)
        if let defaultId = defaultMappingProfileId {
            defaultMappingProfileId = nil
            activeMappingProfileId = defaultId
        }
        refreshActiveProfileForCurrentContext()
    }

    func refreshActiveProfileForCurrentContext() {
        // Caps Lock은 앱이 건드리지 않음 — VDI/로컬 모두 시스템에 위임
        keyInterceptor.activeProfileID = activeMappingProfileId

        guard isEngineRunning else {
            return
        }

        if let activeProfile = profileStore.profile(idString: activeMappingProfileId) {
            let context: KeyboardUsageContext = isVdiMode ? .vdi : .localMac
            let mappings = activeProfile.mappings(for: context)
            persistCustomMappings(mappings)
            keyInterceptor.applyCustomMappings(mappings)
            return
        }

        keyInterceptor.setupDefaultMappings()
    }

    // MARK: - IME Trigger HID Remap

    /// F16은 VDI에서 패스스루되어 Horizon이 Right Alt로 직접 변환합니다.
    /// HIDRemapper에 imeTriggerMapping을 등록하면 다음 applyMappings 호출 시 자동 포함됩니다.
    private func updateIMETriggerRemap() {
        let physicalKeyCode = Int64(kVK_RightCommand)
        HIDRemapper.shared.imeTriggerMapping = (src: physicalKeyCode, dst: Int64(kVK_F16))
        LogService.shared.info(
            "IME trigger remap: rightCmd (0x\(String(physicalKeyCode, radix: 16))) → F16",
            category: "HID"
        )
    }

    // MARK: - VDI / Mac Mapping Switch

    /// VDI 모드: 내장 키보드는 Windows 감각 레이아웃으로 교체하고, 외장 프로필도 VDI 컨텍스트로 재적용
    func switchToVdiMapping() {
        guard isEngineRunning else { return }
        HIDRemapper.shared.applyMappingsForInternalKeyboardSync(Self.vdiInternalKeyboardMappings)
        refreshActiveProfileForCurrentContext()
    }

    /// Mac 모드: 내장 키보드의 VDI 오버라이드를 해제하고 글로벌 매핑을 재적용
    func switchToMacMapping() {
        guard isEngineRunning else { return }
        HIDRemapper.shared.clearMappingsForInternalKeyboardSync()
        refreshActiveProfileForCurrentContext()
    }

    func toggleEngine() {
        if isEngineRunning {
            // 엔진 OFF: HID ownership 해제 전에 매핑 정리.
            // stop() → clearMappingsSync() 가 ownership 게이트를 통과해야 하므로 release 는 그 뒤.
            keyInterceptor.stop()
            HIDRemapper.shared.releaseOwnership()
            isEngineRunning = false
            LogService.shared.info("Engine stopped", category: "Engine")
        } else {
            checkPermissions()
            guard hasAccessibilityPermission else {
                permissionService.requestAccessibilityPermission()
                LogService.shared.warning("Engine start blocked: Accessibility permission missing", category: "Engine")
                return
            }

            // 엔진 ON: HID ownership 획득 후 EventTap 켜고 매핑 적용.
            HIDRemapper.shared.takeOwnership()
            let started = keyInterceptor.start()
            isEngineRunning = started
            if started {
                // HID 매핑 적용 — stop 시 clearMappingsSync 로 해제됐으므로 재적용
                refreshActiveProfileForCurrentContext()
                LogService.shared.info("Engine started", category: "Engine")
            } else {
                // start 실패 시 ownership 도로 반환
                HIDRemapper.shared.releaseOwnership()
                LogService.shared.error("Engine failed to start", category: "Engine")
            }
        }
    }
    
    /// 모든 설정을 초기화하고 기본 상태로 되돌립니다.
    func resetAll() {
        LogService.shared.warning("Reset all triggered", category: "App")
        resetService.resetAll(keyInterceptor: keyInterceptor, keyboardDeviceManager: keyboardDeviceManager) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isEngineRunning = false
                self.currentLatencyMs = 0.0
                self.stateManager.switchCount = 0
                self.stateManager.refreshCurrentSource()
                self.launchAtLoginService.unregisterForReset()

                // ResetService.resetAll 이 keyboardDeviceManager.stopMonitoring 을 호출하므로
                // 디바이스 자동 전환·VDI 컨텍스트 감지가 죽은 상태. 재시작해 앱 lifecycle 의 정상 상태로 복귀.
                self.keyboardDeviceManager.startMonitoring()
                self.lastActiveKeyboard = nil

                LogService.shared.info("Reset completed (monitoring restarted)", category: "App")
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
        keyboardDeviceManager.stopMonitoring()
        if let observer = permissionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Duplicate Installation Detection

    /// mdfind로 동일 bundle ID를 가진 모든 .app 위치를 찾고,
    /// 표준 설치 위치(/Applications)가 아닌 추가 인스턴스가 있으면 사용자에게 알림.
    /// build/DerivedData, /Volumes(마운트된 DMG), 휴지통 등은 제외.
    func checkForDuplicateInstallations() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL

        DispatchQueue.global(qos: .utility).async {
            let allInstalls = Self.findAllInstallations(bundleID: bundleID)
            let others = allInstalls.filter { $0 != currentURL }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.duplicateInstallations = others
                if !others.isEmpty {
                    let pathList = others.map(\.path).joined(separator: ", ")
                    LogService.shared.warning(
                        "Duplicate installations detected: \(pathList)",
                        category: "Install"
                    )
                }
            }
        }
    }

    /// `@MainActor` 격리에서 벗어나 background queue 에서 직접 호출 가능하게 한다.
    /// 본 함수는 외부 프로세스(`mdfind`) 호출과 파일시스템 read-only 조회만 수행하므로 isolation 불필요.
    nonisolated private static func findAllInstallations(bundleID: String) -> [URL] {
        let task = Process()
        task.launchPath = "/usr/bin/mdfind"
        task.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return [] }
            let fm = FileManager.default

            return output.split(whereSeparator: \.isNewline)
                .compactMap { line -> URL? in
                    let path = String(line)
                    // 빌드 산출물 / 휴지통 / 마운트된 DMG / 임시 경로 제외
                    let excluded = [
                        "/build/", "/DerivedData/", "/Caches/",
                        "/.Trashes/", "/.Trash/",
                        "/Volumes/", "/private/var/folders/",
                        "/tmp/", "/private/tmp/",
                        "/Backups.backupdb/"
                    ]
                    if excluded.contains(where: { path.contains($0) }) { return nil }
                    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
                    return fm.fileExists(atPath: url.path) ? url : nil
                }
        } catch {
            return []
        }
    }

    private static func sanitizeSavedWindowFrame(forKey key: String) {
        guard let rawFrame = UserDefaults.standard.string(forKey: key),
              let frame = parseSavedWindowFrame(rawFrame) else {
            return
        }

        let isVisible = NSScreen.screens
            .map(\.visibleFrame)
            .contains { $0.intersects(frame) }

        if !isVisible {
            UserDefaults.standard.removeObject(forKey: key)
            LogService.shared.info("Removed off-screen saved window frame for \(key)", category: "UI")
        }
    }

    private static func parseSavedWindowFrame(_ value: String) -> CGRect? {
        let numbers = value
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }

        guard numbers.count >= 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}
