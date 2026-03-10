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

struct ModifierLayoutView: View {
    @EnvironmentObject var appState: AppState

    @State private var currentStep: Int = 0 // 0=프로필 목록, 1=표기, 2=현재 입력, 3=Mac 로컬, 4=VDI, 5=검증
    @State private var selectedLegendStyle: KeyboardLegendStyle = .mac
    @State private var physicalKeys: [Int64] = []
    @State private var localDesiredKeys: [Int64] = []
    @State private var vdiDesiredKeys: [Int64] = []
    @State private var auxiliaryFnKey: Int64? = nil

    @State private var verifyResults: [Int64: Bool] = [:]
    @State private var verifyLogs: [(keyCode: Int64, label: String, pass: Bool)] = []
    @State private var auxiliaryFnVerified = false

    @State private var showSaveDialog = false
    @State private var newProfileName = ""

    private let leftSideChoices: [Int64] = [
        Int64(kVK_Function),
        Int64(kVK_Control),
        Int64(kVK_Command),
        Int64(kVK_Option)
    ]
    private let minimumPhysicalKeyCount = 3
    private let maximumPhysicalKeyCount = 4
    private let auxiliaryFnCandidates: [Int64] = [
        Int64(kVK_RightControl),
        Int64(kVK_CapsLock),
        Int64(kVK_RightShift)
    ]

    private var currentVerificationContext: KeyboardUsageContext {
        appState.isVdiMode ? .vdi : .localMac
    }

    private var currentVerificationDesiredKeys: [Int64] {
        desiredKeys(for: currentVerificationContext)
    }

    private var configuredSlotCount: Int {
        physicalKeys.count
    }

    private var shouldOfferAuxiliaryFnKey: Bool {
        configuredSlotCount == 3
            && !localDesiredKeys.contains(Int64(kVK_Function))
            && !vdiDesiredKeys.contains(Int64(kVK_Function))
    }

    private var physicalCaptureHint: String {
        switch physicalKeys.count {
        case ..<minimumPhysicalKeyCount:
            return "스페이스바 왼쪽 modifier를 왼쪽부터 계속 눌러 주세요. 최소 3개가 필요합니다."
        case minimumPhysicalKeyCount:
            return "3키 감지가 끝났습니다. 여기서 다음으로 가거나, 4키 키보드라면 마지막 키를 한 번 더 눌러 주세요."
        default:
            return "4키 감지가 끝났습니다."
        }
    }

    private var legendGuideText: String {
        switch selectedLegendStyle {
        case .mac:
            return "Mac 표기는 Ctrl / Opt / Cmd / Fn 기준으로 안내합니다."
        case .windows:
            return "Windows 표기는 Ctrl / Win / Alt / Fn 기준으로 안내합니다. 내부적으로 Win=Cmd, Alt=Opt로 저장됩니다."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch currentStep {
            case 0: profileSelectorView
            case 1: shapeSetupView
            case 2: physicalInputView
            case 3: localMappingView
            case 4: vdiMappingView
            case 5: verificationView
            default: EmptyView()
            }
        }
        .onDisappear {
            appState.keyInterceptor.onVerifyKeyEvent = nil
            if currentStep != 0 {
                appState.refreshActiveProfileForCurrentContext()
            }
        }
        .sheet(isPresented: $showSaveDialog) {
            saveProfileSheet
        }
    }

    private var profileSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("키보드 레이아웃 프로필")
                .font(.headline)

