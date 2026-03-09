import Foundation
import os.log

/// 직렬 큐 기반 입력 소스 상태 관리자
/// 빠른 연속 전환 시 순서를 보장합니다.
@MainActor
class StateManager: ObservableObject {
    
    let inputSourceManager = InputSourceManager()
    var onSystemInputSourceChanged: (() -> Void)?
    
    /// 현재 입력 소스 표시 이름 (UI 바인딩용)
    @Published var currentSourceName: String = ""
    @Published var currentSourceShortName: String = "?"
    @Published var isSource1Active: Bool = true
    
    /// 전환 횟수 카운터 (디버깅용)
    @Published var switchCount: Int = 0
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "StateManager")
    private var inputSourceObserver: NSObjectProtocol?
    private var inputSourcePollTask: Task<Void, Never>?
    private let toggleRetryLimit = 1
    
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
    
    /// 한영전환 트리거 (Right Cmd/Opt에서 호출)
    /// - Mac 로컬 / 원격 Mac: Control+Space
    /// - Windows VDI: F16 릴레이 키
    /// 실제 상태 갱신은 macOS 입력소스 변경 알림에서 처리됩니다.
    func handleTrigger(isVdiMode: Bool) {
        let beforeName = inputSourceManager.currentSourceShortName()
        let beforeIndex = inputSourceManager.currentSourceIndex()

        switchCount += 1

        if isVdiMode {
            inputSourceManager.emitVDIRelayKey()
            logger.info("Toggle triggered: was \(beforeName), posted F16 relay for VDI")
        } else {
            inputSourceManager.toggleViaKeyboardShortcut()
            startPollingForInputSourceChange(from: beforeIndex, retryCount: 0)
            logger.info("Toggle triggered: was \(beforeName), posted Control+Space (state update via notification)")
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
                self?.inputSourcePollTask?.cancel()
                self?.inputSourcePollTask = nil
                self?.refreshCurrentSource()
                self?.onSystemInputSourceChanged?()
            }
        }
    }

    private func startPollingForInputSourceChange(from previousIndex: Int, retryCount: Int) {
        inputSourcePollTask?.cancel()
        inputSourcePollTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 2_000_000)

                if Task.isCancelled { return }

                let currentIndex = self.inputSourceManager.currentSourceIndex()
                if currentIndex != 0 && currentIndex != previousIndex {
                    self.refreshCurrentSource()
                    self.onSystemInputSourceChanged?()
                    self.inputSourcePollTask = nil
                    return
                }
            }

            if retryCount < toggleRetryLimit {
                self.logger.warning("Toggle verification timeout; retrying Control+Space once")
                self.inputSourceManager.toggleViaKeyboardShortcut()
                self.startPollingForInputSourceChange(from: previousIndex, retryCount: retryCount + 1)
                return
            }

            self.logger.warning("Toggle verification timeout after retry")
            self.onSystemInputSourceChanged?()
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
