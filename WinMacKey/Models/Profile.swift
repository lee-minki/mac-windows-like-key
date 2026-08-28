import Foundation
import Carbon.HIToolbox

/// 모디파이어 키 라벨 유틸 (v1.8.0 — `Profile.summary` + `ModifierLayoutView` 공용).
/// SwiftUI 의존 없이 Models·Services·smoke 테스트 어디서나 사용 가능.
struct ModifierSlot: Identifiable, Equatable {
    let id: UUID
    let keyCode: Int64
    var label: String

    static func label(for keyCode: Int64, style: KeyboardLegendStyle = .mac) -> String {
        switch Int(keyCode) {
        case kVK_Function: return "Fn"
        case kVK_Control: return "Ctrl"
        case kVK_Option: return style == .windows ? "Alt" : "Opt"
        case kVK_Command: return style == .windows ? "Win" : "Cmd"
        case kVK_Shift: return "Shift"
        case kVK_RightCommand: return style == .windows ? "RWin" : "RCmd"
        case kVK_RightOption: return style == .windows ? "RAlt" : "ROpt"
        case kVK_RightControl: return "RCtrl"
        case kVK_RightShift: return "RShift"
        case kVK_CapsLock: return "Caps"
        default: return "0x\(String(keyCode, radix: 16, uppercase: true))"
        }
    }

    static func detailedLabel(for keyCode: Int64, style: KeyboardLegendStyle = .mac) -> String {
        let primary = label(for: keyCode, style: style)
        let macLabel = label(for: keyCode, style: .mac)
        if style == .windows && primary != macLabel {
            return "\(primary) (\(macLabel))"
        }
        return primary
    }

    static func secondaryLabel(for keyCode: Int64, style: KeyboardLegendStyle = .mac) -> String? {
        guard style == .windows else { return nil }
        switch Int(keyCode) {
        case kVK_Command: return "Cmd 입력"
        case kVK_Option: return "Opt 입력"
        case kVK_RightCommand: return "RCmd 입력"
        case kVK_RightOption: return "ROpt 입력"
        default: return nil
        }
    }
}

enum KeyboardLegendStyle: String, Codable, CaseIterable, Hashable {
    case mac
    case windows

    var title: String {
        switch self {
        case .mac: return "Mac 키보드"
        case .windows: return "Windows 키보드"
        }
    }

    var keyLegendSummary: String {
        switch self {
        case .mac: return "Ctrl · Opt · Cmd · Fn"
        case .windows: return "Ctrl · Win · Alt · Fn"
        }
    }
}

/// v1.8.0 — 키보드 물리 형태 분류 (위자드 v2 의 핵심 mental model 단위).
/// 사용자가 자기 키보드의 실제 키캡 배열을 선택 → 위자드 표가 그에 맞춰 자동 구성된다.
/// 옵셔널이라 기존 v1.7.x 프로필 (= layout 정보 없음) 도 정상 로드 (Codable 호환).
enum KeyboardLayout: String, Codable, CaseIterable, Hashable {
    /// 맥북 내장 또는 외장 4키 Mac (Fn · Ctrl · Opt · Cmd)
    case mac4key
    case portableMac4key
    /// 외장 Mac 3키 (Ctrl · Opt · Cmd) — Apple Magic Keyboard, Keychron K6 등
    case mac3key
    /// 외장 Windows 3키 (Ctrl · Win · Alt) — 일반 PC 키보드
    case win3key
    /// 외장 Windows 4키 (Fn · Ctrl · Win · Alt) — 일부 노트북식 키캡
    case win4key
    /// 사용자가 직접 슬롯·매핑을 정의 (v1.7.x 이전 호환 + 비표준 키보드)
    case custom

    var title: String {
        switch self {
        case .mac4key: return "맥북 내장 (Fn · Ctrl · Opt · Cmd)"
        case .portableMac4key: return "포터블 Mac 4키 (Ctrl · Fn · Opt · Cmd)"
        case .mac3key: return "외장 Mac 3키 (Ctrl · Opt · Cmd)"
        case .win3key: return "외장 Windows 3키 (Ctrl · Win · Alt)"
        case .win4key: return "외장 Windows 4키 (Fn · Ctrl · Win · Alt)"
        case .custom: return "사용자 정의"
        }
    }

