# Changelog

All notable changes to WinMac Key will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

---

## [1.7.0] — 2026-05-31

**"안정화 + 정리" 릴리스.** v1.6.0 → v1.6.1 → v1.6.2 의 같은 날 sequential hotfix 3건 이후, 핫픽스의 공통 메커니즘(`bufferedReplayWindow`)을 전수 리뷰해 구조적 결함 해소 + 회귀 가드 테스트 추가.

### Changed
- **`bufferedReplayWindow` 메커니즘 main-thread contract 명문화** (`WinMacKey/Services/KeyInterceptor.swift`).
  CGEventTap 콜백(`CFRunLoopAddSource` 로 main RunLoop 등록 → 항상 main thread 발화) + DispatchQueue.main 의 timer/work item 모두 main thread 에서 동작이라는 암묵적 contract 를 클래스 헤더 주석으로 명시 + `begin*/complete*/fail*/buffer*/start*/schedule*/flush*/cancel*` 모든 메서드 시작부에 `assert(Thread.isMainThread, ...)` 추가. DEBUG 빌드에서 위반 시 즉시 crash, RELEASE 영향 0. 향후 `@MainActor` 격리는 별도 Swift 6 마이그레이션 PR (audit B).
- **Adaptive commit window timeout — 앱 카테고리별 분리** (`WinMacKey/Services/KeyInterceptor.swift` + `WinMacKey/Services/ContextManager.swift` + `WinMacKey/WinMacKeyApp.swift`).
  v1.6.2 의 단일 `0.150` 을 두 값으로 분리:
  - **일반 앱**(Notes/TextEdit/Safari 일반 입력 등): `0.100` (100ms) — TIS notification 빠르게 옴, 사용자 체감 즉시
  - **IME-sensitive 앱**(Word/Pages/Keynote/PowerPoint/Excel/Outlook/Adobe Acrobat 등): `0.180` (180ms) — TIS notification 늦게 발화해 짧은 타임아웃에선 매번 풀 대기 + replay burst 가 IME 처리 속도 초과 → 글자 drop. v1.6.2 의 0.150 보다 안정적.
  `ContextManager.imeSensitiveApps` 화이트리스트 + `isIMESensitiveApp` 발행 + `KeyInterceptor.isIMESensitiveAppFocused` 동기화 + `currentInputSourceCommitTimeout` computed property 로 자동 선택.

### Added
- **회귀 가드 스모크 테스트 2개**:
  - `tests/commit_window_smoke.swift` — bufferedReplayWindow 의 guard(VDI/Terminal) + begin/complete/fail/supersede 안전성 7 invariants
  - `tests/buffered_replay_smoke.swift` — IME-sensitive adaptive timeout (0.100 vs 0.180) + 가드 플래그 독립성 6 invariants
  `scripts/run-tests.sh` 에 추가. 향후 commit window 회귀 즉시 감지.

### Note
- Info.plist 1.6.2/21 → **1.7.0/22**, `MARKETING_VERSION 1.7.0`, `CURRENT_PROJECT_VERSION 22`.
- v1.6.0~v1.6.2 의 fix 들은 모두 보존 (P10 isTerminalAppFocused 가드, P13 intra-replay 5ms).
- v1.6.2 의 `inputSourceCommitTimeout = 0.150` 단일 값은 제거 — adaptive 로 대체.
- **P9 (한영 간헐 실패)** 는 별개 후속 — v1.7.0 설치 후 재현 여부 회신 대기. v1.7.0 의 main-thread assert 가 P9 의 잠재적 race 원인을 노출할 가능성 있음(만약 background thread 호출이 원인이라면).

---

## [1.6.2] — 2026-05-31

v1.6.1 publish 직후 사용자 보고 **P13 (Microsoft Word for Mac 에서 한/영 전환 후 느려지고 글자 씹힘) 핫픽스**. v1.3.x 부터 잠재했던 IME-sensitive 앱 호환성 문제.

### Fixed
- **P13 · `bufferedReplayWindow` 의 commit window + replay burst 가 Word for Mac IME 와 충돌** (`WinMacKey/Services/KeyInterceptor.swift`).
  **증상**: Word for Mac 에서 한/영 전환 후 ① 토글 자체가 ~220ms 체감 지연 ② 빠르게 타이핑하면 한 글자씩 씹힘(드롭) 발생. v1.6.0 회귀가 아니라 v1.3.x 부터 있던 사전 기존 버그 — Word 의 IME 가 TIS notification 을 느리게 발화해 commit window 가 매번 풀 타임아웃까지 대기 + 220ms 후 burst replay 의 0.5ms 인터벌이 Word IME 처리 속도보다 빨라 일부 키 drop.
  **수정 (2점 패치)**:
  1. `inputSourceCommitTimeout` **0.220 → 0.150** (220ms → 150ms 단축, 사용자 체감 지연 ~30% 감소). 트레이드오프: TIS notification 이 150-220ms 사이에 오는 극단 케이스에서 첫 글자 mis-route 가능성 — 희박.
  2. `flushBufferedKeyEvents` 의 intra-replay `usleep(500)` **0.5ms → 5ms**. Word/기타 느린 IME 가 각 키를 안정 처리할 시간 확보. 5키 replay 총 시간 2ms → 20ms (인지 불가 수준).
  **영향 범위**: Word for Mac + 잠재적으로 기타 IME-sensitive 앱 (Pages, Keynote, 일부 브라우저 입력 필드). 터미널/SSH 는 v1.6.1 의 isTerminalAppFocused 가드로 이미 우회 중이라 영향 없음.

### Note
- Info.plist 1.6.1/20 → **1.6.2/21**, `MARKETING_VERSION 1.6.2`, `CURRENT_PROJECT_VERSION 21`.
- 본 핫픽스는 commit window 의 튜닝이라 다른 앱(Notes, TextEdit 등 정상 IME 앱) 동작에는 변화 없음.
- **P9 (한영 간헐 실패)** 는 별개 후속 — 사용자 v1.6.2 설치 후 재현 여부 회신 대기.

---

## [1.6.1] — 2026-05-31

v1.6.0 publish 후 사용자 보고 **P10 (Ghostty/SSH 에서 ESC/Backspace → 화면 깨짐) 핫픽스**. v1.5.x 부터 잠재하던 엔진 레벨 회귀.

