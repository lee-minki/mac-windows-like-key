# P7 — Device-Scoped Mapping Plan (디바이스별 동시 active)

> Status: **DRAFT — 검토 + 합의 대기**
> 작성: 2026-05-20
> 작성자: Claude + lee-minki
> 모태 doc: `OPEN_PROBLEMS_ROADMAP.md` §2 P7 (sealed)
>
> 본 plan 합의 전 코드 변경 금지.
> P2 의 M1-M3 commit 은 보존, M4/M5 는 P7 안에 흡수 결정됨.

---

## 0. 한 줄 요약

모든 bound 키보드 프로필이 자기 VID:PID 매칭으로 hidutil 에 **동시 적용**된다. 단일 active profile 개념을 폐기하고, "마지막 입력 사용 키보드" 같은 정보성 표시로 강등. unbound 외장은 평문, M3 first-seen prompt 가 사용자 인지 트리거. 글로벌 트리거 (한영 등) 는 별도 레이어 유지.

---

## 1. Source Agreements (인터뷰 sealed)

`OPEN_PROBLEMS_ROADMAP §2 P7` 참고. 본 doc 에서 더 묻지 않음.

요약:
- 모델 = 디바이스별 동시 active
- 같은 VID:PID 두 대 한계 수용
- Unbound 외장 = 평문, M3 prompt 트리거
- VDI = vdiDesiredKeys 그대로 사용 (별도 override 제거)
- 글로벌 트리거 = 별도 레이어 유지
- "Active" 배지 = "마지막 입력 사용 키보드" 정보성으로 강등
- MVP = 외장 코어 먼저, UI 그 뒤
- Migration 자동
- Release gate = 잘못된 디바이스 적용 OUT, 글로벌 깨짐 OUT

---

## 2. 현재 baseline (요약)

`OPEN_PROBLEMS_ROADMAP §2 P7` 의 "현 모델의 한계 (코드 확인)" 와 동일.

핵심:
- `HIDRemapper.applyMappings` (line 313, HIDRemapper.swift) — `hidutil property --set` 글로벌
- `HIDRemapper.applyMappingsForInternalKeyboardSync` (line 184) — `--matching Product:"Apple Internal Keyboard / Trackpad"` 디바이스별 (내장 only)
- `AppState.activeMappingProfileId` — 단일 active
- `AppState.switchToVdiMapping` / `switchToMacMapping` — VDI 모드 override 적용/해제
- `KeyInterceptor.applyCustomMappings` — 글로벌 매핑 적용 경로 (HIDRemapper 호출)

---

## 3. Target Model

```
+--------------------------------------------------+
|  글로벌 레이어 (Global Layer)                     |
|    - Right Command → F16 (IME trigger)           |
|    - 그 외 디바이스 무관 시스템 매핑                |
+--------------------------------------------------+
                       ▲
                       │ 결합
                       ▼
+--------------------------------------------------+
|  디바이스 레이어 (Per-Device Layer)               |
|    +------------------+  +-------------------+   |
|    | 회사키보드        |  | 맥북키보드 (내장)  |   |
|    | VID:0xABCD       |  | Product:Internal  |   |
|    | mappings...      |  | mappings...       |   |
|    +------------------+  +-------------------+   |
|        ↓ 동시 적용             ↓ 동시 적용         |
+--------------------------------------------------+
                       ▼
                  hidutil property
            --matching ... --set ... (디바이스별)
            --set ... (글로벌)
```

### 3.1 HIDRemapper 변경

**현재**:
```swift
func applyMappings(_ mappings: [Int64: Int64])  // 글로벌
func applyMappingsForInternalKeyboardSync(_ mappings: [Int64: Int64])  // 내장 전용 (하드코딩 Product 매칭)
```

**목표**:
```swift
/// 글로벌 레이어 (IME 트리거 등 디바이스 무관)
func applyGlobalMappings(_ mappings: [Int64: Int64])

/// 디바이스 레이어 (각 bound 프로필별)
func applyDeviceMappings(_ mappings: [Int64: Int64], matching device: KeyboardDeviceIdentifier)

/// 디바이스 레이어 해제 (프로필 unbind 또는 ignore 시)
func clearDeviceMappings(matching device: KeyboardDeviceIdentifier)

/// 전체 디바이스 레이어 재계산 (앱 시작 시, 또는 binding 변경 시)
func reapplyAllDeviceMappings(_ store: KeyboardProfileStore)
```

