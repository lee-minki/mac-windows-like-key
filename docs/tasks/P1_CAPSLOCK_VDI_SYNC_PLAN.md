# P1 — CapsLock VDI Sync Plan

> Status: **DRAFT — 검토 + 합의 대기**
> 작성: 2026-05-18
> 작성자: Claude + lee-minki
> 모태 doc: `OPEN_PROBLEMS_ROADMAP.md` §2 P1 (sealed)
>
> 본 plan 합의 전 코드 변경 금지.
> Phase 0 (실현 가능성 검증) 결과에 따라 Phase 1+ 가 통째로 보류될 수 있음.

---

## 0. 한 줄 요약

VMware/Omnissa Horizon Client 포커스 전환 시 macOS CapsLock 과 VDI 내부 CapsLock 을 양방향 동기화한다. **단, 사용자가 옵션을 켰을 때만 동작하고, 안정성 게이트를 통과 못 하면 출시 자체를 보류**한다.

---

## 1. Source Agreements (인터뷰 sealed)

| 항목 | 합의 (출처: OPEN_PROBLEMS_ROADMAP §2 P1) |
|---|---|
| Default | OFF (opt-in 설정) |
| 동기화 방향 | 양방향 (Mac ↔ VDI) |
| 범위 | Horizon Client 만 (Omnissa / VMware) |
| 우선 시나리오 | Mac 복귀 시 자판 안전 |
| 트리거 시점 | 윈도우 포커스 전환 |
| Release Gate | (a) 기존 기능 0 회귀, (b) 동기화 정확도 ~100% (10회 중 1회라도 틀리면 OUT) |
| Hard constraint | macOS 전역 CapsLock 동작 임의 토글 금지. 옵션 ON 인 경우만 토글 허용. |

이 합의는 인터뷰 라운드 1-3 의 답변으로 도출. 본 doc 에서 더 묻지 않음.

---

## 2. 현재 baseline

- `KeyInterceptor` 가 명시적으로 CapsLock 비간섭 정책:
  - `ensureCapsLockUntouched()` 매핑에서 CapsLock 제거
  - `updateNeedsFlagsChangedProcessing()` 의 Caps Lock 안전 최적화 (commit 9fe9c2a 에서 onVerifyKeyEvent 예외 추가)
- Behavior Matrix 행: `Caps Lock / system-owned / none / not used as app trigger / target`
- 한영 (IME) 토글은 Right Command → F16 → Horizon 측 Right Alt 변환 경로로 이미 잘 동작 (P1 가 참고할 모델)
- Horizon bundle ID 감지 이미 `ContextManager.swift:15-18` 에 존재:
  - `com.vmware.horizon`
  - `com.omnissa.horizon.client.mac`
  - `com.omnissa.horizon.protocol`

---

## 3. 핵심 기술 의문 (Phase 0 검증 대상)

본 plan 의 가장 큰 리스크는 **macOS 측에서 VDI 내부 CapsLock 상태를 알 방법이 없을 가능성**.

| 의문 | 영향 | 검증 방법 |
|---|---|---|
| Q1. Mac CapsLock 상태를 코드에서 읽을 수 있는가? | 양방향 sync 의 핵심. 못 읽으면 Mac→VDI 단방향만 가능 | `CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)` 시험. 또는 `IOKit/hidsystem` 의 `kIOHIDFKeyModeKey` |
| Q2. Mac CapsLock 을 코드에서 토글할 수 있는가? | VDI→Mac 방향의 핵심. 못 토글하면 양방향 불가 | `IOHIDSetModifierLockState` 의 `kIOHIDCapsLockState` 사용. Accessibility 권한 외 추가 권한 필요 여부 확인 |
| Q3. Horizon Client 안에 CapsLock 토글을 어떻게 흘려넣는가? | VDI 측 sync 의 핵심. 합성 keystroke 가 게스트에 닿는지 | `CGEvent` 로 kVK_CapsLock keyDown/keyUp 합성 + Horizon focus 일 때 전달. 또는 RightAlt 같은 우회 트리거 활용 (한영 모델 참고) |
| Q4. VDI 내부 CapsLock 상태를 외부에서 알 수 있는가? | 양방향 동기화 정확도 게이트 | **거의 확실히 No**. → 상태 모델은 "Mac 측 truth + VDI 토글 누적 가정" 으로 추정만 가능 → 정확도 게이트 통과 위험 |
| Q5. Horizon 포커스 전환 정확 감지 가능한가? | 트리거의 신뢰성 | `NSWorkspace.didActivateApplicationNotification` 으로 bundle ID 매칭. 이미 ContextManager 가 처리 중 |

