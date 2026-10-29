import Foundation

/// Read-only diagnostic policy; no permission requests, key contents, or input mutations.
enum InputDiagnostics {
    enum Severity { case ok, information, warning, error }

    struct Finding {
        let severity: Severity
        let detail: String
    }

    struct TapSnapshot {
        let isRunning: Bool
        let exists: Bool
        let isValid: Bool
        let isEnabled: Bool
        let observation: Observation
    }

    struct Observation {
        private(set) var lastEventUptime: UInt64?
        private(set) var lastTriggerUptime: UInt64?

        mutating func record(isKeyboardEvent: Bool, isOwnSyntheticEvent: Bool,
                             isTriggerPress: Bool, isRepeat: Bool, uptime: UInt64) {
            guard isKeyboardEvent, !isOwnSyntheticEvent else { return }
            lastEventUptime = uptime
            if isTriggerPress && !isRepeat { lastTriggerUptime = uptime }
        }
    }

    static func accessibility(granted: Bool, previouslyGranted: Bool) -> Finding {
        if granted { return Finding(severity: .ok, detail: "현재 실행 중인 앱에 손쉬운 사용 권한이 허용되어 있습니다.") }
        let history = previouslyGranted
            ? "이전에 허용되었지만 현재 실행 중인 앱의 권한 확인은 거부 상태입니다. 권한 해제·앱 교체 등 원인은 이 확인만으로 구분할 수 없습니다. "
            : "현재 실행 중인 앱에 손쉬운 사용 권한이 없습니다. "
        return Finding(severity: .error, detail: history + "시스템 설정에서 앱 경로와 허용 상태를 확인하세요. 권한 초기화는 자동으로 실행하지 않습니다.")
    }

    static func inputMonitoring(granted: Bool) -> Finding {
        Finding(severity: granted ? .ok : .warning, detail: granted
            ? "입력 모니터링 사전 확인이 허용 상태입니다."
            : "입력 모니터링 사전 확인이 거부 상태입니다. 장치 식별이나 이벤트 수신이 안 되면 입력 모니터링 설정을 확인하세요. 이 결과만으로 전체 입력 실패를 단정하지 않습니다.")
    }

    static func eventTap(_ snapshot: TapSnapshot) -> Finding {
        guard snapshot.isRunning else {
            return Finding(severity: .information, detail: "인터셉터가 정지되어 있어 이벤트 수신을 확인하지 않습니다.")
        }
        guard snapshot.exists, snapshot.isValid else {
            return Finding(severity: .error, detail: "인터셉터 실행 상태와 달리 유효한 이벤트 탭이 없습니다. 권한을 확인한 뒤 엔진을 다시 시작하세요.")
        }
        guard snapshot.isEnabled else {
            return Finding(severity: .warning, detail: "이벤트 탭은 유효하지만 현재 비활성 상태입니다. 자동 복구 후 다시 진단하고, 계속되면 엔진을 다시 시작하세요.")
        }
        return Finding(severity: .ok, detail: "이벤트 탭이 유효하고 활성 상태입니다. 실제 입력 수신과 F16 감지는 아래 항목에서 별도로 확인합니다.")
    }

    static func secureInput(enabled: Bool) -> Finding {
        Finding(severity: enabled ? .information : .ok, detail: enabled
            ? "Secure Input이 활성화되어 일부 이벤트 관찰이 제한될 수 있습니다. 암호 입력을 마친 뒤 일반 입력창에서 다시 확인하세요. 활성 상태만으로 무반응 원인을 확정할 수 없습니다."
            : "현재 Secure Input은 비활성 상태입니다.")
    }

    static func observedInput(_ snapshot: TapSnapshot, now: UInt64) -> Finding {
        guard snapshot.isRunning else {
            return Finding(severity: .information, detail: "엔진을 켠 뒤 일반 키와 한/영 전환 키를 눌러 수신을 확인하세요.")
        }
        guard let event = snapshot.observation.lastEventUptime else {
            return Finding(severity: .information, detail: "이번 엔진 시작 이후 입력을 아직 관찰하지 못했습니다. 입력하지 않은 상태는 고장이 아닙니다. 일반 키와 한/영 전환 키를 누른 뒤 진단을 다시 실행하세요.")
        }
        let eventAge = seconds(since: event, now: now)
        let trigger = snapshot.observation.lastTriggerUptime.map {
            "F16 누름: \(seconds(since: $0, now: now))초 전."
        } ?? "F16 누름: 아직 관찰되지 않음. 전환 키를 눌러 확인하세요."
        return Finding(severity: snapshot.observation.lastTriggerUptime == nil ? .information : .ok,
                       detail: "최근 입력: \(eventAge)초 전. \(trigger) 앱 자체 합성 이벤트는 제외합니다. 이 기록은 로컬/VDI 언어 전환 성공을 보장하지 않습니다.")
    }

    private static func seconds(since uptime: UInt64, now: UInt64) -> UInt64 {
        now >= uptime ? (now - uptime) / 1_000_000_000 : 0
    }
}
