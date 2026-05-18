# P2 — Per-Keyboard Binding Plan

> Status: **DRAFT — 검토 + 합의 대기**
> 작성: 2026-05-18
> 작성자: Claude + lee-minki
> 모태 doc: `OPEN_PROBLEMS_ROADMAP.md` §2 P2 (sealed)
>
> 본 plan 합의 전 코드 변경 금지.
> P3 (PROFILE_LEGEND_REFACTOR) 라벨 모델과의 정렬은 별도 phase 로 분리.

---

## 0. 한 줄 요약

자동 프로필 전환의 표면을 **"외장 → 내장"** 한 시점만으로 좁히고, 미등록 외장 키보드 첫 입력 시 prompt + "이 키보드 무시 (영구)" 옵션을 제공한다. 핵심 모델: **"내장 키보드 = 안전 fallback"**.

---

## 1. Source Agreements (인터뷰 sealed)

| 항목 | 합의 (출처: OPEN_PROBLEMS_ROADMAP §2 P2) |
|---|---|
| 핵심 모델 | "내장 키보드 = 안전 fallback" |
| 자동 전환 정책 | **외장 → 내장** 시점만 자동. 그 외 swap 은 사용자 명시 |
| 외장 → 외장 swap | 자동 전환 안 함 — 마지막 활성 프로필 유지 |
| 새 키보드 첫 입력 | 메뉴바 알림 / sheet 으로 prompt (Press-to-bind UI 재활용) |
| "이 키보드 무시" 옵션 | 필수, **영구** (메뉴에서 명시 해제 전까지) |
| 내장 키보드 모델 위치 | 일급 — 명시적 프로필 바인딩 가능 |
| 실패 모드 우선순위 | False Positive > False Negative (보수적) |
| 키보드 swap 빈도 | 하루 여러 번 |

이 합의는 인터뷰 라운드 1-3 의 답변으로 도출. 본 doc 에서 더 묻지 않음.

---

## 2. 현재 baseline

### 이미 있는 것

- `Models/Profile.swift`:
  - `SavedKeyboardProfile.deviceIdentifier: KeyboardDeviceIdentifier?` (line 48)
  - `KeyboardProfileStore.profile(forDevice:)` (line 209)
- `Services/KeyboardDeviceManager.swift`:
  - `KeyboardDeviceIdentifier.isInternal` (line 12) — 이미 built-in 감지 됨
  - `lastActiveDevice` 추적 + `onActiveDeviceChanged` 콜백 (line 42, 45)
- `WinMacKeyApp.swift`:
  - `lastActiveKeyboard` 상태 (line 119)
  - `resolveActiveProfile()` (line 361~390) — 현재 우선순위:
    1. 디바이스 매칭 (`profile(forDevice:)`)
    2. 앱 매칭 (`profile(forBundleId:)`)
    3. defaultMappingProfileId 복원
- `Views/KeyboardBindingCaptureView.swift`:
  - v1.3.6 Press-to-bind UI (모달 sheet 으로 디바이스 캡처)

### 부족한 것 (사용자 합의 기준)

- 현재 `onActiveDeviceChanged` 가 **모든 디바이스 전환** 에 대해 `resolveActiveProfile` 을 호출 → 외장↔외장 swap 도 자동 전환됨 (사용자 합의와 어긋남)
- "이 키보드 무시" 라는 영구 ignore 개념이 없음
- 미등록 키보드 첫 입력 시 자동으로 prompt 띄우는 워크플로 없음 (사용자가 메뉴 열고 Bind 클릭해야)

---

## 3. 변경할 정책

### 3.1 자동 전환 게이트

`onActiveDeviceChanged(newDevice)` 핸들러를 다음 의사코드로 좁힌다:

```
def on_active_device_changed(new_device):
    prev_device = lastActiveKeyboard
    lastActiveKeyboard = new_device

    if new_device in ignored_devices:
        return                                # 무시 — 프로필 변경 없음

    if new_device.isInternal:
        # 외장 → 내장 (또는 내장 → 내장) 경우만 자동 전환 OK
        if prev_device is None or prev_device.isExternal:
            resolve_active_profile()
        return

    # 외장 디바이스가 active 가 됐다
    if prev_device is None:
        # 첫 키보드. 등록된 프로필 있으면 적용, 없으면 prompt
        if has_bound_profile(new_device):
            resolve_active_profile()
        else:
            schedule_first_seen_prompt(new_device)
        return

    if prev_device.deviceIdentifier == new_device.deviceIdentifier:
        return                                # 같은 디바이스, 변경 없음

    # 외장 → 외장 swap: 자동 전환 안 함 (사용자 명시 필요)
    if not has_bound_profile(new_device):
        schedule_first_seen_prompt(new_device)
    # 등록되어 있더라도 자동 전환 X — 사용자가 메뉴에서 명시 선택
```

