// Exercises the real StateManager with an inert backend and a manually resumed
// poll clock. No TIS reads/writes, CGEvent posting, observers or TCC requests.
import Foundation

private final class InertInputSources: InputSourceManager {
    var index = 1
    var shortcutCount = 0
    var directCount = 0
    var relayCount = 0
    var directSucceeds = true

    override func currentSourceIndex() -> Int { index }
    override func currentSourceName() -> String { index == 1 ? "ABC" : "Korean" }
    override func currentSourceShortName() -> String { currentSourceName() }
    override func toggleViaKeyboardShortcut() { shortcutCount += 1 }
    override func toggleDirectly() -> Bool {
        directCount += 1
        // Deliberately do not change index or send a system notification.
        // This exposes a stale poll even when the direct request succeeds.
        return directSucceeds
    }
    override func emitVDIRelayKey() { relayCount += 1 }
}

@MainActor
private final class ManualPollClock {
    private var pending: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { pending.append($0) }
    }

    func waitUntilPending(_ count: Int = 1) async {
        for _ in 0..<1_000 {
            if pending.count >= count { return }
            await Task.yield()
        }
        fatalError("Expected \(count) pending poll waits, got \(pending.count)")
    }

    func resumeNext() async {
        await waitUntilPending()
        pending.removeFirst().resume()
        // Let the resumed actor task finish this poll or enqueue its next wait.
        for _ in 0..<20 { await Task.yield() }
    }
}

@main
struct InputSourceVerificationSmoke {
    @MainActor
    static func main() async {
        await directRequestCancelsOlderPoll()
        await cancellationStopsContextWork()
        await newerNormalRequestOwnsItsPoll()
        await successfulVerificationCompletesOnce()
        await boundedRetryAndFallbackRemainIntact()
        await vdiRequestCancelsHostRetry()
        await pairChangeCancelsOldTarget()
        print("input_source_verification_smoke: PASS (7 scenarios; no system input mutation)")
    }

    @MainActor
    private static func manager(_ backend: InertInputSources, _ clock: ManualPollClock) -> StateManager {
        StateManager(
            inputSourceManager: backend,
            observeSystemChanges: false,
            pollIterations: 1,
            waitForNextPoll: { await clock.wait() }
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("input_source_verification_smoke: \(message)") }
    }

    @MainActor
    private static func directRequestCancelsOlderPoll() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        var completed = 0, failed = 0
        state.onSystemInputSourceChanged = { completed += 1 }
        state.onInputSourceToggleVerificationFailed = { failed += 1 }
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        expect(state.handleTerminalTrigger(), "direct request should succeed")
        await clock.resumeNext() // Resume a cancelled wait on purpose.
        expect(backend.shortcutCount == 1 && backend.directCount == 1,
               "old normal poll retried after a newer direct request")
        expect(completed == 1 && failed == 0, "stale poll changed direct-request callbacks")
    }

    @MainActor
    private static func cancellationStopsContextWork() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        var callbacks = 0
        state.onSystemInputSourceChanged = { callbacks += 1 }
        state.onInputSourceToggleVerificationFailed = { callbacks += 1 }
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        state.cancelPendingInputSourceVerification() // Focus/engine integration boundary.
        backend.index = 2
        await clock.resumeNext()
        expect(backend.shortcutCount == 1 && backend.directCount == 0 && callbacks == 0,
               "cancelled context produced input or completion work")
    }

    @MainActor
    private static func newerNormalRequestOwnsItsPoll() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        var completed = 0
        state.onSystemInputSourceChanged = { completed += 1 }
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending(2)
        await clock.resumeNext() // Old generation must leave the new task untouched.
        expect(backend.shortcutCount == 2, "old generation posted an extra shortcut")
        await clock.resumeNext() // New generation still retries normally.
        expect(backend.shortcutCount == 3, "new generation lost its verification task")
        backend.index = 2
        await clock.resumeNext()
        expect(completed == 1 && backend.directCount == 0,
               "new generation did not finish exactly once")
    }

    @MainActor
    private static func successfulVerificationCompletesOnce() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        var completed = 0
        state.onSystemInputSourceChanged = { completed += 1 }
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        backend.index = 2
        await clock.resumeNext()
        expect(backend.shortcutCount == 1 && backend.directCount == 0 && completed == 1,
               "observed source change should complete without retry")
    }

    @MainActor
    private static func boundedRetryAndFallbackRemainIntact() async {
        for directSucceeds in [true, false] {
            let backend = InertInputSources(), clock = ManualPollClock()
            backend.directSucceeds = directSucceeds
            let state = manager(backend, clock)
            var completed = 0, failed = 0
            state.onSystemInputSourceChanged = { completed += 1 }
            state.onInputSourceToggleVerificationFailed = { failed += 1 }
            state.handleTrigger(isVdiMode: false)
            for _ in 0..<3 { await clock.resumeNext() }
            expect(backend.shortcutCount == 3 && backend.directCount == 1,
                   "normal path must keep exactly two retries and one fallback")
            expect(completed == (directSucceeds ? 1 : 0) && failed == (directSucceeds ? 0 : 1),
                   "fallback result callback changed")
        }
    }

    @MainActor
    private static func vdiRequestCancelsHostRetry() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        state.handleTrigger(isVdiMode: true)
        await clock.resumeNext()
        expect(backend.shortcutCount == 1 && backend.relayCount == 1 && backend.directCount == 0,
               "VDI request permitted a stale host input-source change")
    }

    @MainActor
    private static func pairChangeCancelsOldTarget() async {
        let backend = InertInputSources(), clock = ManualPollClock()
        let state = manager(backend, clock)
        state.handleTrigger(isVdiMode: false)
        await clock.waitUntilPending()
        state.configurePair(source1: "new-a", source2: "new-b")
        await clock.resumeNext()
        expect(backend.shortcutCount == 1 && backend.directCount == 0,
               "old pair verification changed the newly configured input pair")
    }
}
