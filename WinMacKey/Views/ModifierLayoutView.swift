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
    @State private var selectedLocalSlotIndex = 0
    @State private var selectedVdiSlotIndex = 0
    @State private var didCaptureSpaceBoundary = false
    @State private var physicalCaptureNeedsMoreKeys = false

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
    private let macTargetChoices: [Int64] = [
        Int64(kVK_Function),
        Int64(kVK_Control),
        Int64(kVK_Command),
        Int64(kVK_Option)
    ]
    private let vdiTargetChoices: [Int64] = [
        Int64(kVK_Control),
        Int64(kVK_Command),
        Int64(kVK_Option)
    ]
    private let minimumPhysicalKeyCount = 3
    private let maximumPhysicalKeyCount = 4
    private let spaceKeyCode = Int64(kVK_Space)
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

    private var localSelectionCursor: Int {
        max(0, min(selectedLocalSlotIndex, max(configuredSlotCount - 1, 0)))
    }

    private var vdiSelectionCursor: Int {
        max(0, min(selectedVdiSlotIndex, max(configuredSlotCount - 1, 0)))
    }

    private var shouldOfferAuxiliaryFnKey: Bool {
        configuredSlotCount == 3
            && !localDesiredKeys.contains(Int64(kVK_Function))
            && !vdiDesiredKeys.contains(Int64(kVK_Function))
    }

    private var physicalCaptureHint: String {
        if didCaptureSpaceBoundary {
            return "\(configuredSlotCount)키 감지가 끝났습니다. 다음 단계로 넘어가세요."
        }
        if physicalCaptureNeedsMoreKeys {
            return "Space 전까지 3개 이상의 modifier를 눌러 주세요."
        }
        switch physicalKeys.count {
        case ..<minimumPhysicalKeyCount:
            return "왼쪽부터 modifier를 누르고 마지막에 Space를 눌러 입력을 끝내세요."
        case minimumPhysicalKeyCount:
            return "3개를 감지했지만 아직 확정 전입니다. 3키면 Space를 눌러 확정하고, 4키면 마지막 키를 더 누른 뒤 Space를 누르세요."
        default:
            return "4개를 감지했지만 아직 확정 전입니다. Space를 눌러 4키로 확정하세요."
        }
    }

    private var legendGuideText: String {
        switch selectedLegendStyle {
        case .mac:
            return "Mac 키보드라면 Ctrl / Opt / Cmd / Fn 인쇄 기준으로 안내합니다."
        case .windows:
            return "Windows 키보드라면 Ctrl / Win / Alt / Fn 인쇄 기준으로 안내합니다. 실제 입력은 macOS의 Cmd / Opt로 감지됩니다."
        }
    }

    private var vdiGuideText: String {
        configuredSlotCount == 4
            ? "VDI 목표는 Windows 기준이라 Ctrl / Win / Alt만 고릅니다. 4키 키보드라면 같은 기능을 두 슬롯에 둘 수 있습니다."
            : "VDI 목표는 Windows 기준이라 Ctrl / Win / Alt만 고릅니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
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
        HStack(spacing: 10) {
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
                    .frame(width: 24, height: 24)
                Text("\(step)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(step <= currentStep ? .primary : .secondary)
        }
    }

    private var shapeSetupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("키보드 키캡 프린팅을 선택하세요")
                    .font(.subheadline)
                Text("이 선택은 뒤 단계에서 키 이름과 부연 설명을 어떻게 보여줄지만 결정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                legendStyleCard(
                    style: .mac,
                    title: "Mac 키보드",
                    detail: "Ctrl · Opt · Cmd · Fn 키캡"
                )
                legendStyleCard(
                    style: .windows,
                    title: "Windows 키보드",
                    detail: "Ctrl · Win · Alt · Fn 키캡"
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.8) : Color.gray.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var physicalInputView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("현재 키보드의 스페이스바 왼쪽 modifier를 실제로 눌러 주세요")
                    .font(.subheadline)
                Text("왼쪽부터 키를 누르고 마지막에 `Space`를 누르면 3키/4키를 자동으로 감지합니다.")
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
                displayStyle: selectedLegendStyle,
                emptyTitle: "대기",
                showSecondaryLabels: selectedLegendStyle == .windows,
                spaceCaptured: didCaptureSpaceBoundary
            )
            Text(physicalCaptureHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            if !physicalKeys.isEmpty {
                physicalCaptureSummaryCard
            }

            HStack {
                Button("← 이전") {
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    currentStep = 1
                }
                .buttonStyle(.bordered)

                Button("한 칸 지우기") {
                    _ = physicalKeys.popLast()
                    didCaptureSpaceBoundary = false
                    physicalCaptureNeedsMoreKeys = false
                    auxiliaryFnKey = nil
                }
                .buttonStyle(.bordered)
                .disabled(physicalKeys.isEmpty)

                Button("초기화") {
                    physicalKeys = []
                    didCaptureSpaceBoundary = false
                    physicalCaptureNeedsMoreKeys = false
                    auxiliaryFnKey = nil
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("다음 →") {
                    syncSelectionBuffersWithPhysicalKeys()
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    selectedLocalSlotIndex = nextCursorIndex(for: localDesiredKeys, total: configuredSlotCount)
                    selectedVdiSlotIndex = nextCursorIndex(for: vdiDesiredKeys, total: configuredSlotCount)
                    currentStep = 3
                }
                .buttonStyle(.borderedProminent)
                .disabled(!didCaptureSpaceBoundary)
            }
        }
    }

    private var physicalCaptureSummaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("감지 요약")
                .font(.caption)
                .foregroundStyle(.secondary)

            summaryLine(title: "키캡 기준", keyCodes: physicalKeys, style: selectedLegendStyle)

            if selectedLegendStyle == .windows {
                summaryLine(title: "macOS 입력", keyCodes: physicalKeys, style: .mac)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func summaryLine(title: String, keyCodes: [Int64], style: KeyboardLegendStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Text(formattedLabels(keyCodes, style: style))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func formattedLabels(_ keyCodes: [Int64], style: KeyboardLegendStyle) -> String {
        guard !keyCodes.isEmpty else { return "-" }
        return keyCodes
            .map { ModifierSlot.label(for: $0, style: style) }
            .joined(separator: " / ")
    }

    private var localMappingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("로컬 macOS에서 원하는 배치를 왼쪽부터 순서대로 선택하세요")
                    .font(.subheadline)
                Text("Mac 로컬 목표는 항상 `Fn / Ctrl / Cmd / Opt` 기준으로 선택합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            slotSelectionCard(
                title: "Mac 로컬 목표",
                selections: localDesiredKeys,
                total: configuredSlotCount,
                displayStyle: .mac,
                selectedIndex: localSelectionCursor,
                onSelectSlot: { selectedLocalSlotIndex = $0 }
            )
            mappingPreviewCard(
                title: "Mac 로컬 미리보기",
                source: physicalKeys,
                target: localDesiredKeys,
                sourceStyle: selectedLegendStyle,
                targetStyle: .mac
            )
            selectionPalette(
                selections: localDesiredKeys,
                choices: macTargetChoices,
                displayStyle: .mac,
                selectedIndex: localSelectionCursor,
                allowsDuplicates: false,
                onSelect: { applyKeySelection($0, to: .local) }
            )

            HStack {
                Button("← 이전") {
                    beginPhysicalKeyCapture()
                    currentStep = 2
                }
                .buttonStyle(.bordered)

                Button("선택 슬롯 지우기") {
                    removeSelectedKey(from: .local)
                }
                .buttonStyle(.bordered)
                .disabled(localDesiredKeys.isEmpty)

                Button("초기화") {
                    localDesiredKeys = []
                    selectedLocalSlotIndex = 0
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("다음 →") {
                    selectedVdiSlotIndex = nextCursorIndex(for: vdiDesiredKeys, total: configuredSlotCount)
                    currentStep = 4
                }
                .buttonStyle(.borderedProminent)
                .disabled(localDesiredKeys.count != configuredSlotCount)
            }
        }
    }

    private var vdiMappingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepIndicator
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Windows VDI 안에서 원하는 배치를 왼쪽부터 순서대로 선택하세요")
                    .font(.subheadline)
                Text(vdiGuideText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            slotSelectionCard(
                title: "VDI 목표",
                selections: vdiDesiredKeys,
                total: configuredSlotCount,
                displayStyle: .windows,
                selectedIndex: vdiSelectionCursor,
                onSelectSlot: { selectedVdiSlotIndex = $0 }
            )
            mappingPreviewCard(
                title: "VDI 미리보기",
                source: physicalKeys,
                target: vdiDesiredKeys,
                sourceStyle: selectedLegendStyle,
                targetStyle: .windows
            )
            selectionPalette(
                selections: vdiDesiredKeys,
                choices: vdiTargetChoices,
                displayStyle: .windows,
                selectedIndex: vdiSelectionCursor,
                allowsDuplicates: true,
                onSelect: { applyKeySelection($0, to: .vdi) }
            )

            if vdiDesiredKeys.count == configuredSlotCount && shouldOfferAuxiliaryFnKey {
                auxiliaryFnSection
            }

            HStack {
                Button("← 이전") {
                    currentStep = 3
                }
                .buttonStyle(.bordered)

                Button("선택 슬롯 지우기") {
                    removeSelectedKey(from: .vdi)
                }
                .buttonStyle(.bordered)
                .disabled(vdiDesiredKeys.isEmpty)

                Button("초기화") {
                    vdiDesiredKeys = []
                    selectedVdiSlotIndex = 0
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
                sourceStyle: selectedLegendStyle,
                targetStyle: .mac,
                highlight: currentVerificationContext == .localMac
            )
            mappingPreviewCard(
                title: "VDI",
                source: physicalKeys,
                target: vdiDesiredKeys,
                sourceStyle: selectedLegendStyle,
                targetStyle: .windows,
                highlight: currentVerificationContext == .vdi
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("현재 컨텍스트 검증")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(0..<configuredSlotCount, id: \.self) { index in
                    let physKey = physicalKeys[index]
                    let desiredKey = currentVerificationDesiredKeys[index]
                    let targetStyle = targetDisplayStyle(for: currentVerificationContext)

                    HStack {
                        Text(ModifierSlot.label(for: physKey, style: selectedLegendStyle))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(ModifierSlot.label(for: desiredKey, style: targetStyle))
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

            HStack(spacing: 8) {
                ForEach(auxiliaryFnCandidates, id: \.self) { keyCode in
                    let isSelected = auxiliaryFnKey == keyCode
                    Button {
                        auxiliaryFnKey = keyCode
                    } label: {
                        keycapChoiceLabel(
                            keyCode: keyCode,
                            displayStyle: selectedLegendStyle,
                            selected: isSelected,
                            usedElsewhere: false,
                            showsSecondaryLabel: selectedLegendStyle == .windows
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

    private func slotSelectionCard(
        title: String,
        selections: [Int64],
        total: Int,
        displayStyle: KeyboardLegendStyle,
        emptyTitle: String = "선택",
        showSecondaryLabels: Bool = false,
        selectedIndex: Int? = nil,
        onSelectSlot: ((Int) -> Void)? = nil,
        spaceCaptured: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            selectionSlotRow(
                selections: selections,
                total: total,
                displayStyle: displayStyle,
                emptyTitle: emptyTitle,
                showSecondaryLabels: showSecondaryLabels,
                selectedIndex: selectedIndex,
                onSelectSlot: onSelectSlot,
                spaceCaptured: spaceCaptured
            )
        }
    }

    private func selectionSlotRow(
        selections: [Int64],
        total: Int,
        displayStyle: KeyboardLegendStyle,
        emptyTitle: String,
        showSecondaryLabels: Bool,
        selectedIndex: Int?,
        onSelectSlot: ((Int) -> Void)?,
        spaceCaptured: Bool
    ) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { index in
                let isFilled = index < selections.count
                let isSelected = selectedIndex == index
                let subtitle = showSecondaryLabels && isFilled
                    ? ModifierSlot.secondaryLabel(for: selections[index], style: displayStyle)
                    : nil

                Button {
                    onSelectSlot?(index)
                } label: {
                    slotKeycap(
                        title: isFilled ? ModifierSlot.label(for: selections[index], style: displayStyle) : emptyTitle,
                        subtitle: subtitle,
                        filled: isFilled,
                        selected: isSelected,
                        slotNumber: index + 1
                    )
                }
                .buttonStyle(.plain)
                .disabled(onSelectSlot == nil)
            }

            spaceKeycap(captured: spaceCaptured)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }

    private func selectionPalette(
        selections: [Int64],
        choices: [Int64],
        displayStyle: KeyboardLegendStyle,
        selectedIndex: Int,
        allowsDuplicates: Bool,
        onSelect: @escaping (Int64) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("선택 슬롯을 누른 뒤 기능 키를 고르세요")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { keyCode in
                    let isCurrentSelection = selectedIndex < selections.count && selections[selectedIndex] == keyCode
                    let isUsedElsewhere = selections.enumerated().contains { offset, value in
                        value == keyCode && offset != selectedIndex
                    }
                    Button {
                        onSelect(keyCode)
                    } label: {
                        keycapChoiceLabel(
                            keyCode: keyCode,
                            displayStyle: displayStyle,
                            selected: isCurrentSelection,
                            usedElsewhere: isUsedElsewhere && !allowsDuplicates,
                            showsSecondaryLabel: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func mappingPreviewCard(
        title: String,
        source: [Int64],
        target: [Int64],
        sourceStyle: KeyboardLegendStyle,
        targetStyle: KeyboardLegendStyle,
        highlight: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                HStack(spacing: 10) {
                    ForEach(0..<min(source.count, target.count), id: \.self) { index in
                        HStack(spacing: 4) {
                            Text(ModifierSlot.label(for: source[index], style: sourceStyle))
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                            Text(ModifierSlot.label(for: target[index], style: targetStyle))
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func slotKeycap(
        title: String,
        subtitle: String?,
        filled: Bool,
        selected: Bool,
        slotNumber: Int
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11)
                .fill(filled ? Color.black.opacity(0.028) : Color.black.opacity(0.015))

            RoundedRectangle(cornerRadius: 11)
                .stroke(selected ? Color.blue.opacity(0.82) : Color.black.opacity(filled ? 0.12 : 0.08), lineWidth: selected ? 1.4 : 1)

            Text("\(slotNumber)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .padding(.top, 5)

            VStack(spacing: subtitle == nil ? 1 : 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(filled ? Color.primary : Color.secondary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: subtitle == nil ? 58 : 64, height: subtitle == nil ? 42 : 46)
    }

    private func spaceKeycap(captured: Bool) -> some View {
        Text("Space")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(captured ? Color.blue : Color.secondary)
            .frame(width: 72, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(captured ? Color.blue.opacity(0.08) : Color.black.opacity(0.018))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(captured ? Color.blue.opacity(0.8) : Color.black.opacity(0.08), lineWidth: captured ? 1.4 : 1)
            )
    }

    private func keycapChoiceLabel(
        keyCode: Int64,
        displayStyle: KeyboardLegendStyle,
        selected: Bool,
        usedElsewhere: Bool,
        showsSecondaryLabel: Bool
    ) -> some View {
        let title = ModifierSlot.label(for: keyCode, style: displayStyle)
        let subtitle = showsSecondaryLabel ? ModifierSlot.secondaryLabel(for: keyCode, style: displayStyle) : nil

        return VStack(spacing: subtitle == nil ? 1 : 2) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 40 : 46)
        .overlay(alignment: .topTrailing) {
            if usedElsewhere {
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                    .padding(6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(selected ? Color.blue.opacity(0.08) : Color.black.opacity(0.018))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(selected ? Color.blue.opacity(0.8) : Color.black.opacity(usedElsewhere ? 0.18 : 0.1), lineWidth: selected ? 1.4 : 1)
        )
    }

    private var saveProfileSheet: some View {
        VStack(spacing: 16) {
            Text("프로필 이름을 입력하세요")
                .font(.headline)

            mappingPreviewCard(title: "Mac 로컬", source: physicalKeys, target: localDesiredKeys, sourceStyle: selectedLegendStyle, targetStyle: .mac)
            mappingPreviewCard(title: "VDI", source: physicalKeys, target: vdiDesiredKeys, sourceStyle: selectedLegendStyle, targetStyle: .windows)

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
        selectedLocalSlotIndex = 0
        selectedVdiSlotIndex = 0
        didCaptureSpaceBoundary = false
        physicalCaptureNeedsMoreKeys = false
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
        didCaptureSpaceBoundary = (minimumPhysicalKeyCount...maximumPhysicalKeyCount).contains(physicalKeys.count) && didCaptureSpaceBoundary
        physicalCaptureNeedsMoreKeys = false
        appState.keyInterceptor.onVerifyKeyEvent = { [self] originalKeyCode, _, _ in
            guard currentStep == 2 else { return }

            if didCaptureSpaceBoundary {
                return
            }

            if originalKeyCode == spaceKeyCode {
                if (minimumPhysicalKeyCount...maximumPhysicalKeyCount).contains(physicalKeys.count) {
                    didCaptureSpaceBoundary = true
                    physicalCaptureNeedsMoreKeys = false
                    syncSelectionBuffersWithPhysicalKeys()
                } else {
                    physicalCaptureNeedsMoreKeys = true
                }
                return
            }

            guard physicalKeys.count < maximumPhysicalKeyCount else { return }
            guard leftSideChoices.contains(originalKeyCode) else { return }
            guard !physicalKeys.contains(originalKeyCode) else { return }

            physicalKeys.append(originalKeyCode)
            physicalCaptureNeedsMoreKeys = false
        }
    }

    private func syncSelectionBuffersWithPhysicalKeys() {
        let count = configuredSlotCount
        localDesiredKeys = Array(localDesiredKeys.prefix(count))
        vdiDesiredKeys = Array(vdiDesiredKeys.prefix(count))
        if count == maximumPhysicalKeyCount {
            auxiliaryFnKey = nil
        }
        selectedLocalSlotIndex = nextCursorIndex(for: localDesiredKeys, total: count)
        selectedVdiSlotIndex = nextCursorIndex(for: vdiDesiredKeys, total: count)
    }

    private func nextCursorIndex(for selections: [Int64], total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(selections.count, total - 1)
    }

    private func targetDisplayStyle(for context: KeyboardUsageContext) -> KeyboardLegendStyle {
        switch context {
        case .localMac: return .mac
        case .vdi: return .windows
        }
    }

    private func applyKeySelection(_ keyCode: Int64, to mode: TargetSelectionMode) {
        let allowsDuplicates = mode == .vdi
        let total = configuredSlotCount
        guard total > 0 else { return }

        switch mode {
        case .local:
            localDesiredKeys = updatedSelections(
                localDesiredKeys,
                keyCode: keyCode,
                selectedIndex: localSelectionCursor,
                total: total,
                allowsDuplicates: allowsDuplicates
            )
            selectedLocalSlotIndex = advancedCursorIndex(
                afterApplyingAt: localSelectionCursor,
                selections: localDesiredKeys,
                total: total
            )
        case .vdi:
            vdiDesiredKeys = updatedSelections(
                vdiDesiredKeys,
                keyCode: keyCode,
                selectedIndex: vdiSelectionCursor,
                total: total,
                allowsDuplicates: allowsDuplicates
            )
            selectedVdiSlotIndex = advancedCursorIndex(
                afterApplyingAt: vdiSelectionCursor,
                selections: vdiDesiredKeys,
                total: total
            )
        }
    }

    private func updatedSelections(
        _ currentSelections: [Int64],
        keyCode: Int64,
        selectedIndex: Int,
        total: Int,
        allowsDuplicates: Bool
    ) -> [Int64] {
        guard total > 0 else { return currentSelections }

        var result = Array(currentSelections.prefix(total))
        let clampedIndex = max(0, min(selectedIndex, total - 1))

        if clampedIndex < result.count {
            if !allowsDuplicates,
               let existingIndex = result.firstIndex(of: keyCode),
               existingIndex != clampedIndex {
                result.swapAt(existingIndex, clampedIndex)
            } else {
                result[clampedIndex] = keyCode
            }
            return result
        }

        if !allowsDuplicates, result.contains(keyCode) {
            return result
        }

        if result.count < total {
            result.append(keyCode)
        }
        return result
    }

    private func advancedCursorIndex(afterApplyingAt index: Int, selections: [Int64], total: Int) -> Int {
        guard total > 0 else { return 0 }
        if index >= selections.count - 1 && selections.count < total {
            return selections.count
        }
        return min(index, total - 1)
    }

    private func removeSelectedKey(from mode: TargetSelectionMode) {
        switch mode {
        case .local:
            guard localSelectionCursor < localDesiredKeys.count else { return }
            localDesiredKeys.remove(at: localSelectionCursor)
            selectedLocalSlotIndex = max(0, min(localSelectionCursor, max(localDesiredKeys.count - 1, 0)))
        case .vdi:
            guard vdiSelectionCursor < vdiDesiredKeys.count else { return }
            vdiDesiredKeys.remove(at: vdiSelectionCursor)
            selectedVdiSlotIndex = max(0, min(vdiSelectionCursor, max(vdiDesiredKeys.count - 1, 0)))
        }
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

    private enum TargetSelectionMode {
        case local
        case vdi
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
