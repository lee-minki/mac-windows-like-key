# 한/영 토글 아키텍처 & 회귀 지도 (IME Toggle Architecture & Regression Map)

> **이 문서를 먼저 읽으세요.** `KeyInterceptor` · `StateManager` · `InputSourceManager` ·
> `ContextManager` 를 건드리기 전에 필수. 이 서브시스템은 **"하나 고치면 하나 터지는"**
> 대표적인 whack-a-mole 영역입니다 — P10 · P13 · P14 회귀가 전부 **같은 replay 코드 한 줄**에서
> 나왔고, 최우선 오픈 버그 **P9**도 여기 있습니다.
>
> 지금 보이는 3-경로 분기·버퍼 윈도우·재시도 폴백은 **군더더기가 아니라, 각각 실제 회귀를
> 막으려고 붙은 것**입니다. "단순화"하려다 이미 해결된 버그를 되살리기 쉽습니다.
>
> _최종 갱신: 2026-07-06 (라이브 로그 캡처 + 소스 + 기존 docs 교차검증)_

---

## 0. 절대 규칙 (Invariants) — 위반 = 회귀

1. **3-경로를 하나로 합치지 말 것.** VDI / 터미널 / 그 외 GUI 는 각각 **정반대의 부작용**
   때문에 갈렸다. (§2, §3)
2. **`flushBufferedKeyEvents` 의 `usleep(5_000)` 및 버퍼 타이밍(100/180/20/30ms)을 순진하게
   바꾸지 말 것.** 이 줄이 **P10 · P13 · P14 의 진앙**이다. 변경은 반드시 하네스 게이트
   (순서·간격 스모크 + Word/SSH/VDI 수동 체크리스트)를 거친다.
3. **GUI 토글은 macOS SymbolicHotKey 60 (⌃Space '이전 입력 소스 선택')에 의존한다.** 이게
   꺼져 있으면 한/영이 침묵한다. `DoctorService` 가 감지·안내한다.
4. **합성 이벤트에는 반드시 `syntheticEventMarker`(WINK, 0x57494E4B) 를 찍는다.** 안 찍으면
   `KeyInterceptor` 탭이 자기가 주입한 이벤트를 재처리/재매핑한다. (`InputSourceManager.post`)
5. **트리거/replay 경로 변경은 P9 진단이 끝난 뒤에.** (2026-07-06 기준 P9 원인 확정됨 → §5)

---

## 1. 왜 이렇게 복잡한가 — 진화 히스토리 (fix → 새 문제)

| 시점 | 문제 | 해결 | 그 해결이 낳은 새 문제 |
|---|---|---|---|
| v0.x | 초기 | **TIS 직접**(`TISSelectInputSource`) + RightCmd tap | 한글 조합버퍼 미commit, 메뉴바 아이콘 stale |
| — | 조합 미commit | `commitComposingText` 시도 | **입력 간섭** → 즉시 제거 (`ec5d530`) |
| **v1.2.0** | 조합 commit + 메뉴바 갱신 | **Control+Space 합성**으로 전환 | Control+Space 가 **간헐적으로 안 먹음** |
| v1.2.1 | Control+Space 불안정 | 검증 폴링 + 재시도 + **TIS 폴백** 추가 | 실패 시 ~150ms 지연 (폴백이 느림) → **P9 씨앗** |
| **v1.6.1 (P10)** | **Ghostty/SSH 에서 ESC·Backspace 화면 깨짐** | 터미널 화이트리스트 → 커밋창 OFF, TIS 직행 | 경로가 2 → 3 갈래로 분기 |
| **v1.6.2 (P13)** | Word for Mac 글자 씹힘/지연 | 커밋창 220→150ms, replay 간격 0.5→5ms | 앱 카테고리별 타임아웃 필요 |
| **v1.7.0** | 버퍼 replay 신뢰성 | main-thread contract + adaptive timeout(100/180ms) | — |
| **P9 (오픈)** | **특정 앱에서 한/영 토글 간헐 실패** | (2026-07-06 원인 확정, 패치 대기) | §5 |

**교훈:** 이 서브시스템의 각 레이어는 "이전 해결책의 부작용을 막는 레이어"다. 스택을 이해하지
않고 아래를 빼면 위가 무너진다.

---

## 2. 3-경로 디스패치 맵

한/영 트리거(F16, HID에서 RightCmd→F16 리맵됨) 도달 시 분기 — `WinMacKeyApp.swift:224-241`:

```
onInputSourceToggle:
  if isVdiMode:        beginVdiRelayCooldownWindow()      // (A) VDI
  else if isTerminalMode: handleTerminalTrigger()          // (B) 터미널
  else:                beginInputSourceCommitWindow()      // (C) 그 외 GUI
                       + stateManager.handleTrigger(...)
```

### (A) VDI — Omnissa Horizon 등
- F16을 **패스스루** → Horizon 이 클라이언트 매핑표(`F16 → Right Alt (AltGr)`)로 변환 → Windows
  게스트가 한/영 처리. macOS 로컬 입력소스는 **안 건드림**.