내부적으로 `hidutil property --matching {"VendorID":N, "ProductID":M} --set {...}` 호출. 기존 internal-only 매칭은 generic device matching 의 special case 로 통합.

### 3.2 AppState 변경

**현재**:
- `@AppStorage activeMappingProfileId` — 단일 active
- `applyProfile(_:)` — activeMappingProfileId 변경 + refreshActiveProfileForCurrentContext
- `resolveActiveProfile()` — 디바이스→앱→default 순서로 한 프로필 선택
- `refreshActiveProfileForCurrentContext()` — activeMappingProfileId 의 매핑을 글로벌 적용
- `handleActiveDeviceChanged(_:)` — (P2/M2) 자동 전환 정책

**목표**:
- `activeMappingProfileId` → 의미 변경 또는 폐기. 어쩌면 "user-selected global profile" (deviceIdentifier 없는 프로필 사용 시) 로 강등
- 새 `lastUsedDeviceForDisplay: KeyboardDeviceIdentifier?` — UI 정보성
- 새 메서드 `reapplyDeviceLayer()` — 모든 bound 프로필을 디바이스 레이어로 동시 적용
- 호출 시점: 엔진 ON, 프로필 add/update/delete, ignore/unignore, 앱 시작 시
- `handleActiveDeviceChanged` 의 자동 전환 로직 폐기 가능 — 단, lastUsedDeviceForDisplay 갱신은 유지

### 3.3 KeyInterceptor / VDI 분기

- `switchToVdiMapping` / `switchToMacMapping` 제거 — 프로필의 vdiDesiredKeys vs localDesiredKeys 가 자체로 컨텍스트 분기
- VDI 모드 토글 시 `reapplyDeviceLayer()` 만 호출 (각 프로필의 mappings(for: context) 결과로 디바이스 레이어 재적용)
- `vdiInternalKeyboardMappings` 하드코딩 제거 — 내장 키보드도 SavedKeyboardProfile 형태로 표현되어 vdiDesiredKeys 채택

### 3.4 Migration

기존 사용자 데이터 (UserDefaults `savedKeyboardProfiles`):
- 각 SavedKeyboardProfile 그대로 보존
- `deviceIdentifier != nil` 인 프로필 → 자동으로 디바이스 레이어로 들어감
- `deviceIdentifier == nil` 인 프로필 → "user-selectable global profile" (activeMappingProfileId 가 가리키는 단일 매핑) — legacy 호환을 위해 글로벌 레이어 하나에 적용
- 사용자 행동 0. P7 release 후 첫 launch 에 자동 적용.

---

## 4. MVP 정의

### MVP Phase A — 디바이스 레이어 코어 (먼저)

- [ ] **A1.** `HIDRemapper`: `applyDeviceMappings(matching:)`, `clearDeviceMappings(matching:)` 신설. 기존 `applyMappingsForInternalKeyboardSync` 는 generic device matching 으로 통합 (내장 = `productName.contains("Internal")` 매칭 또는 VID 5AC + Apple Internal Keyboard product 매칭).
- [ ] **A2.** `KeyboardDeviceIdentifier`: hidutil matching JSON 생성 헬퍼 (`var hidutilMatchingJSON: String { ... }`) — VID:PID 또는 Internal Keyboard 특별 처리
- [ ] **A3.** `AppState.reapplyDeviceLayer()` 신설 — profileStore.profiles 순회하면서 deviceIdentifier 있는 프로필을 디바이스 레이어로 동시 적용. Context (Local/VDI) 반영.
- [ ] **A4.** 엔진 ON / 프로필 update / unignore / 앱 시작 시 `reapplyDeviceLayer()` 호출
- [ ] **A5.** Smoke 자동 검증 — 두 프로필 (다른 VID:PID) 가 동시 적용되어 각자 매핑이 hidutil 출력에 보이는지

### MVP Phase B — VDI 분기 정리

- [ ] **B1.** `switchToVdiMapping` / `switchToMacMapping` 제거 + 호출부 정리
- [ ] **B2.** `vdiInternalKeyboardMappings` 하드코딩 제거
- [ ] **B3.** VDI 모드 토글 시 `reapplyDeviceLayer()` 만 호출하도록 변경

### MVP Phase C — 글로벌 레이어 분리

