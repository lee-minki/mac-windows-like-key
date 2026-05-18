# Keyboard Profile Legend Refactor Plan

> Status: **DRAFT — 검토 대기 중**
> 작성일: 2026-05-16
> 작성자: Claude + lee-minki
>
> 본 문서는 **검토 + 합의** 후에만 구현에 들어갑니다.
> MVP 범위가 합의되기 전까지는 코드 변경 금지.

---

## 1. 배경 / 문제 정의

현재 `SavedKeyboardProfile`은 키캡 인쇄 스타일을 `KeyboardLegendStyle` enum (`mac` / `windows`) 두 가지로만 표현한다.

```swift
enum KeyboardLegendStyle: String, Codable, CaseIterable, Hashable {
    case mac
    case windows
}
```

**한계**
1. **고정된 두 가지**: HHKB / Linux PC / 한글 자소 키캡 / 커스텀 키캡 / 일본어 자판 등 다양한 실물 키보드를 표현 못 함.
2. **키캡 라벨이 enum에 갇혀 있음**: 키마다 다른 인쇄(예: 왼쪽 Cmd만 `Win`, 오른쪽 Cmd는 그대로 `Cmd`)를 표현 못 함.
3. **분기 누수**: `style == .windows` 가 라벨링뿐 아니라 보조 라벨 표시, VDI 모드 기본값 등 UX 로직에까지 침투해 있어 enum 확장이 사실상 막혀 있음.

**유저 요청 (원문, 2026-05-16)**
> 키보드 프로파일을 좀더 추가할수 있어야겠네 지금 두개에서 계속 추가가 가능하도록 가능해?
>
> 지금 내생각에는 키캡 프린팅이 좌측이 네개인지 세개인지만 고르고 키입력을하면서 어떤키인지 확인받게 하는게 좋을것 같은데
>
> 우선순위: **올바른 구조 개편**

→ enum을 확장하기보다, **슬롯 단위 라벨링**으로 모델을 바꿔서 어떤 키보드든 표현 가능하게 한다.

---

## 2. 목표 (Goal)

1. 한 프로필이 임의 키캡 라벨 조합을 표현 가능해야 한다.
2. 위자드에서 사용자가 좌측 키 개수(3/4)를 고르고, 각 슬롯의 키캡 라벨을 키 입력 + 라벨 입력으로 직접 지정한다.
3. `KeyboardLegendStyle` enum 제거. 그에 의존하던 분기 정리.
4. 기존 저장 프로필은 자동 마이그레이션 (사용자 작업 0).

## Non-Goals (이번 라운드 밖)

- target 측 라벨(Mac 로컬 / VDI Windows) 사용자화. target 라벨은 OS가 결정한다는 원칙 유지.
- 새 빌트인 프리셋(HHKB 등) 추가. 사용자 정의로 충분.
- `MappingProfile.swift` 의 정적 프리셋 (standardMac/windowsBluetooth/winMacKeyOriginal) 변경.
- 키캡 라벨 다국어(i18n) 처리.

---

## 3. 변경 후 모델 (제안)

### 3.1 `PhysicalKeySlot` 신규

```swift
struct PhysicalKeySlot: Codable, Hashable {
    var keyCode: Int64       // macOS가 감지하는 실제 modifier (kVK_Control/Option/Command/Function)
    var label: String?       // 키캡에 인쇄된 텍스트. nil = keyCode의 기본 Mac 라벨 사용
}
```

### 3.2 `SavedKeyboardProfile` 변경

```diff
 struct SavedKeyboardProfile: Codable, Identifiable, Equatable, Hashable {
     var id: UUID = UUID()
     var name: String
-    var legendStyle: KeyboardLegendStyle = .mac
-    var physicalKeys: [Int64]
+    var physicalSlots: [PhysicalKeySlot]      // 좌측 3 or 4개
     var localDesiredKeys: [Int64]             // Mac 로컬 타겟 (Mac 라벨 고정)
     var vdiDesiredKeys: [Int64]               // VDI 타겟 (Windows 라벨 고정)
     var auxiliaryFnKey: Int64?
+    var auxiliaryFnLabel: String?             // 보조 Fn 슬롯도 라벨 가질 수 있음 (옵션)
     var bundleId: String?
     var deviceIdentifier: KeyboardDeviceIdentifier?
 }
```