### 3.2 IgnoredDevices 모델

```swift
struct IgnoredDevices: Codable {
    var devices: Set<KeyboardDeviceIdentifier>
}

extension KeyboardProfileStore {
    @AppStorage("ignoredKeyboardDevices") ...   // JSON-serialized
    func ignore(_ device: KeyboardDeviceIdentifier)
    func unignore(_ device: KeyboardDeviceIdentifier)
    func isIgnored(_ device: KeyboardDeviceIdentifier) -> Bool
}
```

- 영구 저장 (UserDefaults JSON)
- 메뉴: Profiles 탭 하단에 "Ignored devices" 섹션 — 목록 + 각 항목에 "Remove (다시 prompt)" 버튼

### 3.3 First-seen prompt

- 미등록 디바이스 + 무시 안 된 디바이스 가 처음 입력하면 메뉴바 위에 sheet
- sheet 내용:
  - "새 키보드가 감지되었습니다: {displayName} ({VID:PID})"
  - 버튼 3개: **[Bind to profile…]**, **[Ignore this keyboard]**, **[Not now]**
  - timeout 10초 자동 닫힘 (= "Not now")
- "Bind to profile…" 은 기존 Press-to-bind UI 와 연결
- "Ignore this keyboard" 는 `ignoredDevices` 에 영구 추가

---

## 4. MVP 정의

### MVP — 반드시 들어가야 할 것

- [ ] **M1.** `Models/IgnoredDevices.swift` 신설 + `KeyboardProfileStore` 에 ignore/unignore/isIgnored API 추가
- [ ] **M2.** `WinMacKeyApp.resolveActiveProfile()` + `onActiveDeviceChanged` 핸들러를 §3.1 의사코드 그대로 보수화
- [ ] **M3.** `Views/FirstSeenKeyboardPromptView.swift` (가칭) 신설 — 새 키보드 감지 sheet
- [ ] **M4.** Profiles 탭 (`Views/DashboardView.swift` profiles tab) 에 "Ignored devices" 섹션 + remove 버튼
- [ ] **M5.** `MANUAL_TEST_PLAN.md` 에 시나리오 추가:
  - S-KB1. 외장 → 내장 전환 시 자동 프로필 복귀 (사용자 합의 case)
  - S-KB2. 외장 → 외장 swap 시 프로필 유지 (자동 전환 X)
  - S-KB3. 미등록 외장 첫 입력 → sheet 표시
  - S-KB4. sheet 에서 "Ignore" 클릭 → 다음 입력에 prompt 안 뜸 + 프로필 자동 적용 안 됨
  - S-KB5. Ignored devices 메뉴에서 remove → 같은 디바이스 다시 입력 시 sheet 재표시
  - S-KB6. 앱 재시작 후에도 ignored 상태 유지
  - S-KB7. 내장 키보드에 명시적으로 프로필 바인딩 → 외장 swap 후 내장 복귀 시 그 프로필 적용

### Stretch — MVP 후

- [ ] S1. 디바이스별 "이 키보드 통계" (마지막 사용 시각, 입력 횟수 등) — 사용자가 어느 키보드를 자주 쓰는지 파악
- [ ] S2. Hot-swap 시 한 keypress 정도의 지연 줄이기 (현재 인프라로 첫 입력은 옛 프로필일 수 있음 — 사용자가 "1개 keypress 정도 OK" 라 sealed 했으니 우선순위 낮음)
- [ ] S3. 디바이스 그룹 (예: "회사 키보드 그룹") — 그룹별 프로필 적용

### 명시적으로 이번에 안 함

- 첫 keypress 정확성 (사용자 합의: 지연 상관없음)
- 외장 → 외장 자동 전환 (사용자 명시 거부)
- 키보드 fingerprinting / 추정 매칭 (False Positive 회피 우선)
- USB/Bluetooth 연결 이벤트 기반 prompt (첫 keypress 기반만)

---

## 5. Release Gate

### Gate A — 기존 기능 0 회귀

