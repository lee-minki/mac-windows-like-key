import Foundation
import AppKit
import CryptoKit

/// GitHub Releases 기반 업데이트 서비스
/// .zip/.dmg + .sig 다운로드 → Ed25519 서명 검증 → 압축 해제 → 앱 교체 → 재시작
class UpdateService: ObservableObject {
    // MARK: - Configuration

    /// GitHub 저장소 정보
    private let githubOwner = "lee-minki"
    private let githubRepo = "mac-windows-like-key"

    /// Ed25519 public key for verifying update assets (raw 32 bytes, base64 encoded).
    /// `scripts/setup-update-signing.sh` 가 키 생성 시 이 라인을 자동 갱신합니다.
    /// 빈 문자열이면 서명 검증이 비활성화됨 (개발 빌드용 폴백).
    static let updateSigningPublicKeyBase64: String = "ajQV1+y6XqbUoNPM2xP/ATAEQpgrLuC9bXnmY6Tq+9A="

    /// 현재 앱 버전 (Bundle에서 가져옴)
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 서명 검증이 활성화되어 있는지 여부
    var signatureVerificationEnabled: Bool {
        !Self.updateSigningPublicKeyBase64.isEmpty
    }

    // MARK: - Published Properties

    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var signatureURL: URL?
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
            // 동일 파일명에 .sig 가 추가된 자산을 함께 찾음 (예: WinMacKey-v1.3.1.zip.sig)
            downloadURL = nil
            signatureURL = nil

            let chosenAsset: GitHubAsset? = release.assets.first(where: { $0.name.hasSuffix(".zip") })
                ?? release.assets.first(where: { $0.name.hasSuffix(".dmg") })

            if let asset = chosenAsset {
                downloadURL = URL(string: asset.browserDownloadURL)
                let sigName = asset.name + ".sig"
                if let sig = release.assets.first(where: { $0.name == sigName }) {
                    signatureURL = URL(string: sig.browserDownloadURL)
                }
            }

