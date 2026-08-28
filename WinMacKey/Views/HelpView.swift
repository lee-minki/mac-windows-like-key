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
                    WinMac Key는 Right Command 입력을 내부적으로 \
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
                        "켜지면 메뉴바 아이콘이 또렷하게 채워지고, 꺼지면 흐릿한 외곽선으로 표시됩니다.",
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
                    
                    Text("※ 로컬 macOS는 Control+Space를 사용합니다. Windows VDI에서는 Right Command가 F16 릴레이를 사용합니다. Caps Lock은 앱이 직접 처리하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                
                GroupBox("키보드 레이아웃 커스터마이징") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("외장 키보드나 Windows 단축키 감각이 필요하다면, 위자드 표에서 키 매핑을 직접 설정할 수 있습니다.")
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 설정 → General Settings → \"새 프로필 만들기\"")
                            Text("2. 시작 화면: 프로필 이름 입력 + 의도 선택")
                            Text("   • \"한/영 전환만\" — 1클릭 즉시 완료 (키 배치 안 바꿈, 식별 프로필)")
                            Text("   • \"키 배치도 바꾸기\" — 매핑 표로 이동")
                            Text("3. 실제 키캡 순서에 맞는 키보드 형태 선택")
                            Text("   • Keys-To-Go 2: 포터블 Mac 4키 (Ctrl · Fn · Opt · Cmd)")
                            Text("   • Mac 추천값: Cmd · Fn · Opt · Ctrl")
                            Text("   • VDI 자동값: Ctrl · Win · Win · Alt")
                            Text("   • \"초기화\" 버튼: 선택한 형태의 추천값으로")
                            Text("4. 확인·저장: 매핑 요약 확인 후 \"저장하고 적용\"")
                            Text("※ 키보드를 누를 필요 없음 — macOS 가 모든 키보드를 같은 키코드로 보고하므로 표만으로 충분합니다 (Mac/Windows 듀얼모드 키보드 포함).")
                                .padding(.top, 4)
                            Text("※ 기존 프로필의 보조 Fn 키 설정은 편집 시 보존되며 새 위자드 UI 에 노출되지 않습니다. 변경하려면 프로필을 삭제하고 재생성하세요.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                GroupBox("키보드 디바이스별 자동 전환") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("내장/외장 키보드마다 다른 프로필을 자동 적용할 수 있습니다.")
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 위저드로 프로필을 만들고 저장합니다.")
                            Text("2. Settings → Profiles 탭에서 해당 프로필의 \"Bind keyboard…\" 버튼을 클릭합니다.")
                            Text("3. 바인딩할 키보드에서 아무 키나 한 번 누르면 디바이스(이름·VID:PID·내장/외장)가 감지됩니다.")
                            Text("4. 감지된 디바이스를 확인하고 \"바인딩\" 을 누릅니다. (키 입력이 어려우면 목록에서 직접 선택)")
                            Text("5. 바인딩 안 된 외장 키보드로 처음 입력하면 안내 창이 떠 [프로필 바인딩 / 이 키보드 무시 / 나중에] 를 묻습니다.")
                            Text("6. 내장 MacBook 키보드도 같은 방식으로 바인딩하면 고정 프로필처럼 동작합니다.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            Text("프로필 우선순위: 키보드 디바이스 > 앱(Bundle ID) > 기본 프로필. 자동 전환은 외장→내장 전환에서만 일어나고, 외장끼리 교체할 때는 마지막 프로필을 유지합니다 (원하는 프로필은 메뉴에서 직접 선택).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    Hammerspoon의 한영전환 핫키는 WinMac Key의 Right Command 전환과 \
                    충돌할 수 있으므로 더 이상 필요하지 않습니다.
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
                    1. Karabiner-Elements에서 `right_command`, `Control+Space`, `F16/F18/F19` 관련 규칙을 끄세요.\n\
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
                    현재 버전은 별도 드라이버 없이 동작합니다. 로컬 macOS에서는 \
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
                    네, 동작합니다. WinMac Key는 IOKit(IOHIDManager)으로 연결된 키보드를 자동 감지하며, \
                    내장 키보드, USB 키보드, Bluetooth 키보드 모두에서 동작합니다.\n\n\
                    내장/외장 키보드 전용 프로필을 만들 수 있습니다:\n\
                    1. 위저드에서 키캡 프린팅(Mac/Windows)을 선택하고 실키 감지 후 프로필을 저장합니다.\n\
                    2. Settings → Profiles 탭에서 "Bind keyboard…" 버튼을 누른 뒤, 바인딩할 키보드에서 아무 키나 한 번 누르면 그 키보드에 프로필이 바인딩됩니다 (Press-to-bind).\n\
                    3. 바인딩 안 된 외장 키보드로 처음 입력하면 안내 창이 떠 [프로필 바인딩 / 이 키보드 무시 / 나중에] 중에서 고를 수 있습니다.\n\n\
                    프로필 우선순위: 키보드 디바이스 프로필 > 앱 프로필 > 기본 프로필.\n\
                    자동 전환은 외장→내장 전환에서만 일어나고, 외장끼리 교체할 때는 마지막 프로필을 유지합니다.
                    """
                )

                faqItem(
                    question: "VDI에서 한영전환 후 Shift+영문을 치면 화면녹화가 켜져요.",
                    answer: """
                    최신 버전은 두 단계로 대응합니다.\n\n\
                    1. 트리거 직후 첫 키를 약 15ms만 버퍼링해 VDI의 `F16 → Right Alt` 변환이 먼저 끝나게 합니다.\n\
                    2. 이어서 50ms 동안 잔여 modifier 플래그를 정리해 `Alt+key` 오발을 막습니다.\n\n\
                    첫 키에만 매우 짧은 정렬이 들어가고, 그 뒤 타이핑은 정상 속도로 통과합니다.
                    """
                )

                faqItem(
                    question: "로컬 Mac에서 첫 글자가 영어로 들어가요. 예: xㅓ미널",
                    answer: """
                    입력소스 전환이 실제로 확인되기 전에 첫 글자가 풀리면 이런 현상이 납니다.\n\n\
                    최신 버전은 `Control+Space` 전환 후 입력소스 변경을 검증하고, 짧은 최소 홀드 시간을 둔 뒤 버퍼를 풉니다.\n\n\
                    그래도 재현되면 다음을 같이 확인하세요.\n\
                    1. 시스템 설정에서 \"이전 입력 소스 선택\"이 정확히 `Control + Space`인지\n\
                    2. Caps Lock 한영전환, Karabiner, Hammerspoon 같은 중복 전환 도구가 꺼져 있는지\n\
                    3. Event Viewer에서 전환 직후 첫 키가 어느 앱에서 어떻게 들어오는지
                    """
                )

                faqItem(
                    question: "Ghostty / Claude Code에서 `[57379u]` 같은 문자열이 떠요.",
                    answer: """
                    이 문자열은 Ghostty가 F16 키를 raw terminal sequence로 출력할 때 보일 수 있습니다.\n\n\
                    최근 터미널 전용 direct tap 실험은 Ghostty에서 실제 Command 단축키 누출 회귀를 만들 수 있어 현재 최종 해법으로 간주하지 않습니다.\n\n\
                    재설계 전까지는 다음을 확인하세요.\n\
                    1. WinMac Key 엔진을 껐다가 다시 켰는지\n\
                    2. 다른 도구가 `Right Command`나 `F16`을 함께 가로채지 않는지\n\
                    3. Event Viewer / 로그에서 실제로 어떤 경로가 사용되는지\n\
                    4. 검색 UI, `Cmd+N`, `Cmd+D` 같은 Command shortcut 누출이 함께 있는지
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
