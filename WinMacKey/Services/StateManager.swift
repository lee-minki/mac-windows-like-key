import Foundation
import os.log

/// 직렬 큐 기반 입력 소스 상태 관리자
/// 빠른 연속 전환 시 순서를 보장합니다.
@MainActor
class StateManager: ObservableObject {
    
    let inputSourceManager = InputSourceManager()
    
    /// 현재 입력 소스 표시 이름 (UI 바인딩용)
    @Published var currentSourceName: String = ""
    @Published var currentSourceShortName: String = "?"
    @Published var isSource1Active: Bool = true
    
    /// 전환 횟수 카운터 (디버깅용)
    @Published var switchCount: Int = 0
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "StateManager")
    private var inputSourceObserver: NSObjectProtocol?
    
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
    
    /// 한영전환 트리거 (Right Cmd tap-only에서 호출)
    /// Control+Space 시스템 단축키를 합성하여 macOS에 전환을 위임합니다.
    /// 실제 상태 갱신은 DistributedNotification 감지(observeSystemInputSourceChanges)에서 처리됩니다.
    func handleTrigger() {
        let beforeName = inputSourceManager.currentSourceShortName()

        // Control+Space 합성 이벤트로 시스템 입력소스 전환
        inputSourceManager.toggleViaKeyboardShortcut()

        switchCount += 1
        logger.info("Toggle triggered: was \(beforeName), posted Control+Space (state update via notification)")
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
                self?.refreshCurrentSource()
            }
        }
    }
    
    deinit {
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