### 3.3 라벨 해석 헬퍼

```swift
extension PhysicalKeySlot {
    /// 화면 표시용 키캡 라벨
    var displayLabel: String {
        label ?? ModifierSlot.defaultMacLabel(for: keyCode)
    }

    /// macOS 입력 기준 보조 라벨 (사용자가 라벨을 override 했을 때만 노출)
    var secondaryMacLabel: String? {
        guard let custom = label,
              custom != ModifierSlot.defaultMacLabel(for: keyCode)
        else { return nil }
        return ModifierSlot.defaultMacLabel(for: keyCode)
    }
}
```

`ModifierSlot.label(for: style:)` 은 다음과 같이 단순화:

```swift
// Before
static func label(for keyCode: Int64, style: KeyboardLegendStyle = .mac) -> String

// After
static func defaultMacLabel(for keyCode: Int64) -> String   // target 측에서 사용
// physical 슬롯은 slot.displayLabel 사용
```

### 3.4 Migration (자동)

`SavedKeyboardProfile.init(from decoder:)` 에서:

1. `physicalSlots` 키가 존재하면 그대로 디코드.
2. 없으면 (옛 포맷) `physicalKeys` + `legendStyle` 읽어서 변환:
   - `legendStyle == .mac` → 각 슬롯 `label = nil`
   - `legendStyle == .windows` → 각 슬롯 `label`을 Windows 인쇄 기준으로 채움
     ```
     kVK_Command       → "Win"
     kVK_RightCommand  → "RWin"
     kVK_Option        → "Alt"
     kVK_RightOption   → "RAlt"
     그 외             → nil (기본 Mac 라벨과 동일)
     ```
3. 한번 저장되면 옛 키는 사라지고 새 포맷만 남는다 (encode에는 새 키만).

---

## 4. UX 변경 (Wizard)

> **2026-05-16 수정**: 첫 안은 Step 1(표기)을 통째로 삭제했으나, 사용자 피드백 (스크린샷 + "포터블 키보드 배열이 다른 경우" 코멘트) 으로 Step 1을 **유지 + 확장** 으로 변경.
>
> 핵심: Mac/Windows 프리셋은 **빠른 시작 단축키**로 남기되, **"직접 설정 (Custom)"** 옵션을 추가해서 어떤 키보드든 표현할 수 있게 한다. 프리셋을 골라도 뒤 단계에서 슬롯별 라벨을 마이크로 조정할 수 있다.

### 4.1 단계 구성

| 현재 | 변경 후 |
|---|---|
| 1. 표기 (Mac/Windows 선택, 2지선다) | **1. 표기 (Mac / Windows / 직접 설정)** — 3지선다로 확장 |
| 2. 현재 입력 (3/4키 캡처) | 2. 현재 입력 (3/4키 캡처) **+ 슬롯별 라벨 마이크로 조정** |
| 3. Mac 로컬 매핑 | 3. Mac 로컬 매핑 (변경 없음) |
| 4. VDI 매핑 | 4. VDI 매핑 (변경 없음) |
| 5. 검증 | 5. 검증 (변경 없음) |

### 4.2 Step 1: 표기 (확장)

