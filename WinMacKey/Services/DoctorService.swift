import Foundation
import AppKit
import Carbon.HIToolbox
import os.log

/// brew doctor 스타일의 진단 및 복구 서비스
/// 시스템 상태를 점검하고, 충돌을 감지하며, 원복을 수행합니다.
@MainActor
class DoctorService: ObservableObject {
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "Doctor")
    
    // MARK: - Published State
    
    @Published var checks: [DoctorCheck] = []
    @Published var isRunning = false
    @Published var lastRunDate: Date?
    
    // MARK: - Check Model
    
    struct DoctorCheck: Identifiable {
        let id = UUID()
        let category: Category
        let title: String
        let detail: String
        let status: Status
        let fixAction: FixAction?
        
        enum Category: String {
            case permission = "권한"
            case engine = "엔진"
            case conflict = "충돌"
            case inputSource = "입력 소스"
            case system = "시스템"
        }
        
        enum Status {
            case ok        // ✅
            case warning   // ⚠️
            case error     // ❌
        }
        
        enum FixAction {
            case openAccessibility
            case stopEngine
            case restartEngine
            case resetAll
            case openSystemSettings
        }
    }
    
    // MARK: - Run All Checks
    
    @MainActor
    func runAllChecks(appState: AppState) {
        isRunning = true
        checks.removeAll()
        
        logger.info("🩺 Doctor: Running all checks...")
        
        // 1. Permission checks
        checkAccessibilityPermission()
        
        // 2. Engine health
        checkEngineHealth(appState: appState)
        checkEventTapHealth(appState: appState)
        
        // 3. Conflict detection
        checkKarabinerConflict()
        checkHammerspoonConflict()
        
        // 4. Input source checks
        checkInputSources()
        checkInputSourceShortcuts()
        
        // 5. System checks
        checkCapsLockSetting()
        
        lastRunDate = Date()
        isRunning = false
        
        let errorCount = checks.filter { $0.status == .error }.count
        let warningCount = checks.filter { $0.status == .warning }.count
        
        if errorCount == 0 && warningCount == 0 {
            logger.info("🩺 Doctor: All checks passed ✅")
        } else {
            logger.warning("🩺 Doctor: \(errorCount) errors, \(warningCount) warnings")
        }
    }
    
    // MARK: - Emergency Recovery (원복)
    
    /// 앱이 건드린 모든 것을 원복합니다.
    @MainActor
    func emergencyRecovery(appState: AppState) {
        logger.info("🚨 Emergency Recovery: Starting...")
        
        // 1. 엔진 즉시 정지 (CGEventTap 해제)
        appState.keyInterceptor.stop()
        appState.isEngineRunning = false
        logger.info("✅ Engine stopped, CGEventTap released")
        
        // 2. ContextManager 모니터링 정지
        appState.contextManager.stopMonitoring()
        logger.info("✅ ContextManager monitoring stopped")
        
        // 3. 이벤트 로그 클리어
        appState.keyInterceptor.events.removeAll()
        logger.info("✅ Event logs cleared")
        
        // 4. UserDefaults 초기화
        let keys = [
            "WinMacKey.Profiles",
            "LastUpdateCheck",
            "AutoCheckUpdates",
            "CustomVirtualizationApps",
            "useVdiMode"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        logger.info("✅ UserDefaults cleared")
        
        // 5. VDI 모드 해제
        appState.useVdiMode = false
        logger.info("✅ VDI mode disabled")
        
        logger.info("🎉 Emergency Recovery completed — system is clean")
    }
    
    // MARK: - Individual Checks
    
    private func checkAccessibilityPermission() {
        let hasPermission = AXIsProcessTrusted()
        
        if hasPermission {
            checks.append(DoctorCheck(
                category: .permission,
                title: "손쉬운 사용 권한",
                detail: "접근성 권한이 정상적으로 부여되어 있습니다.",
                status: .ok,
                fixAction: nil
            ))
        } else {
            checks.append(DoctorCheck(
                category: .permission,
                title: "손쉬운 사용 권한",
                detail: "접근성 권한이 없습니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 WinMac Key를 허용하세요.",
                status: .error,
                fixAction: .openAccessibility
            ))
        }
    }
    
    private func checkEngineHealth(appState: AppState) {
        if appState.isEngineRunning {
            checks.append(DoctorCheck(
                category: .engine,
                title: "인터셉터 엔진",
                detail: "엔진이 정상 실행 중입니다.",
                status: .ok,
                fixAction: nil
            ))
        } else {
            checks.append(DoctorCheck(
                category: .engine,
                title: "인터셉터 엔진",
                detail: "엔진이 실행되고 있지 않습니다. 키 매핑이 동작하지 않습니다.",
                status: .warning,
                fixAction: .restartEngine
            ))
        }
    }
    
    private func checkEventTapHealth(appState: AppState) {
        // Engine running이면 EventTap도 활성화된 것으로 간주
        // (eventTap은 private이므로 직접 접근 불가)
        if appState.isEngineRunning {
            checks.append(DoctorCheck(
                category: .engine,
                title: "CGEventTap 상태",
                detail: "EventTap이 정상 동작 중입니다.",
                status: .ok,
                fixAction: nil
            ))
        }
    }
    
    private func checkKarabinerConflict() {
        let karabinerRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "org.pqrs.Karabiner-Elements.Preferences" ||
            $0.bundleIdentifier == "org.pqrs.Karabiner-Elements.EventViewer" ||
            $0.localizedName?.contains("Karabiner") == true ||
            $0.localizedName?.contains("karabiner") == true
        }
        
        // karabiner_grabber 프로세스 확인
        let grabberRunning = isProcessRunning("karabiner_grabber") || isProcessRunning("karabiner_observer")
        
        if karabinerRunning || grabberRunning {
            checks.append(DoctorCheck(
                category: .conflict,
                title: "Karabiner-Elements 충돌",
                detail: "Karabiner-Elements가 실행 중입니다. 같은 키를 동시에 가로채면 예측 불가능한 동작이 발생합니다. Karabiner에서 빈 프로필을 선택하거나 종료하세요.",
                status: .error,
                fixAction: nil
            ))
        } else {
            checks.append(DoctorCheck(
                category: .conflict,
                title: "Karabiner-Elements",
                detail: "감지되지 않음 — 충돌 없음.",
                status: .ok,
                fixAction: nil
            ))
        }
    }
    
    private func checkHammerspoonConflict() {
        let hsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "org.hammerspoon.Hammerspoon"
        }
        
        if hsRunning {
            checks.append(DoctorCheck(
                category: .conflict,
                title: "Hammerspoon 감지",
                detail: "Hammerspoon이 실행 중입니다. F18/F19 한영전환 핫키가 설정되어 있다면 WinMac Key와 간섭할 수 있습니다. 불필요 시 종료하세요.",
                status: .warning,
                fixAction: nil
            ))
        } else {
            checks.append(DoctorCheck(
                category: .conflict,
                title: "Hammerspoon",
                detail: "감지되지 않음 — 충돌 없음.",
                status: .ok,
                fixAction: nil
            ))
        }
    }
    
    private func checkInputSources() {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "입력 소스 목록",
                detail: "입력 소스 목록을 가져올 수 없습니다.",
                status: .error,
                fixAction: nil
            ))
            return
        }
        
        let hasKorean = sourceList.contains { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id.contains("Korean")
        }
        
        let hasEnglish = sourceList.contains { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id.contains("ABC") || id.contains("US")
        }
        
        if hasKorean && hasEnglish {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "입력 소스 (한글/영문)",
                detail: "한글 및 영문 입력 소스가 모두 등록되어 있습니다.",
                status: .ok,
                fixAction: nil
            ))
        } else if !hasKorean {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "한글 입력 소스 누락",
                detail: "한글 입력 소스가 없습니다. 시스템 설정 → 키보드 → 입력 소스 → 편집에서 '한국어 - 2벌식'을 추가하세요.",
                status: .error,
                fixAction: .openSystemSettings
            ))
        } else if !hasEnglish {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "영문 입력 소스 누락",
                detail: "영문(ABC) 입력 소스가 없습니다. 시스템 설정 → 키보드 → 입력 소스 → 편집에서 'ABC'를 추가하세요.",
                status: .error,
                fixAction: .openSystemSettings
            ))
        }
    }
    
    private func checkInputSourceShortcuts() {
        // SymbolicHotKeys 60 = "이전 입력 소스 선택"
        if let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
           let allKeys = hotkeys["AppleSymbolicHotKeys"] as? [String: Any],
           let key60 = allKeys["60"] as? [String: Any],
           let enabled = key60["enabled"] as? Bool,
           enabled {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "macOS의 '이전 입력 소스 선택' 단축키가 활성화되어 있습니다. WinMac Key와 간섭할 수 있으므로 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 체크를 해제하세요.",
                status: .warning,
                fixAction: .openSystemSettings
            ))
        } else {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "비활성화되어 있습니다 — WinMac Key와 간섭 없음.",
                status: .ok,
                fixAction: nil
            ))
        }
    }
    
    private func checkCapsLockSetting() {
        // SymbolicHotKeys 162 = "CapsLock으로 ABC 입력 소스 전환"
        if let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
           let allKeys = hotkeys["AppleSymbolicHotKeys"] as? [String: Any],
           let key162 = allKeys["162"] as? [String: Any],
           let enabled = key162["enabled"] as? Bool,
           enabled {
            checks.append(DoctorCheck(
                category: .system,
                title: "CapsLock 한영전환",
                detail: "macOS의 CapsLock 한영전환이 활성화되어 있습니다. 시스템 설정 → 키보드 → 입력 소스 → '모든 입력 소스'에서 'Caps Lock 키로 ABC 입력 소스 전환' 체크를 해제하세요.",
                status: .warning,
                fixAction: .openSystemSettings
            ))
        } else {
            checks.append(DoctorCheck(
                category: .system,
                title: "CapsLock 한영전환",
                detail: "비활성화되어 있습니다 — 정상.",
                status: .ok,
                fixAction: nil
            ))
        }
    }
    
    // MARK: - Helpers
    
    private func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    // MARK: - Fix Actions
    
    func performFix(_ action: DoctorCheck.FixAction, appState: AppState) {
        switch action {
        case .openAccessibility:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            
        case .stopEngine:
            appState.keyInterceptor.stop()
            appState.isEngineRunning = false
            
        case .restartEngine:
            appState.keyInterceptor.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.keyInterceptor.start()
                appState.isEngineRunning = true
            }
            
        case .resetAll:
            Task { @MainActor in
                emergencyRecovery(appState: appState)
            }

        case .openSystemSettings:
            let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
            NSWorkspace.shared.open(url)
        }
    }
}
