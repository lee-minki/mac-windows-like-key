# WinMacKey 기능 명세서 (Feature Specification)

> 기준 버전: **v1.4.0 / build 16** · 작성일 2026-05-28
> 목적: 전체 기능의 입력·기대 동작·권한·엣지케이스를 한곳에 정의해, 신규 맥북 설치 시 회귀를 체계적으로 검증한다.
> 함께 볼 것: 핵심 엔진 상세 [`RIGHT_COMMAND_ONLY_SPEC.md`](RIGHT_COMMAND_ONLY_SPEC.md) · 회귀 회귀 검증 [`MANUAL_TEST_PLAN.md`](MANUAL_TEST_PLAN.md) · 신규 설치 검증 [`FRESH_INSTALL_CHECKLIST.md`](FRESH_INSTALL_CHECKLIST.md)

명세 표기 규칙: 각 기능은 `ID | 기대 동작 | 담당 파일:심볼 | 진입 경로 | 권한 | 엣지/회귀 위험`.

---

## 0. 한눈에 보는 데이터 흐름

```
물리 Right Cmd
   └─ HID(hidutil) 리맵 → F16                       [E1]
        └─ CGEventTap 가 F16 포착 → 컨텍스트 분기     [E2~E5]
             ├─ VDI(Horizon)   : F16 패스스루 → Horizon 이 Right Alt 변환
             ├─ Terminal       : 입력소스 직접 전환 (합성 우회)
             ├─ Mac 원격(VNC)  : 로컬 입력소스만 토글
             └─ 로컬 Mac       : Control+Space 합성 + commit 윈도우
   프로필 결정: 디바이스 바인딩 > 앱 바인딩 > 기본    [P7]
   매핑 적용:   takeOwnership → applyMappings → release [HID lifecycle]
```

핵심 설계 불변식: **앱 `init` 은 HID 시스템 상태를 건드리지 않는다.** 실제 hidutil 적용은 엔진 ON 경로에서만 일어난다 (DEBUG assertion 으로 강제).

---

## 1. 핵심 엔진 — Right Cmd → 한/영

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **E1** | Right Cmd 를 HID 레벨에서 F16 으로 리맵 (modifier flag 오염 차단) | `HIDRemapper.applyMappings` | 엔진 ON | 없음(hidutil) | 외부 hidutil 도구(Karabiner)와 충돌; 강제종료 시 매핑 잔존 |
| **E2** | 로컬 Mac: F16 suppress 후 Control+Space 합성 → 입력소스 토글 | `KeyInterceptor.handleTriggerKey` / `translateMapping` | F16 포착 | 손쉬운 사용 | "이전 입력 소스 선택" 단축키 미설정 시 무동작; 권한 stale |
| **E3** | VDI(Horizon) 포커스: F16 을 suppress 안 하고 패스스루 | `KeyInterceptor.handleTriggerKey` (`isVdiAppFocused`) | F16 포착 | 손쉬운 사용 | Horizon 측 F16→Right Alt 매핑 필수(외부 설정) |
| **E4** | 터미널(Ghostty 등) 포커스: 입력소스 직접 전환(합성 우회) | `KeyInterceptor` 터미널 분기 / `ContextManager` | 앱 전환 감지 | 손쉬운 사용 | 이스케이프 시퀀스 누출 회귀 이력; 앱 화이트리스트 의존 |
| **E5** | Mac→Mac 원격(Screen Sharing): 로컬 입력소스만 토글(원격에 문자 forward) | `KeyInterceptor` (`isRemoteMacAppFocused`) | 앱 전환 감지 | 손쉬운 사용 | Screen Sharing 외 VNC 미검증 |
| **E6** | Right Cmd 릴리즈 후 20ms commit 윈도우 동안 입력 버퍼링 | `KeyInterceptor` buffered replay | 릴리즈 직후 | 손쉬운 사용 | 과버퍼링 시 입력 지연 |

상세 동작·상태기계는 [`RIGHT_COMMAND_ONLY_SPEC.md`](RIGHT_COMMAND_ONLY_SPEC.md) 참조.

---

