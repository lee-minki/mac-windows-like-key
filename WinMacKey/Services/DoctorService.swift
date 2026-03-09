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
        guard !isRunning else { return }
        isRunning = true
        checks.removeAll()

        logger.info("🩺 Doctor: Running all checks...")

        Task {
            // 동기 체크: 즉시 실행
            checkAccessibilityPermission()
            checkEngineHealth(appState: appState)
            checkEventTapHealth(appState: appState)

            // 비동기 체크: pgrep 프로세스를 백그라운드 스레드에서 실행 (메인 스레드 블로킹 방지)
            await checkKarabinerConflict()
            checkHammerspoonConflict()

            checkInputSources()
            checkInputSourceShortcuts()
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
            "activeMappingProfileId",
            "visualCustomMappings",
            "eventViewerAlwaysOnTop",
            "savedKeyboardProfiles",
            "toggleTriggerKey",
            "languagePairSource1",
            "languagePairSource2"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        logger.info("✅ UserDefaults cleared")
        
        // 5. HID 매핑 해제 (동기 — 완료 보장)
        HIDRemapper.shared.clearAllMappingsSync()
        logger.info("✅ HID mappings cleared (global + internal keyboard)")
        
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
    
    private func checkKarabinerConflict() async {
        let karabinerRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "org.pqrs.Karabiner-Elements.Preferences" ||
            $0.bundleIdentifier == "org.pqrs.Karabiner-Elements.EventViewer" ||
            $0.localizedName?.contains("Karabiner") == true ||
            $0.localizedName?.contains("karabiner") == true
        }

        // karabiner_grabber 데몬은 NSWorkspace에 안 잡히므로 pgrep으로 확인 (백그라운드 스레드)
        let grabberRunning = await isProcessRunning("karabiner_grabber")
        let observerRunning = await isProcessRunning("karabiner_observer")
        let specificConflict = await karabinerTriggerConflictDetail()

        if karabinerRunning || grabberRunning || observerRunning {
            checks.append(DoctorCheck(
                category: .conflict,
                title: "Karabiner-Elements 충돌",
                detail: specificConflict ?? "Karabiner-Elements가 실행 중입니다. 같은 키를 동시에 가로채면 예측 불가능한 동작이 발생합니다. Karabiner에서 빈 프로필을 선택하거나 종료하세요.",
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
        let expectedKeyCode = 49        // Space
        let expectedModifiers = 262144 // Control

        guard let key60 = symbolicHotKeyInfo(id: "60") else {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "macOS 로컬/원격 Mac용 입력 소스 단축키 상태를 읽지 못했습니다. 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 '이전 입력 소스 선택'이 Control+Space인지 직접 확인하세요.",
                status: .warning,
                fixAction: .openSystemSettings
            ))
            return
        }

        guard key60.enabled else {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "WinMac Key의 로컬 macOS/원격 Mac 경로는 '이전 입력 소스 선택' 단축키를 Control+Space로 합성합니다. 시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스에서 이 항목을 켜고 Control+Space로 설정하세요.",
                status: .error,
                fixAction: .openSystemSettings
            ))
            return
        }

        if key60.keyCode == expectedKeyCode && key60.modifierFlags == expectedModifiers {
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "로컬 macOS/원격 Mac 경로용 Control+Space 설정이 올바릅니다.",
                status: .ok,
                fixAction: nil
            ))
        } else {
            let currentShortcut = describeHotKey(keyCode: key60.keyCode, modifierFlags: key60.modifierFlags)
            checks.append(DoctorCheck(
                category: .inputSource,
                title: "이전 입력 소스 단축키",
                detail: "현재 단축키가 \(currentShortcut)로 설정되어 있습니다. 로컬 macOS/원격 Mac에서 WinMac Key가 동작하려면 '이전 입력 소스 선택'을 Control+Space로 바꿔야 합니다.",
                status: .error,
                fixAction: .openSystemSettings
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

    /// pgrep을 백그라운드 스레드에서 실행하여 메인 스레드를 블로킹하지 않음
    private nonisolated func isProcessRunning(_ name: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.launchPath = "/usr/bin/pgrep"
                task.arguments = ["-x", name]
                task.standardOutput = Pipe()
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()
                    continuation.resume(returning: task.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private nonisolated func karabinerTriggerConflictDetail() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let configPath = NSString(string: "~/.config/karabiner/karabiner.json").expandingTildeInPath

                guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let profiles = json["profiles"] as? [[String: Any]],
                      let selectedProfile = profiles.first(where: { ($0["selected"] as? Bool) == true }) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: Self.describeKarabinerTriggerConflict(in: selectedProfile))
            }
        }
    }

    private nonisolated static func describeKarabinerTriggerConflict(in profile: [String: Any]) -> String? {
        let profileName = (profile["name"] as? String) ?? "현재 프로필"

        if let complex = profile["complex_modifications"] as? [String: Any],
           let rules = complex["rules"] as? [[String: Any]] {
            for rule in rules {
                let enabled = rule["enabled"] as? Bool ?? true
                guard enabled else { continue }

                let description = (rule["description"] as? String) ?? "이름 없는 규칙"
                let manipulators = rule["manipulators"] as? [[String: Any]] ?? []

                for manipulator in manipulators {
                    guard let from = manipulator["from"] as? [String: Any],
                          let keyCode = from["key_code"] as? String else {
                        continue
                    }

                    if keyCode == "right_command" || keyCode == "right_option" {
                        let keyName = keyCode == "right_command" ? "Right Command" : "Right Option"
                        return "Karabiner의 '\(profileName)' 프로필에서 '\(description)' 규칙이 \(keyName) 키를 직접 가로채고 있습니다. WinMac Key와 같은 트리거 키를 동시에 처리하면 즉시 전환되지 않거나 입력 소스 전환창이 뜰 수 있습니다. Karabiner에서 이 규칙을 끄거나 빈 프로필로 전환하세요."
                    }
                }
            }
        }

        if let devices = profile["devices"] as? [[String: Any]] {
            for device in devices {
                let modifications = device["simple_modifications"] as? [[String: Any]] ?? []
                for modification in modifications {
                    guard let from = modification["from"] as? [String: Any],
                          let keyCode = from["key_code"] as? String else {
                        continue
                    }

                    if keyCode == "right_command" || keyCode == "right_option" {
                        let keyName = keyCode == "right_command" ? "Right Command" : "Right Option"
                        return "Karabiner의 '\(profileName)' 프로필에서 \(keyName) 키에 simple modification이 적용되어 있습니다. WinMac Key와 같은 키를 동시에 처리하면 전환이 중복되거나 지연될 수 있습니다. 해당 매핑을 해제하세요."
                    }
                }
            }
        }

        return nil
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
                appState.isEngineRunning = appState.keyInterceptor.start()
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

    private struct SymbolicHotKeyInfo {
        let enabled: Bool
        let keyCode: Int?
        let modifierFlags: Int?
    }

    private func symbolicHotKeyInfo(id: String) -> SymbolicHotKeyInfo? {
        guard let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let allKeys = hotkeys["AppleSymbolicHotKeys"] as? [String: Any],
              let keyInfo = allKeys[id] as? [String: Any] else {
            return nil
        }

        let enabled = keyInfo["enabled"] as? Bool ?? false
        let value = keyInfo["value"] as? [String: Any]
        let parameters = value?["parameters"] as? [Any]
        let keyCode = parameters.flatMap { $0.count > 1 ? ($0[1] as? NSNumber)?.intValue : nil }
        let modifierFlags = parameters.flatMap { $0.count > 2 ? ($0[2] as? NSNumber)?.intValue : nil }

        return SymbolicHotKeyInfo(enabled: enabled, keyCode: keyCode, modifierFlags: modifierFlags)
    }

    private func describeHotKey(keyCode: Int?, modifierFlags: Int?) -> String {
        guard let keyCode else { return "알 수 없음" }

        var parts: [String] = []
        switch modifierFlags ?? 0 {
        case 262144:
            parts.append("Control")
        case 393216:
            parts.append(contentsOf: ["Control", "Shift"])
        case 524288:
            parts.append("Option")
        case 786432:
            parts.append(contentsOf: ["Control", "Option"])
        case 1048576:
            parts.append("Command")
        default:
            break
        }

        let keyLabel: String
        switch keyCode {
        case 49:
            keyLabel = "Space"
        default:
            keyLabel = "keyCode \(keyCode)"
        }

        parts.append(keyLabel)
        return parts.joined(separator: "+")
    }
}
