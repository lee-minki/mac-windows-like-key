import Foundation
import Carbon.HIToolbox

enum KeyboardLegendStyle: String, Codable, CaseIterable, Hashable {
    case mac
    case windows

    var title: String {
        switch self {
        case .mac: return "Mac 표기"
        case .windows: return "Windows 표기"
        }
    }

    var keyLegendSummary: String {
        switch self {
        case .mac: return "Ctrl · Opt · Cmd · Fn"
        case .windows: return "Ctrl · Win · Alt · Fn"
        }
    }
}

enum KeyboardUsageContext: String, Codable, CaseIterable, Hashable {
    case localMac
    case vdi

    var title: String {
        switch self {
        case .localMac: return "Mac 로컬"
        case .vdi: return "VDI"
        }
    }
}

/// Per-app keyboard mapping profile.
struct SavedKeyboardProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var legendStyle: KeyboardLegendStyle = .mac
    var physicalKeys: [Int64]
    var localDesiredKeys: [Int64]
    var vdiDesiredKeys: [Int64]
    /// Optional non-left-side key that should act as Fn for 3-key layouts.
    var auxiliaryFnKey: Int64?
    /// Bundle ID for per-app auto-switching (nil = manual activation only)
    var bundleId: String?

    init(
        id: UUID = UUID(),
        name: String,
        legendStyle: KeyboardLegendStyle = .mac,
        physicalKeys: [Int64],
        localDesiredKeys: [Int64],
        vdiDesiredKeys: [Int64]? = nil,
        auxiliaryFnKey: Int64? = nil,
        bundleId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.legendStyle = legendStyle
        self.physicalKeys = physicalKeys
        self.localDesiredKeys = localDesiredKeys
        self.vdiDesiredKeys = vdiDesiredKeys ?? localDesiredKeys
        self.auxiliaryFnKey = auxiliaryFnKey
        self.bundleId = bundleId
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case legendStyle
        case physicalKeys
        case localDesiredKeys
        case vdiDesiredKeys
        case desiredKeys
        case auxiliaryFnKey
        case bundleId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        legendStyle = try container.decodeIfPresent(KeyboardLegendStyle.self, forKey: .legendStyle) ?? .mac
        physicalKeys = try container.decode([Int64].self, forKey: .physicalKeys)
        let legacyDesired = try container.decodeIfPresent([Int64].self, forKey: .desiredKeys)
        localDesiredKeys = try container.decodeIfPresent([Int64].self, forKey: .localDesiredKeys) ?? legacyDesired ?? physicalKeys
        vdiDesiredKeys = try container.decodeIfPresent([Int64].self, forKey: .vdiDesiredKeys) ?? localDesiredKeys
        auxiliaryFnKey = try container.decodeIfPresent(Int64.self, forKey: .auxiliaryFnKey)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(legendStyle, forKey: .legendStyle)
        try container.encode(physicalKeys, forKey: .physicalKeys)
        try container.encode(localDesiredKeys, forKey: .localDesiredKeys)
        try container.encode(vdiDesiredKeys, forKey: .vdiDesiredKeys)
        try container.encodeIfPresent(auxiliaryFnKey, forKey: .auxiliaryFnKey)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
    }

    var usesDistinctVdiLayout: Bool {
        localDesiredKeys != vdiDesiredKeys
    }

    func desiredKeys(for context: KeyboardUsageContext) -> [Int64] {
        switch context {
        case .localMac: return localDesiredKeys
        case .vdi: return vdiDesiredKeys
        }
    }

    func mappings(for context: KeyboardUsageContext) -> [Int64: Int64] {
        let desiredKeys = desiredKeys(for: context)
        var result: [Int64: Int64] = [:]
        for (index, physKey) in physicalKeys.enumerated() {
            guard index < desiredKeys.count else { break }
            let desiredKey = desiredKeys[index]
            if physKey != desiredKey {
                result[physKey] = desiredKey
            }
        }
        if let auxiliaryFnKey {
            result[auxiliaryFnKey] = Int64(kVK_Function)
        }
        return result
    }

    var summary: String {
        let src = physicalKeys.map { ModifierSlot.label(for: $0, style: legendStyle) }.joined(separator: " · ")
        let local = localDesiredKeys.map { ModifierSlot.label(for: $0, style: legendStyle) }.joined(separator: " · ")
        let vdi = vdiDesiredKeys.map { ModifierSlot.label(for: $0, style: legendStyle) }.joined(separator: " · ")

        var parts: [String] = []
        if usesDistinctVdiLayout {
            parts.append("Local: \(src) -> \(local)")
            parts.append("VDI: \(src) -> \(vdi)")
        } else {
            parts.append("\(src) -> \(local)")
        }

        if let auxiliaryFnKey {
            parts.append("\(ModifierSlot.label(for: auxiliaryFnKey, style: legendStyle)) -> Fn")
        }

        return parts.joined(separator: " | ")
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

    func profile(idString: String) -> SavedKeyboardProfile? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return profiles.first { $0.id == uuid }
    }

    /// Find profile matching a bundle ID for auto-switching
    func profile(forBundleId bundleId: String) -> SavedKeyboardProfile? {
        guard !bundleId.isEmpty else { return nil }
        return profiles.first { $0.bundleId == bundleId }
    }
}
