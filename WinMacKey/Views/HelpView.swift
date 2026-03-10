import SwiftUI

/// 도움말 & 설정 가이드 화면
struct HelpView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            quickStartTab
                .tabItem { Label("시작 가이드", systemImage: "flag.checkered") }
                .tag(0)
            
            keyMappingTab
                .tabItem { Label("키 매핑", systemImage: "keyboard") }
                .tag(1)
            
            migrationTab
                .tabItem { Label("기존 도구 전환", systemImage: "arrow.triangle.swap") }
                .tag(2)
            
            faqTab
                .tabItem { Label("FAQ", systemImage: "questionmark.circle") }
                .tag(3)
        }
        .frame(width: 620, height: 520)
    }
    
    // MARK: - Quick Start (Fresh Mac)
    
    private var quickStartTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("WinMac Key 시작 가이드")
                        .font(.title2.bold())
                    Text("macOS 초기 상태에서 설치하는 분들을 위한 가이드입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Step 1: Permission
                stepCard(
                    number: 1,
                    title: "손쉬운 사용 권한 허용",
                    description: """
                    WinMac Key는 키보드 입력을 가로채서 변환하기 위해 macOS의 \
                    "손쉬운 사용(Accessibility)" 권한이 반드시 필요합니다.
                    """,
                    steps: [
                        "앱을 처음 실행하면 권한 요청 팝업이 표시됩니다.",
                        "\"시스템 설정 열기\" 를 클릭합니다.",
                        "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용",
                        "목록에서 \"WinMac Key\" 를 찾아 토글을 켭니다.",
                        "Mac 비밀번호를 입력하여 확인합니다."
                    ],
                    warning: "권한 허용 후 앱을 한 번 재시작해야 적용될 수 있습니다."
                )
                
                // Step 2: CapsLock Setting
                stepCard(
                    number: 2,
                    title: "CapsLock 한/영 전환 끄기",
                    description: """
                    macOS는 기본적으로 CapsLock 키로 한영 전환을 합니다. \
                    WinMac Key의 Right Command 한영전환과 충돌하지 않도록 이 기능을 꺼야 합니다.
                    """,
                    steps: [
                        "시스템 설정 → 키보드 로 이동합니다.",
                        "\"입력 소스\" 섹션에서 \"모든 입력 소스\" 를 클릭합니다.",
                        "\"Caps Lock 키로 ABC 입력 소스 전환\" 체크를 해제합니다."
                    ],
                    warning: nil
                )
                
                // Step 3: Input Source Shortcut
                stepCard(
                    number: 3,
                    title: "입력 소스 단축키 확인",
                    description: """
                    WinMac Key는 Right Command/Option 입력을 내부적으로 \
                    "이전 입력 소스 선택" 단축키(⌃Space)로 합성합니다. \
                    이 항목이 켜져 있고 Control+Space로 설정되어 있어야 합니다.
                    """,
                    steps: [
                        "시스템 설정 → 키보드 → 키보드 단축키... 를 클릭합니다.",
                        "좌측 목록에서 \"입력 소스\" 를 선택합니다.",
                        "\"이전 입력 소스 선택\" 의 체크박스가 켜져 있는지 확인합니다.",
                        "단축키가 \"Control + Space\" 인지 확인합니다.",
                        "다른 키로 되어 있다면 더블클릭 후 \"Control + Space\" 로 변경합니다.",
                        "\"입력 메뉴에서 다음 소스 선택\" 은 필요 시 비활성화해도 됩니다.",
                        "\"완료\" 를 클릭합니다."
                    ],
                    warning: """
                    이 항목이 꺼져 있거나 다른 키로 바뀌어 있으면 \
                    WinMac Key의 한/영 전환이 동작하지 않습니다.
                    """
                )
                
                // Step 4: Enable Engine
                stepCard(
                    number: 4,
                    title: "엔진 활성화",
                    description: "설정이 끝나면 WinMac Key 엔진을 켭니다.",
                    steps: [
                        "메뉴바(화면 우측 상단)에서 WinMac Key 아이콘을 클릭합니다.",
                        "\"엔진 상태\" 토글을 켭니다.",
                        "키보드를 눌러 정상 동작을 확인합니다."
                    ],
                    warning: nil
                )
            }
            .padding(24)
        }
    }
    
    // MARK: - Key Mapping Tab
    
    private var keyMappingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("키 매핑 테이블")
                        .font(.title2.bold())
                    Text("WinMac Key가 변환하는 키 목록입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Main Mappings
                GroupBox("기본 매핑 (항상 활성)") {
                    VStack(spacing: 0) {
                        mappingHeader
                        Divider()
                        mappingRow("fn (🌐)", "Left Command (⌘)", "Windows 배치와 동일하게 Ctrl 위치에 Cmd 배치", .blue)
                        Divider()
                        mappingRow("Left Command (⌘)", "Left Control (⌃)", "Cmd 위치에 Ctrl을 배치", .green)
                        Divider()
                        mappingRow("Left Control (⌃)", "fn (🌐)", "Ctrl 위치에 fn을 배치", .orange)
                    }
                }
                
                GroupBox("한/영 전환") {
                    VStack(spacing: 0) {
                        mappingHeader
                        Divider()
                        mappingRow("Right Command (⌘)", "한/영 전환", "탭(짧게 누르기)으로 입력 소스 전환 (기본)", .purple)
                        Divider()
                        mappingRow("Right Option (⌥)", "한/영 전환", "탭으로 입력 소스 전환 (설정에서 변경 가능)", .purple)
                    }
                }
                
                GroupBox("VDI 호환 (추가 드라이버 불필요)") {
                    VStack(spacing: 0) {
                        mappingHeader
                        Divider()
                        mappingRow("Right Command (⌘)", "F16", "WinMac Key가 Windows VDI용 릴레이 키를 전송", .red)
                        Divider()
                        mappingRow("VDI Client", "Right Alt", "Omnissa Horizon 등에서 F16을 Right Alt로 매핑", .orange)
                    }
                    
                    Text("※ 로컬 macOS/원격 Mac은 Control+Space, Windows VDI는 F16 릴레이 키를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                
                GroupBox("키보드 레이아웃 커스터마이징") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("외장 키보드나 특수 배치를 사용한다면, 위저드로 직접 키 매핑을 설정할 수 있습니다.")
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 설정 → General Settings → \"새 프로필 만들기\"")
                            Text("2. Step 1: 키캡 프린팅이 `Mac 키보드`인지 `Windows 키보드`인지 선택")
                            Text("3. Step 2: 스페이스바 왼쪽 modifier를 실제로 누르고 마지막에 `Space`를 눌러 현재 입력 감지")
                            Text("4. `Space` 앞에 감지된 키 개수로 3키/4키 자동 판단")
                            Text("5. Step 3: 로컬 macOS에서 `Fn / Ctrl / Cmd / Opt` 배치를 왼쪽부터 선택")
                            Text("6. Step 4: VDI에서 `Ctrl / Win / Alt` 배치를 왼쪽부터 선택")
                            Text("7. 슬롯을 직접 눌러 선택한 뒤 원하는 기능 키로 즉시 교체 가능")
                            Text("8. 3키 키보드라면 `RCtrl`/`Caps`/`RShift`를 보조 Fn 키로 지정 가능")
                            Text("9. Step 5: 현재 컨텍스트를 검증한 뒤 프로필 저장")
                            Text("10. 저장된 프로필은 로컬 Mac과 VDI 사이를 자동 전환하며, 앱 할당은 현재 앱 기준으로 동작")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                
                // Keyboard Layout Diagram
                GroupBox("키보드 배치 비교") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("변환 전 (Mac 기본)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        keyboardRow(keys: [
                            ("⌃", "Control", .gray),
                            ("⌥", "Option", .gray),
                            ("⌘", "Command", .gray),
                            ("Space", "", .gray),
                            ("⌘", "Command", .gray),
                            ("⌥", "Option", .gray),
                        ])
                        
                        Text("변환 후 (WinMac Key 적용)")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        keyboardRow(keys: [
                            ("fn", "", .orange),
                            ("⌥", "Option", .gray),
                            ("⌘", "Command", .blue),
                            ("Space", "", .gray),
                            ("한/영", "", .purple),
                            ("⌥", "Option", .gray),
                        ])
                        
                        Text("※ fn 키 위치에서 Command, Command 위치에서 Control, Control 위치에서 fn이 동작합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Migration Tab
    
    private var migrationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("기존 도구에서 전환하기")
                        .font(.title2.bold())
                    Text("Karabiner-Elements, Hammerspoon 등을 사용 중이라면 아래 단계를 따라주세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Karabiner-Elements
                stepCard(
                    number: 1,
                    title: "Karabiner-Elements 비활성화",
                    description: """
                    Karabiner-Elements는 WinMac Key와 동일한 레벨(CGEventTap)에서 \
                    키 입력을 가로챕니다. 두 프로그램이 동시에 같은 키를 처리하면 \
                    예측 불가능한 동작이 발생합니다.
                    """,
                    steps: [
                        "Karabiner-Elements 앱을 엽니다.",
                        "\"Profiles\" 탭으로 이동합니다.",
                        "\"Add profile\" 로 빈 프로필(예: \"Empty\")을 만듭니다.",
                        "새로 만든 빈 프로필을 \"Select\" 합니다.",
                        "또는 Karabiner-Elements 앱 자체를 종료합니다."
                    ],
                    warning: """
                    Karabiner를 완전히 제거하지 않아도 됩니다. \
                    빈 프로필을 선택하면 모든 매핑이 비활성화되며, \
                    WinMac Key를 끄면 언제든 기존 프로필로 돌아갈 수 있습니다.
                    """
                )
                
                // Hammerspoon
                stepCard(
                    number: 2,
                    title: "Hammerspoon 비활성화",
                    description: """
                    Hammerspoon의 F18/F19 한영전환 핫키는 WinMac Key가 \
                    Right Command로 직접 한영전환을 처리하므로 더 이상 필요하지 않습니다.
                    """,
                    steps: [
                        "메뉴바에서 Hammerspoon 아이콘(🔨)을 클릭합니다.",
                        "\"Quit Hammerspoon\" 을 선택합니다.",
                        "또는 ~/.hammerspoon/init.lua 파일 전체를 주석 처리합니다."
                    ],
                    warning: nil
                )
                
                // macOS Shortcuts
                stepCard(
                    number: 3,
                    title: "macOS 입력 소스 단축키 확인",
                    description: """
                    WinMac Key의 로컬 macOS/원격 Mac 경로는 "이전 입력 소스 선택" 단축키를 \
                    Control+Space로 합성합니다. 비활성화하지 말고, 올바른 키로 맞춰 두어야 합니다.
                    """,
                    steps: [
                        "시스템 설정 → 키보드 → 키보드 단축키... 를 클릭합니다.",
                        "좌측 목록에서 \"입력 소스\" 를 선택합니다.",
                        "\"이전 입력 소스 선택\" 체크박스가 켜져 있는지 확인합니다.",
                        "단축키가 \"Control + Space\" 인지 확인하고, 다르면 변경합니다.",
                        "\"입력 메뉴에서 다음 소스 선택\" 은 필요 시 비활성화합니다.",
                        "\"완료\" 를 클릭합니다."
                    ],
                    warning: """
                    이 항목을 끄면 로컬 macOS/원격 Mac 환경에서 WinMac Key 전환이 동작하지 않습니다.
                    """
                )
                
                // CapsLock
                stepCard(
                    number: 4,
                    title: "CapsLock 한영전환 끄기",
                    description: "시작 가이드의 Step 2와 동일합니다.",
                    steps: [
                        "시스템 설정 → 키보드 로 이동합니다.",
                        "\"입력 소스\" → \"모든 입력 소스\" 를 클릭합니다.",
                        "\"Caps Lock 키로 ABC 입력 소스 전환\" 체크를 해제합니다."
                    ],
                    warning: nil
                )
                
                // Rollback Info
                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("원래대로 돌아가려면?")
                                .font(.headline)
                            Text("""
                            WinMac Key를 끄고 위 단계를 역순으로 수행하면 됩니다: \
                            Karabiner-Elements에서 기존 프로필 선택 → \
                            Hammerspoon 재시작 → macOS 입력 소스 단축키 재활성화.
                            """)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(4)
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - FAQ Tab
    
    private var faqTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("자주 묻는 질문")
                        .font(.title2.bold())
                }
                
                Divider()
                
                faqItem(
                    question: "앱을 실행했는데 키 매핑이 동작하지 않아요.",
                    answer: """
                    1. 메뉴바에서 엔진이 \"실행 중\" 인지 확인하세요.
                    2. 손쉬운 사용 권한이 허용되어 있는지 확인하세요.\n        (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용)
                    3. Karabiner-Elements가 실행 중이면 반드시 비활성화하세요.
                    4. 앱을 종료 후 다시 실행해보세요.
                    """
                )
                
                faqItem(
                    question: "손쉬운 사용 권한을 허용했는데 동작하지 않아요.",
                    answer: """
                    macOS에서는 권한 변경 후 앱을 재시작해야 적용되는 경우가 있습니다. \
                    WinMac Key를 완전히 종료(메뉴바 → \"WinMac Key 종료\") 후 다시 실행해주세요. \
                    그래도 안 되면 손쉬운 사용 목록에서 WinMac Key를 제거한 뒤 다시 추가해보세요.
                    """
                )
                
                faqItem(
                    question: "한/영 전환이 안 돼요.",
                    answer: """
                    Right Command 키를 짧게 \"탭\" 해야 합니다. 길게 누르거나, 누른 상태에서 \
                    다른 키를 함께 누르면 한/영 전환이 아닌 단축키 조합으로 인식됩니다.\n\n\
                    또한 macOS의 \"이전 입력 소스 선택\"이 반드시 `Control + Space`로 켜져 있어야 합니다:\n\
                    시스템 설정 → 키보드 → 키보드 단축키... → 입력 소스.\n\n\
                    또한 macOS에 한글 입력 소스가 등록되어 있어야 합니다:\n\
                    시스템 설정 → 키보드 → 입력 소스 → 편집... → + 버튼으로 \"한국어 - 2벌식\" 추가.
                    """
                )

                faqItem(
                    question: "입력 소스 전환창이 뜨거나 두세 번 눌러야 바뀌어요.",
                    answer: """
                    대부분 WinMac Key 외의 다른 앱이 같은 전환 키를 함께 처리할 때 생깁니다.\n\n\
                    1. Karabiner-Elements에서 `right_command`, `right_option`, `Control+Space`, `F18/F19` 관련 규칙을 끄세요.\n\
                    2. Leader Key 류 앱에서 `Control+Space`를 쓰고 있지 않은지 확인하세요.\n\
                    3. Hammerspoon/BetterTouchTool/Keyboard Maestro에 한영 전환 핫키가 있으면 해제하세요.\n\n\
                    특히 Karabiner의 Right Command 규칙이 켜져 있으면 한 번 눌렀을 때 전환이 중복 실행되어, 즉시 토글되지 않거나 입력 소스 전환창이 뜰 수 있습니다.
                    """
                )
                
                faqItem(
                    question: "VMware에서 한/영 전환이 안 되나요?",
                    answer: """
                    VMware Horizon, Parallels Desktop, Microsoft Remote Desktop 같은 \
                    원격 데스크톱 앱에서는 Right Command 키가 Windows에 전달되지 않을 수 있습니다.\n\n\
                    현재 버전은 별도 드라이버 없이 동작합니다. 로컬 macOS/원격 Mac에서는 \
                    \"이전 입력 소스 선택\"이 `Control + Space`로 켜져 있어야 하고, \
                    Windows VDI 클라이언트에서는 `F16 → Right Alt` 매핑을 추가해야 합니다.\n\n\
                    설정 방법은 GitHub 레포의 docs/VDI_SETUP.md를 참조하세요.
                    """
                )
                
                faqItem(
                    question: "Karabiner-Elements와 동시에 쓸 수 있나요?",
                    answer: """
                    권장하지 않습니다. 두 프로그램 모두 CGEventTap을 사용하여 같은 레벨에서 \
                    키 입력을 가로채므로, 동시에 같은 키를 매핑하면 충돌이 발생합니다.\n\n\
                    Karabiner에서 WinMac Key와 관련 없는 매핑만 남기고 \
                    fn/Cmd/Ctrl/Right Cmd 관련 매핑을 제거하면 공존할 수 있지만, \
                    예상치 못한 문제가 생길 수 있으므로 WinMac Key만 사용하는 것을 권장합니다.
                    """
                )
                
                faqItem(
                    question: "외장 키보드에서도 동작하나요?",
                    answer: """
                    네, 동작합니다. WinMac Key는 모든 키보드 입력을 시스템 레벨에서 인터셉트하므로 \
                    내장 키보드, USB 키보드, Bluetooth 키보드 모두에서 동작합니다.\n\n\
                    외장 키보드의 경우 스페이스바 왼쪽 modifier를 실제로 눌러 3키/4키를 자동으로 감지합니다.\n\n\
                    위저드에서는 먼저 키캡 프린팅이 Mac 키보드인지 Windows 키보드인지 고르고, 현재 입력은 실키로 감지한 뒤 로컬 Mac과 VDI 목표 배치를 각각 따로 잡을 수 있습니다.\n\n\
                    로컬 Mac 단계는 `Fn / Ctrl / Cmd / Opt`, VDI 단계는 `Ctrl / Win / Alt`만 보여주며, 슬롯을 직접 눌러 수정할 수 있습니다.\n\n\
                    3키 키보드라면 `RCtrl`, `Caps`, `RShift` 중 하나를 보조 Fn 키로 지정할 수 있습니다.\n\n\
                    다만 프로필 이름은 장치 식별자가 아니라 표시용이며, 앱 할당은 현재 앱 기준으로 동작합니다.
                    """
                )
                
                Divider()
                
                // Version & Links
                HStack {
                    Text("WinMac Key v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("GitHub") {
                        if let url = URL(string: "https://github.com/lee-minki/mac-windows-like-key") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Component Helpers
    
    private func stepCard(
        number: Int,
        title: String,
        description: String,
        steps: [String],
        warning: String?
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 28, height: 28)
                        Text("\(number)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .trailing)
                            Text(step)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 38)
                
                if let warning = warning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 38)
                }
            }
            .padding(4)
        }
    }
    
    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                Text(question)
                    .font(.subheadline.bold())
            }
            
            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }
    
    private var mappingHeader: some View {
        HStack(spacing: 0) {
            Text("원본 키")
                .font(.caption.bold())
                .frame(width: 160, alignment: .leading)
            Text("변환 키")
                .font(.caption.bold())
                .frame(width: 140, alignment: .leading)
            Text("설명")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func mappingRow(_ from: String, _ to: String, _ desc: String, _ color: Color) -> some View {
        HStack(spacing: 0) {
            Text(from)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 160, alignment: .leading)
            
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(to)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color)
            }
            .frame(width: 140, alignment: .leading)
            
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private func keyboardRow(keys: [(String, String, Color)]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                VStack(spacing: 2) {
                    Text(key.0)
                        .font(.system(.caption2, design: .rounded).bold())
                }
                .frame(width: key.0 == "Space" ? 100 : 64, height: 32)
                .background(key.2.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(key.2.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

#Preview {
    HelpView()
}
