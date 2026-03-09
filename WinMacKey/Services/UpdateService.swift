import Foundation
import AppKit

/// GitHub Releases 기반 업데이트 서비스
/// .zip 다운로드 → 압축 해제 → 앱 교체 → 재시작
class UpdateService: ObservableObject {
    // MARK: - Configuration
    
    /// GitHub 저장소 정보
    private let githubOwner = "lee-minki"
    private let githubRepo = "mac-windows-like-key"
    
    /// 현재 앱 버전 (Bundle에서 가져옴)
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    // MARK: - Published Properties
    
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var lastCheckDate: Date?
    @Published var error: UpdateError?
    
    // 다운로드 진행 상태
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var updateStatus: String = ""
    
    // MARK: - Update Check
    
    /// 업데이트 확인 (GitHub Releases API 사용)
    @MainActor
    func checkForUpdates() async {
        isCheckingForUpdates = true
        error = nil
        
        defer {
            isCheckingForUpdates = false
            lastCheckDate = Date()
            UserDefaults.standard.set(Date(), forKey: "LastUpdateCheck")
        }
        
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            downloadURL = nil
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                error = .networkError
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    error = .noReleasesFound
                } else {
                    error = .serverError(httpResponse.statusCode)
                }
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            // 버전 비교
            let latestVersionString = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            latestVersion = latestVersionString
            releaseNotes = release.body
            
