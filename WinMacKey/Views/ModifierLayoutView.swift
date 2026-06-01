import SwiftUI
import Carbon.HIToolbox

// ModifierSlot 은 v1.8.0 에서 WinMacKey/Models/ModifierSlot.swift 로 분리 (Profile.summary 가 비-SwiftUI
// 환경에서도 사용 가능하도록). 행위 동일.

/// 위자드 의도 카드 (v1.8.0)
private enum WizardIntent {
    case koreanOnly   // 모든 키 identity, 한/영 전환만
    case customize    // 사용자 정의 매핑
}

/// 바인딩 스코프 (v1.8.0)
private enum BindingScope {
    case thisKeyboardAuto  // 이 키보드 자동 바인딩 (저장 후 외장 식별)
    case allKeyboards      // 모든 키보드 (기본 프로필)
    case decideLater       // Profiles 탭에서 결정
}

/// 키보드 매핑 위자드 (v1.8.0 — 키보드 형태 + 의도 mental model)
///
/// 핵심 개선:
///   - **물리 키캡 → 동작** 매핑 (사용자 직관)
///   - 키보드 형태 선택 → 행 자동 구성 (3키/4키, Mac/Win 라벨)
///   - VDI default 자동 (사용자가 안 만져도 됨, 고급에서 직접 편집)
///   - "바꾸지 않음" 명시적 (회색 "(기본)" 표기)
///   - 외장 키보드 자동 바인딩 옵션
///
/// 호환: 기존 v1.7.x 프로필 (`keyboardLayout = nil`) 도 정상 로드/편집 가능.
struct ModifierLayoutView: View {
    @EnvironmentObject var appState: AppState

