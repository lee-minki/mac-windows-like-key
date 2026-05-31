# Open Problems Roadmap

> Status: **v0.5.0 — v1.6.1 Published (P10 FIXED), P9 진단 대기, P11/P12 commit**
> 작성: 2026-05-16, 갱신: 2026-05-31
> 작성자: Claude + lee-minki
>
> 이 문서가 합의된 후에만 새 코드 변경 가능.
> 합의되지 않은 문제는 plan doc 없이 손대지 않는다.

## TL;DR (2026-05-30 snapshot)

| Track | Status | 다음 단계 | 동시 진행 |
|---|---|---|---|
| **P1** CapsLock VDI sync | Sealed, severity **medium** | plan doc 작성 | 독립 |
| **P2** Per-keyboard binding (단일 active 모델) | **Paused** — P7 검토 후 흡수/폐기 결정 | 보류 | — |
| **P3** Profile Legend Refactor | **Superseded by v1.6.0** — 위자드 표 기반 재설계 + 키캡 토글로 통합 | — | 종료 |
| **P4** Wizard flagsChanged 회귀 | **Obsoleted by v1.6.0** — 캡처 제거로 verify-tap 자체 dead code 삭제 | — | 종료 |
| **P5/P6** 오타/공백 사라짐 | Out-of-scope (윈맥키 책임 아님) | 등록 안 함 | — |
| **P7** 디바이스별 독립 매핑 (동시 active) | **Sealed** (인터뷰 1-3 완료) | plan doc 작성 | P2 흡수 결정됨 |
| **P8** 위자드 표 기반 재설계 | **Done (v1.6.0, commit 8ecf24a, Latest Published 2026-05-30)** | — | — |
| **P9** 한영 간헐 실패 (특정 앱, 재시작 fix) | **신규 보고 (v1.5.1 환경), 재현 진단 대기** — 엔진 unchanged 라 v1.6.0 도 동일 가능성 99% | 사용자 v1.6.0 업데이트 후 재현 여부 → 핫픽스 PR | 독립 |
| **P10** Ghostty/SSH 에서 ESC \u2192 이상 문자 | **DONE (v1.6.1, commit f7c7f6b, 2026-05-31)** — `KeyInterceptor.isTerminalAppFocused` 신설 + 가드 2곳 + `WinMacKeyApp` 동기화 | — | — |
| **P11** 키보드 클리닝 모드 (CLEAN-1) | **사용자 commit (2026-05-31), 구현 대기** — 키보드 닦는 동안 전체 키 입력 차단, 마우스로만 토글. `KeyboardCleanTool` ($9.99) 대체. | P9/P10 핫픽스 + 디자인 표준화 이후 합의 | 독립, `FEATURE_SPEC §10 CLEAN-1` |
| **P12** 입력 장치별 스크롤 방향 분리 (SCROLL-1) | **사용자 commit (2026-05-31), 구현 대기** — 트랙패드 자연 / 마우스 휠 반전. **현재 사용자 Logi Options 워크어라운드 대체** (브랜드 무관, 데몬 1개). | P9/P10 핫픽스 + 디자인 표준화 이후 합의 | 독립, Pro 게이팅 후보, `FEATURE_SPEC §10 SCROLL-1` |

**권장 다음 행동**: 사용자 v1.6.0 테스트 회신 → P9/P10 재현 격리 → 핫픽스 PR. **P11/P12 는 P9/P10 안정화 + 디자인 표준화([[project_winmackey_design_standards]]) 이후 본격 진입.** P7 plan doc 은 P9/P10 hotfix 후 재개.

## P9 · 한영전환 간헐 실패 (v1.5.1 보고, 2026-05-30)

**증상**: 특정 앱에서 Right Cmd 한영 토글 안 됨. 같은 시점 다른 앱은 정상. 앱 재시작으로 fix.

**자가복구는 이미 있음** (=원인 아님):
- `KeyInterceptor.swift:390-395` — `tapDisabledByTimeout/ByUserInput` 자동 re-enable
- `PermissionService.swift:28` — `isStaleGrantDetected` 감지 (단, 모달 없음 · MenuBarView 안내만)

**후보 (가능성 순)**:
1. **App-specific Ctrl+Space 소비** — "다른 앱은 정상" 가설과 일치 (IntelliJ 코드 완성, Spotlight 변형 등)
2. **HID remap drift** — Right Cmd→F16 매핑이 다른 hidutil 도구/시스템 이벤트로 풀려나감. 재시작 시 `start()` 가 매핑 재적용 → 우연 fix
3. **Stale grant 표시 사용자 미인지** — 재시작으로 권한 재평가

**대기 정보**: 어떤 앱·번들 ID, 그 앱에서 Ctrl+Space 직접 동작 여부, 메뉴바 ON 확인, v1.6.0 으로도 재현되는지

## P10 · Ghostty/SSH 에서 ESC → 이상 문자 ✅ DONE (v1.6.1, 2026-05-31)