- [ ] **C1.** `HIDRemapper.applyGlobalMappings(_:)` 신설 — 한영 트리거 (Right Command → F16) 만 담당
- [ ] **C2.** `imeTriggerMapping` 흐름을 글로벌 레이어로 격리. 디바이스 레이어 reapply 와 분리.

### MVP Phase D — UI 변경

- [ ] **D1.** Profiles 탭의 "Active" 배지 → "마지막 입력" 표시로 변경
- [ ] **D2.** "Apply" 버튼 (현재 단일 active 선택용) → 의미 약화 또는 제거 (deviceIdentifier 없는 프로필은 여전히 "선택해 사용" 의 user-selected global 로 남길 수 있음)
- [ ] **D3.** MenuBarView 현재 active profile 표시 → "각 키보드별로 다른 매핑 적용 중" 같은 새 표현
- [ ] **D4.** Ignored devices 메뉴 (P2/M4 였던 것) 흡수

### MVP Phase E — 회귀 가드 / 문서

- [ ] **E1.** `MANUAL_TEST_PLAN.md` 시나리오 추가:
  - S-DSM1. 외장 두 대 + 각 프로필 동시 적용 — 각자 매핑 정확히
  - S-DSM2. 외장 unbound → 평문 (매핑 적용 X)
  - S-DSM3. 내장 키보드 프로필 적용 + 외장 키보드 프로필 적용 동시 검증
  - S-DSM4. VDI 모드 진입/이탈 시 각 키보드의 vdiDesiredKeys 적용
  - S-DSM5. 한영 (Right Command) 모든 키보드에서 정상 동작
  - S-DSM6. 디바이스 disconnect → reconnect → 자동 재적용
  - S-DSM7. ignore 등록 → 그 디바이스 매핑 적용 X
  - S-DSM8. 글로벌 매핑 (legacy migration) 사용자가 deviceIdentifier 없는 프로필 가지고 있을 때 user-selected global 로 작동
- [ ] **E2.** `03_BEHAVIOR_MATRIX.md` 행 검토 — 디바이스 레이어 / 글로벌 레이어 행 추가 필요할지 (별도 commit + 합의)
- [ ] **E3.** `CHANGELOG` — 사용자 영향 큰 변화 명시. "단일 active → 디바이스별 동시 active" 전환 안내.

### Out-of-MVP (이번 라운드 명시적으로 안 함)

- 같은 VID:PID 두 대 구별 (사용자 합의로 한계 수용)
- 프로필별 한영 트리거 다른 키 (글로벌 레이어 1개 유지)
- Hot-swap mid-keystroke 정확성 보장 (사용자 합의: 지연 무관)
- 디바이스 그룹 / 태그 / 색상 구분

---

## 5. Release Gate (인터뷰 sealed)

### Gate A — 잘못된 디바이스에 매핑 적용 0회

S-DSM1, S-DSM3, S-DSM6 시나리오에서 회사키보드 매핑이 맥북에서 적용되거나 그 반대 = **즉시 OUT**.

검증: hidutil property 출력 dump + 사용자 수동 입력 테스트로 교차 검증.

### Gate B — 글로벌 동작 회귀 0

S-DSM5 (한영) + 기존 MANUAL_TEST_PLAN 의 모든 시나리오 통과. baseline 회귀 1건이라도 = **OUT**.

---

## 6. Rollback Strategy

1. P7 변경은 거의 모든 매핑 경로를 건드리므로, 작은 phase 단위로 commit + 각 phase 끝에 빌드 / 회귀 가드 통과 확인.
2. `reapplyDeviceLayer` 가 generic 함수 — 잘못된 경우 빈 dictionary 로 호출하면 전체 디바이스 매핑 클리어 가능.
3. Legacy migration path 보존 — deviceIdentifier 없는 프로필은 글로벌 레이어로 적용해 단일 active 모델 호환 유지.
4. Feature flag 가능 — `@AppStorage("p7DeviceScopedMapping") var enabled: Bool = false` 로 출시 직후엔 OFF default, 안정성 검증 후 ON 으로 promote. (단 인터뷰 §migration "자동" 합의와 약간 충돌 — 결정 필요. §8 OQ 참고)

---

## 7. 영향 범위 (코드 수준)