## 2. 프로필 & 매핑 위자드

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **P1** | 기본 프로필(standardMac): 매핑 없음 | `MappingProfile.standardMac` | 자동 | 없음 | — |
| **P2** | 저장 프로필: 물리키 + Mac 목표 + VDI 목표 + 보조 Fn, UUID 저장 | `Profile.SavedKeyboardProfile` | 위자드 완료 | 없음 | 레거시 필드 호환; 이름 충돌 |
| **P3** | 위자드 6화면: `0`목록 → `1`표기(Mac/Win) → `2`현재 입력 감지 → `3`Mac 로컬 배치 → `4`VDI 배치 → `5`검증 | `ModifierLayoutView` | 설정→Profiles | 손쉬운 사용(2·5단계) | 단계별 회귀 다수(아래 P4 핵심) |
| **P4** | **Step 2 현재 입력 감지**: 왼쪽부터 modifier 를 누르고 마지막에 Space → 3/4키 자동 확정. 누른 키만 슬롯에 채움 | `ModifierLayoutView.beginPhysicalKeyCapture` + `KeyInterceptor.onVerifyKeyEvent` | Step 2 진입 | 손쉬운 사용(CGEventTap) | **🔴 Fn 미감지(§7 회귀)**; 빈 매핑 진입 시 flagsChanged 제외 회귀(고정) |
| **P5** | Step 3 Mac 로컬 배치: Fn/Ctrl/Cmd/Opt 중 슬롯별 목표 선택, 3키는 보조 Fn 별도 | `ModifierLayoutView.macTargetChoices` | Step 3 | 없음 | 슬롯 선택 UX 혼동 |
| **P6** | Step 4 VDI 배치: Ctrl/Win/Alt 3종, 로컬과 독립 | `ModifierLayoutView.vdiTargetChoices` | Step 4 | 없음 | VDI 미사용자도 입력 강요 |
| **P7** | 자동 전환 우선순위: 디바이스 바인딩 > 앱 바인딩 > 기본. 외장→내장만 자동, 외장↔외장 swap 은 마지막 프로필 유지(v1.3.8 보수화) | `WinMacKeyApp` / `AppState` resolve | 디바이스·앱 전환 | 손쉬운 사용 | 정책 변경으로 사용자 기대와 어긋날 수 있음 |
| **P8** | Step 5 검증: 매핑 적용 후 키를 눌러 매핑 결과 실시간 표시 | `ModifierLayoutView.applyAndGoToVerification` | Step 5 | 손쉬운 사용 | Step 2 와 동일한 Fn 감지 한계 |

### 2.1 기능 축은 "표기(Mac/Win)"가 아니라 "좌측 3키 vs 4키 + Space"

Step 1 의 **Mac/Windows 표기 선택(`selectedLegendStyle`)은 표시용(cosmetic)** 이다. 같은 keycode 를 "Opt/Cmd" 로 부르냐 "Alt/Win" 으로 부르냐만 바꾼다(`ModifierLayoutView.label(for:style:)` line 13–14). 실제 동작을 결정하는 것은:

1. **슬롯 수 = 3 또는 4** — `configuredSlotCount = physicalKeys.count`. Step 2 에서 Space 앞까지 누른 modifier 개수로 자동 확정.
2. **물리 순서대로 감지된 raw keycode** — Mac 은 `Ctrl·Opt·Cmd`, Windows 는 `Ctrl·Win(→Cmd)·Alt(→Opt)` 로 **Cmd/Opt 위치가 서로 뒤바뀌지만**, Step 2 가 실제 순서를 그대로 포착하므로 표기 선택과 무관하게 정확.

`selectedLegendStyle` 은 감지(`physicalKeys`)·선택지(`leftSideChoices`/`macTargetChoices`/`vdiTargetChoices`)·매핑(`currentMappings`) **어디에도 관여하지 않는다** — 라벨/요약/미리보기/프로필 설명 표시에만 사용. 따라서 위자드의 "Mac/Windows" 단계는 키캡 인지용 보조이며, 기능적 분류는 **3키/4키 + Space 경계** 가 정답.