### Fixed
- **P10 · `bufferedReplayWindow + 터미널 escape sequence` 충돌** (`WinMacKey/Services/KeyInterceptor.swift`, `WinMacKey/WinMacKeyApp.swift`).
  **증상**: SSH 세션에서 ESC/Backspace 누르면 이전 paste 내용이 한 글자씩 줄어들며 무한 재출력 → `^C`/`^L`/`^D` 등 control char 가 화면에 노출. 사용자 SSH 작업 불가능.
  **원인**: Right Cmd 한/영 트리거 직후 220ms `inputSourceCommit` 윈도우 동안 모든 키가 buffer + `return nil` 처리됨 → 220ms 후 flush 가 SSH 가 escape sequence 로 해석할 키 시퀀스를 한꺼번에 replay → 깨짐 cascade. 터미널 분기(`handleTerminalTrigger` + `toggleDirectly()`) 는 commit window 가 불필요한데, `KeyInterceptor` 가 터미널 포커스를 모르고(`isTerminalAppFocused` 자체 부재) `WinMacKeyApp.onInputSourceToggle` 콜백의 if-else 분기에만 의존 → focus race 시 가드 풀림.
  **수정**: ① `KeyInterceptor.isTerminalAppFocused` 프로퍼티 신설(VDI 가드와 같은 패턴) ② `beginInputSourceCommitWindow` 에 `guard !isTerminalAppFocused else { return }` 추가 ③ `handleMappedKey` 의 buffer 분기에도 같은 가드 추가(focus race 안전망) ④ `WinMacKeyApp` 의 `onAppChanged` 에서 `isTerminalAppFocused` 도 동기화.
  **검증**: 터미널 화이트리스트(`com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `ai.warp.Warp-Stable`, `io.alacritty`, `net.kovidgoyal.kitty`, `dev.warp.Warp-Stable`, `com.anthropic.claudefordesktop`) 포커스 시 commit window 자체가 안 열림 + 어떤 이유로 열려 있어도 터미널 키는 즉시 통과.

### Note
- Info.plist 1.6.0/19 → **1.6.1/20**, `MARKETING_VERSION 1.6.1`, `CURRENT_PROJECT_VERSION 20`.
- **P9 (한영 간헐 실패)** 는 별개 후속 — 사용자 v1.6.1 설치 후 재현 여부 회신 대기.
- 본 핫픽스는 엔진 레벨이라 위자드/문서 변경 없음.

---

## [1.6.0] — 2026-05-30

신규 맥 온보딩의 최대 마찰 지점이었던 **프로필 위자드를 캡처 없는 표 기반으로 전면 재설계.** 외부 문서·인앱 도움말 일괄 동기화, 옵셔널 필드 보존 정책 명문화, dead code 정리.

### Changed
- **위자드 전면 재설계 — 캡처 없는 키코드 기반 직접 매핑 표** (`WinMacKey/Views/ModifierLayoutView.swift`).
  근거: macOS 가 모든 키보드를 표준 modifier 키코드(Ctrl/Opt/Cmd/Fn)로 정규화하므로 물리 키 캡처는 **로직적으로 불필요**했고, Mac/Win 듀얼모드 키보드(로지텍 등)에서는 오히려 깨졌다(이모지·한영·Spotlight 오발).
  새 흐름은 3화면 — ① **시작/의도**(프로필 이름 + "한/영 전환만" 1클릭 vs "키 배치도 바꾸기"), ② **매핑 표**(Fn·Ctrl·Opt·Cmd 4행 × Mac/VDI 2열 picker, Mac/Windows 키캡 표기 토글, "Windows 감각" 1클릭 프리셋=Cmd↔Ctrl 스왑, "초기화" 버튼, 라이브 미리보기), ③ **확인·저장**.
- **`SavedKeyboardProfile` 모델 호환성 — 정확한 정의**: 모델 struct 시그니처는 그대로. 새 표 위자드가 UI 에 노출하지 않는 옵셔널 3필드(`auxiliaryFnKey` · `bundleId` · `deviceIdentifier`)는 **편집 시 기존 값을 보존**한다. 변경하려면: `auxiliaryFnKey` 는 프로필 삭제 후 재생성, `bundleId`/`deviceIdentifier` 는 Profiles 탭의 "Bind keyboard…" UI 에서.
- 제거: Step 1 (표기 단독 화면, 표 안 토글로 흡수), Step 2 (현재 입력 감지/캡처), Step 3·4 슬롯+팔레트(표 한 화면으로 통합), 3키/4키 자동판단, 내장/외장 프리셋 버튼, "+ Fn 🌐" 버튼, Fn 이모지 팝업, slot 펄스 글로우.

### Fixed
- **프로필 삭제 안전 처리 (회귀)** (`WinMacKey/WinMacKeyApp.swift`, `WinMacKey/Views/DashboardView.swift`, `WinMacKey/Views/ModifierLayoutView.swift`): 새 ModifierLayoutView 의 삭제 버튼이 `activeMappingProfileId` 리셋과 HID 매핑 clear 를 안 하던 회귀를 수정. invariant 를 `AppState.deleteProfileSafely(_:)` service 메서드로 추출해 두 UI 가 공용 경로 사용.
- **`auxiliaryFnKey` silent 손실 (회귀)** (`WinMacKey/Views/ModifierLayoutView.swift`): 새 위자드가 편집 저장 시 무조건 `nil` 처리하던 코드 제거. 기존 보조 Fn 설정 보존.
- **인앱 도움말 (`HelpView`) 새 흐름 동기화**: 옛 Step 1~5 + `+Fn 🌐` 안내를 새 3화면 표 흐름 안내로 교체.

### Removed
- **dead code 정리** (호출처 0건, 동적 호출 검증 완료): `KeyInterceptor.{onVerifyKeyEvent, startTapForVerify, stopTapForVerify, dispatchVerificationCallback}`, `KeyInterceptor` 의 verify-suppress 분기, `KeyboardDeviceManager.{onFnKeyDown, handleFnKeyDown, appleFnUsagePage/Usage 상수, Fn 검출 분기}`.

### Docs
- 외부 문서 일괄 동기화 (이번 릴리스에 포함): `README.md` · `docs/manual.html` · `docs/FEATURE_SPEC.md` (§2 매트릭스 P1~P8 + §2.1 + §7 회귀 → v1.6 기준 재작성) · `docs/VDI_SETUP.md` · `docs/FRESH_INSTALL_CHECKLIST.md` (Section D Fn 진단 → 표 기반 매핑 검증으로 교체).

### Note
- Info.plist `1.5.1/18` → `1.6.0/19`, `MARKETING_VERSION 1.6.0`, `CURRENT_PROJECT_VERSION 19`.

---

## [1.5.1] — 2026-05-29

신규 맥 "다운로드→설치→설정→사용" 무이탈 온보딩 완성. 첫 사용자가 막히지 않고 끝까지 가도록 펀넬·가이드·동작 모델을 정리.

### Changed
- **엔진 = 프로필 게이트** (`WinMacKey/WinMacKeyApp.swift`): 저장 프로필이 0개면 엔진을 켤 수 없다("엔진 ON = 전 기능 동작" 인지 모델). 설정·프로필을 먼저 끝내야 켜짐. 메뉴바 토글 비활성 + 힌트.
- **권한 프롬프트 순서 수정**: IOHIDManager(입력 모니터링 프롬프트 유발)를 권한이 있을 때만 연다. 첫 실행 환영 *전*에 프롬프트가 뜨던 문제 해소 — 권한은 설정 점검 패널의 명시 버튼에서만 요청.
- 위자드 Step 3 팔레트 순서 `Cmd · Fn · Opt · Ctrl`, Step 4 VDI 맥 4키 기본값 `Ctrl · Win · Win · Alt` 자동 채움.

### Fixed
- **위자드에서 Ctrl/Opt/Cmd 가 감지되지 않던 문제** (`WinMacKey/Services/KeyInterceptor.swift`): 엔진 게이트로 프로필 생성 전엔 엔진(CGEventTap)이 꺼져 있어 modifier 감지가 안 됐다. 검증 전용 tap(`startTapForVerify`/`stopTapForVerify`)을 띄워 엔진 OFF·HID 비간섭 상태에서도 감지.

### Added
- **첫 실행 환영 + 설정 점검 자동 표시**: 첫 실행/프로필 0개/권한·환경 이슈가 있으면 패널로 안내.
- **한/영 전환만 빠른 시작**: 키바인딩 안 바꾸고 한/영만 쓰려는 사용자용 항등 프로필 1클릭 생성(위자드 스킵).
- **위자드 코치마크** (`WinMacKey/Views/ModifierLayoutView.swift`): 단계별 "지금 할 일 + 왜" 카드, 다음 입력 슬롯 펄스 글로우(초록 "여기"/파랑), Fn 이모지 안내 팝업("다시 보지 않기").
- **VDI(Omnissa Horizon) 설정 안내**: Step 4 접이식 카드 — 기본 단축키 전부 해제 + `F16 → Right Alt` 하나만 추가 + '기본값 복원' 함정 경고.
- **앱 다시 시작 버튼**: macOS "종료하고 다시 열기"가 메뉴바 전용(LSUIElement) 앱을 재실행 못 하는 문제 우회(분리 셸 재실행).

### Note
- build 18. v1.5.0(미출시 Draft)의 온보딩을 실사용 가능한 수준으로 완성한 릴리스.

---

## [1.5.0] — 2026-05-29

신규 맥 첫 설치 온보딩 개편. 권한·환경 설정을 실행 시 자동 점검·안내하고, 첫 실행 흐름과 위자드 사용성을 정리.

### Fixed
- **신규 설치에서 손쉬운 사용 권한 프롬프트가 뜨지 않던 문제** (`WinMacKey/WinMacKeyApp.swift`): 권한 요청을 `init` 에서 호출해 LSUIElement(메뉴바 전용) 앱이 실행 완료 전이라 시스템 프롬프트가 표시되지 않았고, 안내 UI 도 없어 신규 사용자가 조용히 막혔다(위자드에서 Ctrl/Opt/Cmd 미인식). 권한 요청을 init 밖으로 옮기고, 실행 후 **설정 점검 패널**로 안내하도록 변경.

### Added
- **설정 점검 패널 (SetupCheckView)** (`WinMacKey/Views/PermissionGuideView.swift`): 실행 시 환경을 점검해 이슈가 있으면 자동 표시 + 메뉴바 "설정 점검" 으로 재진입. 점검 항목:
  - 손쉬운 사용 / 입력 모니터링 권한 (없으면 [요청/설정 열기])
  - **Caps Lock → ABC 입력 소스 전환(SymbolicHotKey 162)** 켜짐 감지 → 대소문자 토글이 막히므로 끄도록 안내 (직접 끄는 공개 API 가 없어 감지+안내 방식)
  - **⌃Space ‘이전 입력 소스 선택’(SymbolicHotKey 60)** 꺼짐 감지 → 한/영 합성에 필요하므로 켜도록 안내
- **첫 실행 환영 + 라이선스 1회 동의 (FirstRunView)**: 앱 소개 + MIT 라이선스 동의 → 설정 점검으로 연결. `hasCompletedFirstRunOnboarding` 로 1회만.
- **위자드 Step 2 슬롯 하이라이트** (`WinMacKey/Views/ModifierLayoutView.swift`): 다음에 입력해야 할 슬롯을 초록 "여기" 로 강조(awaiting), 선택 슬롯은 파랑 — 조작 순서를 명확히.
- **"응용 프로그램으로 이동" (ApplicationMover)**: DMG/다운로드/데스크탑에서 처음 실행되면 /Applications 로 이동 제안 후 재실행(LetsMove 패턴, 비파괴적 — 실패 시 무시·원본 자동삭제 안 함).

### Changed
- **VDI 설정 가이드 보강** (`docs/VDI_SETUP.md`): `F16 → Right Alt` 가 한/영의 유일한 필수 매핑임을 명시 + 선택적 Mac 단축키(⌘C→Ctrl-C 등) 표 + ‘기본값 복원’ 시 F16 매핑이 사라지는 함정 경고.

### Note
- build 17. `.pkg`(모든 사용자용 설치 관리자)는 별도 — **‘Developer ID Installer’ 인증서**가 있어야 공증 배포 가능(현재 미보유, Apple Developer 에서 발급 필요).

---

## [1.4.0] — 2026-05-28

### Fixed
- **프로필 위자드 Step 2 "현재 입력 감지" 에서 내장 맥북 Fn(🌐) 키가 감지되지 않던 문제** (`WinMacKey/Services/KeyboardDeviceManager.swift`, `WinMacKey/Views/ModifierLayoutView.swift`): Fn/Globe 키는 표준 키보드 HID usage page(0x07)가 아니라 **Apple Vendor Top Case 페이지(0x00FF / usage 0x03, hidutil 표기 `0xFF00000003`)** 로 보고된다. 위자드는 CGEventTap 의 `flagsChanged`(keycode 63)에 의존했는데, lone Fn/Globe 이벤트는 시스템 "🌐 키를 다음 용도로 사용" 설정에 따라 OS 가 먼저 소비해 tap 에 도달하지 않는 맥(특히 신규 맥북)이 있었다. 그 결과 4키 키보드의 네 번째(좌측 끝) 키 = Fn 을 등록하지 못해 **4키 구성이 3키로 주저앉았다**.
  - `KeyboardDeviceManager` 가 IOHID 레벨에서 Fn(0x00FF/0x03)을 직접 감지해 `onFnKeyDown` 신호를 발화하고, 위자드가 이를 구독해 "🌐 키 용도" 설정과 무관하게 Fn 입력을 인식하도록 함.
  - Press-to-bind / first-seen 캡처 모드에서 usage-page 필터를 완화해 Fn 단독 입력으로도 키보드 디바이스가 식별되도록 함.

### Added
- **위자드 Step 2 "+ Fn 🌐" 버튼** (`WinMacKey/Views/ModifierLayoutView.swift`): 좌측 끝에 Fn 이 있는 4키 키보드인데 감지가 안 될 때를 위한 보장 폴백. 누르면 Fn 슬롯을 좌측 끝에 추가한다. 런타임 리맵은 hidutil(HID)로 적용되므로 감지 여부와 무관하게 정상 동작한다.
- **기능 명세서·검증 체크리스트** (`docs/FEATURE_SPEC.md`, `docs/FRESH_INSTALL_CHECKLIST.md`): 전체 기능 명세 + 신규 맥북 설치 검증 체크리스트. 위자드의 기능 축은 표기(Mac/Win)가 아니라 **좌측 3키 vs 4키 + Space** 임을 명문화.
- **진단 로그** (`WinMacKey/Services/KeyboardDeviceManager.swift`): 위자드 활성 시 Fn/Globe IOHID 감지 발화를 `Fn(🌐) detected via IOHID` 로 기록 — 신규 맥북에서 감지 동작을 객관 확인하는 용도(일상 Fn 사용은 노이즈 없이 미기록).

### Changed
- **인앱 도움말(HelpView) 을 실제 UI 와 동기화** (`WinMacKey/Views/HelpView.swift`): "키 매핑" 탭과 FAQ 가 구버전 **"Assign current keyboard"** 흐름을 안내하던 것을 v1.3.6 의 **"Bind keyboard…" (Press-to-bind)**, v1.3.8 의 first-seen 프롬프트·자동전환 보수화 동작으로 정정. 위자드 Fn 감지·"+ Fn" 버튼·3키/4키 모델 설명 추가.
- **외부 문서를 공증(notarized) 빌드 기준으로 동기화** (`docs/manual.html`, `README.md`, `docs/SETUP_GUIDE.md`): ad-hoc 미서명/우클릭→열기/`xattr` 우회 안내를 **더블클릭 실행(서명+공증 완료, v1.3.8+)** 으로 정정, 메뉴바 아이콘 ON/OFF·Press-to-bind·first-seen 프롬프트·자동전환 정책·Mac→Mac 원격(로컬 입력소스 토글)·`Cmd+Shift+Opt+D` Doctor 우회 단축키 반영.

### Note
- build 16. 미출시 문서 릴리스였던 v1.3.9 의 문서·도움말 동기화 작업을 본 릴리스에 통합.

---

## [1.3.8] — 2026-05-27

### Changed
- **키보드 자동 프로필 전환 정책 보수화 (P2 / M2)** (`WinMacKey/WinMacKeyApp.swift`): 이전엔 active 키보드 디바이스가 바뀌면 무조건 `resolveActiveProfile` 를 호출해 자동 전환했음. 이제 사용자 합의된 시나리오만 자동 전환:
  - 외장 → 내장 전환 시: 자동 전환 OK (안전 fallback)
  - 외장 → 외장 swap 시: **자동 전환 안 함** — 마지막 활성 프로필 유지 (사용자 명시로만 변경)
  - 첫 디바이스: bound 프로필 있으면 적용, 없으면 first-seen 후보로 등록
  - 같은 디바이스 재방문: no-op
  - `ignoredDevices` 에 등록된 디바이스: 자동 전환 / prompt 모두 차단
- 자동 전환 표면이 좁아져 외장 키보드 swap 시 의도하지 않은 매핑 변화 (False Positive) 가 줄어듦. UX 차이가 큰 변경이라 plan doc [P2_PER_KEYBOARD_BINDING_PLAN](docs/tasks/P2_PER_KEYBOARD_BINDING_PLAN.md) 참고.

### Added
- **`IgnoredDevices` 모델 + `KeyboardProfileStore` ignore/unignore/isIgnored API (P2 / M1)** (`WinMacKey/Models/Profile.swift`): 사용자가 명시적으로 자동 전환 대상에서 제외한 키보드 VID:PID 영구 set. UserDefaults `ignoredKeyboardDevices` 키로 저장. M2/M3 에서 호출.
- **`AppState.firstSeenKeyboardCandidate` @Published 상태 (P2 / M2)**: 미등록 외장 키보드가 처음 입력하면 set. M3 의 first-seen sheet 가 이 값을 watch.
- **First-seen keyboard prompt sheet (P2 / M3)** (`WinMacKey/Views/FirstSeenKeyboardPromptView.swift`): 미등록 외장 키보드가 처음 입력하면 자동으로 modal sheet 가 떠 사용자에게 [프로필 바인딩… / 이 키보드 무시 / 나중에] 중 하나를 묻는다. 10초 timeout 자동 닫힘. "이 키보드 무시" 는 영구 등록 (M1 의 `ignore` API 호출, UserDefaults 보존). `MenuBarView` 와 `DashboardView` 양쪽에 sheet attach 되어 어디서든 응답 가능. `KeyboardDeviceIdentifier` 가 `Identifiable` 채택 (VID:PID = id).
- **글로벌 단축키 우회 진입 (`Cmd+Shift+Opt+D` → Doctor)** (`WinMacKey/Services/GlobalHotKeyService.swift`): 메뉴바 popover 가 응답하지 않을 때를 대비한 Carbon `RegisterEventHotKey` 기반 우회로. `MenuBarLabelView` 가 SwiftUI `openWindow` 를 capture 해 콜백으로 Doctor 윈도우를 연다.
- **배포 빌드 서명·공증** (`scripts/release.sh`): Developer ID 서명 + Hardened Runtime + 앱/DMG notarization + staple → Gatekeeper 경고 없이 설치.

### 메뉴바 아이콘 ON/OFF 명확화
- **엔진 상태 가독성 개선** (`WinMacKey/WinMacKeyApp.swift` `MenuBarLabelView`): ON = 채운 글리프(풀 불투명), OFF = 아웃라인 + opacity 0.45. 메뉴바가 색을 단색 강제해도 채움·불투명도 대비로 한눈에 구분된다.

### Fixed
- **권한 부여 후 재실행 시 DEBUG 빌드 크래시 (lifecycle invariant 위반)** (`WinMacKey/WinMacKeyApp.swift`): `AppState.init` 이 `startEngineOnLaunchIfNeeded()` 를 동기 호출 → 엔진 자동시작 → `toggleEngine` → `refreshActiveProfileForCurrentContext` → `HIDRemapper.applyMappings` 가 **init 도중** 실행. "init 은 HID 비간섭" invariant 를 깨고 DEBUG assertion (`applyCount == 0`) 이 crash 유발. Accessibility 권한이 없을 때 첫 실행은 early-return 으로 우회되다가, 권한 부여 후 재실행 시 재현. 엔진 자동시작을 `DispatchQueue.main.async` 로 init 완료 후로 defer 하여 invariant 준수. RELEASE 빌드는 assertion 이 컴파일아웃되어 crash 는 없었지만 invariant 위반은 동일하게 존재했음.
- **프로필 위자드 Step 2 ("현재 입력 감지") 에서 modifier 키가 감지되지 않던 회귀** (`WinMacKey/Services/KeyInterceptor.swift`): "새 프로필 만들기" 진입 시 `applyCustomMappingsSync([:])` 로 매핑을 비우면서, `updateNeedsFlagsChangedProcessing()` 의 Caps Lock 보호 최적화가 EventTap 의 eventMask 에서 `flagsChanged` 를 제외. 그 결과 Ctrl/Opt/Cmd/Fn 키 이벤트가 tap 에 도달하지 못해 슬롯이 영구 "대기" 상태였음. `onVerifyKeyEvent` 에 didSet 을 달아 검증 모드가 켜진 동안에는 flagsChanged 구독을 강제로 유지하도록 수정. 검증 콜백 해제 시 원래 최적화로 자동 복귀하므로 일반 동작의 Caps Lock 보호는 그대로 유지.
- **중복 설치 경고가 stale 하게 남던 문제 + Finder 우회** (`WinMacKey/Views/MenuBarView.swift`): 중복 탐지를 시작 시 1회만 수행해 그 사이 중복본을 지워도 경고가 남았음. 이제 popover 열 때마다 재탐지하고, "Finder에서 보기" 는 `activateFileViewerSelecting` 로 LSUIElement 앱에서도 Finder 를 전면화한다. 삭제된 경로는 클릭 시 다시 거른다.

---

## [1.3.7] — 2026-05-11

### Fixed
- **업데이트 확인 버튼 누르면 윈도우가 다른 앱 뒤에 숨던 버그**: `MenuBarView` 의 "업데이트 확인..." 버튼이 `NSApp.activate(ignoringOtherApps: true)` 호출 누락. LSUIElement (메뉴바 전용) 앱은 명시적 activate 없으면 새 윈도우가 background 로 열림. 사용자가 "다이얼로그 안 뜸" 으로 인지. 다른 메뉴 버튼 (설정 / Event Viewer / Doctor / Help / Log Viewer) 5종은 모두 activate 를 호출하고 있어 일관성 위반. 한 줄 fix.

---

## [1.3.6] — Superseded by v1.3.7

키보드 디바이스 바인딩 UX 를 "Press-to-bind" 패턴으로 전면 개편. 사용자가 매번 "직전에 어느 키보드를 썼는지" 머릿속에서 추적해야 했던 모호함 해소.

### Added
- **Press-to-bind capture UX** (`WinMacKey/Views/KeyboardBindingCaptureView.swift`):
  - Profile 의 "Bind keyboard…" 버튼 클릭 → modal sheet 열림
  - 대기 → 키 입력 감지 → 디바이스 정보 표시 (이름·VID:PID·내장/외장) → 확인 버튼
  - 10초 timeout · 사용자 취소 · 다른 키보드로 재캡처 가능
  - 같은 디바이스에 이미 바인딩된 다른 프로필이 있으면 충돌 경고 표시
  - 연결된 키보드 목록을 fallback 으로 노출 (키 입력 불편한 경우 직접 선택)
- `KeyboardDeviceManager.startCapture / cancelCapture` API — 일회성 다음-키 감지.
- `tests/keyboard_capture_smoke.swift` — capture mode 5 invariants 자동 검증.

### Changed
- `ProfilesView` 의 "Assign current keyboard" 버튼 → **"Bind keyboard…"** 로 라벨 변경.
- 바인딩 시 같은 디바이스의 다른 프로필 바인딩이 있으면 **자동으로 이전** (한 디바이스 = 한 프로필 보장).
- `DashboardView` 에 `bindingTargetProfile` state + `.sheet(item:)` modifier.

### Fixed (UX 개선)
- 기존: 사용자가 "직전 active device" 라는 implicit state 를 머릿속에서 추적해야 했음. 마우스로 메뉴 조작 중 의도하지 않은 키보드 바인딩 가능.
- v1.3.6: 모달 활성 시점에 명시적으로 키 입력 감지 → 시각적 확인 후 바인딩. 오류 가능성 구조적으로 봉쇄.

---

## [1.3.5] — Superseded by v1.3.7

v1.3.4 의 Mac → Mac Remote Mode 설계가 잘못된 가정 위에 있었음을 확인하고 정정.

### 핵심 정정
- v1.3.4 는 "Mac 원격 = VDI 처럼 F16 패스스루 → 원격 Mac 의 WinMacKey 가 처리" 로 디자인. 사용자가 양쪽 Mac 에 WinMacKey 설치 필요.
- 실측 결과: Apple Screen Sharing 은 **키 스캔코드가 아니라 변환된 character(Unicode) 를 forward**. 즉 로컬 맥북의 IME 결과 문자가 그대로 원격 화면에 입력됨. F16 같은 raw key event 는 원격에 전달 안 됨.
- 따라서 한영전환 처리는 **로컬 맥북에서 끝나야 함**. 원격 Mac 의 WinMacKey 가 받을 게 없음.

### Fixed
- **`KeyInterceptor.handleTriggerKey`**: `isVdiAppFocused || isRemoteMacAppFocused` → `isVdiAppFocused`. Remote Mac 케이스를 패스스루 분기에서 제거.
- **`AppState.onInputSourceToggle`**: `isRemoteMacMode` 별도 분기 삭제. 로컬 Mac 과 동일한 합성 path 사용 (로컬 macOS 의 Control+Space 합성 → 로컬 입력소스 토글 → Screen Sharing 이 변환된 character 를 원격에 forward).
- 결과: 양쪽 Mac 설치 불필요. 맥북의 Right Cmd → 맥북 입력소스 토글 → 원격 화면에 올바른 문자.

### Added
- `tests/trigger_branching_smoke.swift` — KeyInterceptor 의 mode flag 들이 외부 설정 가능 + 서로 독립 + triggerKeyCode=F16 invariant. v1.3.4 와 v1.3.5 둘 다 통과해야 하는 회귀 lock-down (5 invariants).
- `HIDRemapper.skipExternalHidutilCallsForTesting` static flag — smoke 가 실제 hidutil Process spawn 으로 SIGKILL 받는 문제 해결. 카운터/ownership 게이트/snapshot capture 같은 in-memory state 는 정상 검증되지만 실제 시스템 hidutil 은 안 건드림.

### Changed
- `ContextManager.remoteMacApps` 셋은 유지하되 **동작 분기 미사용** — 진단·로깅·UI 표시용으로만. (Screen Sharing 활성 감지가 의미 있어 유지)
- README.md 의 "Mac → Mac 원격접속" 섹션 전면 재작성:
  - 양쪽 설치 → 로컬만 설치
  - F16 패스스루 → 로컬 입력소스 토글
  - "원격 Mac 입력소스 전환" → "원격 화면에 변환된 문자 입력"
- MANUAL_TEST_PLAN.md O 카테고리 기대값 반전 (맥북 입력소스가 토글되는 게 정상).

### Removed
- v1.3.4 의 잘못된 Mac → Mac Remote Mode passthrough 동작.

### Note
- v1.3.4 는 외부 표면(GitHub Latest)에서 Draft 처리.
- 회귀 검증: 7종 smoke (mapping_profile / hid_lifecycle / engine_off_ui / ownership / toggle_off_snapshot / remote_mac_mode / **trigger_branching**) 모두 hotfix 전후 동일 PASS. VDI · 로컬 Mac · Terminal · 외장 키보드 경로 한 줄도 안 바뀜.

---

## [1.3.4] — Superseded by v1.3.5

Mac → Mac Remote Mode 디자인 잘못된 가정으로 실패. 외부 미공개 (Draft).

v1.3.3 lifecycle 검토에서 발견된 HIGH 3건 + MEDIUM 1건 fix + Mac→Mac 원격접속 한영전환 신규 지원.

### Added
- **Mac → Mac 원격접속 한영전환**: Apple Screen Sharing, Apple Remote Desktop, Jump Desktop, CoRD, RealVNC, TeamViewer, AnyDesk, Parsec 자동 감지. 이 앱들이 포커스면 F16 패스스루 — 원격 Mac 의 WinMacKey 가 자체 처리. 로컬 맥북의 입력소스는 안 바뀜. **양쪽 Mac 모두 WinMacKey 설치 + 동일 self-signed cert 필요** (이미 stable signing 으로 권한 영속됨).
- `ContextManager.allRemoteMacApps` + UserDefaults `CustomRemoteMacApps` (사용자 도구 확장 가능).
- `AppState.isRemoteMacMode` published. LogService 에 진입/이탈 기록.
- `KeyInterceptor.isRemoteMacAppFocused` flag — VDI 와 별도 분기.
- `HIDRemapper.restorePreExistingMappingsAndClearInternal()` — engine OFF / Doctor stop / Reset 공용 cleanup. snapshot 복원 + internal keyboard 정리.
- `tests/toggle_off_snapshot_smoke.swift` — HIGH 1 fix 의 cleanup conditional 검증.
- `tests/remote_mac_mode_smoke.swift` — VDI/Remote flag 독립성, 외부 설정 동작 검증.
- MANUAL_TEST_PLAN.md K-6 (VDI internal cleanup), O 카테고리 (Mac→Mac 원격) 신규.
- README.md 의 VDI 섹션에 Mac→Mac 원격 워크플로 추가.

### Fixed
- **HIGH: toggleEngine OFF 가 pre-existing hidutil 을 wipe 하던 문제**: `keyInterceptor.stop()` 의 default `clearHIDMappings: true` → 빈 매핑으로 set. 다른 hidutil 도구(Karabiner 등) 매핑이 사라짐. `restorePreExistingMappingsAndClearInternal()` 으로 변경 — pre-existing snapshot 복원 + internal keyboard cleanup.
- **HIGH: VDI 진입 후 엔진 OFF 시 internal keyboard mapping 잔존**: `clearMappingsSync()` 가 global 만 정리하던 문제. cleanup 메서드가 internal 도 같이 처리.
- **HIGH: Doctor restart 가 ownership 없이 start 하던 문제**: `performFix(.restartEngine)` 이 `takeOwnership()` 호출 안 해 RightCmd→F16 매핑이 적용 안 되던 회귀. 정상 `toggleEngine` ON 흐름과 동일 lifecycle (release → 대기 → take → start → refresh).
- **MEDIUM: Doctor stopEngine ownership release 누락**: `performFix(.stopEngine)` 이 단순 `stop()` 만 호출하고 release 안 함. 다음 restart 가 take 없이 진행되는 cascade 원인. snapshot restore + release 추가.

---

## [1.3.3] — Superseded by v1.3.4

외부 배포된 상태이나 위 HIGH 3건 미수정. 사용자가 다른 hidutil 도구 미사용 + VDI 중 engine 토글 안 함 + Doctor stop→restart 시퀀스 안 하면 영향 없음. 그러나 외부 표면 깨끗하게 유지를 위해 Draft 처리 후 v1.3.4 로 대체.

---

## [Unreleased] — v1.3.3 (Skipped — superseded by v1.3.4)

v1.3.2 외부 코드리뷰 2차 결과 + lifecycle 우회 경로 분석에서 발견된 항목 일괄 패치.
"엔진 OFF = 시스템 영향 없음" 안전 경계를 ownership 모델로 구조적 보장.

### Added
- **HID Ownership 모델**: `HIDRemapper` 에 `isOwnedByEngine` flag + `takeOwnership` / `releaseOwnership` lifecycle. 모든 `applyMappings*` / `clearMappings*` write 메서드에 ownership 가드. 엔진 OFF 상태에서 어떤 path 든 HID 시스템 상태를 못 건드림.
- **Pre-existing hidutil snapshot/restore**: 앱이 처음 HID 를 건드리기 전 시스템 `UserKeyMapping` snapshot 저장. 종료/Reset/Recovery 시 snapshot 으로 복원. Karabiner 등 다른 hidutil 도구의 매핑이 앱에 의해 지워지지 않음.
- **HIDRemapper 가드 우회 cleanup path**: `internalClearAllForTermination` — 종료/Reset 시 ownership 무관 cleanup. `hasAppliedAnyMapping` 가 false 면 no-op (앱이 안 건드린 시스템은 건드리지 않음).
- **Engine-OFF UI invariant smoke** (`tests/engine_off_ui_smoke.swift`): `applyCustomMappings`, `applyCustomMappingsSync`, `setupDefaultMappings` 를 engine OFF 에서 호출해도 HID 호출 0건 자동 검증.
- **Ownership semantics smoke** (`tests/ownership_smoke.swift`): take/release ownership lifecycle, termination cleanup no-op 등 invariant 4종 자동 검증.
- **MANUAL_TEST_PLAN.md K~N 카테고리**: pre-existing hidutil 보존, TCC reset confirmation, update install 검증, 로그 프라이버시.
- **release.sh 진단 로그**: 빌드 후 산출 .app 의 Authority / Identifier / Designated Requirement 자동 출력. Ed25519 서명 후 self-verify round-trip. verify_sign_identity 실패 시 stderr 에 expected vs actual Authority 출력. codesign 출력 변수 캡처 후 awk 추출로 SIGPIPE/pipefail 충돌 회피.

### Fixed
- **`restartTapIfNeeded` HID flicker**: flagsChanged mask 변경 시 EventTap 재시작이 `stop()` 으로 글로벌 HID 매핑을 풀어버려 짧은 시간 동안 RightCmd→F16 트리거가 침묵하던 회귀. `stop(clearHIDMappings: false)` 시그니처 추가, 내부 restart 는 HID 보존.
- **`applyCustomMappings*` 위저드 우회**: engine OFF 에서 직접 호출 시 HID 적용하던 경로. dictionary 갱신 + HID 적용 분리, ownership 가드.
- **TCC reset 자동 실행 silent execution**: `runTccutilResetInTerminal` 이 AppleScript `do script` 로 confirmation 없이 즉시 실행되던 동작. `confirmAndRunTccutilReset` 추가 — NSAlert 로 사용자 명시 동의 후에만 실행. MenuBarView 의 "터미널에서 실행…" 버튼이 이 confirmation path 를 거치도록 변경. "명령 복사" 가 primary action.
- **Update install 추출 .app 검증 부족**: Ed25519 서명 통과해도 .app 의 정체성 별도 확인 없던 문제. `verifyExtractedApp` 신규 — `CFBundleIdentifier == com.winmackey.app`, `CFBundleShortVersionString == latestVersion`, `codesign --verify` round-trip, archive 구조 검증.
- **Update 임시 경로 동시성 race**: 고정 경로 `WinMacKey-update.zip`, `WinMacKeyUpdate/` 가 동시 실행/잔존 파일/외부 placeholder 와 충돌하던 문제. UUID 기반 isolated tmpdir.
- **applicationWillTerminate over-clear**: `HIDRemapper.clearAllMappingsSync` 무조건 호출로 다른 hidutil 도구의 매핑까지 wipe 하던 문제. `internalClearAllForTermination` 으로 변경, snapshot 복원 path 와 결합.
- **GitHub Actions CI 실패 (Xcode 15.0 + strict concurrency)**: `WinMacKeyApp.swift` 의 Task closure 가 outer closure 의 `[weak self]` 만 잡고 inner 에서 그대로 self 캡처하던 패턴을 strict concurrency 가 거부. `Task { @MainActor [weak self] in }` 로 명시 캡처. CI workflow 의 Xcode pin 을 `latest-stable` 로 갱신. Release upload step 은 제거 — local `release.sh` 가 self-signed + Ed25519 와 함께 담당 (Developer ID 도입 시 재활성화).

### Changed
- `LogService.copyToClipboard` 에 `confirmAndCopyToClipboard` wrapper 추가 — 로그 export 가 클립보드 노출이라는 사실을 명시.
- `KeyEvent` 에 `bundleIdAnonymized` (SHA-256 prefix), `keyCodeCategory` (modifier/letter/function/trigger 등) helper 추가. 향후 privacy mode UI 토글 도입 시 사용.
- `MenuBarView` 의 `#Preview` 를 `MenuBarView+Preview.swift` 로 분리 — swiftc CLI smoke test 가 View 파일 컴파일해도 macro 확장 충돌 없도록.

---

## [1.3.2] — Skipped (consolidated into v1.3.3)

내부 빌드만 진행되고 외부 안내 보류. 아래 변경 사항은 모두 v1.3.3 에 포함됨.

v1.3.1 외부 코드 리뷰에서 발견된 7건 일괄 패치. 가장 중요한 항목은 "엔진 OFF 시 시스템 영향 없음" 안전 경계 위반 (앱 실행만으로 hidutil 글로벌 매핑이 변경될 수 있던 버그).

### Fixed
- **HIGH: 앱 init 시점 HID 시스템 미터치 보장**: `KeyInterceptor.init()` 이 `setupDefaultMappings()` 를 호출해 `hidutil` 글로벌 매핑을 변경하던 버그. 사용자의 외부 hidutil 설정이 앱 실행만으로 지워질 수 있었다. `setupDefaultMappings` 를 `computeKeyMappings`(메모리만)와 `setupDefaultMappings`(메모리+HID)로 분리. init은 전자만 호출. HID 적용은 engine ON 경로(`refreshActiveProfileForCurrentContext`)에서만.
- **HIGH: Doctor restart 후 HID 재적용 누락**: `DoctorService.performFix(.restartEngine)` 이 `stop()` → `start()` 만 호출해 RightCmd→F16 매핑이 풀린 상태로 EventTap 만 켜지던 버그. UI는 엔진 ON 인데 한영전환 침묵. start 성공 후 `appState.refreshActiveProfileForCurrentContext()` 호출 추가.
- **MED: Reset/Emergency Recovery 후 모니터링 재시작**: `ResetService.resetAll` 과 `DoctorService.emergencyRecovery` 가 KeyboardDeviceManager / ContextManager 를 stop 후 재시작하지 않아 초기화 후 앱 재시작 전까지 디바이스 자동 전환·VDI 컨텍스트 감지가 죽어 있었다. 두 매니저 모두 monitoring 재시작 + lastActiveKeyboard 리셋.
- **MED: 권한 폴링 분리**: `startPermissionPolling` 이 Accessibility + Input Monitoring 둘 다 만족해야 종료해 Accessibility 만 허용한 사용자는 polling 이 영원히 돌고 자동 엔진 시작 알림이 발화되지 않던 버그. `startAccessibilityPolling` / `startInputMonitoringPolling` 분리. 각자 5분 timeout.
- **MED: release.sh 버전 가드**: 인자로 받은 `VERSION` 과 `Info.plist:CFBundleShortVersionString` 일치 검증. 불일치 시 즉시 거부. `set -euo pipefail` 도입. `check-version-consistency.sh` 자동 호출.
- **LOW: actor isolation 경고**: `AppState.findAllInstallations` 를 `nonisolated` 로 표기. background queue 에서 안전 호출.
- **LOW: VDI 로그 문구 정정**: "Fn=Ctrl, Option=Win, Command=Alt" → "Fn↔Ctrl swap applied". 실제 매핑(`vdiInternalKeyboardMappings`)과 일치.
- **release.sh verify_sign_identity false negative**: `set -euo pipefail` 하에서 `if cmd1 && cmd2 | cmd3` 복합 표현이 의도와 다르게 실패 판정해 키체인에 self-signed identity 가 있어도 ad-hoc fallback 으로 빠지던 버그. 각 명령을 별도 호출로 분해해 exit code 명시 검사.

### Added
- **검증 인프라**: `HIDRemapper` 에 `applyCallCount` / `clearCallCount` 카운터. `AppState.init` 끝에 DEBUG assertion 으로 "init 이 HID 안 건드림" invariant 자동 검증. `tests/hid_lifecycle_smoke.swift` smoke 테스트 추가. `docs/MANUAL_TEST_PLAN.md` 회귀 체크리스트 (10개 카테고리, 30+ 검증 항목).

---

## [1.3.1] — Skipped (consolidated into v1.3.2)

내부 빌드만 진행되고 외부 안내 보류. 아래 변경 사항은 모두 v1.3.2 에 포함됨.

### Added
- **Stable code signing identity 지원**: `scripts/setup-signing.sh` 로 self-signed cert 1회 생성 → 같은 identity로 서명된 빌드 간 손쉬운 사용 권한 영속 (Designated Requirement가 leaf cert SHA-1로 바인딩). Apple Developer Program 없이도 빌드/업데이트마다 권한 재요청 불필요. `SIGN_IDENTITY` 환경변수로 override, cert 없으면 ad-hoc fallback.
- **자동 업데이트 위치 가드**: `UpdateService` 가 `/Applications/` 외 위치(Downloads, Desktop 등)에서 실행 중이면 다운로드를 거부. `UpdateError.notInApplicationsFolder` 신규.
- **중복 설치 감지**: 앱 실행 시 `mdfind` 백그라운드로 동일 bundle ID의 모든 .app 위치를 탐색해 메뉴바에 경고 카드 표시. build/DerivedData/Volumes/Trash/tmp 경로는 자동 제외.
- **Orphan TCC 권한 감지·복구 UI**: 이전에 권한이 부여됐으나 csreq 변경(ad-hoc → self-signed 마이그레이션 등)으로 무효화된 상태를 자동 감지. 메뉴바에서 `tccutil reset Accessibility com.winmackey.app` 명령 클립보드 복사 또는 Terminal.app에서 자동 실행 (AppleScript).
- **Ed25519 자동 업데이트 무결성 검증**: `scripts/setup-update-signing.sh` 로 keypair 생성. public key는 앱에 임베드, private key는 `~/.config/winmackey/update-signing.key` 보관. `release.sh` 가 ZIP/DMG 빌드 후 `.sig` 동봉. 업데이트 다운로드 시 CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` 로 검증, 실패하면 설치 거부. GitHub 계정 탈취로 인한 RCE 시나리오 방어.

### Changed
- `scripts/release.sh` 가 self-signed identity를 실제 codesign 테스트로 자동 감지 후 manual 서명. unsigned .dmg 시대 종료.
- `WinMacKey/Services/KeyInterceptor.swift` 의 133줄 `handleEvent` C 콜백을 `handleTriggerKey` / `handleMappedKey` / `translateMapping` / `dispatchVerificationCallback` 4개 메서드로 분해. 동작 보존 리팩터로 트리거 처리·매핑·버퍼링·검증 책임 분리.
- `UpdateService.replaceApp` 의 `xattr -cr` 자동 호출 제거 — quarantine은 Ed25519 서명 검증으로 충분히 신뢰가 형성된 자산에 대해서만 사용자가 의도적으로 해제할 일.
- `UpdateService.relaunchApp` 을 `/bin/sh -c "open \"...\""` shell interpolation 에서 `Process` + `/usr/bin/open` 인자 배열로 교체.

### Removed
- `WinMacKey.entitlements` 에서 `com.apple.security.cs.allow-unsigned-executable-memory` 와 `com.apple.security.cs.disable-library-validation` 제거. 코드 grep 결과 0건 사용 — 향후 notarize 단계에서도 안전.

---

## [1.3.0] — Skipped (consolidated into v1.3.1)

내부 빌드만 진행되고 외부로 릴리스되지 않음. 아래 변경 사항은 모두 v1.3.1에 포함됨.

### Added
- **F16 HID remap 아키텍처**: `hidutil`로 Right Command를 F16으로 HID 레벨 변환 — modifier flag 오염 원천 차단
- **VDI F16 패스스루**: VDI 모드에서 F16이 Horizon에 직접 전달되어 suppress+재발행 불필요
- **IOKit 기반 외장 키보드 자동 감지**: `IOHIDManager`로 연결된 키보드를 VendorID/ProductID로 식별
- **디바이스별 프로필 자동 전환**: 외장 키보드 입력 시 할당된 프로필로 즉시 전환 (디바이스 > 앱 > 기본 우선순위)
- **Profiles 탭**: "키보드 할당" 버튼으로 키보드 디바이스별 프로필 할당
- **재부팅 후 자동 실행 옵션**: 로그인 항목 등록과 앱 실행 후 엔진 자동 시작 토글 추가
- **CHANGELOG.md**: 프로젝트 변경 이력 문서화

### Fixed
- **VDI에서 한/영+Shift+P 시 "다른 화면에 표시" 팔업 (Win+P)**: modifier flag 오염 원천 차단
- **VDI에서 빠른 영문 대문자 입력 시 Windows 키 조합 오발**: F16 non-modifier remap으로 해결
- 로컬 macOS에서 한영전환 직후 첫 글자가 영어로 들어가던 문제 완화
- 입력소스 전환 검증 실패를 성공으로 처리해 버퍼를 조기 해제하던 레이스 수정
- **Ghostty / Claude Code terminal regression 1차 안정화**: `[57379u]` raw sequence, Command shortcut 누출(`Cmd+N`, `Cmd+D`, 검색 UI`), `pasting text` 오버레이가 사라지는 단계까지 확인
- **진단/런타임 정렬**: Caps Lock 설명과 F16 기반 트리거 경로를 현재 동작에 맞게 정리
- **권한 안내 개선**: 손쉬운 사용 상태 확인과 설치 후 권한 재부여 흐름 정리
- **검증 베이스라인 추가**: 스모크 테스트 스크립트와 버전 메타데이터를 1.3.0 (build 5)로 정리

