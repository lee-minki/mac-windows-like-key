import Foundation

/// 키 매핑 정의
struct KeyMapping: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var fromKey: UInt32     // 원본 키코드
    var toKey: UInt32       // 매핑할 키코드
    var description: String // 사용자 표시용 설명
    
    init(id: UUID = UUID(), fromKey: UInt32, toKey: UInt32, description: String = "") {
        self.id = id
        self.fromKey = fromKey
        self.toKey = toKey
        self.description = description.isEmpty ? "\(KeyEvent.keyCodeHex(fromKey)) → \(KeyEvent.keyCodeHex(toKey))" : description
    }
}

/// 앱별 프로필
struct Profile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleId: String?   // nil이면 기본 프로필
    var mappings: [KeyMapping]
    var isEnabled: Bool = true
    
    init(id: UUID = UUID(), name: String, bundleId: String? = nil, mappings: [KeyMapping] = [], isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.mappings = mappings
        self.isEnabled = isEnabled
    }
    
    /// 기본 Mac 모드 프로필
    static var macMode: Profile {
        Profile(
            name: "Mac Mode",
            bundleId: nil,
            mappings: [
                KeyMapping(
                    fromKey: KeyEvent.capsLockKeyCode,
                    toKey: KeyEvent.capsLockKeyCode,
                    description: "CapsLock → Pure CapsLock (The Silencer)"
                )
            ]
        )
    }
    
    /// Windows 모드 프로필 (VMware용)
    static var windowsMode: Profile {
        Profile(
            name: "Windows Mode",
            bundleId: "com.vmware.horizon",  // VMware Horizon
            mappings: [
                KeyMapping(
                    fromKey: KeyEvent.capsLockKeyCode,
                    toKey: KeyEvent.windowsIMEKeyCode,
                    description: "CapsLock → Windows IME (0x15)"
                )
            ]
        )
    }
}

// MARK: - 프로필 매니저
class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var defaultProfile: Profile = .macMode
    
    private let userDefaultsKey = "WinMacKey.Profiles"
    
    init() {
        loadProfiles()
    }
    
    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = decoded
        } else {
            // 기본 프로필 설정
            profiles = [.macMode, .windowsMode]
            saveProfiles()
        }
    }
    
    func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        saveProfiles()
    }
    
    func removeProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        saveProfiles()
    }
    
    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    /// Bundle ID에 맞는 프로필 찾기
    func profile(for bundleId: String?) -> Profile {
        guard let bundleId = bundleId else { return defaultProfile }
        return profiles.first { $0.bundleId == bundleId && $0.isEnabled } ?? defaultProfile
    }
}
