import Foundation
import os.log

/// 직렬 큐 기반 입력 소스 상태 관리자
/// 빠른 연속 전환 시 순서를 보장합니다.
class StateManager: ObservableObject {
    
    let inputSourceManager = InputSourceManager()
    
    /// 현재 입력 소스 상태 (UI 바인딩용)
    @Published var currentInputSource: InputSource = .english
    
    /// 전환 횟수 카운터 (디버깅용)
    @Published var switchCount: Int = 0
    
    // 빠른 연속 전환 시에도 메인 스레드 큐에서 순차적으로 처리되므로
    // Lua 싱글 스레드와 같은 안전성 보장 (TIS API 메인 스레드 요구사항 충족)
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "StateManager")
    
    init() {
        // 초기 상태 조회
        currentInputSource = inputSourceManager.currentSource()
    }
    
    /// 한영전환 트리거 (Right Cmd tap-only에서 호출)
    /// ⚠️ EventTap 콜백(메인 스레드)에서 직접 호출됨 — 동기 실행으로 다음 키 이벤트 처리 전 전환 완료 보장
    func handleTrigger() {
        let current = inputSourceManager.currentSource()
        let target: InputSource = current == .korean ? .english : .korean

        logger.info("Toggle: \(current.rawValue) → \(target.rawValue)")

        // 입력 소스 전환 — 콜백 내에서 동기 완료 (글자 밀림 방지)
        inputSourceManager.switchTo(target)

        let actual = inputSourceManager.currentSource()

        // @Published 업데이트: EventTap은 메인 RunLoop에서 실행되므로 직접 접근 안전
        currentInputSource = actual
        switchCount += 1

        if actual != target {
            logger.warning("Switch mismatch: expected \(target.rawValue) but got \(actual.rawValue)")
        }
    }
    
    /// 현재 상태 새로고침 (폴링용)
    func refreshCurrentSource() {
        let source = inputSourceManager.currentSource()
        DispatchQueue.main.async {
            self.currentInputSource = source
        }
    }
}
