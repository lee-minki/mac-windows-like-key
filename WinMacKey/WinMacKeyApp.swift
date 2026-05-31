import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // DMG/다운로드에서 실행됐으면 응용 프로그램 폴더로 이동 제안 (v1.5.0)
        ApplicationMover.offerMoveToApplicationsIfNeeded()
    }

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
            // 라벨은 항상 mount 되어 있으므로, 글로벌 단축키가 사용할
            // openWindow capture point 로도 함께 활용.
            MenuBarLabelView()
                .environmentObject(appState)
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

        // 설정 점검 Window (v1.4.1) — 첫 실행 / 권한·환경 점검 패널
        Window("설정 점검", id: "setup-window") {
            SetupCheckView()
                .environmentObject(appState)
        }
        .defaultSize(width: 500, height: 440)
        .windowResizability(.contentSize)

        // 첫 실행 환영/라이선스 Window (v1.4.2)
        Window("WinMac Key 시작하기", id: "firstrun-window") {
            FirstRunView()
                .environmentObject(appState)
        }
        .defaultSize(width: 500, height: 440)
        .windowResizability(.contentSize)
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
    @Published var isVdiMode: Bool = false  // VDI 앱 포커스 여부 (Windows VDI)
    @Published var isTerminalMode: Bool = false
    @Published var isRemoteMacMode: Bool = false  // Mac 원격접속 앱 포커스 (Screen Sharing 등)
    
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
    let globalHotKeyService = GlobalHotKeyService()

    /// MenuBarLabelView 가 SwiftUI 의 `openWindow` 를 capture 해 세팅한다.
    /// 글로벌 단축키 콜백에서 호출되어 메뉴바 우회로 Doctor 윈도우를 연다.
    var doctorWindowOpener: (() -> Void)?

    /// 설정 점검 패널(SetupCheckView)을 여는 opener. MenuBarLabelView 가 capture.
    var setupWindowOpener: (() -> Void)?
    /// 첫 실행 환영/라이선스 패널(FirstRunView)을 여는 opener.
    var firstRunWindowOpener: (() -> Void)?
    private var didRunLaunchSetupCheck = false

    /// 첫 실행 환영/라이선스 동의 완료 여부 (1회).
    @AppStorage("hasCompletedFirstRunOnboarding") var hasCompletedFirstRun: Bool = false

    /// 런치 시 1회 온보딩:
    ///   - 첫 실행이면 환영/라이선스 패널을 띄운다.
    ///   - 이후엔 권한/환경 이슈가 있을 때만 설정 점검 패널을 띄운다.
    /// (init 중 권한 프롬프트는 LSUIElement 앱에서 표시되지 않으므로 실행 후 패널로 안내)
    func runLaunchSetupCheckIfNeeded() {
        guard !didRunLaunchSetupCheck else { return }
        didRunLaunchSetupCheck = true

        if !hasCompletedFirstRun {
            firstRunWindowOpener?()
            NSApp.activate(ignoringOtherApps: true)
            LogService.shared.info("Launch onboarding: showing first-run welcome", category: "App")
            return
        }

        let issues = SetupCheckService.detectIssues(using: permissionService)
        // 이슈가 있거나(권한·설정) 프로필이 0개면(엔진 못 켬) 설정 점검 패널로 안내한다.
        guard !issues.isEmpty || profileStore.profiles.isEmpty else { return }
        setupWindowOpener?()
        NSApp.activate(ignoringOtherApps: true)
        LogService.shared.info("Launch setup check: \(issues.count) issue(s), profiles=\(profileStore.profiles.count) — opened setup panel", category: "App")
    }

    @Published var showResetConfirmation: Bool = false
    @Published var lastActiveKeyboard: KeyboardDeviceIdentifier?
    @Published var duplicateInstallations: [URL] = []

    /// P2 — 미등록 외장 키보드가 처음 입력을 보낸 직후 set 된다.
    /// M3 의 first-seen sheet 가 이 값을 watch 해 prompt 띄움.
    /// sheet 가 닫히면 nil 로 reset.
    @Published var firstSeenKeyboardCandidate: KeyboardDeviceIdentifier?

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
                    // VDI: F16이 패스스루되어 Horizon이 직접 처리.
                    // 로컬 합성 안 함 (로컬 입력소스 부작용 방지).
                    self?.keyInterceptor.beginVdiRelayCooldownWindow()
                    self?.stateManager.switchCount += 1
                } else if isTerminalMode {
                    self?.stateManager.handleTerminalTrigger()
                } else {
                    // 로컬 Mac / Mac 원격 (Screen Sharing 등) / 그 외:
                    // F16 suppress 후 로컬 macOS 에 Control+Space 합성 → 로컬 입력소스 토글.
                    // Mac 원격의 경우 Screen Sharing 이 변환된 character 를 forward 하므로 충분.
                    // (참고: isRemoteMacMode 는 진단·로깅용으로 유지되지만 동작 분기에는 미사용)
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
            let wasRemoteMac = self.isRemoteMacMode
            let isNowRemoteMac = self.contextManager.isRemoteMacApp
            self.keyInterceptor.isVdiAppFocused = isNowVdi
            self.keyInterceptor.isTerminalAppFocused = isNowTerminal  // P10 fix (v1.6.1): 터미널 focus 동기화 — commit window/buffer 비활성화 가드용
            self.keyInterceptor.isRemoteMacAppFocused = isNowRemoteMac
            self.isVdiMode = isNowVdi
            self.isTerminalMode = isNowTerminal
            self.isRemoteMacMode = isNowRemoteMac

            if wasTerminal != isNowTerminal {
                LogService.shared.info("Terminal mode: \(isNowTerminal ? "enabled" : "disabled") (\(appName))", category: "Terminal")
            }
            if wasRemoteMac != isNowRemoteMac {
                LogService.shared.info("Remote Mac mode: \(isNowRemoteMac ? "enabled — F16 will pass through to remote Mac" : "disabled") (\(appName))", category: "RemoteMac")
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

        // P2 — 키보드 디바이스 전환. 정책:
        //   - ignored 디바이스: 무시 (자동 전환 / prompt 둘 다 X)
        //   - 외장 → 내장: 자동 전환 OK (안전 fallback)
        //   - 외장 → 외장: 자동 전환 X — 마지막 활성 프로필 유지, 미등록이면 prompt
        //   - 첫 디바이스: bound 면 적용, 아니면 prompt
        //   - 동일 디바이스 (재방문): no-op
        keyboardDeviceManager.onActiveDeviceChanged = { [weak self] device in
            guard let self = self else { return }
            self.handleActiveDeviceChanged(device)
        }

        checkPermissions()
        // 권한 프롬프트는 init 에서 호출하지 않는다 — LSUIElement 앱은 실행 완료 전
        // AXIsProcessTrustedWithOptions 프롬프트가 표시되지 않아 신규 사용자가 조용히 막혔다.
        // 대신 런치 후 MenuBarLabelView.onAppear 에서 runLaunchSetupCheckIfNeeded() 가
        // 설정 점검 패널을 띄워 권한·환경 이슈를 안내한다 (v1.4.1).
        // 엔진 자동 시작은 init 완료 후로 defer.
        // toggleEngine → refreshActiveProfileForCurrentContext → applyMappings 가
        // init 중 HID 를 건드리면 lifecycle invariant (init 은 HID 비간섭) 위반.
        // DEBUG 빌드에서는 line ~290 의 assertion 이 crash 를 유발한다.
        // 권한이 이미 있고 startEngineOnAppLaunch 가 켜진 상태에서 재실행 시 재현.
        DispatchQueue.main.async { [weak self] in
            self?.startEngineOnLaunchIfNeeded()
        }
        checkForUpdatesOnLaunch()
        setupPermissionObserver()
        contextManager.startMonitoring()
        // IOHIDManager 는 입력 모니터링 권한이 있을 때만 연다 — 없으면 첫 실행 환영 *전*에
        // 권한 프롬프트가 떠 순서가 깨지므로. 권한 부여는 설정 점검 패널의 명시 버튼에서만.
        beginKeyboardMonitoringIfPermitted()
        checkForDuplicateInstallations()

        // 글로벌 단축키 (Cmd+Shift+Opt+D) → Doctor 윈도우.
        // 메뉴바 popover 가 stuck 됐을 때의 우회 진입.
        globalHotKeyService.onTriggered = { [weak self] in
            self?.doctorWindowOpener?()
        }
        globalHotKeyService.register()

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
            // Task closure 가 Sendable 이라 outer [weak self] 만으로는 캡처가 안전하지 않음.
            // Task 에 명시적 [weak self] 를 다시 주어 Swift strict concurrency 통과.
            Task { @MainActor [weak self] in
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
            Task { @MainActor [weak self] in
                self?.checkPermissions()
                self?.launchAtLoginService.refreshStatus()
            }
        }
    }
    
    /// Apply a keyboard layout profile's mappings
    func applyProfile(_ profile: SavedKeyboardProfile) {
        activeMappingProfileId = profile.id.uuidString
    }

    /// 프로필 삭제 안전 처리 — active 프로필 삭제 시 `activeMappingProfileId` 를
    /// `"standardMac"` 으로 리셋하고 custom HID 매핑을 비운다.
    /// 두 진입점(`DashboardView.profileRow`, `ModifierLayoutView.profileRow`)이
    /// 같은 invariant 를 공유하도록 service 메서드로 추출.
    /// (예전엔 `DashboardView` 콜백에 인라인 — 새 UI 추가 시 누락되는 구조적 결함.)
    func deleteProfileSafely(_ profile: SavedKeyboardProfile) {
        let wasActive = (activeMappingProfileId == profile.id.uuidString)
        profileStore.delete(id: profile.id)
        if wasActive {
            activeMappingProfileId = "standardMac"
            keyInterceptor.applyCustomMappings([:])
        }
    }

    func persistCustomMappings(_ mappings: [Int64: Int64]) {
        let stringKeyDict = Dictionary(uniqueKeysWithValues: mappings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: "visualCustomMappings")
        }
    }

    // MARK: - P2 Device-Change Policy

    /// 키보드 active 디바이스가 바뀌었을 때 호출. P2 plan §3.1 의사코드.
    /// resolveActiveProfile 호출 여부를 좁혀서 사용자 합의된 시나리오만 자동 전환.
    private func handleActiveDeviceChanged(_ newDevice: KeyboardDeviceIdentifier) {
        let prevDevice = lastActiveKeyboard
        lastActiveKeyboard = newDevice
        LogService.shared.info("Active keyboard: \(newDevice.displayName)", category: "Device")

        // Ignored 디바이스: 자동 전환 / prompt 모두 차단.
        if profileStore.isIgnored(newDevice) {
            LogService.shared.info(
                "Active keyboard ignored by user policy: \(newDevice.displayName)",
                category: "Device"
            )
            return
        }

        if newDevice.isInternal {
            // 외장 → 내장 (또는 첫 디바이스가 내장): 안전 fallback 자동 전환 OK.
            // 내장 → 내장 (같은 디바이스) 은 의미 없지만, 시스템이 그렇게 보고하면 일관성 유지를 위해 허용.
            let cameFromExternal = (prevDevice?.isInternal == false)
            if prevDevice == nil || cameFromExternal {
                resolveActiveProfile()
            }
            return
        }

        // newDevice 가 외장.
        let hasBoundProfile = profileStore.profile(forDevice: newDevice) != nil

        if prevDevice == nil {
            // 첫 디바이스. bound 면 적용, 아니면 prompt.
            if hasBoundProfile {
                resolveActiveProfile()
            } else {
                firstSeenKeyboardCandidate = newDevice
            }
            return
        }

        if prevDevice == newDevice {
            // 동일 디바이스 재방문. no-op.
            return
        }

        // 외장 → 외장 swap.
        //   - 사용자 합의: 자동 전환 안 함 (마지막 활성 프로필 유지)
        //   - 미등록 디바이스면 prompt
        if !hasBoundProfile {
            firstSeenKeyboardCandidate = newDevice
        }
        // bound 라도 자동 전환 X — 메뉴에서 사용자 명시 선택.
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
            // 엔진 OFF lifecycle:
            //   1. keyInterceptor.stop(clearHIDMappings: false) — EventTap 만 정지, HID 는 아래에서 명시 처리
            //   2. restorePreExistingMappingsAndClearInternal — snapshot 복원 + internal keyboard cleanup
            //   3. releaseOwnership — 게이트 닫기
            // HIGH 1·2 fix: 단순 clear 가 아니라 사전 상태 복원 + VDI internal mapping 도 정리.
            keyInterceptor.stop(clearHIDMappings: false)
            HIDRemapper.shared.restorePreExistingMappingsAndClearInternal()
            HIDRemapper.shared.releaseOwnership()
            isEngineRunning = false
            LogService.shared.info("Engine stopped (snapshot restored, internal cleared)", category: "Engine")
        } else {
            checkPermissions()
            guard hasAccessibilityPermission else {
                permissionService.requestAccessibilityPermission()
                LogService.shared.warning("Engine start blocked: Accessibility permission missing", category: "Engine")
                return
            }

            // 프로필 게이트: 저장된 프로필이 하나도 없으면 엔진을 켜지 않는다.
            // "엔진 ON = 윈맥키 전 기능 동작" 인지 모델 — 설정+프로필을 먼저 끝내야 켤 수 있음.
            // 한/영만 쓰려는 사용자는 설정 점검 패널의 "한/영 전환만 빠른 시작" 으로 프로필 1개 생성.
            guard !profileStore.profiles.isEmpty else {
                LogService.shared.warning("Engine start blocked: no profile — create one first", category: "Engine")
                setupWindowOpener?()
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            // 엔진 ON: HID ownership 획득 후 EventTap 켜고 매핑 적용.
            beginKeyboardMonitoringIfPermitted()  // IM 있으면 디바이스 감지도 시작
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
    
    /// IOHIDManager(키보드 디바이스 감지)는 입력 모니터링 권한 프롬프트를 유발한다.
    /// 권한이 없을 때 init 에서 열면 첫 실행 환영 창 *전*에 프롬프트가 떠 순서가 깨진다.
    /// → 권한이 이미 있을 때만 연다. 없으면 설정 점검 패널의 명시적 버튼으로 부여 후 시작.
    /// (startMonitoring 은 idempotent — 이미 떠 있으면 no-op)
    func beginKeyboardMonitoringIfPermitted() {
        guard permissionService.checkInputMonitoringPermission() else {
            LogService.shared.info("Keyboard monitoring deferred — Input Monitoring not granted yet", category: "Device")
            return
        }
        keyboardDeviceManager.startMonitoring()
    }

    /// 앱을 안전하게 재시작. macOS "종료하고 다시 열기"가 메뉴바 전용(LSUIElement) 앱을
    /// 신뢰성 있게 재실행하지 못하는 문제 우회 — 분리 셸이 현재 인스턴스 종료 후 다시 연다.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"\(path)\""]
        try? task.run()
        LogService.shared.info("Relaunch requested (self-relaunch helper)", category: "App")
        NSApp.terminate(nil)
    }

    /// 한/영 전환만 쓰는 사용자를 위한 빠른 프로필 — 키바인딩 재배치 없음(항등 매핑).
    /// 엔진 게이트(프로필 ≥1)를 만족시키고, Right Cmd 한/영만 동작한다.
    /// (위자드의 키 캡처/검수 단계를 건너뛰는 빠른 경로)
    @discardableResult
    func createKoreanOnlyProfile() -> SavedKeyboardProfile {
        let identity: [Int64] = [Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]
        let profile = SavedKeyboardProfile(
            name: "한/영 전환만",
            legendStyle: .mac,
            physicalKeys: identity,
            localDesiredKeys: identity,
            vdiDesiredKeys: identity
        )
        profileStore.add(profile)
        activeMappingProfileId = profile.id.uuidString
        LogService.shared.info("Created Korean-only profile (no remap)", category: "App")
        return profile
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
        globalHotKeyService.unregister()
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

// MARK: - Menu Bar Label

/// MenuBarExtra 의 `label:` 슬롯은 popover 가 닫혀 있어도 항상 mount 되어 있다.
/// 이 특성을 이용해 SwiftUI 의 `openWindow` 액션을 capture 하여 AppState 에 보관해
/// 글로벌 단축키 (GlobalHotKeyService) 가 메뉴를 거치지 않고 Doctor 윈도우를 열 수
/// 있게 한다.
struct MenuBarLabelView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if appState.isEngineRunning {
                // 활성: 채운 글리프 + 초록 틴트 → 한눈에 "켜짐".
                Image(systemName: "command.square.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else {
                // 비활성: 아웃라인 + 불투명도 낮춤. 메뉴바가 색을 단색으로 강제해도
                // opacity 는 적용되므로 "흐릿한 빈 사각형" 으로 확실히 구분된다.
                Image(systemName: "command.square")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .opacity(0.45)
            }
        }
        .onAppear {
            appState.doctorWindowOpener = {
                openWindow(id: "doctor-window")
            }
            appState.setupWindowOpener = {
                openWindow(id: "setup-window")
            }
            appState.firstRunWindowOpener = {
                openWindow(id: "firstrun-window")
            }
            // 런치 후 1회: 첫 실행이면 환영/라이선스, 이후엔 환경 이슈 있을 때 설정 점검 패널 표시
            appState.runLaunchSetupCheckIfNeeded()
        }
    }
}