            if appState.profileStore.profiles.isEmpty {
                VStack(spacing: 8) {
                    Text("저장된 프로필이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("새 프로필을 만들어 로컬 Mac과 VDI 배치를 각각 설정하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.profileStore.profiles) { profile in
                        profileRow(profile)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
            }

            HStack {
                Button("매핑 초기화") {
                    appState.activeMappingProfileId = "standardMac"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    startWizard()
                } label: {
                    Label("새 프로필 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func profileRow(_ profile: SavedKeyboardProfile) -> some View {
        let isActive = appState.activeMappingProfileId == profile.id.uuidString

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(.body, weight: isActive ? .semibold : .regular))
                    Text(profile.legendStyle.title)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(6)
                }
                Text(profile.summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            Button(isActive ? "사용 중" : "적용") {
                appState.applyProfile(profile)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isActive)

            Button {
                appState.profileStore.delete(id: profile.id)
                if isActive {
                    appState.activeMappingProfileId = "standardMac"
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.08) : Color.clear)
        .cornerRadius(8)
    }

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            stepDot(step: 1, title: "표기")
            stepDot(step: 2, title: "현재 입력")
            stepDot(step: 3, title: "Mac 로컬")
            stepDot(step: 4, title: "VDI")
            stepDot(step: 5, title: "검증")
        }
        .frame(maxWidth: .infinity)
    }

    private func stepDot(step: Int, title: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 28, height: 28)
                Text("\(step)")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(step <= currentStep ? .primary : .secondary)
        }
    }

    private var shapeSetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("키캡 표기 기준만 먼저 선택하세요")
                    .font(.subheadline)
                Text("다음 단계에서 스페이스바 왼쪽 modifier를 실제로 눌러 현재 입력을 감지합니다. 3키/4키는 입력된 개수로 자동 판단합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                legendStyleCard(
                    style: .mac,
                    title: "Mac 키보드 표기",
                    detail: "Ctrl · Opt · Cmd · Fn"
                )
                legendStyleCard(
                    style: .windows,
                    title: "Windows / VDI 표기",
                    detail: "Ctrl · Win · Alt · Fn"
                )
            }

            Text(legendGuideText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("← 취소") {
                    cancelWizard()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("다음 →") {
                    beginPhysicalKeyCapture()
                    currentStep = 2
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func legendStyleCard(style: KeyboardLegendStyle, title: String, detail: String) -> some View {
        let isSelected = selectedLegendStyle == style

        return Button {
            selectedLegendStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var physicalInputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("현재 키보드의 스페이스바 왼쪽 modifier를 실제로 눌러 주세요")
                    .font(.subheadline)
                Text("왼쪽부터 순서대로 누르면 현재 입력 배열을 기록합니다. 3개를 누르면 다음으로 갈 수 있고, 4키 키보드라면 마지막 키를 한 번 더 누르세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(legendGuideText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            slotSelectionCard(
                title: "현재 입력 감지",
                selections: physicalKeys,
                total: maximumPhysicalKeyCount,
                emptyTitle: "대기"
            )
            Text(physicalCaptureHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack {
                Button("← 이전") {
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    currentStep = 1
                }
                .buttonStyle(.bordered)

                Button("한 칸 지우기") {
                    _ = physicalKeys.popLast()
                    if physicalKeys.count < maximumPhysicalKeyCount {
                        auxiliaryFnKey = nil
                    }
                }
                .buttonStyle(.bordered)
                .disabled(physicalKeys.isEmpty)

                Button("초기화") {
                    physicalKeys = []
                    auxiliaryFnKey = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("다음 →") {
                    syncSelectionBuffersWithPhysicalKeys()
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    currentStep = 3
                }
                .buttonStyle(.borderedProminent)
                .disabled(physicalKeys.count < minimumPhysicalKeyCount)
            }
        }
    }

    private var localMappingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("로컬 macOS에서 원하는 배치를 왼쪽부터 순서대로 선택하세요")
                    .font(.subheadline)
                Text("현재 입력: \(formattedLabels(physicalKeys))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            presetButtons(for: .local)
            slotSelectionCard(
                title: "Mac 로컬 목표",
                selections: localDesiredKeys,
                total: configuredSlotCount
            )
            mappingPreviewCard(
                title: "Mac 로컬 미리보기",
                source: physicalKeys,
                target: localDesiredKeys
            )
            selectionPalette(
                selections: localDesiredKeys,
                choices: leftSideChoices,
                onSelect: selectLocalDesiredKey
            )

            HStack {
                Button("← 이전") {
                    beginPhysicalKeyCapture()
                    currentStep = 2
                }
                .buttonStyle(.bordered)

                Button("한 칸 지우기") {
                    _ = localDesiredKeys.popLast()
                }
                .buttonStyle(.bordered)
                .disabled(localDesiredKeys.isEmpty)

                Button("초기화") {
                    localDesiredKeys = []
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("다음 →") {
                    currentStep = 4
                }
                .buttonStyle(.borderedProminent)
                .disabled(localDesiredKeys.count != configuredSlotCount)
            }
        }
    }

    private var vdiMappingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Windows VDI 안에서 원하는 배치를 왼쪽부터 순서대로 선택하세요")
                    .font(.subheadline)
                Text("현재 입력: \(formattedLabels(physicalKeys))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("VDI 단계는 비어 있는 상태로 시작합니다. 로컬 Mac과 같게 쓰고 싶을 때만 복사 버튼을 사용하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Mac 로컬 배치 복사") {
                    vdiDesiredKeys = localDesiredKeys
                }
                .buttonStyle(ChipButtonStyle(tint: .blue))

                Spacer()
            }

            presetButtons(for: .vdi)
            slotSelectionCard(
                title: "VDI 목표",
                selections: vdiDesiredKeys,
                total: configuredSlotCount
            )
            mappingPreviewCard(
                title: "VDI 미리보기",
                source: physicalKeys,
                target: vdiDesiredKeys
            )
            selectionPalette(
                selections: vdiDesiredKeys,
                choices: leftSideChoices,
                onSelect: selectVdiDesiredKey
            )

            if vdiDesiredKeys.count == configuredSlotCount && shouldOfferAuxiliaryFnKey {
                auxiliaryFnSection
            }

            HStack {
                Button("← 이전") {
                    currentStep = 3
                }
                .buttonStyle(.bordered)

                Button("한 칸 지우기") {
                    _ = vdiDesiredKeys.popLast()
                }
                .buttonStyle(.bordered)
                .disabled(vdiDesiredKeys.isEmpty)

                Button("초기화") {
                    vdiDesiredKeys = []
                    auxiliaryFnKey = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("적용 및 검증 →") {
                    applyAndGoToVerification()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vdiDesiredKeys.count != configuredSlotCount)
            }
        }
    }

    private var verificationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("현재 \(currentVerificationContext.title) 기준 매핑을 실시간으로 확인하세요")
                    .font(.subheadline)
                Text("프로필 저장 후에는 로컬 Mac과 VDI 사이를 오갈 때 자동으로 해당 배치로 전환됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            mappingPreviewCard(
                title: "Mac 로컬",
                source: physicalKeys,
                target: localDesiredKeys,
                highlight: currentVerificationContext == .localMac
            )
            mappingPreviewCard(
                title: "VDI",
                source: physicalKeys,
                target: vdiDesiredKeys,
                highlight: currentVerificationContext == .vdi
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("현재 컨텍스트 검증")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(0..<configuredSlotCount, id: \.self) { index in
                    let physKey = physicalKeys[index]
                    let desiredKey = currentVerificationDesiredKeys[index]

                    HStack {
                        Text(ModifierSlot.label(for: physKey, style: selectedLegendStyle))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(ModifierSlot.label(for: desiredKey, style: selectedLegendStyle))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 48)

                        if let pass = verifyResults[desiredKey] {
                            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(pass ? .green : .red)
                            Text(pass ? "확인됨" : "불일치")
                                .font(.caption2)
                                .foregroundColor(pass ? .green : .red)
                        } else {
                            Image(systemName: "circle.dotted")
                                .foregroundColor(.gray)
                            Text("눌러서 확인")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                if let auxiliaryFnKey {
                    HStack {
                        Text(ModifierSlot.label(for: auxiliaryFnKey, style: selectedLegendStyle))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("Fn")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 48)
                        Image(systemName: auxiliaryFnVerified ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundColor(auxiliaryFnVerified ? .green : .gray)
                        Text(auxiliaryFnVerified ? "확인됨" : "눌러서 확인")
                            .font(.caption2)
                            .foregroundColor(auxiliaryFnVerified ? .green : .gray)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text("실시간 이벤트 로그")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(verifyLogs.indices.reversed(), id: \.self) { index in
                            let log = verifyLogs[index]
                            HStack(spacing: 6) {
                                Text(log.label)
                                    .font(.system(.caption, design: .monospaced))
                                Image(systemName: log.pass ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundColor(log.pass ? .green : .gray)
                                    .font(.caption)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(12)

            HStack {
                Button("← 다시 설정") {
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    appState.refreshActiveProfileForCurrentContext()
                    verifyResults = [:]
                    verifyLogs = []
                    auxiliaryFnVerified = false
                    currentStep = 4
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    newProfileName = ""
                    showSaveDialog = true
                } label: {
                    Label("프로필 저장", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var auxiliaryFnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보조 Fn 키 (선택)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("3키 키보드라면 오른쪽 보조 키 하나를 Fn으로 지정할 수 있습니다. 이 값은 로컬 Mac과 VDI에 공통 적용됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(auxiliaryFnCandidates, id: \.self) { keyCode in
                    let isSelected = auxiliaryFnKey == keyCode
                    Button {
                        auxiliaryFnKey = keyCode
                    } label: {
                        keycapChoiceLabel(
                            keyCode: keyCode,
                            selected: isSelected,
                            used: false,
                            roleCaption: "보조 Fn"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if auxiliaryFnKey != nil {
                    Button("선택 해제") {
                        auxiliaryFnKey = nil
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func presetButtons(for mode: SelectionMode) -> some View {
        HStack(spacing: 8) {
            Button("기본 \(selectedLegendStyle == .windows ? "Windows" : "Mac") \(configuredSlotCount)키") {
                applyDefaultPreset(for: mode)
            }
            .buttonStyle(ChipButtonStyle(tint: .blue))

            Button("Windows 기준") {
                assignPreset(
                    configuredSlotCount == 4
                        ? [Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)]
                        : [Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)],
                    to: mode
                )
            }
            .buttonStyle(ChipButtonStyle())

            Button("Mac 기준") {
                assignPreset(
                    configuredSlotCount == 4
                        ? [Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)]
                        : [Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)],
                    to: mode
                )
            }
            .buttonStyle(ChipButtonStyle())

            Spacer()
        }
    }

    private func slotSelectionCard(title: String, selections: [Int64], total: Int, emptyTitle: String = "선택") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            selectionSlotRow(selections: selections, total: total, emptyTitle: emptyTitle)
        }
    }

    private func selectionSlotRow(selections: [Int64], total: Int, emptyTitle: String) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                let isFilled = index < selections.count

                VStack(spacing: 4) {
                    slotKeycap(
                        title: isFilled ? ModifierSlot.label(for: selections[index], style: selectedLegendStyle) : emptyTitle,
                        subtitle: isFilled ? ModifierSlot.secondaryLabel(for: selections[index], style: selectedLegendStyle) : nil,
                        filled: isFilled
                    )

                    Text("슬롯 \(index + 1)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Text("Space")
                .font(.system(.caption, weight: .bold))
                .frame(width: 80, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }

    private func selectionPalette(
        selections: [Int64],
        choices: [Int64],
        onSelect: @escaping (Int64) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("왼쪽부터 순서대로 선택")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                ForEach(choices, id: \.self) { keyCode in
                    let isUsed = selections.contains(keyCode)
                    Button {
                        onSelect(keyCode)
                    } label: {
                        keycapChoiceLabel(
                            keyCode: keyCode,
                            selected: false,
                            used: isUsed,
                            roleCaption: "선택 가능"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUsed)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func mappingPreviewCard(
        title: String,
        source: [Int64],
        target: [Int64],
        highlight: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if highlight {
                    Text("현재 적용")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
            }

            if target.isEmpty {
                Text("아직 선택되지 않았습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(0..<min(source.count, target.count), id: \.self) { index in
                        HStack(spacing: 4) {
                            Text(ModifierSlot.label(for: source[index], style: selectedLegendStyle))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                            Text(ModifierSlot.label(for: target[index], style: selectedLegendStyle))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func slotKeycap(title: String, subtitle: String?, filled: Bool) -> some View {
        VStack(spacing: subtitle == nil ? 0 : 2) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(filled ? Color.primary : Color.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(filled ? Color.secondary : Color.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(width: 68, height: subtitle == nil ? 44 : 50)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(filled ? Color.blue.opacity(0.08) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(filled ? Color.blue.opacity(0.32) : Color.black.opacity(0.09), lineWidth: 1)
        )
    }

    private func keycapChoiceLabel(
        keyCode: Int64,
        selected: Bool,
        used: Bool,
        roleCaption: String
    ) -> some View {
        let title = ModifierSlot.label(for: keyCode, style: selectedLegendStyle)
        let subtitle = ModifierSlot.secondaryLabel(for: keyCode, style: selectedLegendStyle)
        let borderColor = selected ? Color.blue.opacity(0.55) : Color.black.opacity(used ? 0.08 : 0.12)
        let fillColor = selected ? Color.blue.opacity(0.07) : Color.black.opacity(used ? 0.025 : 0.015)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(used ? Color.secondary : Color.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if used {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                } else if selected {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
            }

            Text(roleCaption)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(used ? Color.secondary : (selected ? Color.blue : Color.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            used
                                ? Color.black.opacity(0.04)
                                : (selected ? Color.blue.opacity(0.1) : Color.black.opacity(0.035))
                        )
                )
        }
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 64 : 72, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1)
        )
        .opacity(used ? 0.72 : 1.0)
    }

    private var saveProfileSheet: some View {
        VStack(spacing: 16) {
            Text("프로필 이름을 입력하세요")
                .font(.headline)

            mappingPreviewCard(title: "Mac 로컬", source: physicalKeys, target: localDesiredKeys)
            mappingPreviewCard(title: "VDI", source: physicalKeys, target: vdiDesiredKeys)

            if let auxiliaryFnKey {
                Text("\(ModifierSlot.label(for: auxiliaryFnKey, style: selectedLegendStyle)) -> Fn")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("예: 회사 키보드, VDI 외장 3키", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            Text("프로필은 현재 입력, Mac 로컬 목표, VDI 목표를 함께 저장합니다. 자동 전환은 현재 앱의 Bundle ID 기준으로 동작합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 320, alignment: .leading)

            HStack {
                Button("취소") {
                    showSaveDialog = false
                }
                .buttonStyle(.bordered)

                Button("저장") {
                    saveCurrentProfile()
                    showSaveDialog = false
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    currentStep = 0
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func startWizard() {
        selectedLegendStyle = appState.isVdiMode ? .windows : .mac
        physicalKeys = []
        localDesiredKeys = []
        vdiDesiredKeys = []
        auxiliaryFnKey = nil
        verifyResults = [:]
        verifyLogs = []
        auxiliaryFnVerified = false
        appState.keyInterceptor.onVerifyKeyEvent = nil
        currentStep = 1
    }

    private func cancelWizard() {
        appState.keyInterceptor.onVerifyKeyEvent = nil
        appState.refreshActiveProfileForCurrentContext()
        currentStep = 0
    }

    private func beginPhysicalKeyCapture() {
        appState.keyInterceptor.applyCustomMappingsSync([:])
        appState.keyInterceptor.onVerifyKeyEvent = { [self] originalKeyCode, _, _ in
            guard currentStep == 2 else { return }
            guard physicalKeys.count < maximumPhysicalKeyCount else { return }
            guard leftSideChoices.contains(originalKeyCode) else { return }
            guard !physicalKeys.contains(originalKeyCode) else { return }
            physicalKeys.append(originalKeyCode)
        }
    }

    private func syncSelectionBuffersWithPhysicalKeys() {
        let count = configuredSlotCount
        localDesiredKeys = Array(localDesiredKeys.prefix(count))
        vdiDesiredKeys = Array(vdiDesiredKeys.prefix(count))
        if count == maximumPhysicalKeyCount {
            auxiliaryFnKey = nil
        }
    }

    private func selectLocalDesiredKey(_ keyCode: Int64) {
        guard localDesiredKeys.count < configuredSlotCount else { return }
        guard !localDesiredKeys.contains(keyCode) else { return }
        localDesiredKeys.append(keyCode)
    }

    private func selectVdiDesiredKey(_ keyCode: Int64) {
        guard vdiDesiredKeys.count < configuredSlotCount else { return }
        guard !vdiDesiredKeys.contains(keyCode) else { return }
        vdiDesiredKeys.append(keyCode)
    }

    private func desiredKeys(for context: KeyboardUsageContext) -> [Int64] {
        switch context {
        case .localMac: return localDesiredKeys
        case .vdi: return vdiDesiredKeys
        }
    }

    private func currentMappings(for context: KeyboardUsageContext) -> [Int64: Int64] {
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

    private func applyAndGoToVerification() {
        let mappings = currentMappings(for: currentVerificationContext)
        appState.persistCustomMappings(mappings)
        appState.keyInterceptor.activeProfileID = "visualCustomProfile"
        appState.keyInterceptor.applyCustomMappingsSync(mappings)

        verifyResults = [:]
        verifyLogs = []
        auxiliaryFnVerified = false
        currentStep = 5

        let desiredSet = Set(currentVerificationDesiredKeys)
        let fnKeyCode = Int64(kVK_Function)

        appState.keyInterceptor.onVerifyKeyEvent = { [self] incomingKey, _, _ in
            guard currentStep == 5 else { return }

            let label = ModifierSlot.label(for: incomingKey, style: selectedLegendStyle)
            if desiredSet.contains(incomingKey) {
                verifyResults[incomingKey] = true
                verifyLogs.append((keyCode: incomingKey, label: "\(label) ✅ 매핑 확인", pass: true))
            } else if auxiliaryFnKey != nil && incomingKey == fnKeyCode {
                auxiliaryFnVerified = true
                verifyLogs.append((keyCode: incomingKey, label: "Fn ✅ 보조 키 확인", pass: true))
            } else if leftSideChoices.contains(incomingKey) || auxiliaryFnCandidates.contains(incomingKey) {
                verifyLogs.append((keyCode: incomingKey, label: "\(label) — 미매핑", pass: false))
            } else {
                verifyLogs.append((keyCode: incomingKey, label: label, pass: true))
            }

            if verifyLogs.count > 50 {
                verifyLogs.removeFirst()
            }
        }
    }

    private func saveCurrentProfile() {
        let profile = SavedKeyboardProfile(
            name: newProfileName.trimmingCharacters(in: .whitespaces),
            legendStyle: selectedLegendStyle,
            physicalKeys: physicalKeys,
            localDesiredKeys: localDesiredKeys,
            vdiDesiredKeys: vdiDesiredKeys,
            auxiliaryFnKey: auxiliaryFnKey
        )
        appState.profileStore.add(profile)
        appState.applyProfile(profile)
    }

    private func formattedLabels(_ keyCodes: [Int64]) -> String {
        keyCodes.map { ModifierSlot.label(for: $0, style: selectedLegendStyle) }.joined(separator: " · ")
    }

    private enum SelectionMode {
        case local
        case vdi
    }

    private func applyDefaultPreset(for mode: SelectionMode) {
        switch selectedLegendStyle {
        case .mac:
            if configuredSlotCount == 4 {
                assignPreset([Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)], to: mode)
            } else {
                assignPreset([Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command)], to: mode)
            }
        case .windows:
            if configuredSlotCount == 4 {
                assignPreset([Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)], to: mode)
            } else {
                assignPreset([Int64(kVK_Control), Int64(kVK_Command), Int64(kVK_Option)], to: mode)
            }
        }
    }

    private func assignPreset(_ values: [Int64], to mode: SelectionMode) {
        let trimmed = Array(values.prefix(configuredSlotCount))
        switch mode {
        case .local: localDesiredKeys = trimmed
        case .vdi: vdiDesiredKeys = trimmed
        }
    }
}

private struct ChipButtonStyle: ButtonStyle {
    var tint: Color = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? tint.opacity(0.9) : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? tint.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.32), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
