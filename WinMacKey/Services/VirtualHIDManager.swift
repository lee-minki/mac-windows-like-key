import Foundation
import os.log

/// Karabiner DriverKit virtual HID keyboard manager
///
/// Launches the KarabinerHelper with admin privileges (macOS password dialog)
/// and communicates via named pipes (FIFOs) to control the virtual keyboard.
///
/// ## Architecture
/// ```
/// WinMacKey (user app)
///     | Named Pipes (FIFO)
/// KarabinerHelper (root, via NSAppleScript admin privileges)
///     | UNIX Socket
/// Karabiner daemon -> virtual keyboard driver
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
    // Karabiner modifier bitmask (USB HID standard)

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

    /// AppDelegate termination cleanup
    static weak var appShared: VirtualHIDManager?

    @Published var state: ConnectionState = .disconnected

    private var helperPID: pid_t = 0
    private var inputHandle: FileHandle?    // app writes -> helper stdin
    private var outputHandle: FileHandle?   // helper stdout -> app reads
    private var outputBuffer = ""
    private let responseQueue = DispatchQueue(label: "com.winmackey.vhid.response", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.winmackey.app", category: "VirtualHIDManager")

    /// Named pipe paths for IPC with the privileged helper
    private static let fifoDir = "/tmp/com.winmackey"
    private static let fifoIn  = fifoDir + "/helper.in"
    private static let fifoOut = fifoDir + "/helper.out"

    /// Helper binary is ready for key posting
    var isReady: Bool { state.isReady }

    // MARK: - Lifecycle

    /// Launch the helper process with admin privileges (password dialog)
    func start() {
        guard helperPID == 0 else {
            logger.warning("Helper process already running")
            return
        }

        guard let helperPath = findHelperBinary() else {
            logger.error("KarabinerHelper binary not found")
            DispatchQueue.main.async { self.state = .error("헬퍼 바이너리 없음") }
            return
        }

        guard isKarabinerDaemonRunning() else {
            logger.warning("Karabiner daemon not running")
            DispatchQueue.main.async { self.state = .error("Karabiner 데몬 미실행") }
            return
        }

        DispatchQueue.main.async { self.state = .connecting }

        logger.info("Starting KarabinerHelper...")
        launchHelperWithAdminPrivileges(helperPath: helperPath)
    }

    /// Stop the helper process and clean up IPC resources
    func stop() {
        guard helperPID != 0 || inputHandle != nil else {
            DispatchQueue.main.async { self.state = .disconnected }
            return
        }

        // Send quit command — helper exits cleanly
        sendCommand(["cmd": "quit"])

        // Close our end of the pipes — helper reads EOF and exits
        cleanupSync()

        DispatchQueue.main.async { self.state = .disconnected }

        logger.info("KarabinerHelper stopped")
    }

    // MARK: - Key Posting

    /// Send key down event to the virtual keyboard
    /// - Parameters:
    ///   - modifiers: HID modifier bitmask (use Modifier constants)
    ///   - keys: HID Usage ID array (empty = modifier only)
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

    /// Send key up (release all) event to the virtual keyboard
    func postKeyUp() {
        guard isReady else { return }
        sendCommand(["cmd": "release"])
    }

    /// Ping the helper to check connection status
    func ping() {
        sendCommand(["cmd": "ping"])
    }

    // MARK: - Helper Binary Management

    /// Search for the helper binary in known locations
    private func findHelperBinary() -> String? {
        let candidates = [
            // App bundle (production)
            Bundle.main.bundlePath + "/Contents/Helpers/KarabinerHelper",
            // Development build (relative to app binary)
            Bundle.main.bundlePath + "/../../../KarabinerHelper/build/Release/KarabinerHelper"
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

    /// Check if Karabiner daemon is running via socket file
    private func isKarabinerDaemonRunning() -> Bool {
        let socketDir = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: socketDir) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".sock") }
    }

    /// Check if Karabiner driver is installed
    static func isDriverInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/.Karabiner-VirtualHIDDevice-Manager.app")
    }

    /// Check if Karabiner daemon is active
    static func isDaemonRunning() -> Bool {
        let socketDir = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: socketDir) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".sock") }
    }

    // MARK: - Process Launch

    /// Launch helper with admin privileges via NSAppleScript.
    /// Shows the standard macOS password dialog. Communicates via named pipes (FIFOs).
    private func launchHelperWithAdminPrivileges(helperPath: String) {
        // 1. Create named pipe directory and FIFOs
        try? FileManager.default.createDirectory(
            atPath: Self.fifoDir, withIntermediateDirectories: true)
        // Clean up stale FIFOs from previous session
        unlink(Self.fifoIn)
        unlink(Self.fifoOut)

        guard Darwin.mkfifo(Self.fifoIn, 0o600) == 0,
              Darwin.mkfifo(Self.fifoOut, 0o600) == 0 else {
            logger.error("Failed to create named pipes: \(String(cString: strerror(errno)))")
            DispatchQueue.main.async { self.state = .error("IPC 파이프 생성 실패") }
            return
        }

        // 2. Build AppleScript to launch helper with admin privileges
        // The `&` backgrounds the helper so `do shell script` returns immediately.
        // The shell forks: child handles FIFO redirects + exec, parent echoes PID and exits.
        let escapedHelper = helperPath.replacingOccurrences(of: "'", with: "'\\''")
        let scriptSource = """
        do shell script "'\(escapedHelper)' < '\(Self.fifoIn)' > '\(Self.fifoOut)' 2>/dev/null & echo $!" with administrator privileges
        """

        // 3. Execute on background thread (password dialog is system-managed)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }

            guard let appleScript = NSAppleScript(source: scriptSource) else {
                self.logger.error("Failed to create AppleScript")
                self.cleanupSync()
                DispatchQueue.main.async { self.state = .error("스크립트 생성 실패") }
                return
            }

            var scriptError: NSDictionary?
            let result = appleScript.executeAndReturnError(&scriptError)

            if let error = scriptError {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "인증 취소됨"
                self.logger.error("Admin authorization failed: \(msg)")
                self.cleanupSync()
                DispatchQueue.main.async { self.state = .error(msg) }
                return
            }

            // Parse helper PID from script output
            let resultStr = result.stringValue ?? ""
            let pidStr = resultStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = pid_t(pidStr) {
                self.helperPID = pid
                self.logger.info("KarabinerHelper launched (PID: \(pid))")
            }

            // 4. Connect to FIFOs (blocks until helper opens its end)
            self.connectToFIFOs()
        }
    }

    /// Connect to named pipes with timeout.
    /// The FileHandle opens block until the helper process opens its end of each FIFO.
    private func connectToFIFOs() {
        let semaphore = DispatchSemaphore(value: 0)
        var writeHandle: FileHandle?
        var readHandle: FileHandle?

        let connectQueue = DispatchQueue(label: "com.winmackey.vhid.connect")
        connectQueue.async {
            // Opens block until helper opens the other end of each FIFO
            writeHandle = FileHandle(forWritingAtPath: Self.fifoIn)
            readHandle = FileHandle(forReadingAtPath: Self.fifoOut)
            semaphore.signal()
        }

        // Wait up to 10 seconds for the helper to connect
        if semaphore.wait(timeout: .now() + .seconds(10)) == .timedOut {
            logger.error("FIFO connection timed out — helper may have failed to start")
            cleanupSync()
            DispatchQueue.main.async { self.state = .error("연결 시간 초과") }
            return
        }

        guard let wh = writeHandle, let rh = readHandle else {
            logger.error("Failed to open named pipes")
            cleanupSync()
            DispatchQueue.main.async { self.state = .error("FIFO 연결 실패") }
            return
        }

        self.inputHandle = wh
        self.outputHandle = rh

        // Set up async stdout reading
        rh.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // Empty data = EOF — helper process exited
                self?.logger.info("Helper process exited (EOF)")
                self?.cleanupSync()
                DispatchQueue.main.async {
                    self?.state = .disconnected
                }
                return
            }
            if let str = String(data: data, encoding: .utf8) {
                self?.handleOutput(str)
            }
        }

        logger.info("FIFO communication established")
    }

    /// Synchronous cleanup of all IPC resources
    private func cleanupSync() {
        outputHandle?.readabilityHandler = nil
        inputHandle?.closeFile()
        outputHandle?.closeFile()
        inputHandle = nil
        outputHandle = nil
        helperPID = 0
        outputBuffer = ""

        // Remove named pipes
        unlink(Self.fifoIn)
        unlink(Self.fifoOut)
    }

    // MARK: - Communication

    /// Send a JSON command to the helper via the input FIFO
    private func sendCommand(_ command: [String: Any]) {
        guard let handle = inputHandle else { return }

        do {
            let data = try JSONSerialization.data(withJSONObject: command)
            if var jsonString = String(data: data, encoding: .utf8) {
                jsonString += "\n"
                if let lineData = jsonString.data(using: .utf8) {
                    handle.write(lineData)
                }
            }
        } catch {
            logger.error("Failed to serialize command: \(error.localizedDescription)")
        }
    }

    /// Parse line-delimited JSON from helper stdout
    private func handleOutput(_ output: String) {
        responseQueue.async { [weak self] in
            guard let self = self else { return }

            self.outputBuffer += output

            // Parse line by line
            while let newlineIndex = self.outputBuffer.firstIndex(of: "\n") {
                let line = String(self.outputBuffer[self.outputBuffer.startIndex..<newlineIndex])
                self.outputBuffer = String(self.outputBuffer[self.outputBuffer.index(after: newlineIndex)...])

                if !line.isEmpty {
                    self.handleResponse(line)
                }
            }
        }
    }

    /// Handle a parsed JSON response from the helper
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
                self.logger.info("Virtual HID keyboard ready")

            case "connected":
                self.logger.info("Connected to Karabiner daemon")

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
                break // Normal response

            default:
                self.logger.info("Unknown status: \(status)")
            }
        }
    }

    deinit {
        stop()
    }
}