**증상 (v1.5.1 + v1.6.0 환경 재현 확인)**: SSH 세션에서 ESC/Backspace 누르면 paste 내용이 한 글자씩 줄어들며 무한 재출력 + `^C`/`^L`/`^D` 노출. 사용자 SSH 작업 불가능.

**확진 증거 (2026-05-31 사용자 스크린샷)**: 매 프롬프트 trailing fragment 가 정확히 1글자씩 짧아짐(`macbook-to-macmini'` → `macbook-to-m` → `macbook-to-` → ... → `m` → 빈 → control chars). 이 패턴은 buffer 가 안 비고 매번 재주입 + Backspace 가 한 글자씩 갉아먹는 동작과 정확히 일치 — 후보 #1 (`bufferedReplayWindow + ESC` 충돌) 확정.

**근본 원인**: `KeyInterceptor` 에 `isTerminalAppFocused` 자체가 부재. 220ms `inputSourceCommit` 윈도우 동안 ESC/Backspace 가 buffer + `return nil` → 220ms 후 flush 가 한꺼번에 replay → SSH escape sequence 충돌. 터미널 분기 가드가 `WinMacKeyApp.onInputSourceToggle` 콜백의 if-else 분기에만 의존 → focus race 시 풀림.

**수정 (v1.6.1, 4점 패치, commit `f7c7f6b`)**:
1. `KeyInterceptor.isTerminalAppFocused: Bool = false` 프로퍼티 신설 (`isVdiAppFocused` 와 동일 패턴)
2. `beginInputSourceCommitWindow` 에 `guard !isTerminalAppFocused else { return }`
3. `handleMappedKey` 의 buffer 분기에도 `&& !isTerminalAppFocused` (focus race 안전망)
4. `WinMacKeyApp.onAppChanged` 에서 `keyInterceptor.isTerminalAppFocused = isNowTerminal` 동기화