- 30ms `vdiRelayCooldown` 버퍼(릴레이 정착 대기). `KeyInterceptor.beginVdiRelayCooldownWindow`.
- **주의:** VDI 에서 Cmd/Ctrl 감각이 다른 것은 별개 3겹 스택 때문 — ①상시 Windows식 스왑
  (`MappingProfile`: Cmd→Ctrl 등) ②VDI 전용 내장키보드 Fn↔Ctrl 스왑 ③Horizon 자체 매핑표.
  한/영 토글 버그와 혼동하지 말 것.

### (B) 터미널 — Ghostty · iTerm2 · Terminal · Warp · Alacritty · kitty · Claude desktop
- `ContextManager.terminalApps` 화이트리스트(+ `CustomTerminalApps` UserDefaults).
- **커밋 윈도우/버퍼를 아예 안 연다.** `handleTerminalTrigger` → `toggleDirectly()`
  (= `TISSelectInputSource`, 즉시·무버퍼).
- **왜?** (P10) 커밋창이 열리면 트리거 직후 ESC/Backspace/paste 가 버퍼됐다 한꺼번에 replay 되어
  **SSH escape sequence 로 오해석 → 화면 깨짐**. 그래서 터미널은 최소 경로만.
- 트레이드오프: 무버퍼라 전환 확정 전에 친 글자가 이전 IME 로 샐 수 있음(ㅊ 류). 터미널에선
  escape 안전 > 조합 정확성 으로 판단.

### (C) 그 외 GUI — TextEdit · Notes · 브라우저 · 그리고 **Codex 등**
- `toggleViaKeyboardShortcut()` = **Control+Space 합성**(조합버퍼 auto-commit + 메뉴바 갱신).
- `StateManager.startPollingForInputSourceChange`(`:107`): 20×2ms(≈40–80ms) 폴링으로 입력소스
  변경 검증 → 실패 시 **Control+Space 재시도** → 그래도 실패 시 **`toggleDirectly()`(TIS)로 폴백**.
- 100ms(일반) / 180ms(IME-sensitive) 커밋 윈도우로 replay 버퍼링(§4).
- **이 경로가 P9의 무대다.** (§5)

---

## 3. 경로별 "건드리면 터지는 것"

| 경로 | 절대 하지 말 것 | 이유 |
|---|---|---|
| VDI | F16 을 로컬에서 삼키기 | Horizon 이 못 받아 게스트 한/영 죽음 |
| 터미널 | 커밋창/버퍼 켜기 | SSH escape 화면 깨짐(P10) 재발 |
| GUI | Control+Space 를 TIS 로 **전면** 교체 | 조합 미commit·메뉴바 stale (v1.2.0 이전으로 회귀) |
| 공통 | `usleep(5_000)` 제거/축소 | Word 등 느린 IME 글자 드롭(P13/P14) 재발 |
| 공통 | 합성 이벤트 마커 누락 | 탭 재진입/재매핑 → 무한 루프·중복 입력 |

---

## 4. "100ms" 오해 — 지연(latency) 사실관계

- **100ms 는 고정 지연이 아니라 타임아웃 상한(ceiling)이다.** 커밋 윈도우는 **한/영 전환 직후에만**
  열리고, TIS 변경이 확정되면 즉시 flush 한다(`completeInputSourceCommitWindow`).
- **일반 타이핑(한/영 안 바꿀 때)은 지연 0** — 윈도우가 안 열림.
- 실제로 느끼는 바닥은 **20ms 최소 홀드**(`inputSourceCommitMinimumHoldNanos`)이지 100ms 가 아니다.
- 프로젝트 자체 측정(`docs/private/UX_HYPOTHESES`):
  - 일반 앱(TIS ≈15ms): **p50=20ms, p95=28ms, p99=34ms** / `minhold=0` 가정 시 p50=15ms
  - Word 등 IME앱(TIS ≈120ms): p50=120ms, p95=180ms (→ 180ms adaptive timeout 근거)
- **결론:** 빠른 타자를 위해 상한(100ms)을 깎는 건 대개 헛수고. 만질 값은 **20ms 최소 홀드**이고,
  그것도 ㅊ 누락과의 트레이드오프라 실측 후에.

---

## 5. P9 — 특정 앱 한/영 토글 간헐 실패 (원인 확정, 패치 대기)

**정의(`docs/private/…REGRESSION_REVIEW`):** "특정 앱에서 한/영 토글 간헐 실패, 재시작으로 일시
fix. 후보: **앱의 Ctrl+Space 소비** / HID remap drift / stale grant."

**2026-07-06 라이브 캡처로 재현·원인 확정:**
- 대상: **Codex**(`com.openai.codex`, Electron 계열 `SkyComputerUseClient`).
- 관측: 한/영 **17회 중 verification timeout 14회**, Control+Space 30발 발사, 매번 ~150ms 헛발질
  후 TIS 폴백으로 겨우 전환.
