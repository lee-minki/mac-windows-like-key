import Foundation
import ServiceManagement

/// 로그인 시 자동 시작 상태를 관리합니다.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastErrorMessage: String?

    init() {
        status = SMAppService.mainApp.status
        lastErrorMessage = nil
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var isAvailable: Bool {
        status != .notFound
    }

    var statusTitle: String {
        switch status {
        case .enabled:
            return "ON"
        case .requiresApproval:
            return "승인 필요"
        case .notRegistered:
            return "OFF"
        case .notFound:
            return "사용 불가"
        @unknown default:
            return "알 수 없음"
        }
    }

    var statusDetail: String {
        if let lastErrorMessage {
            return lastErrorMessage
        }

        switch status {
        case .enabled:
            return "로그인 후 WinMac Key를 자동 실행합니다. 손쉬운 사용 권한이 이미 있으면 엔진도 바로 켭니다."
        case .requiresApproval:
            return "시스템 설정 → 일반 → 로그인 항목에서 WinMac Key를 허용해야 자동 시작이 활성화됩니다."
        case .notRegistered:
            return "현재 로그인 시 자동 시작이 꺼져 있습니다."
        case .notFound:
            return "현재 빌드에서는 로그인 항목 등록을 찾을 수 없습니다. Applications 폴더의 서명된 앱에서 다시 시도하세요."
        @unknown default:
            return "자동 시작 상태를 확인할 수 없습니다."
        }
    }

    var shouldShowSettingsButton: Bool {
        requiresApproval || !isAvailable || lastErrorMessage != nil
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        lastErrorMessage = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = message(for: error, enabling: enabled)
        }

        refreshStatus()
        return lastErrorMessage == nil && status != .requiresApproval && status != .notFound
    }

    func refreshStatus() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func unregisterForReset() {
        guard isRegistered else {
            refreshStatus()
            lastErrorMessage = nil
            return
        }

        do {
            try SMAppService.mainApp.unregister()
        } catch {
            // Reset 동작은 계속 진행합니다.
        }

        refreshStatus()
        lastErrorMessage = nil
    }

    private func message(for error: Error, enabling: Bool) -> String {
        let action = enabling ? "활성화" : "비활성화"
        return "로그인 시 자동 시작 \(action)에 실패했습니다. \((error as NSError).localizedDescription)"
    }
}