### Changed
- **트리거 표면 단순화**: Right Option 선택지를 제거하고 Right Command 단일 트리거 모델로 정리
- **터미널 경로 분기**: terminal-like 앱에서 direct input-source switch를 사용할 수 있도록 context/transport 경로 확장
- **플랫폼 관리 확장**: 키보드 디바이스/로그인 항목 관리용 서비스 구조 추가
- **트리거 감지**: CGEventTap `flagsChanged` → `keyDown/keyUp` (F16은 modifier가 아니므로)
- **modifier flag 스트리핑/쿨다운 제거**: F16은 modifier flag를 생성하지 않으므로 불필요
- HelpView 매뉴얼 전면 재작성 — 디바이스 프로필, VDI 고스트 키 방지 등 신기능 반영
- README, VDI_SETUP, SETUP_GUIDE 문서 업데이트

---

## [1.2.3] — 2026-03-09

### Fixed
- GitHub Actions release workflow 권한 설정 수정 (`contents: write`)

---

## [1.2.2] — 2026-03-09

### Fixed
- GitHub release 빌드 호환성 수정 (DMG 생성 플로우)

---

## [1.2.1] — 2026-03-09

### Added
- IME 입력소스 커밋 윈도우 (70ms 버퍼링) — 빠른 한영전환 시 글자 누락 방지
- VDI 포커스 시 내장 키보드 자동 매핑 전환 (Fn→Ctrl, Ctrl→Fn)