    // 단계: 0=프로필 목록, 1=시작(라디오), 2=매핑 표, 3=확인·저장
    @State private var currentStep: Int = 0
    @State private var editingProfileId: UUID? = nil
    @State private var newProfileName: String = ""
    @State private var selectedLayout: KeyboardLayout = .mac4key
    @State private var selectedIntent: WizardIntent = .koreanOnly
    /// 사용자가 변경한 Mac 매핑. nil(없음) = "안 바꿈".
    @State private var localMappings: [Int64: Int64] = [:]
    /// 사용자가 직접 편집한 VDI 매핑. nil(없음) = layout.vdiDefaults 사용.
    @State private var vdiOverrides: [Int64: Int64] = [:]
    @State private var bindingScope: BindingScope = .thisKeyboardAuto
    @State private var showVDIAdvanced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch currentStep {
            case 0: profileListView
            case 1: startView
            case 2: mappingTableView
            case 3: confirmSaveView
            default: EmptyView()
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)  // v1.8.0 — 윈도우 너비 확보 (잘림 방지)
    }

    // MARK: - Step 0 · 프로필 목록

    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("키보드 프로필").font(.title3).bold()
                Spacer()
                Button { startNewProfile() } label: {
                    Label("새 프로필 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if appState.profileStore.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(.secondary)
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
                    if let layout = profile.keyboardLayout {
                        Text(layoutBadge(layout))
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if isActive {
                        Text("Active").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2)).clipShape(Capsule()).foregroundStyle(.green)
                    }
                }
                Text(profile.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("편집") { startEditing(profile) }.buttonStyle(.bordered).controlSize(.small)
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

    private func layoutBadge(_ layout: KeyboardLayout) -> String {
        switch layout {
        case .mac4key: return "Mac 4키"
        case .mac3key: return "Mac 3키"
        case .win3key: return "Win 3키"
        case .win4key: return "Win 4키"
        case .custom:  return "Custom"
        }
    }

    // MARK: - Step 1 · 시작 (키보드 형태 + 의도)

    private var startView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("새 프로필 만들기").font(.title3).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("프로필 이름").font(.caption).foregroundStyle(.secondary)
                TextField("예: 내 키보드", text: $newProfileName).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("키보드 형태").font(.caption).foregroundStyle(.secondary)
                ForEach(KeyboardLayout.allCases.filter { $0 != .custom }, id: \.self) { layout in
                    radioRow(layout.title, selected: selectedLayout == layout) {
                        selectedLayout = layout
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("어떻게 쓸까?").font(.caption).foregroundStyle(.secondary)
                radioRow("한/영 전환만  (키 배치 그대로, 1클릭 완료)",
                         selected: selectedIntent == .koreanOnly) {
                    selectedIntent = .koreanOnly
                }
                radioRow("키 배치 바꾸기  (다음 화면 표에서 직접)",
                         selected: selectedIntent == .customize) {
                    selectedIntent = .customize
                }
            }

            Spacer(minLength: 0)
            HStack {
                Button("← 취소") { cancelWizard() }.buttonStyle(.bordered)
                Spacer()
                Button("다음 →") {
                    if selectedIntent == .koreanOnly {
                        currentStep = 3  // 매핑 표 건너뛰고 바로 확인
                    } else {
                        currentStep = 2
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func radioRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title).font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4).padding(.horizontal, 6)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2 · 매핑 표 (적응형)

    private var mappingTableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("키 배치").font(.title3).bold()
            Text("바꿀 키만 골라요. 안 만지면 그대로 (\"기본\"). VDI 는 자동으로 표준 Windows 키 배열로 보냅니다.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            // 헤더
            HStack(spacing: 0) {
                Text("내 키캡").frame(width: 90, alignment: .leading)
                Text("Mac 에서").frame(width: 220, alignment: .leading)
                Text("VDI (자동)").frame(width: 130, alignment: .leading)
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            // 행 — 키보드 형태에 따라 동적
            VStack(spacing: 4) {
                ForEach(Array(selectedLayout.physicalKeys.enumerated()), id: \.offset) { idx, sourceKey in
                    mappingRow(
                        sourceKey: sourceKey,
                        capLabel: selectedLayout.capLabels[idx],
                        vdiDefault: selectedLayout.vdiDefaults[idx],
                        legendStyle: layoutLegend(selectedLayout)
                    )
                }
            }

            // VDI 직접 편집 (접힘, 고급)
            DisclosureGroup(isExpanded: $showVDIAdvanced) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VDI 측은 보통 자동 default 가 정답입니다. 정말 필요한 경우만 변경하세요.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(Array(selectedLayout.physicalKeys.enumerated()), id: \.offset) { idx, sourceKey in
                        vdiOverrideRow(
                            sourceKey: sourceKey,
                            capLabel: selectedLayout.capLabels[idx],
                            vdiDefault: selectedLayout.vdiDefaults[idx]
                        )
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("VDI 매핑 직접 편집 (고급)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack {
                Button("← 뒤로") { currentStep = 1 }.buttonStyle(.bordered)
                Button("초기화") {
                    localMappings.removeAll()
                    vdiOverrides.removeAll()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("다음 →") { currentStep = 3 }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func mappingRow(sourceKey: Int64, capLabel: String, vdiDefault: Int64, legendStyle: KeyboardLegendStyle) -> some View {
        let macTarget = localMappings[sourceKey] ?? sourceKey
        let isDefault = (localMappings[sourceKey] == nil)
        let macChoices: [Int64] = [
            Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)
        ]
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(capLabel).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("→").foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .leading)

            Menu {
                Button("바꾸지 않음 (기본)") { localMappings[sourceKey] = nil }
                Divider()
                ForEach(macChoices, id: \.self) { choice in
                    Button(ModifierSlot.label(for: choice, style: .mac)) {
                        localMappings[sourceKey] = choice
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if isDefault {
                        Text("\(capLabel)  (기본 — 안 바꿈)").foregroundStyle(.secondary)
                    } else {
                        Text(ModifierSlot.label(for: macTarget, style: .mac))
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.blue)
                    }
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 220, alignment: .leading)

            Text(ModifierSlot.label(for: vdiOverrides[sourceKey] ?? vdiDefault, style: .windows))
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(isDefault ? Color.clear : Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func vdiOverrideRow(sourceKey: Int64, capLabel: String, vdiDefault: Int64) -> some View {
        let vdiTarget = vdiOverrides[sourceKey] ?? vdiDefault
        let isDefault = (vdiOverrides[sourceKey] == nil)
        let vdiChoices: [Int64] = [
            Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)  // Ctrl·Win·Alt
        ]
        return HStack(spacing: 0) {
            Text("\(capLabel) → VDI").frame(width: 100, alignment: .leading).font(.caption)
            Menu {
                Button("자동 (기본)") { vdiOverrides[sourceKey] = nil }
                Divider()
                ForEach(vdiChoices, id: \.self) { choice in
                    Button(ModifierSlot.label(for: choice, style: .windows)) {
                        vdiOverrides[sourceKey] = choice
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isDefault
                         ? "\(ModifierSlot.label(for: vdiTarget, style: .windows))  (기본)"
                         : ModifierSlot.label(for: vdiTarget, style: .windows))
                        .foregroundStyle(isDefault ? .secondary : .primary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
        .padding(.vertical, 2).padding(.horizontal, 12)
    }

    // MARK: - Step 3 · 확인·저장

    private var confirmSaveView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("확인하고 저장").font(.title3).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("프로필 이름").font(.caption).foregroundStyle(.secondary)
                TextField("프로필 이름", text: $newProfileName).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("미리보기 — \(selectedLayout.title)").font(.caption).foregroundStyle(.secondary)
                if selectedIntent == .koreanOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "globe").foregroundStyle(.green)
                        Text("한/영 전환만 (모든 키 그대로)").font(.callout)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(selectedLayout.physicalKeys.enumerated()), id: \.offset) { idx, sourceKey in
                            let cap = selectedLayout.capLabels[idx]
                            let macTarget = localMappings[sourceKey] ?? sourceKey
                            let vdiTarget = vdiOverrides[sourceKey] ?? selectedLayout.vdiDefaults[idx]
                            let changed = (localMappings[sourceKey] != nil) || (vdiOverrides[sourceKey] != nil)
                            HStack(spacing: 6) {
                                Text(cap).frame(width: 50, alignment: .leading).font(.caption.monospaced())
                                Text("→").foregroundStyle(.secondary).font(.caption2)
                                Text("Mac: \(ModifierSlot.label(for: macTarget, style: .mac))")
                                    .frame(width: 100, alignment: .leading).font(.caption.monospaced())
                                Text("VDI: \(ModifierSlot.label(for: vdiTarget, style: .windows))")
                                    .frame(width: 100, alignment: .leading).font(.caption.monospaced())
                                if changed {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("저장 후 어디에 적용?").font(.caption).foregroundStyle(.secondary)
                radioRow("이 키보드에만  (외장 자동 바인딩 — 첫 입력 시 식별)",
                         selected: bindingScope == .thisKeyboardAuto) {
                    bindingScope = .thisKeyboardAuto
                }
                radioRow("모든 키보드  (기본 프로필)",
                         selected: bindingScope == .allKeyboards) {
                    bindingScope = .allKeyboards
                }
                radioRow("나중에 결정  (Profiles 탭에서 직접 바인딩)",
                         selected: bindingScope == .decideLater) {
                    bindingScope = .decideLater
                }
            }

            Spacer(minLength: 0)
            HStack {
                Button("← 뒤로") {
                    currentStep = (selectedIntent == .koreanOnly) ? 1 : 2
                }.buttonStyle(.bordered)
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
        // 1) layout 추론 (legacy 호환)
        if let savedLayout = profile.keyboardLayout {
            selectedLayout = savedLayout
        } else {
            selectedLayout = inferLayout(from: profile)
        }
        // 2) 의도 추론
        let isIdentity = profile.localDesiredKeys == profile.physicalKeys &&
                         profile.vdiDesiredKeys == profile.physicalKeys
        selectedIntent = isIdentity ? .koreanOnly : .customize
        // 3) 사용자 매핑 복원
        localMappings.removeAll()
        vdiOverrides.removeAll()
        for (i, source) in profile.physicalKeys.enumerated() {
            if i < profile.localDesiredKeys.count {
                let target = profile.localDesiredKeys[i]
                if target != source { localMappings[source] = target }
            }
        }
        // VDI overrides 는 layout.vdiDefaults 와 다를 때만 저장
        let defaults = selectedLayout.vdiDefaults
        if defaults.count == profile.vdiDesiredKeys.count {
            for (i, source) in profile.physicalKeys.enumerated() {
                let target = profile.vdiDesiredKeys[i]
                if i < defaults.count, target != defaults[i] {
                    vdiOverrides[source] = target
                }
            }
        }
        currentStep = 2
    }

    private func inferLayout(from profile: SavedKeyboardProfile) -> KeyboardLayout {
        let keys = profile.physicalKeys
        let hasFn = keys.contains(Int64(kVK_Function))
        switch (profile.legendStyle, hasFn) {
        case (.mac, true):     return .mac4key
        case (.mac, false):    return .mac3key
        case (.windows, true): return .win4key
        case (.windows, false):return .win3key
        }
    }

    private func cancelWizard() {
        currentStep = 0
        editingProfileId = nil
        newProfileName = ""
        selectedLayout = .mac4key
        selectedIntent = .koreanOnly
        localMappings.removeAll()
        vdiOverrides.removeAll()
        bindingScope = .thisKeyboardAuto
        showVDIAdvanced = false
    }

    private func layoutLegend(_ layout: KeyboardLayout) -> KeyboardLegendStyle {
        switch layout {
        case .mac4key, .mac3key: return .mac
        case .win3key, .win4key: return .windows
        case .custom: return .mac
        }
    }

    private func saveAndClose() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let physicalKeys = selectedLayout.physicalKeys
        let localDesired: [Int64]
        let vdiDesired: [Int64]

        if selectedIntent == .koreanOnly {
            localDesired = physicalKeys  // identity
            vdiDesired = physicalKeys
        } else {
            localDesired = physicalKeys.map { localMappings[$0] ?? $0 }
            let defaults = selectedLayout.vdiDefaults
            vdiDesired = physicalKeys.enumerated().map { idx, source in
                vdiOverrides[source] ?? (idx < defaults.count ? defaults[idx] : source)
            }
        }

        // 바인딩 스코프 → deviceIdentifier 자동 설정
        let lastActiveDevice = appState.lastActiveKeyboard
        let deviceId: KeyboardDeviceIdentifier? = {
            switch bindingScope {
            case .thisKeyboardAuto: return lastActiveDevice  // 마지막 활성 외장 자동 바인딩
            case .allKeyboards:     return nil               // 기본 프로필
            case .decideLater:      return nil
            }
        }()

        if let editingId = editingProfileId,
           var existing = appState.profileStore.profiles.first(where: { $0.id == editingId }) {
            existing.name = name
            existing.legendStyle = layoutLegend(selectedLayout)
            existing.keyboardLayout = selectedLayout
            existing.physicalKeys = physicalKeys
            existing.localDesiredKeys = localDesired
            existing.vdiDesiredKeys = vdiDesired
            // bindingScope 가 명시되면 deviceIdentifier 갱신, 아니면 보존
            if bindingScope != .decideLater {
                existing.deviceIdentifier = deviceId
            }
            appState.profileStore.update(existing)
            appState.applyProfile(existing)
        } else {
            let profile = SavedKeyboardProfile(
                name: name,
                legendStyle: layoutLegend(selectedLayout),
                keyboardLayout: selectedLayout,
                physicalKeys: physicalKeys,
                localDesiredKeys: localDesired,
                vdiDesiredKeys: vdiDesired,
                deviceIdentifier: deviceId
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
