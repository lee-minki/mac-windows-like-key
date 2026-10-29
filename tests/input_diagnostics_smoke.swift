import Foundation

@main
struct InputDiagnosticsSmoke {
    static func main() {
        var count = 0
        func expect(_ condition: @autoclosure () -> Bool, _ scenario: String) {
            precondition(condition(), scenario)
            count += 1
            print("PASS: \(scenario)")
        }
        func snapshot(running: Bool = true, exists: Bool = true, valid: Bool = true,
                      enabled: Bool = true, observation: InputDiagnostics.Observation = .init()) -> InputDiagnostics.TapSnapshot {
            .init(isRunning: running, exists: exists, isValid: valid, isEnabled: enabled, observation: observation)
        }

        expect(InputDiagnostics.accessibility(granted: true, previouslyGranted: false).severity == .ok,
               "current accessibility grant")
        expect(InputDiagnostics.accessibility(granted: false, previouslyGranted: false).severity == .error,
               "missing accessibility grant")
        let revoked = InputDiagnostics.accessibility(granted: false, previouslyGranted: true)
        expect(revoked.severity == .error && revoked.detail.contains("구분할 수 없습니다"),
               "previous grant plus denial does not diagnose a signature mismatch")
        expect(InputDiagnostics.inputMonitoring(granted: false).severity == .warning,
               "missing input monitoring is reported separately")
        expect(InputDiagnostics.inputMonitoring(granted: true).severity == .ok,
               "input monitoring preflight allowed")
        expect(InputDiagnostics.eventTap(snapshot(running: false, exists: false, valid: false, enabled: false)).severity == .information,
               "stopped engine is unobserved, not a failed tap")
        expect(InputDiagnostics.eventTap(snapshot(exists: false)).severity == .error,
               "running flag cannot hide a missing tap")
        expect(InputDiagnostics.eventTap(snapshot(valid: false)).severity == .error,
               "invalid tap is an error even when enabled flag is true")
        expect(InputDiagnostics.eventTap(snapshot(enabled: false)).severity == .warning,
               "disabled tap is distinct from running engine")
        expect(InputDiagnostics.eventTap(snapshot()).severity == .ok,
               "valid enabled tap reports only tap health")
        let secure = InputDiagnostics.secureInput(enabled: true)
        expect(secure.severity == .information && secure.detail.contains("확정할 수 없습니다"),
               "Secure Input is evidence, not a proven root cause")
        expect(InputDiagnostics.secureInput(enabled: false).severity == .ok,
               "Secure Input disabled")
        let idle = InputDiagnostics.observedInput(snapshot(), now: 10_000_000_000)
        expect(idle.severity == .information && idle.detail.contains("고장이 아닙니다"),
               "no observed input is idle or unknown, not failure")

        var observation = InputDiagnostics.Observation()
        observation.record(isKeyboardEvent: true, isOwnSyntheticEvent: true, isTriggerPress: true,
                           isRepeat: false, uptime: 1_000_000_000)
        expect(observation.lastEventUptime == nil && observation.lastTriggerUptime == nil,
               "own synthetic input cannot prove keyboard reception or F16 reception")
        observation.record(isKeyboardEvent: false, isOwnSyntheticEvent: false, isTriggerPress: true,
                           isRepeat: false, uptime: 1_000_000_000)
        expect(observation.lastEventUptime == nil && observation.lastTriggerUptime == nil,
               "tap administration callback cannot prove keyboard reception")
        observation.record(isKeyboardEvent: true, isOwnSyntheticEvent: false, isTriggerPress: false,
                           isRepeat: false, uptime: 2_000_000_000)
        expect(observation.lastEventUptime == 2_000_000_000 && observation.lastTriggerUptime == nil,
               "ordinary input updates event time without claiming F16")
        let ordinary = InputDiagnostics.observedInput(snapshot(observation: observation), now: 5_000_000_000)
        expect(ordinary.severity == .information && ordinary.detail.contains("3초 전") && ordinary.detail.contains("아직 관찰되지 않음"),
               "ordinary event and missing trigger are distinguished")
        observation.record(isKeyboardEvent: true, isOwnSyntheticEvent: false, isTriggerPress: true,
                           isRepeat: false, uptime: 3_000_000_000)
        observation.record(isKeyboardEvent: true, isOwnSyntheticEvent: false, isTriggerPress: true,
                           isRepeat: true, uptime: 4_000_000_000)
        expect(observation.lastEventUptime == 4_000_000_000 && observation.lastTriggerUptime == 3_000_000_000,
               "repeated F16 updates input activity but is not a new trigger press")
        let stale = InputDiagnostics.observedInput(snapshot(observation: observation), now: 304_000_000_000)
        expect(stale.severity == .ok && stale.detail.contains("300초 전") && stale.detail.contains("301초 전"),
               "old observed input retains its age instead of claiming recent activity or failure")
        expect(stale.detail.contains("성공을 보장하지 않습니다"),
               "event observation is not proof of local or VDI language change")
        expect(InputDiagnostics.observedInput(snapshot(observation: observation), now: 0).detail.contains("0초 전"),
               "clock anomaly does not underflow elapsed time")
        expect(InputDiagnostics.observedInput(snapshot(running: false, observation: observation), now: 304_000_000_000).severity == .information,
               "stopped engine does not present previous events as current health")
        print("input_diagnostics_smoke: PASS (\(count) scenarios; no app launch, permission mutation, or event posting)")
    }
}
