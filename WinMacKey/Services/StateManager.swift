import Foundation
import os.log

/// 직렬 큐 기반 입력 소스 상태 관리자
/// 빠른 연속 전환 시 순서를 보장합니다.
@MainActor
class StateManager: ObservableObject {
    
    let inputSourceManager = InputSourceManager()
    var onSystemInputSourceChanged: (() -> Void)?
    var onInputSourceToggleVerificationFailed: (() -> Void)?
    
    /// 현재 입력 소스 표시 이름 (UI 바인딩용)
    @Published var currentSourceName: String = ""
    @Published var currentSourceShortName: String = "?"
    @Published var isSource1Active: Bool = true
    
    /// 전환 횟수 카운터 (디버깅용)
    @Published var switchCount: Int = 0
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "StateManager")
    private var inputSourceObserver: NSObjectProtocol?
    private var inputSourcePollTask: Task<Void, Never>?
    private let toggleRetryLimit = 2
    /// 전환 검증 폴링 반복 횟수 (× 2ms). P9 fix: 20(40ms) → 40(80ms).
    /// DistributedNotification(TIS 변경 알림)이 IPC 지연으로 40ms 를 넘겨 도착하면 폴이 성급히
    /// timeout → 재시도가 Control+Space(토글)를 되돌려(oscillation) 씹힘을 유발하던 문제.
    /// 창을 넓혀 느린 전환/알림을 성공으로 인식 → 불필요한 재시도 자체를 줄인다.
    private static let inputSourcePollIterations = 40
    /// 입력 소스 변경이 이미 확인되어 commitWindow가 완료된 경우 true
    /// 폴링과 DistributedNotification의 이중 호출을 방지합니다.
    private var commitWindowCompleted = false
    
    init() {
        refreshCurrentSource()
        observeSystemInputSourceChanges()
    }
    
    /// 언어 페어 설정 (AppState에서 호출)
    func configurePair(source1: String, source2: String) {
        inputSourceManager.source1ID = source1
        inputSourceManager.source2ID = source2
        refreshCurrentSource()
    }
    
    /// - Mac 로컬 / 원격 Mac: Control+Space
    /// - Windows VDI: F16 릴레이 키
    /// 실제 상태 갱신은 macOS 입력소스 변경 알림에서 처리됩니다.
    func handleTrigger(isVdiMode: Bool) {
        let beforeName = inputSourceManager.currentSourceShortName()
        let beforeIndex = inputSourceManager.currentSourceIndex()

        switchCount += 1
        commitWindowCompleted = false  // 새 토글 시작 시 리셋

        if isVdiMode {
            inputSourceManager.emitVDIRelayKey()
            logger.info("Toggle triggered: was \(beforeName), posted F16 relay for VDI")
        } else {
            inputSourceManager.toggleViaKeyboardShortcut()
            startPollingForInputSourceChange(from: beforeIndex, retryCount: 0)
            logger.info("Toggle triggered: was \(beforeName), posted Control+Space (state update via notification)")
        }
    }

    func handleTerminalTrigger() {
        let beforeName = inputSourceManager.currentSourceShortName()

        switchCount += 1
        commitWindowCompleted = true

        if inputSourceManager.toggleDirectly() {
            refreshCurrentSource()
            onSystemInputSourceChanged?()
            logger.info("Toggle triggered: was \(beforeName), switched directly for terminal context")
        } else {
            logger.warning("Terminal toggle failed via direct TIS toggle")
            onInputSourceToggleVerificationFailed?()
        }
    }

    /// 현재 상태 새로고침
    func refreshCurrentSource() {
        let idx = inputSourceManager.currentSourceIndex()
        currentSourceName = inputSourceManager.currentSourceName()
        currentSourceShortName = inputSourceManager.currentSourceShortName()
        isSource1Active = (idx == 1)
    }
    
    // MARK: - System Input Source Observer
    
    /// 시스템 입력소스 변경 감지 (Ctrl+Space, 메뉴바 클릭 등 외부 전환 시에도 동기화)
    private func observeSystemInputSourceChanges() {
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.inputSourcePollTask?.cancel()
                self.inputSourcePollTask = nil
                self.refreshCurrentSource()
                if !self.commitWindowCompleted {
                    self.commitWindowCompleted = true
                    self.onSystemInputSourceChanged?()
                }
            }
        }
    }

    private func startPollingForInputSourceChange(from previousIndex: Int, retryCount: Int) {
        inputSourcePollTask?.cancel()
        inputSourcePollTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            for _ in 0..<Self.inputSourcePollIterations {
                try? await Task.sleep(nanoseconds: 2_000_000)

                if Task.isCancelled { return }

                let currentIndex = self.inputSourceManager.currentSourceIndex()
                if currentIndex != 0 && currentIndex != previousIndex {
                    self.refreshCurrentSource()
                    if !self.commitWindowCompleted {
                        self.commitWindowCompleted = true
                        self.onSystemInputSourceChanged?()
                    }
                    self.inputSourcePollTask = nil
                    return
                }
            }

            // P9 fix — 재시도 전 idempotency 가드.
            // 폴 timeout 이 곧 "전환 실패"는 아니다. 전환이 단지 느려서(알림 지연) 폴 창을 넘겼을 뿐이면
            // 이 시점엔 이미 바뀌어 있다. 이때 Control+Space(토글)를 재발사하면 되돌려(oscillation)
            // 씹힘을 만든다. 따라서 재발사 직전 한 번 더 확인해, 이미 바뀌었으면 성공 처리하고 끝낸다.
            let settledIndex = self.inputSourceManager.currentSourceIndex()
            if settledIndex != 0 && settledIndex != previousIndex {
                self.refreshCurrentSource()
                if !self.commitWindowCompleted {
                    self.commitWindowCompleted = true
                    self.onSystemInputSourceChanged?()
                }
                self.inputSourcePollTask = nil
                return
            }

            if retryCount < toggleRetryLimit {
                self.logger.warning("Toggle verification timeout; source still unchanged, retrying Control+Space (attempt \(retryCount + 1)/\(self.toggleRetryLimit))")
                self.inputSourceManager.toggleViaKeyboardShortcut()
                self.startPollingForInputSourceChange(from: previousIndex, retryCount: retryCount + 1)
                return
            }

            self.logger.warning("Toggle verification timeout after retry; falling back to direct TIS toggle")
            if self.inputSourceManager.toggleDirectly() {
                self.refreshCurrentSource()
                if !self.commitWindowCompleted {
                    self.commitWindowCompleted = true
                    self.onSystemInputSourceChanged?()
                }
                self.inputSourcePollTask = nil
                return
            }

            self.logger.warning("Toggle verification timeout after retry")
            self.onInputSourceToggleVerificationFailed?()
            self.inputSourcePollTask = nil
        }
    }
    
    deinit {
        inputSourcePollTask?.cancel()
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
