import SwiftUI
import Carbon.HIToolbox

// MARK: - Data Models

struct ModifierSlot: Identifiable, Equatable {
    let id: UUID
    let keyCode: Int64
    var label: String
    
    static func label(for keyCode: Int64) -> String {
        switch Int(keyCode) {
        case kVK_Function: return "Fn"
        case kVK_Control: return "Ctrl"
        case kVK_Option: return "Opt"
        case kVK_Command: return "Cmd"
        case kVK_Shift: return "Shift"
        case kVK_RightCommand: return "RCmd"
        case kVK_RightOption: return "ROpt"
        case kVK_RightControl: return "RCtrl"
        case kVK_RightShift: return "RShift"
        case kVK_CapsLock: return "Caps"
        default: return "0x\(String(keyCode, radix: 16, uppercase: true))"
        }
    }
}

// MARK: - Main View

struct ModifierLayoutView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var currentStep: Int = 0 // 0=프로필 선택, 1=물리감지, 2=원하는키입력, 3=검증
    
    // Step 1: 물리 키 감지
    @State private var detectedPhysicalKeys: [Int64] = []
    @State private var waitingSlot1: Int = 0
    private let minimumSlots = 3
    private let maximumSlots = 4
    
    // Step 2: 원하는 키 입력
    @State private var desiredKeys: [Int64] = []
    @State private var waitingSlot2: Int = 0
    @State private var auxiliaryFnKey: Int64? = nil
    @State private var isCapturingAuxiliaryFnKey = false
    
    // Step 3: 검증
    @State private var verifyResults: [Int64: Bool] = [:] // desiredKey → pass/fail
    @State private var verifyLogs: [(keyCode: Int64, label: String, pass: Bool)] = []
    @State private var auxiliaryFnVerified = false
    
    // 프로필 저장
    @State private var showSaveDialog = false
    @State private var newProfileName = ""
    
    // Modifier 키코드
    private let knownModifiers: Set<Int64> = [
        Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command),
        Int64(kVK_RightCommand), Int64(kVK_RightOption), Int64(kVK_RightControl),
        Int64(kVK_CapsLock), Int64(kVK_Shift), Int64(kVK_RightShift)
    ]
    private let auxiliaryFnCandidates: [Int64] = [
        Int64(kVK_RightControl),
        Int64(kVK_CapsLock),
        Int64(kVK_RightShift)
    ]

    private var requiredSlotCount: Int {
        max(detectedPhysicalKeys.count, minimumSlots)
    }

    private var shouldOfferAuxiliaryFnKey: Bool {
        detectedPhysicalKeys.count == minimumSlots && !desiredKeys.contains(Int64(kVK_Function))
    }

    private var currentMappings: [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for (index, physKey) in detectedPhysicalKeys.enumerated() {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch currentStep {
            case 0: profileSelectorView
            case 1: stepOneView
            case 2: stepTwoView
            case 3: stepThreeView
            default: EmptyView()
            }
        }
        .onDisappear {
            appState.keyInterceptor.onVerifyKeyEvent = nil
        }
        .sheet(isPresented: $showSaveDialog) {
            saveProfileSheet
        }
    }
    
    // MARK: - Step 0: Profile Selector
    
    private var profileSelectorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("키보드 레이아웃 프로필")
                .font(.headline)
            
            if appState.profileStore.profiles.isEmpty {
                VStack(spacing: 8) {
                    Text("저장된 프로필이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("새 프로필을 만들어 키보드 배치를 설정하세요")
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
                    appState.keyInterceptor.applyCustomMappings([:])
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
                Text(profile.name)
                    .font(.system(.body, weight: isActive ? .semibold : .regular))
                Text(profile.summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Button(isActive ? "사용 중" : "적용") {
                applyProfile(profile)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isActive)
            
            Button {
                appState.profileStore.delete(id: profile.id)
                if isActive {
                    appState.activeMappingProfileId = "standardMac"
                    appState.keyInterceptor.applyCustomMappings([:])
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
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        HStack(spacing: 20) {
            stepDot(step: 1, title: "물리 키")
            stepDot(step: 2, title: "원하는 키")
            stepDot(step: 3, title: "검증")
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
    
    // MARK: - Step 1: 물리 키 감지
    
    private var stepOneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("현재 키보드의 **스페이스바 왼쪽 키**를 왼쪽부터 순서대로 눌러주세요")
                    .font(.subheadline)
                Text("3키 키보드는 3개만 눌러도 됩니다. 4번째 키가 있으면 이어서 눌러주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            keySlotRow(
                detected: detectedPhysicalKeys,
                waitingSlot: detectedPhysicalKeys.count >= minimumSlots ? nil : waitingSlot1,
                total: maximumSlots,
                stepLabel: "물리 키"
            )
            
            HStack {
                Button("← 취소") {
                    cancelWizard()
                }
                .buttonStyle(.bordered)
                
                Button("초기화") {
                    startStep1()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if detectedPhysicalKeys.count >= minimumSlots {
                    Button("다음 →") {
                        goToStep2()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - Step 2: 원하는 키 입력 (키 누르기)
    
    private var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("각 슬롯에 **원하는 기능 키**를 순서대로 눌러주세요")
                    .font(.subheadline)
                Text("물리 배치: \(detectedPhysicalKeys.map { ModifierSlot.label(for: $0) }.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            keySlotRow(
                detected: desiredKeys,
                waitingSlot: waitingSlot2,
                total: requiredSlotCount,
                stepLabel: "원하는 키"
            )
            
            // 매핑 미리보기
            if !desiredKeys.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("매핑 미리보기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(0..<desiredKeys.count, id: \.self) { idx in
                            HStack(spacing: 4) {
                                Text(ModifierSlot.label(for: detectedPhysicalKeys[idx]))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                Text(ModifierSlot.label(for: desiredKeys[idx]))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(8)
            }

            if desiredKeys.count == requiredSlotCount && shouldOfferAuxiliaryFnKey {
                auxiliaryFnSection
            }
            
            HStack {
                Button("← 이전") {
                    startStep1() // Step 1로 돌아가기
                    currentStep = 1
                }
                .buttonStyle(.bordered)
                
                Button("초기화") {
                    startStep2()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if desiredKeys.count == requiredSlotCount {
                    Button("적용 및 검증 →") {
                        applyAndGoToStep3()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - Step 3: 검증
    
    private var stepThreeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepIndicator
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("아무 키나 눌러서 매핑이 올바르게 적용되었는지 확인하세요")
                    .font(.subheadline)
                if auxiliaryFnKey != nil {
                    Text("보조 Fn 키도 한 번 눌러서 함께 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 매핑 + 검증 결과
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<requiredSlotCount, id: \.self) { idx in
                    let physKey = detectedPhysicalKeys[idx]
                    let desKey = desiredKeys[idx]
                    
                    HStack {
                        Text(ModifierSlot.label(for: physKey))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundColor(.blue)
                        Text(ModifierSlot.label(for: desKey))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 40)
                        
                        if let pass = verifyResults[desKey] {
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
                        Text(ModifierSlot.label(for: auxiliaryFnKey))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("Fn")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 40)

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
            
            // 실시간 로그
            VStack(alignment: .leading, spacing: 4) {
                Text("실시간 이벤트 로그").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(verifyLogs.indices.reversed(), id: \.self) { idx in
                            let log = verifyLogs[idx]
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
                    // HID 정리 후 Step 2로 (동기 — 완료 보장)
                    HIDRemapper.shared.clearMappingsSync()
                    appState.keyInterceptor.applyCustomMappings([:])
                    appState.keyInterceptor.onVerifyKeyEvent = nil
                    startStep2()
                    currentStep = 2
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

            Text("3키 키보드에서는 오른쪽 키 하나를 Fn으로 둘 수 있습니다. `RCtrl`이 가장 무난합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(auxiliaryFnKey.map { ModifierSlot.label(for: $0) } ?? "미지정")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 64, alignment: .leading)
                    .foregroundStyle(auxiliaryFnKey == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.blue))

                if isCapturingAuxiliaryFnKey {
                    Text("오른쪽 보조 키를 눌러주세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("지원 키: RCtrl, Caps, RShift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                Button(isCapturingAuxiliaryFnKey ? "입력 중..." : auxiliaryFnKey == nil ? "보조 Fn 키 지정" : "다른 키로 변경") {
                    isCapturingAuxiliaryFnKey = true
                }
                .buttonStyle(.bordered)
                .disabled(isCapturingAuxiliaryFnKey)

                if isCapturingAuxiliaryFnKey {
                    Button("취소") {
                        isCapturingAuxiliaryFnKey = false
                    }
                    .buttonStyle(.bordered)
                }

                if auxiliaryFnKey != nil {
                    Button("선택 해제") {
                        auxiliaryFnKey = nil
                        isCapturingAuxiliaryFnKey = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Shared Key Slot Row
    
    private func keySlotRow(detected: [Int64], waitingSlot: Int?, total: Int, stepLabel: String) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { idx in
                let isDetected = idx < detected.count
                let isWaiting = idx == waitingSlot && !isDetected
                
                VStack(spacing: 4) {
                    if isDetected {
                        Text(ModifierSlot.label(for: detected[idx]))
                            .font(.system(.body, weight: .semibold))
                            .frame(width: 55, height: 46)
                            .background(Color.green.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.5), lineWidth: 1))
                            .cornerRadius(8)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if isWaiting {
                        Text("눌러요")
                            .font(.system(.caption, weight: .medium))
                            .frame(width: 55, height: 46)
                            .background(Color.blue.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 2).opacity(0.8))
                            .cornerRadius(8)
                        
                        Text("슬롯 \(idx + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else {
                        Text("—")
                            .font(.system(.body, weight: .medium))
                            .frame(width: 55, height: 46)
                            .background(Color.gray.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            .cornerRadius(8)
                        
                        Text("슬롯 \(idx + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Text("Space")
                .font(.system(.caption, weight: .bold))
                .frame(width: 80, height: 46)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Save Profile Sheet
    
    private var saveProfileSheet: some View {
        VStack(spacing: 16) {
            Text("프로필 이름을 입력하세요")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(0..<requiredSlotCount, id: \.self) { idx in
                        VStack(spacing: 2) {
                            Text(ModifierSlot.label(for: detectedPhysicalKeys[idx]))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.down").font(.system(size: 8)).foregroundColor(.blue)
                            Text(ModifierSlot.label(for: desiredKeys[idx]))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        .frame(width: 45)
                    }
                }

                if let auxiliaryFnKey {
                    Text("\(ModifierSlot.label(for: auxiliaryFnKey)) -> Fn")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            
            TextField("예: 맥북 내장, Keychron K2, ...", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            Text("프로필 이름은 표시용입니다. 장치 자동 식별은 아직 지원하지 않고, 자동 전환은 앱 할당으로만 동작합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 280, alignment: .leading)
            
            HStack {
                Button("취소") { showSaveDialog = false }
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
        .frame(width: 360)
    }
    
    // MARK: - Logic
    
    private func startWizard() {
        // HID 매핑 해제 → 원래 물리 키코드를 감지할 수 있도록 (동기 — 완료 보장)
        HIDRemapper.shared.clearMappingsSync()
        appState.keyInterceptor.applyCustomMappings([:])
        
        startStep1()
        currentStep = 1
    }
    
    private func cancelWizard() {
        appState.keyInterceptor.onVerifyKeyEvent = nil
        // 기존 프로필 다시 적용
        appState.keyInterceptor.setupDefaultMappings()
        currentStep = 0
    }
    
    private func startStep1() {
        detectedPhysicalKeys = []
        waitingSlot1 = 0
        desiredKeys = []
        waitingSlot2 = 0
        auxiliaryFnKey = nil
        isCapturingAuxiliaryFnKey = false
        auxiliaryFnVerified = false
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] original, _, _ in
            guard currentStep == 1 else { return }
            guard detectedPhysicalKeys.count < maximumSlots else { return }
            guard knownModifiers.contains(original) else { return }
            guard !detectedPhysicalKeys.contains(original) else { return }
            
            detectedPhysicalKeys.append(original)
            waitingSlot1 = detectedPhysicalKeys.count
        }
    }
    
    private func goToStep2() {
        appState.keyInterceptor.onVerifyKeyEvent = nil
        startStep2()
        currentStep = 2
    }
    
    private func startStep2() {
        desiredKeys = []
        waitingSlot2 = 0
        auxiliaryFnKey = nil
        isCapturingAuxiliaryFnKey = false
        auxiliaryFnVerified = false
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] original, _, _ in
            guard currentStep == 2 else { return }
            guard knownModifiers.contains(original) else { return }

            if isCapturingAuxiliaryFnKey {
                guard auxiliaryFnCandidates.contains(original) else { return }
                guard !detectedPhysicalKeys.contains(original) else { return }
                auxiliaryFnKey = original
                isCapturingAuxiliaryFnKey = false
                return
            }

            guard desiredKeys.count < requiredSlotCount else { return }
            guard !desiredKeys.contains(original) else { return }

            desiredKeys.append(original)
            waitingSlot2 = desiredKeys.count
        }
    }
    
    private func applyAndGoToStep3() {
        let newMappings = currentMappings
        
        // UserDefaults에 저장
        let stringKeyDict = Dictionary(uniqueKeysWithValues: newMappings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: "visualCustomMappings")
        }
        
        // HID + CGEventTap 모두 적용 (동기 — Step 3 진입 전 완료 보장)
        appState.activeMappingProfileId = "visualCustomProfile"
        appState.keyInterceptor.applyCustomMappingsSync(newMappings)
        
        // Step 3: 검증 모드
        verifyResults = [:]
        verifyLogs = []
        auxiliaryFnVerified = false
        currentStep = 3
        
        // 검증 콜백: HID가 적용되었으므로 들어오는 keyCode가 이미 desired key여야 함
        let desiredSet = Set(desiredKeys)
        let fnKeyCode = Int64(kVK_Function)
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] incomingKey, _, _ in
            guard currentStep == 3 else { return }
            
            let label = ModifierSlot.label(for: incomingKey)
            
            if desiredSet.contains(incomingKey) {
                // 원하는 키 중 하나가 도착 → 매핑 성공
                verifyResults[incomingKey] = true
                verifyLogs.append((keyCode: incomingKey, label: "\(label) ✅ 매핑 확인", pass: true))
            } else if auxiliaryFnKey != nil && incomingKey == fnKeyCode {
                auxiliaryFnVerified = true
                verifyLogs.append((keyCode: incomingKey, label: "Fn ✅ 보조 키 확인", pass: true))
            } else if knownModifiers.contains(incomingKey) {
                // modifier 키인데 desired에 없는 경우 → 매핑 안 된 키
                verifyLogs.append((keyCode: incomingKey, label: "\(label) — 미매핑", pass: false))
            } else {
                // 일반 키
                verifyLogs.append((keyCode: incomingKey, label: "\(label)", pass: true))
            }
            
            if verifyLogs.count > 50 { verifyLogs.removeFirst() }
        }
    }
    
    private func saveCurrentProfile() {
        let profile = SavedKeyboardProfile(
            name: newProfileName.trimmingCharacters(in: .whitespaces),
            physicalKeys: detectedPhysicalKeys,
            desiredKeys: desiredKeys,
            auxiliaryFnKey: auxiliaryFnKey
        )
        appState.profileStore.add(profile)
        applyProfile(profile)
    }
    
    private func applyProfile(_ profile: SavedKeyboardProfile) {
        let mappings = profile.mappings
        
        let stringKeyDict = Dictionary(uniqueKeysWithValues: mappings.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyDict) {
            UserDefaults.standard.set(data, forKey: "visualCustomMappings")
        }
        
        appState.activeMappingProfileId = profile.id.uuidString
        appState.keyInterceptor.applyCustomMappings(mappings)
    }
}
