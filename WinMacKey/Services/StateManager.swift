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
    
    init() {
        refreshCurrentSource()
    }
    
    /// 언어 페어 설정 (AppState에서 호출)
    func configurePair(source1: String, source2: String) {
        inputSourceManager.source1ID = source1
        inputSourceManager.source2ID = source2
        refreshCurrentSource()
    }
    
    /// 한영전환 트리거 (Right Cmd tap-only에서 호출)
    /// ⚠️ EventTap 콜백(메인 스레드)에서 직접 호출됨 — 동기 실행으로 다음 키 이벤트 처리 전 전환 완료 보장
    func handleTrigger() {
        let beforeIdx = inputSourceManager.currentSourceIndex()
        let beforeName = inputSourceManager.currentSourceShortName()
        
        // 입력 소스 전환 — 콜백 내에서 동기 완료 (글자 밀림 방지)
        inputSourceManager.toggle()
        
        let afterIdx = inputSourceManager.currentSourceIndex()
        let afterName = inputSourceManager.currentSourceShortName()
        
        logger.info("Toggle: \(beforeName) → \(afterName)")
        
        // @Published 업데이트: EventTap은 메인 RunLoop에서 실행되므로 직접 접근 안전
        currentSourceName = inputSourceManager.currentSourceName()
        currentSourceShortName = afterName
        isSource1Active = (afterIdx == 1)
        switchCount += 1
        
        if afterIdx == beforeIdx {
            logger.warning("Switch may have failed: still on \(afterName)")
        }
    }
    
    /// 현재 상태 새로고침
    func refreshCurrentSource() {
        let idx = inputSourceManager.currentSourceIndex()
        currentSourceName = inputSourceManager.currentSourceName()
        currentSourceShortName = inputSourceManager.currentSourceShortName()
        isSource1Active = (idx == 1)
    }
}