| 파일 | 변경 종류 | 비고 |
|---|---|---|
| `Services/HIDRemapper.swift` | 큰 폭 수정 | applyMappings 분리, device matching 일반화 |
| `WinMacKey/WinMacKeyApp.swift` | 큰 폭 수정 | activeMappingProfileId 의미 변경, reapplyDeviceLayer 신설, switchToVdiMapping 제거, handleActiveDeviceChanged 단순화 |
| `Services/KeyInterceptor.swift` | 영향 적음 | applyCustomMappings 의 호출자 변경, 인터셉터 로직 자체는 거의 그대로 |
| `Models/Profile.swift` | 변경 없음 | SavedKeyboardProfile 그대로. Migration 은 decoder 가 처리 (deviceIdentifier 있고 없고 로 자연스럽게 분기) |
| `Services/KeyboardDeviceManager.swift` | 작은 수정 | `hidutilMatchingJSON` 같은 헬퍼 추가 |
| `Views/DashboardView.swift` | 중간 수정 | Active 배지 변경, Apply 버튼 의미 변경 |
| `Views/MenuBarView.swift` | 중간 수정 | 현재 active profile 표시 부분 |
| `Views/FirstSeenKeyboardPromptView.swift` | 변경 없음 | M3 그대로 활용 |
| `docs/MANUAL_TEST_PLAN.md` | 추가 | S-DSM1~8 |
| `docs/design/03_BEHAVIOR_MATRIX.md` | 검토 | E2 |
| `CHANGELOG.md` | 큰 추가 | 사용자 영향 큰 모델 변경 |

---

## 8. Open Implementation Questions

- [ ] OQ1. `hidutil property --matching` 의 multi-set 지원 — 같은 sudoer 세션에서 여러 매칭을 동시에 set 가능한지, 또는 한 매칭만 active 인지 확인 필요 (CLI 실험)
- [ ] OQ2. 같은 디바이스에 다른 매핑이 두 번 set 되면 overwrite 인가 append 인가? (Phase A 검증 첫 번째)
- [ ] OQ3. Feature flag 도입 여부 — 인터뷰의 "migration 자동" 과 충돌 가능성. 사용자 결정 필요 후 §6 갱신
- [ ] OQ4. `kIOHIDProductKey` 매칭이 Apple Internal Keyboard 외 다른 키보드의 productName 과 잘 매칭되는지 (유니코드, 공백 등 escape 이슈)
- [ ] OQ5. 디바이스 disconnect/reconnect 시 hidutil 매핑이 자동 유지되는지 — macOS 가 unmatched 상태에서 매핑 lost 가능. S-DSM6 시나리오로 검증.
- [ ] OQ6. `imeTriggerMapping` 이 현재 `HIDRemapper.applyMappings` 안에 inject 되는데, 글로벌 레이어 분리하면 device 레이어 reapply 시 빠져나가는 문제 없는지

---

## 9. 5-조건 Harness Gate 점검 (ROADMAP §1.3)

| 조건 | 충족 여부 |
|---|---|
| 1. ROADMAP 등록 | ✓ P7 |
| 2. Plan doc 합의 | ⏳ 본 doc 합의 대기 |
| 3. 영향 받는 Matrix 행 식별 | ⏳ E2 에서 검토 — 디바이스 / 글로벌 레이어 행 추가 필요할지 |
| 4. 회귀 가드 식별 | ✓ MANUAL_TEST_PLAN S-DSM1~8 + 기존 baseline |
| 5. Rollback 전략 | ✓ §6 (단 OQ3 해결 필요) |

→ 조건 2, 3, OQ3 만 사용자 OK 받으면 Phase A 진행 가능.

---

## 10. 작업 순서 (제안)

1. Phase A 진행 — 디바이스 레이어 코어. 매번 작은 commit + 회귀 가드.
2. Phase A 끝나면 사용자에게 한 번 데모 + 검증 요청
3. Phase B (VDI 분기 정리) — 회귀 위험 큰 phase. 별도 commit 단위
4. Phase C (글로벌 레이어 분리)
5. Phase D (UI 변경) — 사용자 체감에 큰 영향
6. Phase E (문서 / 회귀 가드 / CHANGELOG)
7. 사용자 최종 검증 → Gate A, B 통과 → release 준비

---

## 11. Changelog of this doc

- 2026-05-20 v0.1 초안 작성. 인터뷰 sealed 반영. Phase A~E 구조. P2 M1-M3 흡수 결정 명시.
