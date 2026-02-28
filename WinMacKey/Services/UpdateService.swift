import Foundation
import AppKit

/// GitHub Releases 기반 업데이트 서비스
/// DMG 배포 시 수동 업데이트 체크 및 다운로드 기능을 제공합니다.
class UpdateService: ObservableObject {
    // MARK: - Configuration
    
    /// GitHub 저장소 정보 (실제 배포 시 변경 필요)
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
            
            // DMG 파일 찾기
            if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
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
    
    /// DMG 다운로드 및 열기
    @MainActor
    func downloadAndInstall() async {
        guard let url = downloadURL else {
            error = .noDownloadURL
            return
        }
        
        // Safari에서 다운로드 페이지 열기 (가장 간단한 방법)
        NSWorkspace.shared.open(url)
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