**Q4 가 가장 큰 리스크**. Q4 의 답이 "외부에서 못 안다" 인데 사용자 게이트가 "10회 중 1회라도 틀리면 OUT" 이면, **양방향 sync 는 구조적으로 통과 불가능**할 수 있음.

---

## 4. Approach Decision Tree

```
Phase 0: 실현 가능성 검증 (코드 1~2일)
    │
    ├── Q1, Q2, Q3, Q5 모두 ✓
    │       │
    │       └── Q4 결과로 분기:
    │             │
    │             ├── Q4 ✓ (외부 관측 가능):
    │             │     → Phase 1 양방향 sync 구현 진행
    │             │
    │             └── Q4 ✗ (관측 불가, 보편적 시나리오):
    │                   → 단방향 inbound 만 (Mac → VDI focus 진입 시) 으로 scope down
    │                   → 또는 P1 자체 보류 결정
    │
    └── Q1-3, Q5 중 하나라도 ✗:
            → P1 자체 보류. ROADMAP 에 "infeasible with current macOS API" 로 기록
```

**Phase 0 가 가장 중요**. 코드 작성 시작 전, **두 화면짜리 진단 harness** 를 먼저 만들어 Q1~Q5 답을 모두 얻고 사용자와 한번 더 합의한 뒤에 Phase 1 진행.

---

## 5. MVP 정의

### MVP Phase 0 — 실현 가능성 진단 harness

- [ ] **F0-1.** `scripts/diagnose-capslock.swift` — 셸 스크립트로 5분 안에 Q1~Q3 답 출력
  - Mac CapsLock 현재 상태 print
  - 토글 시도 + 결과 확인
  - 합성 CapsLock keystroke 가 Mac 전역에 반영되는지 / 다른 앱에 닿는지
- [ ] **F0-2.** Horizon Client 띄우고 수동으로 합성 keystroke 흘려보내서 VDI 내부 반응 관찰
- [ ] **F0-3.** Q1~Q5 결과를 본 doc §3 표에 기록 + Decision Log entry
- [ ] **F0-4.** 사용자와 한번 더 review → 양방향 / 단방향 / 보류 결정

### MVP Phase 1 — opt-in 동기화 (Phase 0 통과 시에만)

- [ ] **F1-1.** `Models/CapsLockSyncSetting.swift` 신설
  - `@AppStorage("capsLockSyncEnabled") var capsLockSyncEnabled: Bool = false`
- [ ] **F1-2.** `Services/CapsLockSyncService.swift` 신설
  - Horizon focus 진입 시 / 이탈 시 트리거
  - 옵션 OFF 면 no-op
  - Mac CapsLock 상태 읽기 / 쓰기 헬퍼
  - 합성 keystroke 보내기 헬퍼
- [ ] **F1-3.** `ContextManager` 의 Horizon focus 이벤트 → `CapsLockSyncService` 와 연결
- [ ] **F1-4.** Settings UI 에 토글 + 경고 문구 ("실험적 기능 / Horizon 전용 / 다른 VDI 미지원")
- [ ] **F1-5.** `03_BEHAVIOR_MATRIX.md` 의 CapsLock 행 변경:
  ```diff
  - | Caps Lock | system-owned | none | not used as app trigger | target |
  + | Caps Lock (sync OFF, default) | system-owned | none | not used as app trigger | target |
  + | Caps Lock (sync ON, Horizon focus 전환 시) | opt-in | CapsLock state read + synthesized toggle | Mac ↔ Horizon VDI CapsLock 동기화 | target |
  ```
  ← **Matrix row 변경은 별도 commit, 사용자 명시 합의 필요** (ROADMAP §4 G2 룰)
- [ ] **F1-6.** `MANUAL_TEST_PLAN.md` 에 시나리오 추가:
  - S-CL1. sync OFF 기본 — CapsLock 평소처럼 동작, 한영 정상
  - S-CL2. sync ON, Mac CapsLock ON 후 Horizon focus → VDI 내부 대문자 확인
  - S-CL3. sync ON, VDI 내부 CapsLock 토글 후 Mac focus → Mac 측 상태 일치
  - S-CL4. sync ON, 10회 연속 토글 → 정확도 측정 (10/10 통과해야 release)
  - S-CL5. sync ON, 한영 토글이 평소대로 동작하는지 회귀 확인
  - S-CL6. sync OFF 로 끄고 다시 ON 했을 때 상태 누설 없음