> **4키의 네 번째(좌측 끝) 키 = Fn.** (Mac `fn·ctrl·opt·cmd` / Windows 노트북 `fn·ctrl·win·alt`) → Fn 미감지(§7)면 4키 키보드도 3키로 주저앉아 **"3키 vs 4키" 구별 자체가 깨진다.** Fn 버그의 사용자 영향 핵심.

---

## 3. 키보드 디바이스 관리 (IOHIDManager)

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **D1** | 내장/외장 구분 (productName "Internal" + VID:PID) | `KeyboardDeviceManager` / `KeyboardDeviceIdentifier.isInternal` | 시작+모니터링 | 없음(IOKit) | Magic Keyboard 판정; 제3사 키보드 |
| **D2** | 활성 키보드 추적 (마지막 입력 디바이스) | `KeyboardDeviceManager.inputValueCallback` → `handleInputValue` | 입력 시 | 없음 | **usage page 0x07 만 추적 → Fn 단독 입력은 추적 안 됨(§7)** |
| **D3** | 미등록 외장 키보드 첫 입력 → first-seen 후보 set | `AppState.firstSeenKeyboardCandidate` | 첫 입력 | 없음 | 타이밍 레이스 |
| **D4** | First-seen 프롬프트: [바인딩 / 무시 / 나중에], 10초 자동닫힘 | `FirstSeenKeyboardPromptView` | 후보 non-nil | 없음 | "나중에" 재알림 정책 |
| **D5** | Press-to-bind: 키 입력 캡처 → 디바이스 확정 → 프로필 바인딩, fallback 목록 제공 | `KeyboardBindingCaptureView` + `KeyboardDeviceManager.startCapture` | Profiles 탭 버튼 | 없음 | **Fn 로 캡처 시 무반응(§7)**; 캡처 재시작 state |
| **D6** | 한 디바이스 ↔ 한 프로필, 충돌 시 자동 이전 + 경고 | `KeyboardProfileStore` 바인딩 API | 바인딩 확정 | 없음 | UserDefaults 동시성 |
| **D7** | Ignored Devices: "이 키보드 무시" 영구 등록 → 자동전환·프롬프트 차단 | `KeyboardProfileStore` ignore/unignore | 프롬프트 "무시" | 없음 | 해제 UI 접근성 |

---

## 4. VDI · 특수 모드

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **V1** | VDI 앱 자동 감지 (Horizon/Fusion/Parallels/RDP 등 Bundle ID) | `ContextManager` | 앱 전환 | 없음 | Bundle ID 리브랜딩(Horizon→Omnissa) |
| **V2** | VDI 포커스 시 내장 키보드만 Fn↔Ctrl swap 적용 | `AppState` VDI 매핑 전환 | isVdiMode 변경 | 없음 | 재적용 레이턴시(~30ms) |
| **V3** | F16(flag 없음)로 Win+P 등 고스트 단축키 차단 | `HIDRemapper` IME 트리거 매핑 | 엔진 ON | 없음 | hidutil 원복 난이도 |
| **V4** | 터미널 모드: 컨텍스트 자동 감지로 직접 입력소스 전환 | `ContextManager` 터미널 판정 | 앱 전환 | 손쉬운 사용 | 화이트리스트 외 터미널 미감지 |

---

## 5. 권한 · 시스템 통합

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **A1** | 손쉬운 사용 권한 체크/요청 + 폴링 | `PermissionService.checkAccessibilityPermission` (`AXIsProcessTrusted`) | 시작+폴링 | 손쉬운 사용 | TCC stale |
| **A2** | 입력 모니터링 권한 체크 | `PermissionService.checkInputMonitoringPermission` (`CGPreflightListenEventAccess`) | 시작+폴링 | 입력 모니터링 | **온보딩이 손쉬운 사용만 안내** — IM 미부여 시 일부 입력 경로 영향 가능 |
| **A3** | 권한 안내 가이드 + 시스템 설정 열기 | `PermissionGuideView` | 권한 없을 때 | — | 손쉬운 사용만 설명 |
| **A4** | Stale 권한(서명/경로 변경) 감지 + 안내 | `PermissionService` stale 감지 | 시작 | — | 재부여 경로 노출 |
| **S1** | 로그인 시 자동 실행 (SMAppService) | `LaunchAtLoginService` | General 토글 | 로그인 항목 | macOS 13- 미지원 |
| **S2** | 권한 부여 후 엔진 자동 시작 (init 후 defer) | `AppState` 부트스트랩 | 권한 감지 | 손쉬운 사용 | init 중 HID 호출 금지 불변식 |
| **S3** | 종료 시 HID cleanup + pre-existing 복원 | 종료 핸들러 / `HIDRemapper` | 종료 | 없음 | 강제종료 시 잔존 |
| **S4/S5** | 전체 초기화 / 긴급 복구 | `ResetService` / `DoctorService` | Doctor | 없음 | 파일 기반 프로필 포함 여부 |

