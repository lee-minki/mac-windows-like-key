import Foundation
import os.log

/// Karabiner DriverKit 가상 HID 키보드 관리자
///
/// KarabinerHelper C++ 바이너리를 root 권한으로 실행하고,
/// stdin/stdout 파이프를 통해 JSON 명령을 교환하여 가상 키보드를 제어합니다.
///
/// ## 동작 구조
/// ```
/// WinMacKey (일반 앱)
///     ↕ stdin/stdout JSON
/// KarabinerHelper (root 권한, C++ 프로세스)
///     ↕ UNIX Socket
/// Karabiner 데몬 → 가상 키보드 드라이버
/// ```
class VirtualHIDManager: ObservableObject {
    
    // MARK: - Types
    
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case ready
        case error(String)
        
        var displayName: String {
            switch self {
            case .disconnected: return "미연결"
            case .connecting: return "연결 중..."
            case .ready: return "준비됨"
            case .error(let msg): return "오류: \(msg)"
            }
        }
        
        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }
    
    // MARK: - HID Modifier Bitmask
    // Karabiner modifier 비트마스크 (USB HID 표준)
    
    struct Modifier {
        static let leftControl:  UInt8 = 0x01
        static let leftShift:    UInt8 = 0x02
        static let leftOption:   UInt8 = 0x04
        static let leftCommand:  UInt8 = 0x08
        static let rightControl: UInt8 = 0x10
        static let rightShift:   UInt8 = 0x20
        static let rightOption:  UInt8 = 0x40
        static let rightCommand: UInt8 = 0x80
    }
    
    // MARK: - Properties
    
    /// AppDelegate에서 앱 종료 시 접근하기 위한 약한 참조
    static weak var appShared: VirtualHIDManager?
    
    @Published var state: ConnectionState = .disconnected
    
    private var helperProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var outputBuffer = ""
    private let responseQueue = DispatchQueue(label: "com.winmackey.vhid.response", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.winmackey.app", category: "VirtualHIDManager")
    
    /// 헬퍼 바이너리가 준비되었는지 확인
    var isReady: Bool { state.isReady }
    
    // MARK: - Lifecycle
    
    /// 헬퍼 프로세스를 시작합니다 (root 권한 필요)
    func start() {
        guard helperProcess == nil else {
            logger.warning("Helper process already running")
            return
        }
        
        guard let helperPath = findHelperBinary() else {
            logger.error("KarabinerHelper binary not found")
            DispatchQueue.main.async {
                self.state = .error("헬퍼 바이너리 없음")
            }
            return
        }
        
        // Karabiner 데몬 소켓 존재 확인
        guard isKarabinerDaemonRunning() else {
            logger.warning("Karabiner daemon not running")
            DispatchQueue.main.async {
                self.state = .error("Karabiner 데몬 미실행")
            }
            return
        }
        
        DispatchQueue.main.async {
            self.state = .connecting
        }
        
        logger.info("Starting KarabinerHelper...")
        launchHelperWithAdminPrivileges(helperPath: helperPath)
    }
    
    /// 헬퍼 프로세스를 정지합니다
    func stop() {
        guard let process = helperProcess, process.isRunning else {
            helperProcess = nil
            DispatchQueue.main.async { self.state = .disconnected }
            return
        }
        
        // quit 명령 전송
        sendCommand(["cmd": "quit"])
        
        // 잠깐 대기 후 강제 종료
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if let process = self?.helperProcess, process.isRunning {
                process.terminate()
            }
            self?.helperProcess = nil
            self?.stdinPipe = nil
            self?.stdoutPipe = nil
            DispatchQueue.main.async {
                self?.state = .disconnected
            }
        }
        
        logger.info("KarabinerHelper stop requested")
    }
    
    // MARK: - Key Posting
    
    /// 가상 키보드에 키 다운 이벤트 전송
    /// - Parameters:
    ///   - modifiers: HID modifier 비트마스크 (Modifier 상수 사용)
    ///   - keys: HID Usage ID 배열 (빈 배열이면 modifier만 전송)
    func postKeyDown(modifiers: UInt8, keys: [UInt16] = []) {
        guard isReady else {
            logger.warning("Attempted postKeyDown but not ready")
            return
        }
        
        var command: [String: Any] = [
            "cmd": "post_key",
            "modifiers": modifiers
        ]
        if !keys.isEmpty {
            command["keys"] = keys.map { Int($0) }
        } else {
            command["keys"] = [Int]()
        }
        
        sendCommand(command)
    }
    
    /// 가상 키보드에 키 업(릴리스) 이벤트 전송
    func postKeyUp() {
        guard isReady else { return }
        sendCommand(["cmd": "release"])
    }
    
    /// 연결 상태 확인 (ping)
    func ping() {
        sendCommand(["cmd": "ping"])
    }
    
    // MARK: - Helper Binary Management
    
    /// 헬퍼 바이너리 경로 탐색
    /// 1. 앱 번들 내 Contents/Helpers/
    /// 2. 빌드 디렉토리
    /// 3. 프로젝트 디렉토리
    private func findHelperBinary() -> String? {
        let candidates = [
            // 앱 번들 내
            Bundle.main.bundlePath + "/Contents/Helpers/KarabinerHelper",
            // 빌드 출력 (개발 중)
            Bundle.main.bundlePath + "/../../../KarabinerHelper/build/Release/KarabinerHelper",
            // 프로젝트 루트 기준 (개발 중)
            "/Users/mk/worksapces/mac-windows-like-key/KarabinerHelper/build/Release/KarabinerHelper"
        ]
        
        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.isExecutableFile(atPath: resolved) {
                logger.info("Found helper at: \(resolved)")
                return resolved
            }
        }
        
        logger.error("Helper binary not found in any candidate path")
        return nil
    }
    
    /// Karabiner 데몬이 실행 중인지 소켓 파일로 확인
    private func isKarabinerDaemonRunning() -> Bool {
        let socketDir = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: socketDir) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".sock") }
    }
    
    /// Karabiner 드라이버가 설치되어 있는지 확인
    static func isDriverInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
    }
    
    /// Karabiner 드라이버 활성화 여부 확인
    static func isDaemonRunning() -> Bool {
        let socketDir = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: socketDir) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".sock") }
    }
    
    // MARK: - Process Launch
    
    /// AppleScript를 사용하여 관리자 권한으로 헬퍼 실행
    /// (macOS 표준 비밀번호 대화상자 표시)
    private func launchHelperWithAdminPrivileges(helperPath: String) {
        // 개발 중에는 직접 sudo로 실행 (터미널 권한 필요)
        // 프로덕션에서는 SMAppService 또는 AuthorizationRef 사용 예정
        
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [helperPath]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        
        // 프로세스 종료 핸들링
        process.terminationHandler = { [weak self] proc in
            self?.logger.info("KarabinerHelper terminated with status: \(proc.terminationStatus)")
            DispatchQueue.main.async {
                self?.state = .disconnected
                self?.helperProcess = nil
            }
        }
        
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.helperProcess = process
        
        // stdout 비동기 읽기
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            self?.handleOutput(str)
        }
        
        // stderr 로깅
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                self?.logger.warning("Helper stderr: \(str)")
            }
        }
        
        do {
            try process.run()
            logger.info("KarabinerHelper process started (PID: \(process.processIdentifier))")
        } catch {
            logger.error("Failed to start KarabinerHelper: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.state = .error("실행 실패: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Communication
    
    /// JSON 명령을 헬퍼의 stdin에 전송
    private func sendCommand(_ command: [String: Any]) {
        guard let pipe = stdinPipe,
              let process = helperProcess, process.isRunning else {
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: command)
            if var jsonString = String(data: data, encoding: .utf8) {
                jsonString += "\n"
                if let lineData = jsonString.data(using: .utf8) {
                    pipe.fileHandleForWriting.write(lineData)
                }
            }
        } catch {
            logger.error("Failed to serialize command: \(error.localizedDescription)")
        }
    }
    
    /// 헬퍼의 stdout 출력 처리
    private func handleOutput(_ output: String) {
        responseQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.outputBuffer += output
            
            // 줄 단위로 파싱
            while let newlineIndex = self.outputBuffer.firstIndex(of: "\n") {
                let line = String(self.outputBuffer[self.outputBuffer.startIndex..<newlineIndex])
                self.outputBuffer = String(self.outputBuffer[self.outputBuffer.index(after: newlineIndex)...])
                
                if !line.isEmpty {
                    self.handleResponse(line)
                }
            }
        }
    }
    
    /// JSON 응답 파싱 및 상태 업데이트
    private func handleResponse(_ json: String) {
        guard let data = json.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = response["status"] as? String else {
            logger.warning("Invalid response: \(json)")
            return
        }
        
        logger.info("Helper response: \(status)")
        
        DispatchQueue.main.async {
            switch status {
            case "ready":
                self.state = .ready
                self.logger.info("✅ Virtual HID keyboard ready")
                
            case "connected":
                self.logger.info("🔌 Connected to Karabiner daemon")
                
            case "not_ready":
                if case .ready = self.state {
                    self.state = .connecting
                }
                
            case "closed":
                self.state = .disconnected
                
            case "error":
                let message = response["message"] as? String ?? "unknown"
                self.state = .error(message)
                self.logger.error("Helper error: \(message)")
                
            case "warning":
                let message = response["message"] as? String ?? ""
                self.logger.warning("Helper warning: \(message)")
                
            case "ok", "bye":
                break // 정상 응답
                
            default:
                self.logger.info("Unknown status: \(status)")
            }
        }
    }
    
    deinit {
        stop()
    }
}
