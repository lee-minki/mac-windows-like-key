# WinMacKey 기능 명세서 (Feature Specification)

> 기준 버전: **v1.6.0 / build 19** · 작성일 2026-05-28 · 최종 갱신 2026-05-30
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

## 2. 프로필 & 매핑 위자드 (v1.6.0+ · 캡처 없는 표 기반)

| ID | 기대 동작 | 담당 | 진입 | 권한 | 엣지/위험 |
|----|-----------|------|------|------|-----------|
| **P1** | 기본 프로필(standardMac): 매핑 없음 | `MappingProfile.standardMac` | 자동 | 없음 | — |
| **P2** | 저장 프로필: physicalKeys + Mac 목표 + VDI 목표 + (옵셔널) auxiliaryFnKey/bundleId/deviceIdentifier, UUID 저장 | `Profile.SavedKeyboardProfile` | 위자드 완료 | 없음 | 옵셔널 3필드는 새 위자드 UI 미노출이지만 편집 시 보존 |
| **P3** | 위자드 3화면: `0`프로필 목록 → `1`시작·의도 → `2`매핑 표 → `3`확인·저장 | `ModifierLayoutView` | 설정→Profiles | 없음 (캡처 제거) | 1.5.x 이전의 옛 6화면 흐름은 v1.6.0 에서 완전 제거 |
| **P4** | **시작·의도**: 프로필 이름 + 두 의도 카드 (① "한/영 전환만" 1클릭 즉시 완료 — 식별 프로필 ② "키 배치도 바꾸기" → 표) | `ModifierLayoutView.startIntentView` | Step 1 진입 | 없음 | — |
| **P5** | **매핑 표**: 4행(Fn·Ctrl·Opt·Cmd) × 2열(Mac 로컬·VDI) picker. Mac/Windows 키캡 표기 토글, "Windows 감각"(Cmd↔Ctrl 스왑) 1클릭 프리셋, "초기화" 버튼, 라이브 미리보기 | `ModifierLayoutView.mappingTableView` + `mappingRow` | Step 2 진입 | 없음 | 키캡 토글은 라벨만 바뀜 (행 순서는 고정, polish 후보) |
| **P6** | **확인·저장**: 매핑 요약 + 저장하고 적용 / 변경 저장 (편집 시) | `ModifierLayoutView.confirmSaveView` + `saveAndClose` | Step 3 진입 | 없음 | 편집 시 옵셔널 3필드(auxFn/bundleId/deviceId) 보존, 새로 생성 시 nil |
| **P7** | 자동 전환 우선순위: 디바이스 바인딩 > 앱 바인딩 > 기본. 외장→내장만 자동, 외장↔외장 swap 은 마지막 프로필 유지(v1.3.8 보수화) | `WinMacKeyApp` / `AppState` resolve | 디바이스·앱 전환 | 손쉬운 사용 | 정책 변경으로 사용자 기대와 어긋날 수 있음 |
| **P8** | **안전 삭제 invariant**: active 프로필 삭제 시 `activeMappingProfileId="standardMac"` 리셋 + custom HID 매핑 clear | `AppState.deleteProfileSafely` | DashboardView·ModifierLayoutView 휴지통 | 없음 | service 추출 전(v1.5.1) 회귀 이력 — DashboardView 만 처리하고 새 UI 누락 |

### 2.1 기능 축은 "키코드" — 키캡 표기·물리 위치 무관

새 위자드는 **macOS 가 모든 키보드를 표준 modifier 키코드(`kVK_Function`·`kVK_Control`·`kVK_Option`·`kVK_Command`)로 정규화한다는 사실** 위에 선다. `hidutil` 매핑도 키코드→키코드이므로 어떤 물리 키보드(Mac/Windows/듀얼모드/펑션 키 위치 다른 외장)든 동일한 키코드를 받는다 → **표 4행이 모든 경우를 망라.** 누를 필요 없음.

- `selectedLegendStyle` (Mac/Windows) = **표시용(cosmetic)** — `Opt` vs `Alt`, `Cmd` vs `Win` 라벨만 전환 (`ModifierSlot.label(for:style:)`). 실제 매핑·키코드는 일체 영향 없음.
- "Windows 감각" 프리셋 = Mac 에서 `kVK_Command` ↔ `kVK_Control` 스왑 (Windows 키보드 단축키 감각).
- 옛 "3키 vs 4키 + Space 경계" 자동 판단 / "좌측 끝 = Fn" 인지 / Fn 캡처는 **v1.6.0 에서 모두 제거** — 표가 항상 4행으로 모든 키를 다룬다.

> **호환성 정의**: 모델 struct 시그니처는 그대로. 새 표 UI 가 노출하지 않는 옵셔널 3필드(`auxiliaryFnKey`·`bundleId`·`deviceIdentifier`)는 편집 시 기존 값을 **보존**한다. 변경하려면 `auxiliaryFnKey` 는 프로필 삭제 후 재생성, `bundleId`/`deviceIdentifier` 는 Profiles 탭의 "Bind keyboard…" UI 에서.

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

## 7. 옛 위자드 Fn 감지 회귀 (역사적 — v1.6.0 에서 무효화)

> **v1.6.0 (build 19) 부터 위자드 캡처가 완전 제거되어 이 회귀 자체가 사라졌다.** 새 표 기반 위자드는 키를 누르지 않으므로 Fn 감지 경로가 더 이상 의존성이 아니다 — `KeyInterceptor.onVerifyKeyEvent` / `KeyboardDeviceManager.onFnKeyDown` / `appleFnUsagePage` 상수 등 관련 코드는 dead code 정리로 모두 삭제. Press-to-bind(`KeyboardBindingCaptureView`)의 Fn 미지원은 별개 이슈로 잔존 — 다만 일반 modifier 키로 바인딩 가능하므로 실사용 영향 미미.

