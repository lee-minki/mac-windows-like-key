import Foundation

/// Per-app keyboard mapping profile
/// Created via the visual keyboard layout wizard (ModifierLayoutView).
struct SavedKeyboardProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var physicalKeys: [Int64]
    var desiredKeys: [Int64]
    /// Bundle ID for per-app auto-switching (nil = manual activation only)
    var bundleId: String?

    var mappings: [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for (index, physKey) in physicalKeys.enumerated() {
            guard index < desiredKeys.count else { break }
            let desKey = desiredKeys[index]
            if physKey != desKey {
                result[physKey] = desKey
            }
        }
        return result
    }

    var summary: String {
        let src = physicalKeys.map { ModifierSlot.label(for: $0) }.joined(separator: " · ")
        let dst = desiredKeys.map { ModifierSlot.label(for: $0) }.joined(separator: " · ")
        return "\(src) -> \(dst)"
    }
}

/// Profile storage (UserDefaults-backed)
class KeyboardProfileStore: ObservableObject {
    @Published var profiles: [SavedKeyboardProfile] = []
    private let storageKey = "savedKeyboardProfiles"

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedKeyboardProfile].self, from: data) {
            profiles = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(_ profile: SavedKeyboardProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: SavedKeyboardProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            save()
        }
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    /// Find profile matching a bundle ID for auto-switching
    func profile(forBundleId bundleId: String) -> SavedKeyboardProfile? {
        guard !bundleId.isEmpty else { return nil }
        return profiles.first { $0.bundleId == bundleId }
    }
}