### Out-of-MVP (이번 라운드 명시적으로 안 함)

- 다른 VDI (Citrix Workspace, RDP, Parallels) 지원
- 비-Horizon Mac → Mac 원격 (Screen Sharing) 환경에서의 CapsLock 동기화
- VDI 안의 CapsLock 상태를 게스트 OS 측에서 명시적으로 보고받는 방식 (Horizon plugin 작성)
- CapsLock state 의 OS 통계 / 사용자 분석

---

## 6. Release Gate (인터뷰 sealed 그대로)

다음 둘을 모두 통과해야 release.

### Gate A — 기존 기능 0 회귀

다음 시나리오가 **sync ON / OFF 양쪽** 에서 모두 baseline 과 동일하게 동작해야 함:

- 한영 토글 (Right Command, 모든 컨텍스트)
- 모든 modifier 매핑 (Standard Mac / Windows Bluetooth / 사용자 프로필)
- CapsLock 평소 동작 (sync OFF 기준 — 다른 macOS 앱에서 대문자 lock 정상)
- 위자드 / 프로필 wizard / Press-to-bind UI

**측정**: `MANUAL_TEST_PLAN.md` 기존 시나리오 전수 통과 + 위 sync ON / OFF 양쪽 통과.

### Gate B — 동기화 정확도

S-CL4 시나리오 (10회 연속 토글 동기화) 가 **10 / 10 통과**. 1회라도 틀리면 OUT.

**측정**: 사용자 + 보조자 둘이서 한 세션에 10회 토글 → 양쪽 결과 기록. 결과는 `docs/design/07_REGRESSION_NOTES.md` 에 evidence 형식으로 첨부.

---

## 7. Rollback Strategy

1. **`capsLockSyncEnabled = false` 가 default**. 사용자가 토글 OFF 하면 즉시 모든 sync 로직 no-op.
2. `Services/CapsLockSyncService.swift` 가 단독 모듈로 분리 → 회귀 발견 시 호출부 (ContextManager 의 한 줄) 만 주석 처리하면 전체 무효화 가능.
3. `Models/CapsLockSyncSetting.swift` 의 default 를 `false` 로 박아둔 상태에서 commit → 사용자가 실수로 켰던 경우도 다음 release 에서 OFF 강제 가능 (옵션: `capsLockSyncForceOff` 임시 플래그 추가).

---

## 8. Open Implementation Questions (Phase 0 답변 후 closed)

- [ ] OQ1. macOS CapsLock 토글에 추가 권한 필요한가? (Accessibility 외 / 첫 설치 후 안내 추가?)
- [ ] OQ2. 합성 CapsLock keystroke 이 Mac 외 다른 앱 (예: Finder) 에서 의도치 않게 작동하는가?
- [ ] OQ3. Horizon focus 진입 직전 macOS 측 CapsLock 토글 이벤트가 Horizon 가 가로채는가?
- [ ] OQ4. macOS 부팅 직후 / 잠금 해제 직후 첫 Horizon 진입에서 race condition 있는가?
- [ ] OQ5. Sync 옵션이 켜진 상태에서 CapsLock 키 자체를 다른 키로 remap 하는 사용자 프로필이 있을 때 충돌은?

---

## 9. 5-조건 Harness Gate 점검 (ROADMAP §1.3)

| 조건 | 충족 여부 |
|---|---|
| 1. ROADMAP 등록 | ✓ P1 |
| 2. Plan doc 합의 | ⏳ 본 doc 합의 대기 |
| 3. 영향 받는 Matrix 행 식별 | ✓ Caps Lock 행 (변경 필요) |
| 4. 회귀 가드 식별 | ✓ MANUAL_TEST_PLAN S-CL1~6 |
| 5. Rollback 전략 | ✓ §7 |

→ Phase 0 진행 가능 (조건 2 만 사용자 OK 받으면 됨).
→ Phase 1 진행은 Phase 0 결과 + 추가 합의 필요.

---

## 10. Changelog of this doc

- 2026-05-18 v0.1 초안 작성. 인터뷰 sealed 반영. Phase 0 (feasibility) → Phase 1 (구현) 결정 트리 도입. Q1~Q5 핵심 기술 의문 명시.