---

## 6. UI · 진단 · 업데이트

| ID | 기대 동작 | 담당 | 진입 | 권한 |
|----|-----------|------|------|------|
| **U1** | 메뉴바 아이콘 ON(채움)/OFF(외곽선) 구분 | `MenuBarLabelView` | 항상 | 없음 |
| **U2** | 메뉴바 popover: 상태·토글·빠른 액션 | `MenuBarView` | 클릭 | 없음 |
| **U3** | 설정 3탭(General/Profiles/Debug) | `DashboardView` | 메뉴 | 없음 |
| **U4** | Doctor: 다항목 진단 + 수동 복구(시작/중지/재시작/초기화/긴급) | `DoctorView`+`DoctorService` | 메뉴 | 없음 |
| **U5** | Event Viewer: 실시간 키 이벤트 + 지연시간(최대 1000) | `EventViewerView` ← `KeyInterceptor.onKeyEvent` | 메뉴 | 없음 |
| **U6** | 로그 뷰어: 파일 로그 필터/검색/복사 | `LogView`+`LogService` (`~/Library/Application Support/WinMacKey/winmackey.log`) | 메뉴 | 없음 |
| **U7** | 글로벌 단축키 `Cmd+Shift+Opt+D` → Doctor (popover 먹통 우회) | `GlobalHotKeyService` | 자동 등록 | 없음 |
| **UP1** | GitHub Releases 업데이트 체크 | `UpdateService` | 자동+수동 | 없음 |
| **UP2** | Ed25519 서명 검증 후 설치 | `UpdateService` | 설치 전 | 없음 |
| **UP3** | Developer ID 서명 + 공증(staple) → Gatekeeper 무경고 | `scripts/release.sh` | 배포 CI | — |
| **UP4** | `/Applications/` 외 설치 거부 | `UpdateService` | 체크 | 없음 |
| **UP5** | 중복 설치 감지(mdfind) + popover 재탐지 | `AppState` 설치 탐색 | 시작+popover | 없음 |

---

## 7. 🔴 회귀 핵심 — "이전엔 되던 Fn 인식이 왜 죽었나"

신규 맥북에서 표면화된 증상: **프로필 만들기 위자드 Step 2(현재 입력 감지)에서 내장 키보드 Fn 을 눌러도 슬롯이 "대기" 에서 안 바뀜.** 팀원은 최신 1.3.8 설치본.

Fn 감지 경로가 **둘**이고, 역사가 다르다:

### 경로 A — 위자드 Step 2 (CGEventTap)
- Fn 은 `leftSideChoices` 에 포함되어 원래 감지 대상. flagsChanged(keycode 63 + `maskSecondaryFn`)로 들어와야 `onVerifyKeyEvent` 가 호출됨.
- **죽었던 시점**: `844b3c3`(2026-03-27) — Caps Lock 보호 최적화(`updateNeedsFlagsChangedProcessing`)가 *매핑이 비면 flagsChanged 를 eventMask 에서 제외*. 위자드는 빈 매핑 진입 → Ctrl/Opt/Cmd/Fn 전부 미감지("대기" 고정).
- **복구**: `9fe9c2a`(2026-05-16, **build 12**) — 검증 모드면 flagsChanged 강제 구독.
- **현재 상태**: 팀원 빌드(최신 1.3.8 ≥ build 13)에 이 수정 포함. 따라서 **build 12 회귀는 원인이 아니다.** Ctrl/Opt/Cmd 는 잡히는데 **Fn 만** 안 잡힌다면, 남은 원인은 macOS 의 Fn/Globe 전달 특성:
  - **lone Fn/Globe 키의 flagsChanged 전달은 환경 의존적.** 특히 *시스템 설정 → 키보드 → "🌐 키를 다음 용도로 사용"* 이 입력소스 변경/이모지 등으로 설정되면 OS 가 Fn 키를 먼저 소비해 keycode-63 이벤트가 tap 에 도달하지 않을 수 있다. 신규 맥북의 기본값이 개발자 맥과 달라 차이가 생김.
  - → CGEventTap 단독으로는 lone Fn 을 신뢰성 있게 못 잡는 구조적 한계.

