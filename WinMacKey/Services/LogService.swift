import Foundation
import AppKit
import os.log

/// 파일 기반 로깅 서비스
/// 앱의 주요 이벤트를 파일에 기록하고, 피드백용으로 내보낼 수 있습니다.
@MainActor
class LogService: ObservableObject {
    
    static let shared = LogService()
    
    // MARK: - Published
    
    @Published var entries: [LogEntry] = []
    @Published var isLogging = true
    
    // MARK: - Properties
    
    private let maxEntriesInMemory = 500
    private let maxFileSize: UInt64 = 5 * 1024 * 1024  // 5MB
    private let logger = Logger(subsystem: "com.winmackey.app", category: "LogService")
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    private let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    
    /// 로그 파일 경로 (한 번만 초기화)
    lazy var logFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("WinMacKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("winmackey.log")
    }()
    
    // MARK: - Log Entry Model
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        
        enum Level: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
            
            var emoji: String {
                switch self {
                case .info: return "ℹ️"
                case .warning: return "⚠️"
                case .error: return "❌"
                case .debug: return "🔍"
                }
            }
        }
        
        var formatted: String {
            "[\(Self.displayFormatter.string(from: timestamp))] [\(level.rawValue)] [\(category)] \(message)"
        }

        var fileFormatted: String {
            "[\(Self.fileFormatter.string(from: timestamp))] [\(level.rawValue)] [\(category)] \(message)"
        }

        private static let displayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()

        private static let fileFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return f
        }()
    }
    
    // MARK: - Init
    
    private init() {
        // 앱 시작 시 헤더 기록
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        writeToFile("=== WinMac Key v\(version) (Build \(build)) ===")
        writeToFile("=== macOS \(osVersion) ===")
        writeToFile("=== Session started: \(fileDateFormatter.string(from: Date())) ===")
        writeToFile("")
    }
    
    // MARK: - Logging Methods
    
    func info(_ message: String, category: String = "App") {
        log(level: .info, category: category, message: message)
    }
    
    func warning(_ message: String, category: String = "App") {
        log(level: .warning, category: category, message: message)
    }
    
    func error(_ message: String, category: String = "App") {
        log(level: .error, category: category, message: message)
    }
    
    func debug(_ message: String, category: String = "App") {
        log(level: .debug, category: category, message: message)
    }
    
    nonisolated func logFromBackground(_ message: String, level: LogEntry.Level = .info, category: String = "App") {
        Task { @MainActor in
            log(level: level, category: category, message: message)
        }
    }
    
    private func log(level: LogEntry.Level, category: String, message: String) {
        guard isLogging else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        // 메모리에 추가
        entries.append(entry)
        if entries.count > maxEntriesInMemory {
            entries.removeFirst(entries.count - maxEntriesInMemory)
        }
        
        // 파일에 기록
        writeToFile(entry.fileFormatted)
        
        // os.log에도 전달
        switch level {
        case .info: logger.info("\(entry.formatted)")
        case .warning: logger.warning("\(entry.formatted)")
        case .error: logger.error("\(entry.formatted)")
        case .debug: logger.debug("\(entry.formatted)")
        }
    }
    
    // MARK: - File Operations
    
    private func writeToFile(_ line: String) {
        let url = logFileURL
        let lineWithNewline = line + "\n"
        
        // 파일 크기 체크 → 로테이션
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            rotateLogFile()
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = lineWithNewline.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? lineWithNewline.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func rotateLogFile() {
        let url = logFileURL
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("winmackey.log.old")
        
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
    }
    
    // MARK: - Export
    
    /// 로그 파일의 전체 내용을 반환
    func exportLogContent() -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return "(로그 파일을 읽을 수 없습니다)"
        }
        return content
    }
    
    /// 시스템 정보 + 최근 로그를 피드백용으로 포맷
    func exportForFeedback() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        var report = """
        === WinMac Key Bug Report ===
        Version: \(version) (Build \(build))
        macOS: \(osVersion)
        Date: \(fileDateFormatter.string(from: Date()))
        
        === Recent Logs (last 100) ===
        
        """
        
        let recent = entries.suffix(100)
        for entry in recent {
            report += entry.fileFormatted + "\n"
        }
        
        return report
    }
    
    /// 로그를 클립보드에 복사
    func copyToClipboard() {
        let content = exportForFeedback()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    /// 로그 파일 경로 열기 (Finder에서)
    func revealInFinder() {
        NSWorkspace.shared.selectFile(logFileURL.path, inFileViewerRootedAtPath: "")
    }
    
    /// 메모리 로그 클리어 (파일은 유지)
    func clearMemoryLogs() {
        entries.removeAll()
    }
    
    /// 파일 로그도 클리어
    func clearAllLogs() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: logFileURL)
        info("Logs cleared", category: "LogService")
    }
    
    /// 로그 파일 크기
    var logFileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64 else {
            return "0 KB"
        }
        
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
}