### Fixed
- 한영전환 직후 글자 씹힘/중복 입력 문제 개선
- HID-CGEventTap 이중 매핑 버그 수정

---

## [1.2.0] — 2026-03-07

### Added
- **Control+Space 기반 한영전환**: `TISSelectInputSource` API 의존성 완전 제거
- **네이티브 VDI 지원**: 별도 가상 키보드 드라이버 없이 F16 릴레이 키로 VDI 한영전환
- **hidutil HID 레벨 매핑**: Fn/Globe 키 포함 modifier 키 리매핑
- **프로필 시스템**: Mac 로컬 / VDI 컨텍스트별 목표 배치 저장 및 자동 전환
- **프로필 위저드**: 실키 감지, 3키/4키 자동 판단, Mac/VDI 배치 개별 설정
- Karabiner DriverKit 완전 불필요

### Changed
- 한영전환 메커니즘을 `TISSelectInputSource` → `Control+Space 합성` 으로 전환
- 메뉴바 아이콘이 macOS 네이티브 입력소스 표시기와 동기화

---

## [0.1.0] — 2026-03-01

### Added
- 인앱 도움말 매뉴얼 (HelpView)
- GitHub Releases 기반 앱 내 자동 업데이트
- 파일 기반 로깅 및 로그 뷰어
- Doctor 진단/복구 기능
- Event Viewer 실시간 키 입력 모니터링
- CGEventTap 자동 재활성화 (타임아웃 복구)

### Fixed
- tap-only 한/영 전환 정확도 개선
- 키 리매핑 로직 전면 재작성
- EventViewer, ContextManager, 레이턴시 표시 수정

---

## [1.0.0] — 2026-02-28

### Added
- 초기 릴리즈
- CGEventTap 기반 키보드 이벤트 인터셉트
- Right Command tap-only 한/영 전환
- 키코드 리매핑 (fn ↔ Cmd ↔ Ctrl)
- 메뉴바 유틸리티 (MenuBarExtra)
- 앱별 컨텍스트 인식 (VDI 자동 감지)