### 경로 B — Press-to-bind / first-seen (IOHIDManager)
- `KeyboardDeviceManager.inputValueCallback` 이 **`kHIDPage_KeyboardOrKeypad`(0x07) 만** 통과(`KeyboardDeviceManager.swift:207`).
- 그런데 **Fn/Globe 는 0x07 이 아니라 Apple Vendor Top Case 페이지(usage page 0x00FF, usage 0x03)** 로 보고됨. 앱 스스로도 이 사실을 안다: `HIDRemapper.swift:152` 의 `0x3F → 0xFF00000003 // Fn (Apple vendor-specific)`.
- 이 필터는 `KeyboardDeviceManager` **최초 생성(`ccc9bba`, 2026-03-27)부터 존재** → 이 경로는 **태초부터 Fn 미지원**(회귀 아님, 원래 미구현).

### 결론
- **사용자 영향의 핵심**: 4키 구성의 좌측 끝 키가 Fn 이라, Fn 미감지면 4키 키보드가 3키로 주저앉아 **"3키 vs 4키" 기능 구별이 깨진다**(§2.1). 즉 이 버그는 4키 레이아웃 설정을 사실상 불가능하게 만든다.
- **위자드(경로 A)**: build 회귀 아님. macOS 의 Fn/Globe 전달 의존성 때문에 신규 맥북에서 표면화. 1차 확인 = "🌐 키 용도 → 아무 작업 안 함" 후 재시도 + Ctrl/Cmd/Opt 는 잡히는지 분리 테스트.
- **바인딩(경로 B)**: 처음부터 Fn 미지원.
- **근본 수정(공통)**: Fn 을 IOHID usage page `0x00FF`/usage `0x03` 으로 감지(앱이 이미 매핑을 알고 있음). 경로 B 는 캡처 모드에서 usage-page 필터를 완화, 경로 A 는 IOHID 기반 Fn 신호(`onFnKeyDown`)를 위자드에 합류 + "+ Fn 🌐" 버튼 폴백.

> **v1.4.0 (build 16) 에서 수정 완료**: `KeyboardDeviceManager.onFnKeyDown`(IOHID 0x00FF/0x03 감지) + 위자드 Step 2 구독 + "+ Fn 🌐" 버튼(보장 폴백), 캡처 모드 usage-page 필터 완화. IOHID 감지의 실기 동작은 [`FRESH_INSTALL_CHECKLIST.md`](FRESH_INSTALL_CHECKLIST.md) 섹션 D 로 검증.

---

## 8. 알려진 제약 (By Design / 미구현)

- Caps Lock 은 앱이 처리하지 않음(시스템 위임).
- 외장↔외장 swap 자동 전환 안 함(마지막 프로필 유지) — 의도된 정책(P7).
- 사용자 정의 VDI/Terminal 앱 추가 UI 없음.
- Karabiner 동시 사용 시 F16 매핑 충돌(Doctor 경고).
- macOS 13 이하 SMAppService(로그인 항목) 미지원.
- Mac→Mac 원격은 Screen Sharing 만 검증, 타 VNC 미검증.

---

## 9. 자동 스모크 테스트 (`tests/`)

`hid_lifecycle_smoke` · `ownership_smoke` · `engine_off_ui_smoke` · `toggle_off_snapshot_smoke` · `mapping_profile_smoke` · `remote_mac_mode_smoke` · `trigger_branching_smoke` · `keyboard_capture_smoke` — 실행 `scripts/run-tests.sh` (CI 미설정, 수동).
