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
        case kVK_RightCommand: return "RCmd"
        case kVK_RightOption: return "ROpt"
        case kVK_RightControl: return "RCtrl"
        case kVK_CapsLock: return "Caps"
        default: return "0x\(String(keyCode, radix: 16, uppercase: true))"
        }
    }
}

/// 저장 가능한 키보드 프로필
struct SavedKeyboardProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var physicalKeys: [Int64]
    var desiredKeys: [Int64]
    
    var mappings: [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for (index, physKey) in physicalKeys.enumerated() {
            let desKey = desiredKeys[index]
            if physKey != desKey {
                result[physKey] = desKey
            }
        }
        return result
    }
    
    var summary: String {
        let src = physicalKeys.map { ModifierSlot.label(for: $0) }.joined(separator: "·")
        let dst = desiredKeys.map { ModifierSlot.label(for: $0) }.joined(separator: "·")
        return "\(src) → \(dst)"
    }
}

/// 프로필 저장소
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
    
    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }
}

// MARK: - Main View

struct ModifierLayoutView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var profileStore = KeyboardProfileStore()
    
    @State private var currentStep: Int = 0 // 0=프로필 선택, 1=물리감지, 2=원하는키입력, 3=검증
    
    // Step 1: 물리 키 감지
    @State private var detectedPhysicalKeys: [Int64] = []
    @State private var waitingSlot1: Int = 0
    private let totalSlots = 4
    
    // Step 2: 원하는 키 입력
    @State private var desiredKeys: [Int64] = []
    @State private var waitingSlot2: Int = 0
    
    // Step 3: 검증
    @State private var verifyResults: [Int64: Bool] = [:] // desiredKey → pass/fail
    @State private var verifyLogs: [(keyCode: Int64, label: String, pass: Bool)] = []
    
    // 프로필 저장
    @State private var showSaveDialog = false
    @State private var newProfileName = ""
    
    // Modifier 키코드
    private let knownModifiers: Set<Int64> = [
        Int64(kVK_Function), Int64(kVK_Control), Int64(kVK_Option), Int64(kVK_Command),
        Int64(kVK_RightCommand), Int64(kVK_RightOption), Int64(kVK_RightControl),
        Int64(kVK_CapsLock), Int64(kVK_Shift), Int64(kVK_RightShift)
    ]
    
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
            
            if profileStore.profiles.isEmpty {
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
                    ForEach(profileStore.profiles) { profile in
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
                profileStore.delete(id: profile.id)
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
            
            Text("현재 키보드의 **스페이스바 왼쪽 키**를 왼쪽부터 순서대로 눌러주세요")
                .font(.subheadline)
            
            keySlotRow(
                detected: detectedPhysicalKeys,
                waitingSlot: waitingSlot1,
                total: totalSlots,
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
                
                if detectedPhysicalKeys.count == totalSlots {
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
                total: totalSlots,
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
                
                if desiredKeys.count == totalSlots {
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
            
            Text("아무 키나 눌러서 매핑이 올바르게 적용되었는지 확인하세요")
                .font(.subheadline)
            
            // 매핑 + 검증 결과
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<totalSlots, id: \.self) { idx in
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
    
    // MARK: - Shared Key Slot Row
    
    private func keySlotRow(detected: [Int64], waitingSlot: Int, total: Int, stepLabel: String) -> some View {
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
                    ForEach(0..<totalSlots, id: \.self) { idx in
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
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            
            TextField("예: 맥북 내장, Keychron K2, ...", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            
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
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] original, _, _ in
            guard currentStep == 1 else { return }
            guard detectedPhysicalKeys.count < totalSlots else { return }
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
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] original, _, _ in
            guard currentStep == 2 else { return }
            guard desiredKeys.count < totalSlots else { return }
            guard knownModifiers.contains(original) else { return }
            // 원하는 키에서는 중복 허용하지 않음
            guard !desiredKeys.contains(original) else { return }
            
            desiredKeys.append(original)
            waitingSlot2 = desiredKeys.count
        }
    }
    
    private func applyAndGoToStep3() {
        var newMappings: [Int64: Int64] = [:]
        for (index, physKey) in detectedPhysicalKeys.enumerated() {
            let desKey = desiredKeys[index]
            if physKey != desKey { newMappings[physKey] = desKey }
        }
        
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
        currentStep = 3
        
        // 검증 콜백: HID가 적용되었으므로 들어오는 keyCode가 이미 desired key여야 함
        let desiredSet = Set(desiredKeys)
        
        appState.keyInterceptor.onVerifyKeyEvent = { [self] incomingKey, _, _ in
            guard currentStep == 3 else { return }
            
            let label = ModifierSlot.label(for: incomingKey)
            
            if desiredSet.contains(incomingKey) {
                // 원하는 키 중 하나가 도착 → 매핑 성공
                verifyResults[incomingKey] = true
                verifyLogs.append((keyCode: incomingKey, label: "\(label) ✅ 매핑 확인", pass: true))
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
            desiredKeys: desiredKeys
        )
        profileStore.add(profile)
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