- 기제: **Codex가 합성 Ctrl+Space 를 자기 자동완성으로 소비** → 입력소스가 폴링 창 안에 안 바뀜
  → timeout → 재시도(또 소비됨) → 최후에 `toggleDirectly()` 폴백. 문서의 1순위 후보와 정확히 일치.
- 반증 완료: Cmd/Ctrl 스왑 충돌 아님(합성 이벤트는 WINK 마커로 탭 통과), SymbolicHotKey 60 은
  켜져 있음(즉 시스템 단축키 문제 아님, **앱이 가로채는** 문제).

**아직 남은 확정 테스트:** 동일 재현을 **TextEdit/Notes** 에서 → timeout ≈0 이면 "앱이 소비"가
최종 확정 (순한 텍스트필드는 정상).

**권장 패치 방향(트리거 코어 무변경):**
- Ctrl+Space 를 소비하는 Electron/IDE 류(Codex 등)를 **터미널처럼 TIS 직행 버킷으로 carve-out**.
  이런 앱은 어차피 Control+Space 가 안 먹으므로 조합-commit 이점도 없음 → TIS 직행이 옳다.
- 구현: `ContextManager.terminalApps` 확장 또는 별도 "직행 토글" 버킷 신설, 혹은 무빌드로
  `CustomTerminalApps` UserDefaults 에 `com.openai.codex` 추가.
- **`usleep`·버퍼 코어는 건드리지 않음** → P10/P13/P14 회귀 표면 0.

---

## 6. 진단 도구 함정 (Diagnostics Gotchas)

**⚠️ `scripts/filter-logs.sh --mode buffer "$LOG"` 는 버퍼/토글 이벤트를 절대 못 찾는다.**

- `winmackey.log`(= `LogService`) 에는 `[Terminal]`/`[VDI]` 컨텍스트 전환만 들어간다.
- `KeyInterceptor` · `StateManager` · `InputSourceManager` 의 진단 로그는 **os.log**
  (`subsystem: com.winmackey.app`)로 가고, 대부분 **`.info` 레벨이라 디스크에 영구 저장되지 않는다**
  (`log show` 로 사후 조회 시 0건).

**올바른 캡처 — 재현 중 라이브 스트림:**
```bash
log stream --level debug \
  --predicate 'subsystem == "com.winmackey.app"' \
  --style compact
```

**로그에서 경로 구분:**
| 신호 | 의미 |
|---|---|
| `Trigger key (F16) detected (VDI=true …)` | VDI 경로 |
| `switched directly for terminal context` | 터미널 경로(TIS 직행) |
| `Toggle: posted Control down + Space …` | GUI 경로(Control+Space) |
| `Toggle verification timeout; retrying` | **P9 징후** — Control+Space 안 먹힘 |
| `Replayed N buffered key events (win, reason)` | 커밋창 flush (reason: `input-source-changed` / `min-hold` / `timeout` / `vdi-relay-settle`) |

---

## 7. 변경 전 회귀 체크리스트 (필수)

토글 서브시스템을 건드렸다면, 커밋 전 아래 **6개 표면 전부** 수동 확인:

- [ ] **일반 GUI** (TextEdit/Notes): 한/영 후 즉시 타자 — 씹힘/이전키 없음
- [ ] **IME-sensitive** (Word/Pages): 빠른 타자 시 글자 드롭 없음 (P13)
- [ ] **터미널/SSH** (Ghostty + ssh 세션): ESC/Backspace 화면 안 깨짐 (P10)
- [ ] **Ctrl+Space 소비 앱** (Codex 등 Electron/IDE): 한/영 간헐 실패 없음 (P9)
- [ ] **VDI** (Horizon): F16→Right Alt 릴레이 유지, 게스트 한/영 정상
- [ ] **Remote Mac** (Screen Sharing): 로컬 토글이 원격에 문자로 forward

> 스모크: `scripts/run-tests.sh` (`tests/buffered_replay_smoke.swift` — 커밋창/adaptive timeout
> invariants). 통과해도 위 **수동 체크리스트는 대체 불가** — 실기기 IME 동작은 자동화 밖이다.

---

## 부록: 핵심 심볼 위치

| 항목 | 위치 |
|---|---|
| 토글 디스패처 | `WinMacKeyApp.swift:224-241` |
| 커밋 윈도우/버퍼 replay | `KeyInterceptor.swift` (`beginInputSourceCommitWindow`, `flushBufferedKeyEvents`) |
| 검증 폴링/재시도/TIS 폴백 | `StateManager.swift:107-150` |
| Control+Space 합성 / TIS 직행 | `InputSourceManager.swift` (`toggleViaKeyboardShortcut`, `toggleDirectly`) |
| 터미널/VDI/IME 화이트리스트 | `ContextManager.swift` |
| 오픈 로드맵 (P9 등) | `docs/tasks/OPEN_PROBLEMS_ROADMAP.md` |