```
┌─────────────────────────────────────────────────────┐
│ 키보드 키캡 프린팅을 선택하세요                       │
│                                                     │
│ ┌─────────────────────────────────────────────────┐ │
│ │ (•) Mac 키보드                                  │ │
│ │     Ctrl · Opt · Cmd · Fn 키캡                  │ │
│ └─────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────┐ │
│ │ ( ) Windows 키보드                              │ │
│ │     Ctrl · Win · Alt · Fn 키캡                  │ │
│ └─────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────┐ │
│ │ ( ) 직접 설정 (Custom)                          │ │
│ │     포터블 / 자작 / 특이 배열 키보드용             │ │
│ │     슬롯별로 키캡 라벨을 직접 입력합니다             │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

- **Mac 키보드**: 모든 슬롯의 `label = nil` (= keyCode의 기본 Mac 라벨 사용).
- **Windows 키보드**: 슬롯의 keyCode가 Cmd/Opt 류면 `Win`/`Alt` 라벨로 자동 채움.
- **직접 설정**: 슬롯 라벨을 비워 두고 Step 2에서 슬롯별로 입력하게 한다. (Mac 라벨이 기본값으로 들어가 있고 사용자가 자유 편집.)

내부적으로는 셋 다 같은 `PhysicalKeySlot.label` 필드만 다르게 채울 뿐, **데이터 모델 상으로는 enum이 아니다.** "프리셋"은 wizard 셋업 편의 기능이지 저장 모델 상태가 아니다.

### 4.3 Step 2: 현재 입력 + 슬롯별 라벨 조정

```
┌─────────────────────────────────────────────────────┐
│ 좌측 키 개수: ( ) 3키   (•) 4키                       │
│                                                     │
│ 스페이스 왼쪽부터 modifier를 차례대로 누르고          │
│ 마지막에 Space 를 눌러 확정하세요.                    │
│                                                     │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐         │
│ │ 슬롯 1 │ │ 슬롯 2 │ │ 슬롯 3 │ │ 슬롯 4 │         │
│ │  Ctrl  │ │  Opt   │ │  Cmd   │ │   -    │         │
│ │ [편집] │ │ [편집] │ │ [편집] │ │        │         │
│ └────────┘ └────────┘ └────────┘ └────────┘         │
│                                                     │
│  선택된 슬롯 라벨:                                    │
│   [Ctrl] [Opt] [Cmd] [Fn] [Alt] [Win]               │
│   [직접 입력 ___________]                            │
└─────────────────────────────────────────────────────┘
```

- 키 입력으로 슬롯의 `keyCode` 가 채워짐.
- 라벨은 Step 1에서 고른 프리셋이 채워 둔 상태로 시작.
- **"직접 설정"을 골랐을 때만 라벨 편집 UI가 기본 노출**. 프리셋을 골랐을 때는 접혀 있고 "라벨 조정" 버튼으로 열 수 있게.
- 보조 라벨(macOS 입력 기준)은 slot.label이 keyCode의 기본 Mac 라벨과 다를 때만 노출.

### 4.4 Local / VDI / 검증 단계

- 변경 없음. target 측 라벨은 OS가 정함 (Mac 로컬 = Mac 라벨, VDI = Windows 라벨 고정).
- preview 카드의 source 측 라벨만 `slot.displayLabel` 로 교체.

---

## 5. MVP 정의 (제안)

### MVP — 반드시 들어가야 할 것

- [ ] **M1.** `PhysicalKeySlot` 모델 신설 + `SavedKeyboardProfile` 교체
- [ ] **M2.** 옛 포맷 자동 마이그레이션 (decode 시점) + 저장하면 새 포맷으로 영속
- [ ] **M3.** `KeyboardLegendStyle` enum 제거 + 의존 분기 정리
- [ ] **M4.** Wizard Step 1 (표기 선택) 을 **3지선다(Mac / Windows / 직접 설정)** 로 확장 + Step 2 에 슬롯별 라벨 마이크로 조정 UI 추가
- [ ] **M5.** Source 측 라벨 표시 전부 `slot.displayLabel` 로 통일 (DashboardView 행 포함)
- [ ] **M6.** 기존 빌드/유닛 테스트 통과 (`scripts/build.sh` 같은 게 있다면)

### Stretch — MVP 후

- [ ] S1. 빌트인 프리셋 ("Mac 표준", "Windows 표준") 한 번 클릭으로 슬롯 라벨 일괄 채우기
- [ ] S2. 자주 쓰는 라벨 자동완성 / 최근 사용 라벨 추천
- [ ] S3. 슬롯별 키캡 색상/이모지 (시각화)
- [ ] S4. `MappingProfile.swift` 정적 프리셋도 슬롯 라벨 모델로 흡수

### 명시적으로 이번에 안 함

- target 라벨 사용자화
- 키캡 라벨 i18n
- 듀얼 라벨 (한/영 병기) 같은 시각 표현

---

## 6. 영향 범위 (코드 수준)

| 파일 | 변경 종류 | 메모 |
|---|---|---|
| `Models/Profile.swift` | 모델 교체 + Migration | `PhysicalKeySlot` 추가, `legendStyle` 제거 |
| `Views/ModifierLayoutView.swift` | 큰 폭 수정 | Step 1 삭제, Step 2 UI 재구성, `style == .windows` 분기 정리 |
| `Views/DashboardView.swift` | 행 표시 수정 | `profile.legendStyle.title` 칩 → 라벨 요약으로 |
| `Views/EventViewerView.swift` | 영향 없음 (확인 필요) | 검색 결과 단순 match |
| `Services/KeyInterceptor.swift` | 영향 없음 (확인 필요) | `mappings(for:)` 계약만 유지하면 됨 |
| 기타 grep 결과 | 미미 | `legendStyle.title` 출력 자리만 교체 |

---

## 7. 위험 / 미해결

1. **마이그레이션 검증**: 현재 사용자(나 본인)가 가진 프로필이 정확히 어떤 상태인지 사전에 dump 해서 마이그레이션 결과를 사람이 한 번 확인할 필요.
2. **검증 단계의 보조 라벨**: 사용자가 슬롯 라벨을 "한글" 같이 비표준 텍스트로 넣었을 때 검증 화면이 너무 좁아지지 않게 폰트/길이 처리.
3. **`auxiliaryFnLabel` 의 필요성**: 보조 Fn 슬롯은 라벨을 따로 줄 일이 잘 없을 듯. **MVP에서는 생략하고 Stretch로 미루는 것을 권장**.

---

## 8. 합의 필요 항목 (사용자 결정 요청)

다음 7가지를 결정한 뒤 작업 시작.

- [ ] **Q1.** MVP 범위 (M1~M6) 그대로 OK? 빼고 싶은 것?
- [ ] **Q2.** `auxiliaryFnLabel` 은 MVP에서 빼도 되는지? (제안: 빼기)
- [ ] **Q3.** 마이그레이션 검증 — 작업 들어가기 전 `defaults read` 로 현재 프로필 dump 해서 보관할까?
- [ ] **Q4.** 빌트인 라벨 칩에 어느 값까지 포함? 제안: `Ctrl / Opt / Cmd / Fn / Alt / Win / Shift / Caps`
- [ ] **Q5.** 직접 입력 길이 제한? 제안: 최대 6글자 (`HanYeong` 같은 8자도 허용할지)
- [ ] **Q6.** 기존 빌드 절차 (`scripts/`, `build/`) 확인하고 회귀 테스트 한 줄 짜야 하는지?
- [ ] **Q7.** PR 분할 — 한 PR로 다 갈까, Model PR + Wizard PR 두 개로 나눌까?

---

## 9. 작업 순서 (합의 후)

1. 현재 사용자 프로필 dump 백업
2. Profile.swift 모델 교체 + Migration + 유닛 테스트 (옛 JSON → 새 모델)
3. ModifierSlot/슬롯 라벨 헬퍼 정리
4. Wizard Step 1/2 통합 UI
5. 나머지 View 의존 정리 (DashboardView 등)
6. 빌드 + 수동 회귀 (`docs/MANUAL_TEST_PLAN.md` 항목 따라)
7. CHANGELOG / README 업데이트
8. 커밋 단위 정리 후 사용자 확인

---

## 10. Changelog of this doc

- 2026-05-16 v0.1 초안 작성
- 2026-05-16 v0.2 사용자 피드백 반영: Step 1 삭제안 → **Mac / Windows / 직접 설정** 3지선다로 확장. "프리셋은 빠른 시작용 단축키, 데이터 모델은 슬롯 단위 라벨" 원칙은 유지.