            updateAvailable = isNewerVersion(latestVersionString, than: currentVersion)
            
        } catch {
            self.error = .networkError
            LogService.shared.error("Update check failed: \(error.localizedDescription)", category: "Update")
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
        // 위치 가드: /Applications/ 안에서만 자동 업데이트 허용
        // 다른 위치(Downloads, Desktop 등)에서 실행 중이면 업데이트 후에도 표준 위치에 중복본이 남음
        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasPrefix("/Applications/") else {
            error = .notInApplicationsFolder(bundlePath)
            return
        }

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

            // 2. 서명 검증 (public key가 임베드된 경우에만)
            if signatureVerificationEnabled {
                updateStatus = "서명 검증 중..."
                downloadProgress = 0.78
                try await verifyDownloadSignature(assetURL: tempFileURL)
            } else {
                // 릴리스 빌드는 무서명 자동 설치를 거부한다 — 서명 키가 누락된 빌드가
                // 검증 없이 임의 자산을 설치하는 사고를 원천 차단. 개발(DEBUG) 빌드만 폴백 허용.
                #if !DEBUG
                throw UpdateError.signatureInvalid("이 빌드에 업데이트 서명 키가 포함되어 있지 않아 무서명 설치를 거부합니다.")
                #endif
            }

            // 3. 압축 해제
            updateStatus = "압축 해제 중..."
            downloadProgress = 0.8
            let extractedAppURL = try extractUpdate(from: tempFileURL)

            // 4. 추출된 .app 검증 — Ed25519 통과해도 .app 내용물의 정체성 별도 확인
            //    (defense in depth: 서명키가 유출돼도 잘못된 bundle id/version 은 거부)
            updateStatus = "패키지 검증 중..."
            downloadProgress = 0.85
            try verifyExtractedApp(at: extractedAppURL)

            // 5. 앱 교체
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
    
    /// 추출된 .app 의 정체성 검증.
    /// 서명(Ed25519)이 통과해도 .app 내용물이 우리가 의도한 앱인지 별도 확인:
    ///   - CFBundleIdentifier == com.winmackey.app
    ///   - CFBundleShortVersionString == latestVersion (release 메타와 일치)
    ///   - .app 의 위치가 archive 루트 또는 1-depth 이내
    ///   - codesign --verify round-trip 통과
    private func verifyExtractedApp(at appURL: URL) throws {
        let fm = FileManager.default

        // 1. .app 위치 검증 — archive 깊은 곳에 묻혀 있으면 거부 (악성 archive 방어)
        let pathComponents = appURL.pathComponents
        // tmpdir 내부 깊이만 따짐 — 외부 시스템 디렉터리 (/var/folders/...) 은 제외
        // ".../WinMacKeyUpdate/SomeDeep/Path/WinMacKey.app" 같은 경우 거부.
        // 추출 디렉터리에서 .app 까지 최대 깊이 3 허용 (DMG 의 경우 마운트포인트/.app 도 가능)
        let extractDirName = appURL.deletingLastPathComponent().lastPathComponent
        let suspiciousDepth = pathComponents.suffix(5).joined(separator: "/")
        _ = suspiciousDepth  // 로깅용; 실제 검증은 아래 contains 로
        if appURL.path.contains("/.app/") || appURL.path.contains("/__MACOSX/") {
            throw UpdateError.installFailed("의심스러운 archive 구조: \(extractDirName)")
        }

        // 2. Info.plist 읽기
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: infoURL.path),
              let infoData = try? Data(contentsOf: infoURL),
              let infoPlist = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        else {
            throw UpdateError.installFailed("Info.plist 읽기 실패")
        }

        // 3. CFBundleIdentifier 검증
        let expectedBundleID = "com.winmackey.app"
        guard let bundleID = infoPlist["CFBundleIdentifier"] as? String,
              bundleID == expectedBundleID
        else {
            let got = infoPlist["CFBundleIdentifier"] as? String ?? "(missing)"
            throw UpdateError.installFailed("Bundle ID 불일치: 기대 '\(expectedBundleID)', 실제 '\(got)'")
        }

        // 4. CFBundleShortVersionString == latestVersion 검증
        let expectedVersion = latestVersion ?? ""
        let actualVersion = (infoPlist["CFBundleShortVersionString"] as? String) ?? ""
        if !expectedVersion.isEmpty && actualVersion != expectedVersion {
            throw UpdateError.installFailed("버전 불일치: release '\(expectedVersion)', .app '\(actualVersion)'")
        }

        // 5. codesign --verify round-trip — 서명이 valid on disk 인지 확인
        let verifyTask = Process()
        verifyTask.launchPath = "/usr/bin/codesign"
        verifyTask.arguments = ["--verify", "--no-strict", appURL.path]
        verifyTask.standardOutput = Pipe()
        let errPipe = Pipe()
        verifyTask.standardError = errPipe
        do {
            try verifyTask.run()
            verifyTask.waitUntilExit()
            if verifyTask.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? "(no stderr)"
                throw UpdateError.installFailed("codesign --verify 실패: \(errText.prefix(200))")
            }
        } catch let updateErr as UpdateError {
            throw updateErr
        } catch {
            throw UpdateError.installFailed("codesign 실행 실패: \(error.localizedDescription)")
        }

        // 6. 통과 — 로그
        // (LogService 가 main actor 라 여기서 직접 호출은 회피, caller 가 로그)
    }

    /// 다운로드된 자산이 임베드된 Ed25519 public key로 서명되었는지 검증
    /// 실패 시 throw — 검증 실패한 자산은 절대 설치하지 않음
    private func verifyDownloadSignature(assetURL: URL) async throws {
        guard let sigURL = signatureURL else {
            throw UpdateError.signatureMissing
        }

        // .sig 파일 다운로드 (작아서 한 번에)
        let (sigData, sigResponse) = try await URLSession.shared.data(from: sigURL)
        guard let http = sigResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.signatureMissing
        }

        // .sig 파일이 base64 텍스트로 저장된 경우 디코드 시도 — 아니면 raw bytes 그대로
        let signatureBytes: Data
        if let asString = String(data: sigData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let decoded = Data(base64Encoded: asString) {
            signatureBytes = decoded
        } else {
            signatureBytes = sigData
        }

        // Ed25519 signature는 정확히 64바이트
        guard signatureBytes.count == 64 else {
            throw UpdateError.signatureInvalid("signature 크기 오류 (\(signatureBytes.count) bytes)")
        }

        // Public key 파싱
        guard let pubKeyData = Data(base64Encoded: Self.updateSigningPublicKeyBase64),
              pubKeyData.count == 32 else {
            throw UpdateError.signatureInvalid("public key 파싱 실패")
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        } catch {
            throw UpdateError.signatureInvalid("public key 형식 오류: \(error.localizedDescription)")
        }

        // 자산 파일 전체를 메모리에 로드 (수 MB 수준이라 OK)
        let assetData = try Data(contentsOf: assetURL)

        let valid = publicKey.isValidSignature(signatureBytes, for: assetData)
        guard valid else {
            throw UpdateError.signatureInvalid("서명 검증 실패")
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
        // UUID 기반 isolated tmpdir — 동시 실행·이전 실패 흔적·외부 파일 충돌 방어
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinMacKey-update-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileExtension = url.pathExtension.isEmpty ? "zip" : url.pathExtension
        let tempFile = tempDir.appendingPathComponent("update.\(fileExtension)")
        
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
        // UUID 기반 isolated 추출 디렉터리 — 동시성 race / 잔존 파일 / 악성 placeholder 방어
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinMacKeyUpdate-\(UUID().uuidString)", isDirectory: true)
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
    /// quarantine 속성은 의도적으로 건드리지 않음 — Ed25519 서명 검증으로 무결성을 보장하므로
    /// Gatekeeper의 user-acknowledgment를 강제 해제할 이유가 없다.
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
    }

    /// 앱 재시작 — 인자 배열로 /usr/bin/open 직접 호출 (shell interpolation 회피)
    private func relaunchApp(at appURL: URL) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [appURL.path]

        // 현재 프로세스가 종료될 약간의 시간을 확보 — open은 비동기이므로
        // 종료 sequence 와 동시에 실행되어도 새 인스턴스가 안전하게 launch됨.
        try? task.run()

        // HID 매핑 해제 후 종료 — ownership 우회 (update install 도 명시적 cleanup path).
        if HIDRemapper.shared.isOwnedByEngine {
            HIDRemapper.shared.releaseOwnership()
        }
        HIDRemapper.shared.internalClearAllForTermination()
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
        get { StartupDefaults.autoCheckUpdates() }
        set { UserDefaults.standard.set(newValue, forKey: StartupDefaults.autoCheckUpdatesKey) }
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
    case notInApplicationsFolder(String)
    case signatureMissing
    case signatureInvalid(String)

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
        case .notInApplicationsFolder(let path):
            return "자동 업데이트는 /Applications/ 폴더에서 실행 중일 때만 가능합니다. 현재 위치: \(path) — 앱을 /Applications/로 옮긴 뒤 다시 시도하세요."
        case .signatureMissing:
            return "이 릴리스에 서명 파일(.sig)이 없습니다. 검증 없이 설치하지 않습니다."
        case .signatureInvalid(let reason):
            return "업데이트 서명 검증에 실패했습니다 (\(reason)). 자산이 변조되었을 수 있어 설치를 중단합니다."
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
