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
    
    // 빠른 연속 전환 대비 직렬 큐
    // Lua 단일 스레드의 경쟁 조건 문제 완전 해결
    private let queue = DispatchQueue(
        label: "com.winmackey.state",
        qos: .userInteractive
    )
    
    private let logger = Logger(subsystem: "com.winmackey.app", category: "StateManager")
    
    init() {
        // 초기 상태 조회
        currentInputSource = inputSourceManager.currentSource()
    }
    
    /// 한영전환 트리거 (Right Cmd tap-only에서 호출)
    func handleTrigger() {
        queue.async { [self] in
            let current = inputSourceManager.currentSource()
            let target: InputSource = current == .korean ? .english : .korean
            
            logger.info("Toggle: \(current.rawValue) → \(target.rawValue)")
            
            // 입력 소스 전환 (동기 + 폴링 확인)
            inputSourceManager.switchTo(target)
            
            // 전환 후 실제 상태 확인
            let actual = inputSourceManager.currentSource()
            
            // UI 업데이트 (메인 스레드)
            DispatchQueue.main.async { [self] in
                currentInputSource = actual
                switchCount += 1
                
                if actual != target {
                    logger.warning("Switch mismatch: expected \(target.rawValue) but got \(actual.rawValue)")
                }
            }
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