- 현재 사용자 프로필 모두 그대로 작동
- Press-to-bind UI (v1.3.6) 기존 워크플로 영향 없음
- 한영 / 모든 modifier 매핑 baseline 통과
- 위자드 / Settings UI 정상

### Gate B — 사용자 합의 시나리오 정확도

- S-KB1~S-KB7 7개 시나리오 모두 통과
- False Positive 0 회 (잘못된 프로필 자동 적용 0) — **이게 사용자가 가장 싫어한 케이스**
- False Negative 는 허용 (수동 전환으로 회복 가능)

---

## 6. Rollback Strategy

1. `M2` 의 보수화 로직은 단일 함수 (`onActiveDeviceChanged` 핸들러) 안에 격리. 회귀 시 옛 로직으로 한 줄 swap.
2. `IgnoredDevices` 는 별도 UserDefaults 키 (`ignoredKeyboardDevices`). 사용자가 명시 ignore 안 했으면 빈 set → no-op.
3. First-seen sheet 는 `M3` 단일 View. 호출부 (`onActiveDeviceChanged`) 만 disable 하면 sheet 안 뜸.
4. 모든 M1~M4 가 독립 → 부분 rollback 가능 (예: prompt UX 만 빼고 ignore 기능만 남기기).

---

## 7. Open Implementation Questions

- [ ] OQ1. `KeyboardDeviceIdentifier` 의 `Codable` 가 `Set<>` 에 잘 들어가는지 검증 (Hashable 이미 OK)
- [ ] OQ2. 미등록 외장 디바이스의 첫 입력은 이미 처리됨 (입력은 들어옴) — sheet 띄우는 동안 그 입력이 어느 프로필 매핑으로 처리될지? (제안: prev 프로필 그대로 유지, sheet 응답 뒤에 적용 / 무시)
- [ ] OQ3. sheet 가 떠 있는 동안 또 다른 새 디바이스 입력이 오면 어떻게? (제안: queue 또는 그냥 첫 sheet 만 표시, 두 번째는 dismiss 뒤에 다시 trigger)
- [ ] OQ4. 같은 디바이스가 잠시 disconnect → reconnect 되었을 때 ignore 상태 유지되는가? (VID:PID 기반이라 보존돼야 정상)
- [ ] OQ5. P3 (PROFILE_LEGEND_REFACTOR) 진행 시 `deviceIdentifier` 필드는 모델 마이그레이션에서 보존되는가? (PROFILE_LEGEND_REFACTOR_PLAN §3.4 마이그레이션 검증 필요)

---

## 8. P3 와의 정렬 (별도 phase)

본 plan 의 MVP M1~M5 는 P3 (PROFILE_LEGEND_REFACTOR) 와 **독립** 진행 가능.

단, P3 가 끝난 뒤 별도 phase 로 다음 정렬 필요:

- **P2-Align-1**: `SavedKeyboardProfile.physicalSlots` 가 device-bound 프로필 의도와 정합한지 확인 — 슬롯 라벨이 그 디바이스의 인쇄와 다를 때 사용자에게 경고할지
- **P2-Align-2**: First-seen prompt sheet 에서 "Bind to profile…" 진입 시 PROFILE_LEGEND_REFACTOR v0.2 Step 1 의 3지선다(Mac/Windows/Custom) UX 와 연결

이 정렬 phase 는 P3 sealed 후 별도 doc 으로 작성.

---

## 9. 5-조건 Harness Gate 점검 (ROADMAP §1.3)

| 조건 | 충족 여부 |
|---|---|
| 1. ROADMAP 등록 | ✓ P2 |
| 2. Plan doc 합의 | ⏳ 본 doc 합의 대기 |
| 3. 영향 받는 Matrix 행 식별 | ⚠️ 없음 — Behavior Matrix 는 trigger/transport 관점이라 키보드 디바이스 자동 전환 행이 따로 없음. M1 진행 전 03_BEHAVIOR_MATRIX 에 행 추가 필요할지 점검 |
| 4. 회귀 가드 식별 | ✓ MANUAL_TEST_PLAN S-KB1~7 |
| 5. Rollback 전략 | ✓ §6 |

→ 조건 2 + 3 만 사용자 OK 받으면 진행 가능.

---

## 10. Changelog of this doc

- 2026-05-18 v0.1 초안 작성. 인터뷰 sealed 그대로 반영. §3.1 의사코드로 정책 명시. P3 와 정렬 phase 분리.