### 역사 메모 (v1.5.x 이하)
신규 맥북에서 표면화된 증상은 **옛 위자드 Step 2(현재 입력 감지)에서 내장 키보드 Fn 을 눌러도 슬롯이 "대기" 에서 안 바뀜.** Fn 감지 경로가 둘 — (A) CGEventTap 경유 + (B) IOHIDManager 경유 — 이고 각자 회귀/구조적 한계가 있었다:

- **(A) Step 2 CGEventTap**: 옛 `updateNeedsFlagsChangedProcessing` 최적화(`844b3c3`, 2026-03-27)가 빈 매핑에서 flagsChanged 를 제외 → 위자드 진입 시 modifier 전부 미감지("대기" 고정). `9fe9c2a`(2026-05-16, build 12) 에서 검증 모드면 강제 구독으로 복구. 다만 lone Fn/Globe 키의 flagsChanged 전달은 macOS 환경 의존적("🌐 키 용도" 설정에 따라 OS 가 먼저 소비) — 신규 맥북 기본값이 달라 표면화.
- **(B) IOHIDManager**: `KeyboardDeviceManager.inputValueCallback` 이 `kHIDPage_KeyboardOrKeypad`(0x07) 만 통과 — Fn 은 Apple Vendor Top Case(0x00FF / 0x03)로 보고되어 처음부터 미지원(회귀 아님).
- **v1.4.0 (build 16) 수정**: `onFnKeyDown` (IOHID 0x00FF/0x03) + 위자드 Step 2 구독 + "+ Fn 🌐" 폴백 버튼 + 캡처 모드 usage-page 필터 완화. 캡처 자체가 v1.6.0 에서 제거되어 이 fix 도 함께 deleted.

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

---

## 10. 향후 기능 (계획 · 미구현)

> 명세만 확정. **아직 구현하지 않음.** 우선순위·UX는 별도 합의.

### CLEAN-1 · 키보드 클리닝 시스템 (Keyboard Cleaning Mode)
| 항목 | 내용 |
|---|---|
| **목적** | 키보드를 닦는 동안 **모든 키 입력을 차단** — 닦다가 키가 눌려 글자 입력·단축키·삭제 등이 일어나는 것을 방지. |
| **동작** | 클리닝 모드 ON 시 **모든 키보드 입력(keyDown/keyUp/flagsChanged)을 suppress**. 화면에 "클리닝 중" 오버레이 표시. |
| **켜기/끄기** | **마우스로만** 토글 (키가 다 막혀 있으므로 키보드로는 못 끔). 메뉴바 항목 + 화면 오버레이의 큰 "클리닝 종료" 버튼(마우스 클릭). |
| **안전장치** | ① 마우스/트랙패드는 항상 동작(잠금 해제 보장). ② 일정 시간(예: 5분) 자동 해제 옵션. ③ 전원/시스템 키 등 OS 강제 키는 막지 않음(잠금 위험 회피). |
| **구현 메모(예정)** | 기존 `KeyInterceptor`의 CGEventTap 재사용 — 클리닝 모드 플래그가 켜지면 콜백에서 모든 키 이벤트 `return nil`(suppress). 손쉬운 사용 권한 필요(이미 보유). 엔진 ON/OFF와 독립적인 별도 모드로 둘지 검토. |
| **상태** | 🔴 미구현 (명세만) |

### SCROLL-1 · 입력 장치별 스크롤 방향 분리 (Per-Device Scroll Direction)
| 항목 | 내용 |
|---|---|
| **목적** | **트랙패드 = macOS 자연 스크롤 유지(콘텐츠가 손가락 따라옴), 외장 마우스 휠 = Windows 방식(휠 위 = 콘텐츠 위)** 로 **분리.** macOS는 단일 글로벌 "자연스러운 스크롤" 토글이라 둘이 묶여 Windows 출신 사용자가 가장 자주 짜증내는 지점. WinMacKey 가 *"Windows 사용성을 Mac에서"* 라는 정체성에 부합. |
| **동작** | 스크롤 이벤트가 발생하면 **입력 장치(트랙패드 vs 마우스)를 판별** → 마우스 휠이면 deltaY/deltaX 부호 반전, 트랙패드면 그대로 통과. macOS 자연스크롤 글로벌 설정은 그대로 두고(트랙패드 기준), 마우스만 앱이 반전. |
| **켜기/끄기** | 메뉴바 / 설정 토글. (선택) 장치별 화이트리스트 — "이 마우스만 반전" |
| **구현 메모(예정)** | `CGEventTap` 으로 `kCGScrollWheel` 이벤트 구독 → `CGEventSource` / `IOHIDDevice` 정보로 source 가 mouse 인지 trackpad 인지 판별 (트랙패드는 `kCGScrollWheelEventIsContinuous=1` + momentum 등) → mouse 인 경우 새 이벤트로 deltaY/X 반전 후 재발행. OSS 참고: Scroll Reverser / Mos / LinearMouse. 손쉬운 사용 권한(이미 보유). |
| **안전장치** | ① 토글 OFF 시 즉시 원상복구(이벤트 통과만). ② momentum/관성 스크롤은 트랙패드만, 마우스는 step 단위 그대로. ③ 줌(⌘+휠) 같은 modifier 조합은 부호 반전 영향 검토 — 필요 시 제외. |
| **상태** | 🔴 미구현 (명세만) |