**검증**: 터미널 화이트리스트(`com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `ai.warp.Warp-Stable`, `io.alacritty`, `net.kovidgoyal.kitty`, `dev.warp.Warp-Stable`, `com.anthropic.claudefordesktop`) 포커스 시 commit window 안 열림. 빌드 0 새 warning, 스모크 11개 PASS.

**Release**: GitHub `v1.6.1` Latest Published, 다른 맥 자동 업데이트 트리거.

상세 진단 컨텍스트는 메모리 `project_winmackey_v160_pending_bugs.md`.

---

---

## 1. 이 문서의 목적

기존 인프라가 잘 잡혀 있다 (`docs/design/01~07`, `docs/tasks/IMPLEMENTATION_PLAN.md`). 이 문서는 **그 위에 새로 쌓이는 변경**이 난개발이 되지 않게 묶어두는 게이트다.

### 1.1 이 문서가 다루는 것

- 현재 열려 있는 문제 인벤토리 (severity 포함)
- 각 문제의 의존성 / 우선순위
- 어떤 문제가 기존 invariant 와 충돌하는지 (예: CapsLock 시스템 소유 원칙)
- 새 문제가 들어왔을 때 어디에 무엇을 써야 하는지 (Behavior Matrix? Plan doc? Implementation Plan?)
- 합의 전 코드 변경 금지 게이트

### 1.2 이 문서가 다루지 않는 것

- 코드 디자인 디테일 → 문제별 plan doc (예: `PROFILE_LEGEND_REFACTOR_PLAN.md`)
- 작업 절차 / hook / commit 규약 → 이미 `05_DEVELOPMENT_RULES.md`
- Context × Scenario 정합성 contract → 이미 `03_BEHAVIOR_MATRIX.md`
- Phased AC 체크리스트 → 이미 `IMPLEMENTATION_PLAN.md` (필요 시 새 phase 추가)

### 1.3 작업 시작 게이트 (Harness Gate)

새 코드 변경은 다음 조건을 모두 만족해야 시작 가능:

1. 이 ROADMAP 에 해당 문제가 등록되어 있고
2. 문제의 plan doc (있다면) 이 사용자와 합의된 상태이고
3. 영향 받는 Behavior Matrix 행이 식별되었고
4. 회귀 가드 (테스트 / 수동 체크리스트) 가 식별되었고
5. Rollback 전략이 정의되었다.

5개 중 하나라도 안 채워졌으면 **stop & ask**.

---

## 2. 현재 열려 있는 문제 인벤토리

### Legend

- **Severity**: blocker / high / medium / low
- **Confidence**: high (재현 + 코드 확인) / medium (재현, 원인 가설) / low (가설만)
- **Status**: draft / planned / in-progress / done

---

### P1. VDI ↔ Mac CapsLock 비동기화

| | |
|---|---|
| Severity | **medium** (사용자 본인 평가 — "지금도 쓸 만함", 2026-05-18) |
| Confidence | high (사용자 인터뷰 round 1-3 완료) |
| Status | **요구사항 sealed**, plan doc 미작성 |
| 충돌 invariant | `03_BEHAVIOR_MATRIX.md` row "Caps Lock / system-owned / not used as app trigger / target" |

**사용자 인터뷰 sealed 합의 (2026-05-16/17)**

| 항목 | 합의 |
|---|---|
| Default | OFF (opt-in 설정) |
| 동기화 방향 | 양방향 (Mac ↔ VDI) |
| 범위 | Horizon Client 만 (다른 VDI 는 명시 요청 시) |
| 우선 시나리오 | Mac 복귀 시 자판 안전 |
| 트리거 시점 | 윈도우 포커스 전환 (사용자 행위 = 임의 토글 아님 으로 간주) |
| Release Gate | (a) 기존 기능 한 번이라도 망가뜨림 = OUT, (b) 동기화 정확도 10회 중 1회라도 틀림 = OUT |

**도출되는 plan doc 분기**
- 양방향 sync 의 구현 복잡도 vs 엄격한 게이트 충돌 → plan doc 작성 시 "단방향 inbound 만으로 게이트 통과 가능한지 먼저 검증" 으로 시작. 통과 못하면 P1 자체 보류.

**증상** (사용자 보고, 2026-05-16)
> VDI내부에서 한영은 연동이 되고 있지만, 캡스락은 연동이 안됨. 캡스락이 서로 다르게 불일치할때 화면 포인트를 바꿀때마다 캡스락 알림이 뜸. 이건 로지텍 캡스락 연동알람을 꺼서 일단 팝업은 뜨진 않지만 해결되진 않음.

**현재 동작 (baseline)**
- 앱이 명시적으로 CapsLock 을 절대 건드리지 않음:
  - `KeyInterceptor.ensureCapsLockUntouched()` (KeyInterceptor.swift) — 매핑 테이블에서 CapsLock 항목 제거
  - `KeyInterceptor.updateNeedsFlagsChangedProcessing()` 최적화 주석 "Caps Lock 등 시스템 modifier 동작 간섭을 원천 방지"
- 한영 (IME) 은 Right Command → F16 트리거로 처리 (`02_ARCHITECTURE.md`)
- VDI 컨텍스트: F16 패스스루 → Horizon Client 가 Right Alt 로 변환 → Windows IME 가 한영 토글
- VDI 내부의 CapsLock 상태는 Windows OS / VDI 세션 안에서만 관리됨
- macOS CapsLock 은 OS 전역 lock — 모든 앱이 공유

**왜 중요한가**

- 한영 + CapsLock 은 한국어 사용자가 매일 수십 번 토글하는 키. 두 OS 의 lock 상태가 다르면 같은 키 입력이 다른 결과를 낸다 (대소문자 뒤바뀜).
- 로지텍 알림은 증상이지 원인이 아니다 — 알림을 꺼도 입력 결과가 어긋난다.
- 한영은 이미 OS 경계를 넘어 동기화되는데 CapsLock 만 안 되는 것은 사용자 멘탈 모델에서 비대칭.

**해결 방향 후보** (요건 합의 전, 가설만)

| 옵션 | 요약 | 장점 | 단점 / 리스크 |
|---|---|---|---|
| **A. 현상 유지** | 동기화하지 않음. "VDI CapsLock 은 따로" 라고 매뉴얼화 | 코드 변경 0, 기존 invariant 보존 | 사용자 불편 그대로 |
| **B. VDI 진입/이탈 시점 동기화** | VDI 윈도우 포커스 시점에 Mac CapsLock state 를 읽어 VDI 에 토글 주입 (또는 그 반대) | 사용자 입력 흐름 자연스러움 | (1) VDI 의 CapsLock state 를 읽을 API 가 없음 — Mac 측 추정만 가능. (2) 토글 주입 타이밍 race. (3) 시스템 알림이 다시 뜰 수도. |
| **C. VDI 전용 CapsLock 가로채기** | VDI 포커스 상태에서 CapsLock 입력을 가로채 다른 키로 변환해 VDI 에 전달. Mac CapsLock 상태는 절대 안 건드림 | Mac 측 invariant 보존 | VDI 내부에서 CapsLock 입력은 Horizon 의 키 매핑에 의존. 가로챈 키를 무엇으로 보낼지 (VDI 측 매크로? F-key?) 별도 설계 필요. |
| **D. Logi Options+ 측 우회** | 로지텍 드라이버 설정으로 macOS CapsLock 을 다른 키로 remap → VDI 안에서 그 키를 CapsLock 으로 처리 | 앱 코드 변경 없음 | (1) 사용자가 로지텍 안 쓰면 적용 불가. (2) 다른 macOS 앱에서 CapsLock 작동 자체가 변형됨. |

**해결된 의문 (인터뷰로 합의)**

- Q1 → 양방향 sync 가 이상적, 단 안정성 게이트 통과 시에만
- Q2 → macOS 전역 CapsLock 동작 보존이 hard constraint, 강제 토글 금지
- Q3 → 명시 단축키 방식은 채택 안 함 (윈도우 포커스 전환 자체를 트리거로)
- Q4 → 일단 Horizon 만, 다른 VDI/키보드는 명시 요청 시

**Plan doc 작성 시점**: 즉시 가능. 단 `03_BEHAVIOR_MATRIX.md` 의 CapsLock row "system-owned / not used" 변경 합의 필요 → plan doc 의 §1 에 row 변경안 포함하고 별도 commit 으로 진행.

---

### P2. 키보드 다양성에 따른 슬롯 매핑 전략

| | |
|---|---|
| Severity | medium |
| Confidence | high (사용자 인터뷰 round 1-3 완료) |
| Status | **요구사항 sealed**, plan doc 미작성 |
| 의존 | [[PROFILE_LEGEND_REFACTOR_PLAN]] M1~M5 가 라벨 측면 절반 해결 — P2 는 자동 전환 정책 보수화 중심 |

**사용자 인터뷰 sealed 합의 (2026-05-18)**

| 항목 | 합의 |
|---|---|
| 핵심 모델 | **내장 키보드 = 안전 fallback** |
| 자동 전환 정책 | **외장 → 내장** 시점만 자동. 그 외 swap 은 사용자 명시 |
| 외장 → 외장 swap | 자동 전환 안 함 — 마지막 활성 프로필 유지 |
| 새 키보드 첫 입력 | 메뉴바 알림 / sheet 으로 prompt (Press-to-bind UI 재활용) |
| "이 키보드 무시" 옵션 | 필수, **영구** (메뉴에서 명시 해제 전까지) |
| 내장 키보드 모델 위치 | 일급 — 명시적 프로필 바인딩 가능 |
| 실패 모드 우선순위 | False Positive > False Negative (보수적) |
| 키보드 swap 빈도 | 하루 여러 번 (자주) |

**도출되는 작업 범위**
- 현재 `WinMacKeyApp.swift:363` 의 `lastActiveKeyboard` → `profile(forDevice:)` 자동 전환 로직 보수화 (외장→내장 만)
- "ignored devices" 집합 + 메뉴 관리 UI 신설
- prompt UX (Press-to-bind sheet 재활용 가능 여부 확인)

**증상** (사용자 보고, 2026-05-16)
> 키보드별로 구별이 다르므로 이걸 적용시키는데 있어서 4키도 있고 3키도있고 윈도우버전도있고 맥북버전도 있고 하니까 키보드를 어사인하는것에 대해서, 그별로 내가원하는 키로 어떻게 적용시킬지에대한 고민이 필요해

**현재 동작 (baseline) — 이미 잘 되어 있는 부분**

- `SavedKeyboardProfile.deviceIdentifier`: VID:PID 기반 디바이스 바인딩 (Models/Profile.swift:48)
- `KeyboardProfileStore.profile(forDevice:)`: 디바이스 식별자로 프로필 lookup (Profile.swift:209)
- `AppState.lastActiveKeyboard`: 마지막 입력 키보드 추적 (WinMacKeyApp.swift:119)
- 자동 전환 로직: `WinMacKeyApp.swift:363` `lastActiveKeyboard` → `profile(forDevice:)` 조회 → 적용
- Press-to-bind UI (v1.3.6): 모달 sheet 에서 키 입력으로 디바이스 캡처해 프로필에 바인딩

**현재 동작의 부족함**

- 프로필이 "어떤 키보드용" 인지는 device binding 으로 표현되지만, **그 키보드의 키캡 인쇄 / 슬롯 개수 / 사용자 의도** 가 프로필 단일 modelLevel 에 잘 표현 안 됨.
- 예: "회사 외장 4키 Windows 키보드" 프로필을 만들고 그 키보드를 바인딩해도, 사용자가 위자드를 처음 통과할 때 표기 선택을 잘못하면 (Mac/Windows 이분법) 라벨이 어긋남.
- 키보드 종류가 늘수록 위자드 단계마다 사용자 mental load 증가.

**연계되는 다른 변경**

- [[PROFILE_LEGEND_REFACTOR_PLAN]] (별도 doc, v0.2) — 키캡 라벨을 슬롯 단위 모델로 전환. P2 의 절반은 이게 해결.
- 남는 부분: 새 키보드 연결 시점의 자동 행동 (자동 바인딩 prompt? 무시? 가장 유사한 기존 프로필 추천?)

**해결 방향 후보**

| 옵션 | 요약 | 비고 |
|---|---|---|
| **α. Refactor 만 진행** | PROFILE_LEGEND_REFACTOR 로 슬롯 단위 라벨 모델 도입. 새 디바이스 처리는 그대로 (수동 바인딩) | 가장 작은 변경. P2 의 80% 는 이걸로 해결될 가능성 |
| **β. α + 새 디바이스 prompt** | 처음 보는 키보드가 입력하면 메뉴바 알림: "Bind this keyboard to a profile?" | UX 개선. Press-to-bind UI 가 이미 있어서 추가 비용 낮음 |
| **γ. α + 프로필 추천 ML** | 입력 패턴 보고 가장 유사한 기존 프로필 추천 | 과잉 설계, 보류 |

**해결된 의문**

- Q1 → 첫 keypress 기준 (현 인프라 그대로). 연결 이벤트 기반은 보류.
- Q2 → "이 키보드 무시" 영구 옵션으로 해결
- Q3 → 보수화 작업은 PROFILE_LEGEND_REFACTOR 와 독립 가능. 단, 라벨 모델 정렬을 위해 직렬화 권장 (P3 → P2 순서)

---

### P3. Profile Legend Refactor

| | |
|---|---|
| Severity | medium |
| Confidence | high |
| Status | plan doc v0.2 작성됨 ([[PROFILE_LEGEND_REFACTOR_PLAN]]), 합의 7항목 대기 |
| 의존 | 없음 (독립 진행 가능) |
| 차단하는 작업 | P2 (의존성 있음) |

세부 내용 ⇒ `docs/tasks/PROFILE_LEGEND_REFACTOR_PLAN.md`

이 ROADMAP 에서는 우선순위만 결정한다. 현재 plan doc 의 합의 게이트 7개가 미해결.

---

### P7. 디바이스별 독립 매핑 (동시 active 모델)

| | |
|---|---|
| Severity | high (사용자 직관과 현 모델의 갭) |
| Confidence | high (사용자 인터뷰 round 1-3 완료) |
| Status | **요구사항 sealed (2026-05-20)**, plan doc 미작성 |
| 충돌 | P2 의 단일 active 모델 가정 — P7 합의 후 P2 흡수/폐기 결정 |

**사용자 인터뷰 sealed 합의 (2026-05-20)**

| 항목 | 합의 |
|---|---|
| 핵심 모델 | **디바이스별 동시 active** — 모든 bound 프로필이 자기 VID:PID 매칭으로 hidutil 적용. 단일 active 폐기 |
| 같은 VID:PID 두 대 | 한계 수용 (구분 안 함, 사용자 시나리오 없음) |
| Unbound 외장 동작 | 평문 (매핑 적용 X). 사용자가 매핑 필요 인지 → 프로필 만들어 bind. M3 first-seen prompt 가 트리거 |
| VDI 모드 정렬 | 프로필의 vdiDesiredKeys 그대로 사용. 별도 `switchToVdiMapping` override 제거 가능 |
| 글로벌 트리거 (한영 등) | 디바이스 레이어와 별도 글로벌 레이어로 분리 유지 |
| UI "Active" 배지 | "마지막 입력 사용 키보드" 정보성 표시로 강등 |
| MVP 우선순위 | (a) 외장 디바이스별 동시 active 가 먼저, UI 는 그 뒤 |
| Migration | 자동 — deviceIdentifier 있으면 동시 active, 없으면 글로벌 레이어 |
| Release Gate | 매핑이 잘못된 키보드에 적용 = OUT, 한영 트리거 / 글로벌 동작 깨짐 = OUT |

**다음 단계**: P7 plan doc 작성 → 5-조건 harness gate 통과 → Phase A (외장 디바이스별 동시 active 코어) 구현 시작.

**P2 흡수/폐기 결정**
- M1 IgnoredDevices: **유지** — P7 모델에서도 "이 키보드 매핑 만들지 마라" 의미 유효
- M2 외장→내장 자동 전환: **의미 약화** — 동시 active 면 전환 개념이 사라짐. 코드는 유지하되 사용자 체감 영향 minimal
- M3 first-seen prompt: **유지** — unbound 외장 첫 입력 시 prompt 가 P7 의 sealed 흐름 ("사용자 인지 → 매핑 만들기") 트리거
- M4 ignored devices UI / M5 manual test: 보류 → P7 plan 안에서 재배치

**증상 / 발견 경위 (2026-05-20)**

P2 의 M1-M3 구현을 사용자가 테스트하던 중 발견. 회사키보드(외장) 와 맥북키보드(내장) 둘 다 프로필을 만들고 binding 했지만, 한 번에 하나만 active 되어 다른 키보드의 매핑이 자기 프로필대로 동작하지 않음.

> "이상한게 지금 바인딩을 로컬키보드에 하고 치고있는데 fn키 위취가 커맨드로 바뀌지 않네 설정과 달라"
>
> "솔직히 맥북키보드랑 외장키보드를 각각 실행시키는건 안어려울것같은데 왜 이러지 / 왜 하나만 액티브 되는거야"

**현 모델의 한계 (코드 확인)**

- `KeyInterceptor` + `HIDRemapper.applyMappings` 는 `hidutil property --set` 글로벌 적용. 단 한 시점에 한 set 의 매핑만.
- 예외: `HIDRemapper.applyMappingsForInternalKeyboardSync` 는 `--matching Product:"Apple Internal Keyboard / Trackpad"` 로 내장 키보드만 매칭 — 이건 디바이스별 매핑이 hidutil 차원에서 가능하다는 증거.
- 그러나 외장 키보드는 글로벌 set 한 개 only.
- AppState 의 `activeMappingProfileId` 도 한 번에 하나만 표현 가능.

**사용자가 기대한 모델**

- 각 SavedKeyboardProfile 이 자기 deviceIdentifier 의 VID:PID 매칭으로 hidutil 적용
- 모든 bound 프로필이 동시 active — 키보드 누르는 순간 그 디바이스 매핑이 적용
- "active profile" 이라는 글로벌 개념 폐기 또는 보조 표시로만
- swap / 전환 / fallback 개념 자체가 디바이스 단위로 분리되어 의미 약화

**P2 와의 관계**

P2 sealed 합의 (단일 active 모델 전제) 는 잘못된 출발점. P7 합의 후 P2 의 다음 부분 재검토:
- M1 IgnoredDevices: **유지** (디바이스별 매핑 모델에서도 "이 키보드는 무시" 는 유의미)
- M2 외장→내장 자동 전환 정책: **의미 변경** — 동시 active 면 전환 개념이 사라짐. 코드는 안전하게 남아 있지만 사용자 체감에 큰 영향 없어짐
- M3 first-seen prompt: **유지** (새 디바이스 → 매핑 만들지 묻기는 여전히 유효)
- M4 ignored devices UI: 보류 → P7 의 UI 안에 흡수 가능
- M5 manual test plan: 보류 → P7 의 시나리오로 재작성

**해결 방향 후보 (인터뷰 전, 가설만)**

| 옵션 | 요약 | 비고 |
|---|---|---|
| **α. Full device-bound** | 각 bound 프로필이 자기 VID:PID 매칭으로 hidutil 적용. unbound 디바이스는 평문 또는 글로벌 기본 매핑 | 사용자 직관에 가장 가까움. 같은 VID:PID 두 대는 구별 불가 (한계) |
| **β. Hybrid** | 내장 키보드는 디바이스별 매핑 (이미 있음), 외장은 여전히 글로벌 + auto-switch 강화 | 변경 부담 작음. 외장 여러 대 시나리오 미해결 |
| **γ. 글로벌 + Layered** | 글로벌 매핑 위에 디바이스별 override layer | 가장 유연하지만 구현 복잡. hidutil 의 layering 지원 불명확 |

**미해결 의문 (인터뷰 1라운드 대상)**

- Q1. 정말 "동시 active" 가 핵심 요구사항인지, 아니면 "사용자가 키보드 누를 때 그 키보드 프로필이 적용된다" 정도면 OK 인지 (현 P2 + 강한 auto-switch 로도 후자는 달성 가능)
- Q2. 같은 VID:PID 두 대 (예: 회사 키보드 두 개) — 어떻게 처리할지 (구분 불가가 release blocker 인지)
- Q3. unbound 외장 키보드는 평문 / 기본 프로필 / 가장 최근 활성 프로필 중 어느 쪽?
- Q4. VDI 모드의 내장 키보드 Fn↔Ctrl swap 은 디바이스별 매핑과 어떻게 정렬?
- Q5. 사용자가 명시적으로 active 프로필을 메뉴에서 "선택" 하는 옵션은 여전히 필요한가, 아니면 폐기?

---

### P5 / P6. (out-of-scope, 인터뷰로 진단)

| | |
|---|---|
| Severity | n/a (윈맥키 관심사 아님) |
| Status | **등록 안 함**. 사용자 결정. |

**P5 — 일반 키보드보다 오타 빈도 증가**
- 사용자 보고: 일반 키보드는 안 그런데 이건 더 틀린다 (빠른 타이핑 시 글자 누락, modifier 조합 빗나감)
- 인터뷰 결과: 한국어 IME 조작 중에만 두드러짐. 윈맥키 OFF 해도 발생. → macOS 한국어 IME / 타사 컴포넌트 측 가설.

**P6 — Hermes/OMX 에서 "Space → Shift+Enter" 시 공백 사라짐**
- 사용자 보고: 100% 재현. Claude (Codex CLI) 에서는 발생 X.
- 인터뷰 결과: 윈맥키 OFF 에서도 정확히 동일 (100% 재현). → Ghostty / Hermes / OMX 측 단독 책임 확정.

이 두 문제는 ROADMAP 에 정식 등록 X. 윈맥키 코드 변경 대상 아님. 본 도큐먼트는 향후 재논의 시 참고용으로만 기록.

---

### P4. (방금 해결) Wizard flagsChanged 회귀

| | |
|---|---|
| Severity | blocker (해결됨) |
| Status | done — commit 9fe9c2a |
| 회귀 가드 | 없음 (수동 테스트만) |

**남은 follow-up**

- F4-1. `MANUAL_TEST_PLAN.md` 에 "위자드 Step 2 modifier 캡처" 시나리오 추가 (현재 없음 — 회귀 가드 비어 있음)
- F4-2. (선택) `scripts/run-tests.sh` 의 smoke 에 `KeyInterceptor` 단위 시나리오 추가 검토. `onVerifyKeyEvent` didSet → `needsFlagsChangedProcessing` 전환 invariant.

---

## 3. 의존성 / 작업 순서

```
P4 (done) ─── F4-1 (manual test) ── (선택) F4-2 (smoke test)

P1 (CapsLock VDI sync, sealed) ─── plan doc 작성 ── 구현 (KeyInterceptor + 새 CapsLockSyncService + Horizon focus)
P2 (per-keyboard binding, sealed) ── plan doc 작성 ── 구현 (KeyboardDeviceManager + ignored devices UI)
P3 (PROFILE_LEGEND_REFACTOR) ─── 합의 7항목 ── M1~M5 ── (이후 P2 와 라벨 모델 정렬)
```

**코드 표면 분리** — P1 과 P2 는 거의 안 겹침:

| Track | 주 작업면 | 신규 도입 |
|---|---|---|
| P1 | `Services/KeyInterceptor.swift`, `Services/ContextManager.swift` (Horizon focus 추가) | `Services/CapsLockSyncService.swift` (가칭) |
| P2 | `WinMacKeyApp.swift:363` (auto-switch 로직 보수화), `Services/KeyboardDeviceManager.swift` | `Models/IgnoredDevices.swift` (가칭), 메뉴 UI |
| P3 | `Models/Profile.swift`, `Views/ModifierLayoutView.swift` | `Models/PhysicalKeySlot.swift` |

→ **P1 + P2 병렬 가능. P3 도 독립 진행 가능**. PR/commit 단위만 분리.

**Recommended ordering (v0.2 갱신)**

1. **F4-1**: MANUAL_TEST_PLAN 에 위자드 캡처 시나리오 추가 (5분, 회귀 차단). 누가 먼저 들어가든 무관.
2. **P1 plan doc + P2 plan doc**: 병렬로 두 doc 동시 작성. 합의 후 병렬 구현.
3. **P3 합의**: 7항목 답변. 합의 후 M1~M5 구현. P2 라벨 모델 정렬 단계는 P3 끝난 뒤.
4. **F4-2**: 시간 남으면.

---

## 4. 하네스 갭 (기존 규약이 못 막는 것)

| Gap | 무엇이 비어있나 | 보완안 |
|---|---|---|
| G1 | Wizard / Capture flow 자동 회귀 테스트 없음 (F4 가 자동 발견됐어야 했는데 사용자 보고로 알게 됨) | `tests/` 에 KeyInterceptor smoke 시나리오 — onVerifyKeyEvent didSet → flagsChanged 마스크 invariant. 단, KeyInterceptor 는 macOS API heavy 라서 mock 비용 큼. 우선 MANUAL_TEST_PLAN 보강이 현실적 |
| G2 | Behavior Matrix 에 CapsLock 행이 "system-owned/not used" 로 잠겨 있어 P1 진행이 곧 row 변경. row 변경 절차가 명시되지 않았음 | `05_DEVELOPMENT_RULES.md` 에 "Matrix row 변경 = 별도 commit + 합의 doc" 룰 추가 검토 |
| G3 | 새 plan doc 가 늘어나는데 어디에 두는지가 ad-hoc (`docs/design/` vs `docs/tasks/`) | 룰: 합의 대기 / 진행 중 plan = `docs/tasks/`. 합의 완료 + 안정화 = `docs/design/` 로 promote. 이 ROADMAP 도 promote 대상 |
| G4 | "이번 라운드 in-scope 인지" 가 PR 시점에 흐트러질 수 있음 | 모든 PR 본문은 ROADMAP 의 P# 번호 인용 의무화 (예: "Implements P3 / M1") |

---

## 5. Decision Log (append-only)

> 새 결정이 나올 때마다 한 줄씩 append. 작성자 / 날짜 / 결정 / 근거.

| 날짜 | 결정 | 근거 / Doc 링크 |
|---|---|---|
| 2026-05-16 | P4 standalone commit (refactor 와 분리) | 사용자 선택, 위자드가 아예 안 쓰여서 즉시 fix 필요 |
| 2026-05-16 | PROFILE_LEGEND_REFACTOR v0.1 → v0.2: Step 1 삭제안 폐기, 3지선다 확장으로 전환 | 사용자 피드백 "포터블 키보드 배열 다름". v0.2 §4.2 |
| 2026-05-16 | 이 ROADMAP 문서 신설 | 사용자 요청 — 하네스 엔지니어링 디시플린 확립 |
| 2026-05-17 | P1 요구사항 sealed | 사용자 인터뷰 라운드 1-3. opt-in 양방향, Horizon 만, Mac 복귀 자판 안전 우선, 엄격한 release gate |
| 2026-05-18 | P2 요구사항 sealed | 사용자 인터뷰 라운드 1-3. "내장 = 안전 fallback" 모델, 외장→내장 만 자동, "이 키보드 무시" 영구 옵션 |
| 2026-05-18 | P5 / P6 등록 안 함 | OFF 해도 동일 증상 발생 확인. 윈맥키 책임 밖. |
| 2026-05-18 | P1 severity high → medium | 사용자 본인 자체 평가 — "캡스락 쓰다보니까 걍 지금도 쓸 만한것같아". 작업은 계속 진행하되 시급도 down. |
| 2026-05-18 | P1 / P2 병렬 진행 가능 명시 | 코드 표면 분리 (P1=KeyInterceptor/CapsLockSyncService, P2=KeyboardDeviceManager/IgnoredDevices). |
| 2026-05-20 | P2 paused, P7 신규 등록 | 사용자 P2 M1-M3 테스트 중 "동시 active" 기대 발견. P2 의 단일 active 가정이 잘못된 출발점이었음. P7 인터뷰로 모델 재정의. M1-M3 commit 들은 보존 (P7 토대로 활용). |
| 2026-05-20 | P7 요구사항 sealed | 인터뷰 라운드 1-3. 동시 active, 같은 VID:PID 한계 수용, unbound 평문, VDI = vdiDesiredKeys 그대로, 글로벌 레이어 분리, "Active" 배지 정보성으로 강등, MVP = 외장 코어 먼저, migration 자동, gate = 잘못된 디바이스 적용 / 글로벌 깨짐. |

---

## 6. 합의 게이트 (사용자 결정 요청)

다음 사항이 답변된 후에야 각 phase 가 시작된다.

### G-A. P1 (CapsLock) 합의 항목 — ✅ ALL SEALED (인터뷰)

- [x] Q1 → 양방향 sync, 단 게이트 통과 시
- [x] Q2 → macOS 전역 CapsLock 동작 보존 hard constraint
- [x] Q3 → 명시 단축키 안 채택 안 함, 윈도우 포커스 전환을 트리거로
- [x] Q4 → Horizon 만 (다른 VDI 명시 요청 시)

다음 단계: **P1 plan doc 작성** → 단방향 inbound 만으로 게이트 통과 가능한지 먼저 검증.

### G-B. P3 (Profile Legend Refactor) 합의 항목

기존 `PROFILE_LEGEND_REFACTOR_PLAN.md` §8 의 7항목 (Q1~Q7) — **여전히 미답변, 별도 트랙 진행 필요**

### G-C. P2 (per-keyboard binding) 합의 항목 — ✅ ALL SEALED (인터뷰)

- [x] 자동 전환 정책 → 외장→내장 만
- [x] 외장↔외장 → 자동 안 함
- [x] 새 키보드 → prompt
- [x] "무시" 옵션 → 영구
- [x] 내장 키보드 → 일급 (바인딩 가능)
- [x] 실패 모드 → False Positive 회피 우선

다음 단계: **P2 plan doc 작성** (P3 합의 후 진행 권장 — 라벨 모델 정렬을 위해).

### G-D. 이 ROADMAP 자체

- [ ] ROADMAP 의 문제 인벤토리 / severity / 의존성 구조가 사용자 의도와 일치하는가
- [ ] G1~G4 하네스 갭 보완안에 동의하는가
- [ ] PR 본문에 P# 인용 의무화 (G4) 도입에 동의하는가

---

## 7. References

- `docs/design/01_REQUIREMENTS.md` — 제품 요건
- `docs/design/02_ARCHITECTURE.md` — 아키텍처
- `docs/design/03_BEHAVIOR_MATRIX.md` — Context × Scenario contract
- `docs/design/05_DEVELOPMENT_RULES.md` — 작업 규약 (TDD, hook, commit)
- `docs/design/07_REGRESSION_NOTES.md` — 알려진 회귀
- `docs/tasks/IMPLEMENTATION_PLAN.md` — phased AC 체크리스트
- `docs/tasks/PROFILE_LEGEND_REFACTOR_PLAN.md` — P3 detail
- `docs/MANUAL_TEST_PLAN.md` — 수동 검증 시나리오
- 메모: `~/.claude/projects/-Users-mk/memory/project_winmackey_auto_switch.md` (57일 전, 일부 outdated)

---

## 8. Changelog of this doc

- 2026-05-16 v0.1 초안. P1 / P2 / P3 / P4 인벤토리, 하네스 갭, 합의 게이트 정의.
- 2026-05-18 v0.2 P1 / P2 인터뷰 라운드 1-3 완료, sealed 합의 반영. P5 / P6 out-of-scope 로 명시.
- 2026-05-18 v0.2.1 TL;DR snapshot 추가. P1 severity high → medium (사용자 자체 평가). P1+P2 병렬 진행 가능 명시 + 코드 표면 분리 표.
- 2026-05-20 v0.3 P7 (디바이스별 독립 매핑 / 동시 active) 신규 등록. P2 paused (P7 검토 후 결정). 사용자 시연 + 코드 확인으로 모델 갭 식별.
- 2026-05-20 v0.3.1 P7 인터뷰 라운드 1-3 완료, sealed 합의 반영. [[P7_DEVICE_SCOPED_MAPPING_PLAN]] v0.1 작성. P2 M1-M3 흡수 결정 명시.