    /// 형태가 결정되면 물리 키캡 (사용자가 보는 라벨) 도 정해진다.
    /// 표의 행 라벨 = 이 배열.
    var physicalKeys: [Int64] {
        switch self {
        case .mac4key: return [Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]
        case .portableMac4key: return [Int64(kVK_Control), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Command)]
        case .mac3key: return [Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]
        case .win3key: return [Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]  // macOS 가 Win 키보드 받을 때: Win→Cmd, Alt→Opt
        case .win4key: return [Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]
        case .custom: return []  // 사용자가 직접 정의
        }
    }

    /// 키캡 표시용 라벨 (사용자가 화면에서 보는 텍스트). physicalKeys 와 같은 순서.
    /// Mac 계열은 Cmd/Opt 그대로, Win 계열은 Win/Alt 로 표기.
    var capLabels: [String] {
        switch self {
        case .mac4key: return ["Fn", "Ctrl", "Opt", "Cmd"]
        case .portableMac4key: return ["Ctrl", "Fn", "Opt", "Cmd"]
        case .mac3key: return ["Ctrl", "Opt", "Cmd"]
        case .win3key: return ["Ctrl", "Win", "Alt"]
        case .win4key: return ["Fn", "Ctrl", "Win", "Alt"]
        case .custom: return []
        }
    }

    var localDefaults: [Int64] {
        switch self {
        case .portableMac4key:
            return [Int64(kVK_Command), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Control)]
        default:
            return physicalKeys
        }
    }

    /// VDI 자동 매핑 default (사용자가 안 만지면 이 값).
    /// **v1.8.1 사용자 명시 (release blocker fix):**
    ///   - 4키: Ctrl · Win · Win · Alt   ← 표준 Windows 4키 배열 (양쪽 Win 키 사용 가능)
    ///   - 3키: Ctrl · Win · Alt          ← 표준 Windows 3키 배열
    /// 룰: 키보드 형태(Mac/Win)와 무관하게, VDI 에서는 **표준 Windows 키 배열** 로 보냄.
    /// 사용자가 Mac 키보드 쓰든 Win 키보드 쓰든 VDI 안에서 Windows 단축키 (Ctrl+C 등) 가 일관되게 동작.
    var vdiDefaults: [Int64] {
        switch self {
        case .mac4key:
            // [Fn, Ctrl, Opt, Cmd] → VDI [Ctrl, Win, Win, Alt]
            return [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)]
        case .portableMac4key:
            return [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)]
        case .mac3key:
            // [Ctrl, Opt, Cmd] → VDI [Ctrl, Win, Alt]
            return [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)]
        case .win3key:
            // [Ctrl, Opt, Cmd] (macOS 가 Win→Cmd/Alt→Opt 매핑) → VDI [Ctrl, Win, Alt]
            return [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)]
        case .win4key:
            // [Fn, Ctrl, Opt, Cmd] → VDI [Ctrl, Win, Win, Alt]
            return [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Command), Int64(kVK_Option)]
        case .custom:
            return []
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
    /// v1.8.0 — 키보드 물리 형태 (3키/4키, Mac/Win 라벨). 옵셔널: 기존 v1.7.x 프로필도 정상 로드.
    /// nil = legacy custom (v1.7.x 이전 위자드로 만든 프로필) — 위자드 v2 에서 편집 시 form 추론.
    var keyboardLayout: KeyboardLayout?
    var physicalKeys: [Int64]
    var localDesiredKeys: [Int64]
    var vdiDesiredKeys: [Int64]
    /// Optional non-left-side key that should act as Fn for 3-key layouts.
    var auxiliaryFnKey: Int64?
    /// Bundle ID for per-app auto-switching (nil = manual activation only)
    var bundleId: String?
    /// Keyboard device identifier for per-device auto-switching
    var deviceIdentifier: KeyboardDeviceIdentifier?

    init(
        id: UUID = UUID(),
        name: String,
        legendStyle: KeyboardLegendStyle = .mac,
        keyboardLayout: KeyboardLayout? = nil,
        physicalKeys: [Int64],
        localDesiredKeys: [Int64],
        vdiDesiredKeys: [Int64]? = nil,
        auxiliaryFnKey: Int64? = nil,
        bundleId: String? = nil,
        deviceIdentifier: KeyboardDeviceIdentifier? = nil
    ) {
        self.id = id
        self.name = name
        self.legendStyle = legendStyle
        self.keyboardLayout = keyboardLayout
        self.physicalKeys = physicalKeys
        self.localDesiredKeys = localDesiredKeys
        self.vdiDesiredKeys = vdiDesiredKeys ?? localDesiredKeys
        self.auxiliaryFnKey = auxiliaryFnKey
        self.bundleId = bundleId
        self.deviceIdentifier = deviceIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case legendStyle
        case keyboardLayout  // v1.8.0
        case physicalKeys
        case localDesiredKeys
        case vdiDesiredKeys
        case desiredKeys
        case auxiliaryFnKey
        case bundleId
        case deviceIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        legendStyle = try container.decodeIfPresent(KeyboardLegendStyle.self, forKey: .legendStyle) ?? .mac
        keyboardLayout = try container.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout)  // v1.8.0, 기존 프로필은 nil
        physicalKeys = try container.decode([Int64].self, forKey: .physicalKeys)
        let legacyDesired = try container.decodeIfPresent([Int64].self, forKey: .desiredKeys)
        localDesiredKeys = try container.decodeIfPresent([Int64].self, forKey: .localDesiredKeys) ?? legacyDesired ?? physicalKeys
        vdiDesiredKeys = try container.decodeIfPresent([Int64].self, forKey: .vdiDesiredKeys) ?? localDesiredKeys
        auxiliaryFnKey = try container.decodeIfPresent(Int64.self, forKey: .auxiliaryFnKey)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        deviceIdentifier = try container.decodeIfPresent(KeyboardDeviceIdentifier.self, forKey: .deviceIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(legendStyle, forKey: .legendStyle)
        try container.encodeIfPresent(keyboardLayout, forKey: .keyboardLayout)  // v1.8.0
        try container.encode(physicalKeys, forKey: .physicalKeys)
        try container.encode(localDesiredKeys, forKey: .localDesiredKeys)
        try container.encode(vdiDesiredKeys, forKey: .vdiDesiredKeys)
        try container.encodeIfPresent(auxiliaryFnKey, forKey: .auxiliaryFnKey)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encodeIfPresent(deviceIdentifier, forKey: .deviceIdentifier)
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

/// P2 — 사용자가 명시적으로 자동 전환 / first-seen prompt 대상에서 제외한
/// 키보드 식별자 집합. 영구 저장 (UserDefaults). VID:PID 기준.
struct IgnoredDevices: Codable, Equatable {
    var devices: Set<KeyboardDeviceIdentifier> = []

    static let empty = IgnoredDevices()
}

/// Profile storage (UserDefaults-backed)
class KeyboardProfileStore: ObservableObject {
    @Published var profiles: [SavedKeyboardProfile] = []
    @Published var ignoredDevices: IgnoredDevices = .empty
    private let storageKey = "savedKeyboardProfiles"
    private let ignoredDevicesKey = "ignoredKeyboardDevices"

    init() {
        load()
        loadIgnoredDevices()
    }

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

    /// Find profile matching a keyboard device for per-device auto-switching
    func profile(forDevice identifier: KeyboardDeviceIdentifier) -> SavedKeyboardProfile? {
        profiles.first {
            guard let device = $0.deviceIdentifier else { return false }
            return device.vendorId == identifier.vendorId && device.productId == identifier.productId
        }
    }

    // MARK: - Ignored devices (P2)

    private func loadIgnoredDevices() {
        if let data = UserDefaults.standard.data(forKey: ignoredDevicesKey),
           let decoded = try? JSONDecoder().decode(IgnoredDevices.self, from: data) {
            ignoredDevices = decoded
        }
    }

    private func saveIgnoredDevices() {
        if let data = try? JSONEncoder().encode(ignoredDevices) {
            UserDefaults.standard.set(data, forKey: ignoredDevicesKey)
        }
    }

    /// 사용자가 first-seen prompt 에서 "Ignore this keyboard" 선택 시.
    /// 같은 VID:PID 가 다시 입력해도 prompt / 자동 전환 모두 하지 않는다.
    func ignore(_ device: KeyboardDeviceIdentifier) {
        ignoredDevices.devices.insert(device)
        saveIgnoredDevices()
    }

    /// "Ignored devices" 메뉴에서 사용자가 명시적으로 해제할 때.
    func unignore(_ device: KeyboardDeviceIdentifier) {
        ignoredDevices.devices.remove(device)
        saveIgnoredDevices()
    }

    func isIgnored(_ device: KeyboardDeviceIdentifier) -> Bool {
        ignoredDevices.devices.contains(device)
    }
}