            // .zip 또는 .dmg 파일 찾기 (zip 우선)
            if let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) {
                downloadURL = URL(string: zipAsset.browserDownloadURL)
            } else if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                downloadURL = URL(string: dmgAsset.browserDownloadURL)
            }
            
            updateAvailable = isNewerVersion(latestVersionString, than: currentVersion)
            
        } catch {
            self.error = .networkError
            print("[UpdateService] Error checking for updates: \(error)")
        }
    }
    
    /// 버전 비교 (Semantic Versioning)
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(newComponents.count, currentComponents.count) {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            
            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        
        return false
    }
    
    // MARK: - Download & Install
    
    /// 앱 다운로드 → 교체 → 재시작
    @MainActor
    func downloadAndInstall() async {
        guard let url = downloadURL else {
            error = .noDownloadURL
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        updateStatus = "다운로드 준비 중..."
        error = nil
        
        defer {
            isDownloading = false
        }
        
        do {
            // 1. 다운로드
            updateStatus = "다운로드 중..."
            let (tempFileURL, _) = try await downloadWithProgress(url: url)
            
            // 2. 압축 해제
            updateStatus = "압축 해제 중..."
            downloadProgress = 0.8
            let extractedAppURL = try extractUpdate(from: tempFileURL)
            
            // 3. 앱 교체
            updateStatus = "설치 중..."
            downloadProgress = 0.9
            let appPath = Bundle.main.bundleURL
            try replaceApp(currentApp: appPath, newApp: extractedAppURL)
            
            // 4. 재시작
            updateStatus = "재시작 중..."
            downloadProgress = 1.0
            relaunchApp(at: appPath)
            
        } catch let updateErr as UpdateError {
            error = updateErr
        } catch {
            self.error = .installFailed(error.localizedDescription)
        }
    }
    
    /// URLSession으로 파일 다운로드 (진행률 추적)
    private func downloadWithProgress(url: URL) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }
        
        let expectedLength = response.expectedContentLength
        let tempDir = FileManager.default.temporaryDirectory
        let fileExtension = url.pathExtension.isEmpty ? "zip" : url.pathExtension
        let tempFile = tempDir.appendingPathComponent("WinMacKey-update.\(fileExtension)")
        
        // 기존 파일 제거
        try? FileManager.default.removeItem(at: tempFile)
        
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempFile)
        
        var downloaded: Int64 = 0
        var buffer = Data()
        let bufferSize = 65536  // 64KB 버퍼
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            
            if buffer.count >= bufferSize {
                handle.write(buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                
                if expectedLength > 0 {
                    let progress = min(Double(downloaded) / Double(expectedLength) * 0.75, 0.75)
                    await MainActor.run {
                        downloadProgress = progress
                    }
                }
            }
        }
        
        // 잔여 데이터 쓰기
        if !buffer.isEmpty {
            handle.write(buffer)
        }
        handle.closeFile()
        
        return (tempFile, response)
    }
    
    /// 다운로드된 업데이트 파일을 풀어 .app 경로를 반환
    private func extractUpdate(from downloadedFileURL: URL) throws -> URL {
        switch downloadedFileURL.pathExtension.lowercased() {
        case "zip":
            return try extractZipUpdate(from: downloadedFileURL)
        case "dmg":
            return try extractDmgUpdate(from: downloadedFileURL)
        default:
            throw UpdateError.unsupportedArchiveFormat(downloadedFileURL.pathExtension)
        }
    }

    /// .zip 압축 해제 → .app 경로 반환
    private func extractZipUpdate(from zipURL: URL) throws -> URL {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinMacKeyUpdate", isDirectory: true)
        
        // 기존 디렉토리 제거
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // unzip 실행
        let task = Process()
        task.launchPath = "/usr/bin/unzip"
        task.arguments = ["-o", zipURL.path, "-d", extractDir.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw UpdateError.extractFailed
        }
        
        return try findAppBundle(in: extractDir)
    }

    /// .dmg 마운트 후 .app을 임시 디렉터리로 복사하여 반환
    private func extractDmgUpdate(from dmgURL: URL) throws -> URL {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("WinMacKeyMount-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attachTask = Process()
        attachTask.launchPath = "/usr/bin/hdiutil"
        attachTask.arguments = ["attach", dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path]
        attachTask.standardOutput = Pipe()
        attachTask.standardError = Pipe()

        try attachTask.run()
        attachTask.waitUntilExit()

        guard attachTask.terminationStatus == 0 else {
            throw UpdateError.extractFailed
        }

        defer {
            let detachTask = Process()
            detachTask.launchPath = "/usr/bin/hdiutil"
            detachTask.arguments = ["detach", mountPoint.path]
            detachTask.standardOutput = Pipe()
            detachTask.standardError = Pipe()
            try? detachTask.run()
            detachTask.waitUntilExit()
            try? fm.removeItem(at: mountPoint)
        }

        let mountedAppURL = try findAppBundle(in: mountPoint)
        let copiedAppURL = fm.temporaryDirectory.appendingPathComponent("WinMacKeyUpdate-\(UUID().uuidString).app")
        try? fm.removeItem(at: copiedAppURL)
        try fm.copyItem(at: mountedAppURL, to: copiedAppURL)
        return copiedAppURL
    }

    private func findAppBundle(in directory: URL) throws -> URL {
        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator where url.pathExtension == "app" {
                return url
            }
        }
        throw UpdateError.appNotFoundInArchive
    }
    
    /// 현재 앱을 새 버전으로 교체
    private func replaceApp(currentApp: URL, newApp: URL) throws {
        let fm = FileManager.default
        let backupURL = currentApp.deletingLastPathComponent()
            .appendingPathComponent("WinMacKey.app.bak")
        
        // 백업 (기존 백업 제거)
        try? fm.removeItem(at: backupURL)
        
        // 현재 앱 → 백업
        try fm.moveItem(at: currentApp, to: backupURL)
        
        do {
            // 새 앱 → 현재 위치로 이동
            try fm.moveItem(at: newApp, to: currentApp)
            
            // 성공 시 백업 제거
            try? fm.removeItem(at: backupURL)
        } catch {
            // 실패 시 백업 복원
            try? fm.moveItem(at: backupURL, to: currentApp)
            throw UpdateError.installFailed("앱 교체 실패: \(error.localizedDescription)")
        }
        
        // Gatekeeper quarantine 속성 제거 (서명 없는 앱용)
        let xattrTask = Process()
        xattrTask.launchPath = "/usr/bin/xattr"
        xattrTask.arguments = ["-cr", currentApp.path]
        xattrTask.standardOutput = Pipe()
        xattrTask.standardError = Pipe()
        try? xattrTask.run()
        xattrTask.waitUntilExit()
    }
    
    /// 앱 재시작
    private func relaunchApp(at appURL: URL) {
        // 0.5초 후 새 앱 실행 (현재 프로세스가 종료될 시간)
        let script = """
        sleep 0.5
        open "\(appURL.path)"
        """
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        try? task.run()
        
        // HID 매핑 해제 후 종료
        HIDRemapper.shared.clearMappingsSync()
        NSApplication.shared.terminate(nil)
    }
    
    /// GitHub Releases 페이지 열기
    func openReleasesPage() {
        let urlString = "https://github.com/\(githubOwner)/\(githubRepo)/releases"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Helpers
    
    /// 마지막 체크 이후 경과 시간
    var timeSinceLastCheck: String? {
        guard let lastCheck = lastCheckDate ?? UserDefaults.standard.object(forKey: "LastUpdateCheck") as? Date else {
            return nil
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastCheck, relativeTo: Date())
    }
    
    /// 자동 업데이트 체크 설정
    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "AutoCheckUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "AutoCheckUpdates") }
    }
}

// MARK: - Error Types

enum UpdateError: LocalizedError {
    case invalidURL
    case networkError
    case noReleasesFound
    case serverError(Int)
    case noDownloadURL
    case downloadFailed
    case extractFailed
    case appNotFoundInArchive
    case unsupportedArchiveFormat(String)
    case installFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 업데이트 URL입니다."
        case .networkError:
            return "네트워크 연결을 확인해주세요."
        case .noReleasesFound:
            return "릴리스를 찾을 수 없습니다."
        case .serverError(let code):
            return "서버 오류가 발생했습니다. (코드: \(code))"
        case .noDownloadURL:
            return "다운로드 URL을 찾을 수 없습니다."
        case .downloadFailed:
            return "다운로드에 실패했습니다."
        case .extractFailed:
            return "압축 해제에 실패했습니다."
        case .appNotFoundInArchive:
            return "다운로드한 파일에서 앱을 찾을 수 없습니다."
        case .unsupportedArchiveFormat(let ext):
            return "자동 설치를 지원하지 않는 업데이트 형식입니다. (\(ext))"
        case .installFailed(let reason):
            return "설치 실패: \(reason)"
        }
    }
}

// MARK: - GitHub API Models

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubAsset]
    let publishedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int
    let downloadCount: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case downloadCount = "download_count"
    }
}
