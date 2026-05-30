import SwiftUI
import Carbon.HIToolbox

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

/// 키보드 매핑 위자드 (v1.6 재설계) — **캡처 없는 키코드 기반 직접 매핑 표**.
/// macOS 가 모든 키보드를 표준 modifier 키코드(Ctrl/Opt/Cmd/Fn)로 정규화하므로,
/// 물리 키 캡처는 로직적으로 불필요했고 Mac/Win 모드 키보드에선 오히려 깨졌다.
/// → 사용자가 표에서 "각 키를 무엇으로 쓸지" 직접 고른다. 캡처 단계 삭제.
struct ModifierLayoutView: View {
    @EnvironmentObject var appState: AppState

    // 단계: 0=프로필 목록, 1=시작(의도), 2=매핑 표, 3=확인·저장
    @State private var currentStep: Int = 0
    @State private var editingProfileId: UUID? = nil
    @State private var newProfileName: String = ""
    @State private var selectedLegendStyle: KeyboardLegendStyle = .mac
    /// 표 상태: source 키코드 → 사용자가 고른 desired 키코드 (없으면 source 자신=안 바꿈)
    @State private var localTargets: [Int64: Int64] = [:]
    @State private var vdiTargets: [Int64: Int64] = [:]

    /// 표가 다루는 표준 modifier 집합 (macOS 가 모든 키보드를 이 키코드로 정규화).
    private let sourceModifiers: [Int64] = [
        Int64(kVK_Function),
        Int64(kVK_Control),
        Int64(kVK_Option),
        Int64(kVK_Command)
    ]
    private let macLocalChoices: [Int64] = [
        Int64(kVK_Command), Int64(kVK_Function), Int64(kVK_Option), Int64(kVK_Control)
    ]
    private let vdiChoices: [Int64] = [
        Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)  // Ctrl · Win · Alt
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch currentStep {
            case 0: profileListView
            case 1: startIntentView
            case 2: mappingTableView
            case 3: confirmSaveView
            default: EmptyView()
            }
        }
        .padding(16)
    }

    // MARK: - Step 0 · 프로필 목록

    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("키보드 프로필").font(.title3).bold()
                Spacer()
                Button {
                    startNewProfile()
                } label: {
                    Label("새 프로필 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if appState.profileStore.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("저장된 프로필이 없습니다").font(.subheadline)
                    Text("새 프로필을 만들어 엔진을 켤 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.profileStore.profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: SavedKeyboardProfile) -> some View {
        let isActive = appState.activeMappingProfileId == profile.id.uuidString
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name).font(.subheadline).bold()
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Capsule()).foregroundStyle(.green)
                    }
                }
                Text(profile.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("편집") { startEditing(profile) }
                .buttonStyle(.bordered).controlSize(.small)
            Button("적용") { appState.applyProfile(profile) }
                .buttonStyle(.bordered).controlSize(.small).disabled(isActive)
            Button { appState.deleteProfileSafely(profile) } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 1 · 시작 (의도 선택)

    private var startIntentView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("어떻게 쓸까요?").font(.title3).bold()
            VStack(alignment: .leading, spacing: 4) {
                Text("프로필 이름").font(.caption).foregroundStyle(.secondary)
                TextField("예: 내 키보드", text: $newProfileName).textFieldStyle(.roundedBorder)
            }
            VStack(spacing: 10) {
                intentCard(
                    icon: "globe",
                    color: .green,
                    title: "한/영 전환만",
                    detail: "키 배치는 그대로. Right Command 로 한/영만 전환합니다. (캡처 없이 바로 완료)",
                    action: { quickCreateKoreanOnlyAndDone() }
                )
                intentCard(
                    icon: "slider.horizontal.3",
                    color: .blue,
                    title: "키 배치도 바꾸기",
                    detail: "각 키를 어떤 키로 쓸지 표에서 고릅니다. 어떤 키보드든 동일하게 동작.",
                    action: { currentStep = 2 }
                )
            }
            Spacer(minLength: 0)
            HStack {
                Button("← 취소") { cancelWizard() }.buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private func intentCard(icon: String, color: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2 · 매핑 표

    private var mappingTableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("키 배치 정하기").font(.title3).bold()
            Text("각 키를 어떤 키로 쓸지 고르세요. 안 바꾸려면 \"바꾸지 않음\". macOS 가 모든 키보드를 같은 키코드로 보고하므로 누를 필요 없습니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text("키캡 표기:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $selectedLegendStyle) {
                    Text("Mac (Cmd/Opt)").tag(KeyboardLegendStyle.mac)
                    Text("Windows (Win/Alt)").tag(KeyboardLegendStyle.windows)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()
                Spacer()
                Button("Windows 감각") { applyWindowsFeelPreset() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Mac 에서 Cmd↔Ctrl 스왑 (Windows 단축키 감각).")
                Button("초기화") {
                    localTargets.removeAll()
                    vdiTargets.removeAll()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            HStack(spacing: 0) {
                Text("키").frame(width: 80, alignment: .leading)
                Text("Mac 에서").frame(width: 180, alignment: .leading)
                Text("VDI (Windows) 에서").frame(width: 200, alignment: .leading)
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(sourceModifiers, id: \.self) { source in
                    mappingRow(source: source)
                }
            }

            Divider()
            HStack(spacing: 10) {
                Text("미리보기").font(.caption).foregroundStyle(.secondary)
                Text(mappingPreview()).font(.caption.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            HStack {
                Button("← 뒤로") { currentStep = 1 }.buttonStyle(.bordered)
                Spacer()
                Button("다음 →") { currentStep = 3 }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func mappingRow(source: Int64) -> some View {
        let macTarget = localTargets[source] ?? source
        let vdiTarget = vdiTargets[source] ?? source
        let changed = (macTarget != source) || (vdiTarget != source)
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(ModifierSlot.label(for: source, style: selectedLegendStyle))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("→").foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            mappingPicker(
                current: macTarget, source: source,
                choices: macLocalChoices, style: selectedLegendStyle
            ) { localTargets[source] = $0 }
                .frame(width: 180, alignment: .leading)

            mappingPicker(
                current: vdiTarget, source: source,
                choices: vdiChoices, style: .windows
            ) { vdiTargets[source] = $0 }
                .frame(width: 200, alignment: .leading)

            Spacer()
        }
        .padding(8)
        .background(changed ? Color.blue.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func mappingPicker(
        current: Int64,
        source: Int64,
        choices: [Int64],
        style: KeyboardLegendStyle,
        onPick: @escaping (Int64) -> Void
    ) -> some View {
        Menu {
            Button("바꾸지 않음 (\(ModifierSlot.label(for: source, style: style)))") { onPick(source) }
            Divider()
            ForEach(choices, id: \.self) { choice in
                Button(ModifierSlot.label(for: choice, style: style)) { onPick(choice) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(ModifierSlot.label(for: current, style: style))
                    .foregroundStyle(current == source ? .secondary : .primary)
                if current != source {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6)).foregroundStyle(.blue)
                }
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func mappingPreview() -> String {
        let parts = sourceModifiers.compactMap { source -> String? in
            let mac = localTargets[source] ?? source
            let vdi = vdiTargets[source] ?? source
            guard mac != source || vdi != source else { return nil }
            let s = ModifierSlot.label(for: source, style: selectedLegendStyle)
            let m = ModifierSlot.label(for: mac, style: selectedLegendStyle)
            let v = ModifierSlot.label(for: vdi, style: .windows)
            return "\(s)→\(m)|\(v)"
        }
        return parts.isEmpty ? "변경 없음 (한/영 전환만)" : parts.joined(separator: "   ")
    }

    // MARK: - Step 3 · 확인·저장

    private var confirmSaveView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("확인하고 저장").font(.title3).bold()
            VStack(alignment: .leading, spacing: 4) {
                Text("프로필 이름").font(.caption).foregroundStyle(.secondary)
                TextField("프로필 이름", text: $newProfileName).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("매핑 요약").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sourceModifiers, id: \.self) { source in
                        let mac = localTargets[source] ?? source
                        let vdi = vdiTargets[source] ?? source
                        let changed = (mac != source) || (vdi != source)
                        HStack(spacing: 6) {
                            Text(ModifierSlot.label(for: source, style: selectedLegendStyle))
                                .frame(width: 50, alignment: .leading).font(.caption.monospaced())
                            Text("→").foregroundStyle(.secondary).font(.caption)
                            Text("Mac: \(ModifierSlot.label(for: mac, style: selectedLegendStyle))")
                                .frame(width: 100, alignment: .leading).font(.caption.monospaced())
                            Text("VDI: \(ModifierSlot.label(for: vdi, style: .windows))")
                                .frame(width: 100, alignment: .leading).font(.caption.monospaced())
                            if changed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green).font(.caption2)
                            } else {
                                Text("(안 바꿈)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
            HStack {
                Button("← 뒤로") { currentStep = 2 }.buttonStyle(.bordered)
                Spacer()
                Button(editingProfileId == nil ? "저장하고 적용" : "변경 저장") { saveAndClose() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Actions / Helpers

    private func startNewProfile() {
        cancelWizard()
        currentStep = 1
    }

    private func startEditing(_ profile: SavedKeyboardProfile) {
        editingProfileId = profile.id
        newProfileName = profile.name
        selectedLegendStyle = profile.legendStyle
        localTargets.removeAll()
        vdiTargets.removeAll()
        for (i, source) in profile.physicalKeys.enumerated() {
            if i < profile.localDesiredKeys.count {
                let target = profile.localDesiredKeys[i]
                if target != source { localTargets[source] = target }
            }
            if i < profile.vdiDesiredKeys.count {
                let target = profile.vdiDesiredKeys[i]
                if target != source { vdiTargets[source] = target }
            }
        }
        currentStep = 2
    }

    private func cancelWizard() {
        currentStep = 0
        editingProfileId = nil
        newProfileName = ""
        selectedLegendStyle = .mac
        localTargets.removeAll()
        vdiTargets.removeAll()
    }

    private func quickCreateKoreanOnlyAndDone() {
        if newProfileName.trimmingCharacters(in: .whitespaces).isEmpty {
            newProfileName = "한/영 전환만"
        }
        localTargets.removeAll()
        vdiTargets.removeAll()
        saveAndClose()
    }

    /// Windows 단축키 감각: Mac 에서 Cmd↔Ctrl 스왑 (복붙·저장 등이 Win 키보드처럼).
    private func applyWindowsFeelPreset() {
        localTargets[Int64(kVK_Command)] = Int64(kVK_Control)
        localTargets[Int64(kVK_Control)] = Int64(kVK_Command)
    }

    private func saveAndClose() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let localDesired = sourceModifiers.map { localTargets[$0] ?? $0 }
        let vdiDesired = sourceModifiers.map { vdiTargets[$0] ?? $0 }
        if let editingId = editingProfileId,
           var existing = appState.profileStore.profiles.first(where: { $0.id == editingId }) {
            existing.name = name
            existing.legendStyle = selectedLegendStyle
            existing.physicalKeys = sourceModifiers
            existing.localDesiredKeys = localDesired
            existing.vdiDesiredKeys = vdiDesired
            // 옵셔널 3필드(auxiliaryFnKey · bundleId · deviceIdentifier) 는 보존 정책 통일:
            // 새 표 위자드는 이 필드들을 UI 에 노출하지 않으므로 편집 시 기존 값을 그대로 둔다.
            // (auxiliaryFnKey 를 silent nil 처리하던 회귀를 제거 — 사용자 데이터 손실 차단.)
            //  - auxiliaryFnKey 변경하려면 프로필 삭제 후 재생성
            //  - bundleId / deviceIdentifier 는 Profiles 탭의 별도 UI (Bind keyboard…) 에서 관리
            appState.profileStore.update(existing)
            appState.applyProfile(existing)
        } else {
            let profile = SavedKeyboardProfile(
                name: name,
                legendStyle: selectedLegendStyle,
                physicalKeys: sourceModifiers,
                localDesiredKeys: localDesired,
                vdiDesiredKeys: vdiDesired
            )
            appState.profileStore.add(profile)
            appState.applyProfile(profile)
        }
        cancelWizard()
    }
}

#Preview {
    ModifierLayoutView()
        .environmentObject(AppState())
        .frame(width: 680, height: 540)
}
