# WinMacKey UX/디자인 레퍼런스 리서치

> **목적**: WinMacKey의 온보딩 · 권한 요청 · Pro 유료 전환 · 메뉴/설정 전환 UI 기준을 세우기 위한 경쟁/참고 앱 레퍼런스 수집과 실행 플랜.
> **조사일**: 2026-05-30
> **조사 대상**: Raycast, Bartender, Karabiner-Elements, BetterTouchTool, Rectangle Pro, (보조) CleanShot X / AltTab / Shottr + Apple HIG / macOS TCC / freemium UX 베스트프랙티스
> **검증 원칙**: 출처 URL 명시. 확인 못한 항목은 본문에 `[미검증]`으로 표기. 통계는 vendor/UX 리포트 출처이므로 방향성 참고용.

---

## 0. 한눈에 보기 — WinMacKey가 가져갈 핵심 결론

| 흐름 | 가장 적합한 레퍼런스 | 핵심 차용 포인트 |
|---|---|---|
| 온보딩 | **Karabiner**(권한 다단계) + **Raycast**(핵심동작 체험) | 3~5스텝 진행률 체크리스트, 스킵 가능·재실행 가능, "읽지 말고 직접 해보게" |
| 권한 요청 | **Bartender**(무서운 권한 설득) + **Karabiner**(드라이버 재인증) + **Rectangle**(딥링크 happy path) | 프라이밍 1줄 why + "우리는 X 안 합니다" + 정확한 Settings 창 딥링크 + grant 폴링 + 재실행 안내 |
| Pro 유료 전환 | **Rectangle Pro**(자동전환=Pro 검증) + **Bartender**(원타임+무카드 체험) + **Raycast**(검색형 업셀) | 코어 무료·자동전환만 Pro 게이트, 잠긴 채로 보여주는 "Pro 뱃지", 무카드 체험, 맥락 시점 업셀 |
| 메뉴/설정 | **Raycast**(탭+맥락설정) + **Bartender**(개념당 탭+Advanced 버킷) | 소수 상위 탭, 고급옵션 격리, "마지막 탭 기억", 프로파일 export/import |

---

## 1. 온보딩 / 초기 설치

### Raycast — "핵심 동작을 직접 시켜라"
- 첫 실행 = **다중 슬라이드 환영 캐러셀** → 핫키 설정이 온보딩의 주역.
- 기본 핫키 `⌥Space`, 온보딩에 **"Replace Spotlight"** 원클릭 버튼 ("스팟라이트와 동시에 쓰지 않으니 ⌘Space를 넘겨받는 게 더 매끄럽다"는 논리로 설득).
- **Quickstart 5스텝 모델**: ① 다운로드+핫키 → ② 시스템 검색 → ③ 스니펫(직접 "Create Snippet" 입력) → ④ 익스텐션 스토어 → ⑤ AI 챗. 글로 읽히지 않고 **실제 1개 동작을 시켜서** 핵심 인터랙션을 학습시킴.
- **"Show Onboarding"** 커맨드로 언제든 재실행 가능 (원샷 아님).
- 기존 설정 import 지원 → 새 맥에서도 "익숙한 느낌".
- `[미검증]` 첫 실행 시 로그인 강제 여부.

### Bartender — "보여주고, 말하지 마라" (단, 리매퍼엔 부분만 적용)
- **공식 셋업 위저드 없음**. 첫 실행 시 Control Center/Siri 외 모든 메뉴바 아이콘을 **자동으로 숨겨** 즉시 "메뉴바가 깨끗해졌다"는 가시적 결과를 보여줌.
- drag-to-organize는 별도 오버레이가 아니라 **환경설정 창 안에서** (Shown/Hidden/Always Hidden 섹션 간 드래그) 가르침. macOS 네이티브 제스처(`⌘+drag`) 재활용.
- ⚠️ **WinMacKey 시사점**: Bartender는 결과가 즉시 눈에 보여 위저드가 불필요했지만, 리매퍼는 **눈에 보이는 결과가 없으므로 위저드가 오히려 더 정당**하다. Bartender 방식을 그대로 베끼면 안 됨.

### Karabiner — 가장 동질적인(=무서운 다단계) 온보딩
- Accessibility + Input Monitoring + **DriverKit 시스템 확장 승인**(재부팅 동반)까지 — WinMacKey와 똑같은 다층 권한 부담.
- 커뮤니티 룰 import를 **5스텝 UI**로 손잡고 안내: Add predefined rule → Import more rules from internet → 웹 Import + OS Allow → 앱 Import → Enable.
- 핵심 교훈: 무서운 다단계는 **각 단계를 명시적으로 손잡고**, 상태 검증을 붙여야 함.

### 베스트프랙티스 (Apple HIG + UX 데이터)
- HIG: "온보딩이 필요하면 빠르고·재미있고·**스킵 가능**하게. 스킵하면 다음 실행 때 다시 띄우지 말되 나중에 쉽게 찾게." 스플래시/약관으로 진입 지연 금지.
- 진행률 표시(체크리스트/스텝카운터/바)는 완료율 **~20–30%↑**.
- 플로우 길이 스윗스팟 **3–7스텝**(>20스텝은 완료율 30–50%↓). 설정 스텝에 **가치 행동을 섞어라**(권한 후 "지금 키 하나 바꿔보기").
- 자동 코치마크는 대부분 스킵·기억 안 됨 → **사용자가 누르면 뜨는** 온디맨드 가이드가 자동 투어보다 전환 **~123%↑**.

> **WinMacKey 온보딩 권장**: 스킵 가능·완료 후 재노출 없음·나중에 재실행 가능한 **3스텝 진행률 체크리스트** = ① Accessibility 부여 → ② Input Monitoring 부여 → ③ 재실행 + 완료. 마지막에 "지금 키 하나 리맵해보기" 가치 행동.

---

## 2. 권한 요청 UX (WinMacKey의 최우선 흐름)

### ⚠️ macOS TCC 기술 현실 (반드시 인지)
- **Accessibility / Input Monitoring / Screen Recording은 단순 Allow/Deny 다이얼로그가 없다.** 사용자가 System Settings → Privacy & Security에서 **직접 토글**해야 하고, **앱을 종료 후 재실행해야** 적용됨 ("Quit & Reopen").
- 따라서 표준 UX 4단계:
  1. **프라이밍 화면** (가치 먼저 설명)
  2. **정확한 Pane으로 딥링크** (사용자가 헤매지 않게 자동 오픈)
  3. **grant 폴링/검증** (`AXIsProcessTrusted()` / `IOHIDCheckAccess()` 주기 체크 → UI 자동 진행)
  4. **재실행 안내** (grant는 재실행 후 적용)
- WinMacKey는 **Accessibility + Input Monitoring 둘 다** 필요 → **2개의 분리된 게이트 스텝**, 각각 자체 딥링크·검증, 마지막에 공통 재실행.

**딥링크 URL 스킴** (Ventura+ / 구버전 fallback 병행 권장):
| Pane | URL (Ventura+) |
|---|---|
| Accessibility | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` |
| Input Monitoring | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent` |
| Screen Recording | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture` |

**검증 API**: Accessibility = `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt:true)`. Input Monitoring = `IOHIDCheckAccess()` / `IOHIDRequestAccess()` 또는 `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`.
> 함정(rdar://7381305): `AXIsProcessTrustedWithOptions(NULL)`를 먼저 호출하면 이후 `IOHIDRequestAccess()` 프롬프트가 안 뜰 수 있음 → **순서 주의, 두 권한 독립 처리.**

### Bartender — "무서운 권한 설득" 카피 공식 (최고의 레퍼런스)
공식 권한 페이지 verbatim:
- Screen Recording: *"Bartender reads your menu bar items so it can show the correct image for each item."*
- 신뢰 문장(핵심): *"The only area Bartender reads is the menu bar. Please be assured Bartender does not record your screen in any way."*
- Accessibility: *"Bartender needs Accessibility permissions to move your menu bar items…"*

**카피 공식 = [한 줄 무엇] + [한 줄 왜/이득] + [명시적 "우리는 그 무서운 짓 안 합니다"]**. 추가로 macOS가 보여줄 경고(보라색 녹화 인디케이터)를 **미리 설명**해 사용자가 놀라지 않게 함.
**재실행/복구**: Screen Recording은 부여 후 quit&relaunch 필요 명시. remove→relaunch→re-grant 복구 경로 + `tccutil reset Accessibility com.surteesstudios.Bartender` 폴백 제공.

### Karabiner — 드라이버 확장 재인증 지옥 (WinMacKey가 반드시 대비)
- 드라이버 확장 승인은 **가장 큰 온보딩 위험**. 부팅마다 재평가되어 grant 상태와 앱 상태가 분리됨 → "이미 켰는데도 매번 권한 요청 팝업" (issue #4299), "Allow 버튼이 아예 안 뜸" (#3294/#3941), Tahoe에서 Input Monitoring에 안 보임(#4376) 등.
- 흔한 근본원인: **서드파티 보안 SW가 드라이버 확장 로드 차단** (공식 문서화).
- 흔해서 **전용 도움말 페이지** "Driver alert keeps showing up"가 따로 존재.
- ✅ v16에서 **Input Monitoring을 Accessibility로 통합**해 무서운 grant 개수 축소 — WinMacKey도 가능하면 따라가야 함.

### Rectangle — 가장 깔끔한 happy path
- 권한 **딱 하나**(Accessibility)만, 첫 실행 시 prompt + **정확한 화면으로 바로 이동**. 드라이버/시스템확장 불필요 → "happy path" 레퍼런스.

### AltTab — 안티패턴 (반드시 피할 것)
- Screen Recording 누락 시 **조용히 아무것도 안 함**(단축키 눌러도 무반응), 권한 화면에서 beachball 행. → **절대 silent fail 금지**: 권한 누락 시 명시적·행동가능한 blocked 상태 화면 + 딥링크, 실행마다 grant 재확인(한 번 부여돼도 유지된다고 가정 X).

### 프라이밍 효과 (UX 데이터)
- 이유를 주면 grant 확률 ~12%↑, 잘 짠 pre-permission은 수락률 최대 **~81%↑**(방향성 참고).
- 토글형 권한(Accessibility/Input Monitoring)은 **네이티브 프롬프트 자체가 없으므로** 프라이밍이 더더욱 필수.
- 카피 예: ~~"Allow input monitoring"~~ → *"WinMacKey가 키를 시스템 전역에서 리맵하려면 키보드를 읽어야 합니다 — 키 입력을 저장하거나 전송하지 않습니다."*

---

## 3. Pro / 유료 전환

### 핵심 검증: "하드웨어 변화 시 자동 전환 = 정당한 Pro 차별점"
- **Rectangle Pro**가 *"Arrange an entire workspace… Activate when displays are connected or disconnected"* 를 Pro로 게이팅 → **WinMacKey Pro의 "키보드 연결 시 프로파일 자동 전환"과 직접적 동형**. 자동전환을 Pro로 잡는 건 교과서적으로 옳음.

### 가격/체험 모델 비교
| 앱 | 모델 | 가격 | 체험 |
|---|---|---|---|
| **Bartender 6** | 원타임(1 메이저) | $20 | **4주 풀기능, 무카드** |
| Bartender Pro | 구독 | $15/년 (위젯·클립보드 등) | — |
| Bartender Mega | 라이프타임 | $80 (영구 업그레이드) | — |
| **BetterTouchTool** | 원타임+업데이트창 | **$12**(2년 업데이트) / **$24** 라이프타임 | **45일 풀언락** |
| **Rectangle Pro** | 원타임, 구독X, IAP X | ~$9.99 `[3rd-party]` (3 Mac까지) | **10일** |
| **Raycast Pro** | 구독 | $8/mo(연납) ~ $10/mo | **14일 풀언락, 무카드** |

### 게이팅·업셀 배치 (베스트프랙티스 + 사례)
- **코어는 진짜 쓸모있게 무료로**, *사용자가 의존하게 된 뒤* 중요 기능을 게이트. WinMacKey = 코어 리맵 무료(일상 의존+입소문) / **Pro 자동 프로파일 전환** 게이트 → 교과서적 배치.
- **잠긴 채로 보여주기**: Pro 기능을 "Pro 뱃지" 달아 visible-but-locked → 숨기지 말고 욕구 유발 (Raycast의 60+ 모델 어필과 동일 결).
- **업셀은 맥락 시점에**: 잠긴 기능 클릭, 수동 프로파일 전환 반복, 10일+ 지속 사용 등 high-signal 순간. 활성화 전 업셀 금지.
- **검색형/비방해 업셀**: Raycast는 "Upgrade to Pro"를 루트 검색 커맨드로 노출(나그 모달 X).
- **무카드·풀언락 체험**(Bartender 4주 / Raycast 14일 / BTT 45일)이 강력. 원타임 라이선스 + "Pro 기능 미리보기 → 한 번 결제" 소프트 게이트가 궁합.
- **페이월 카피**: 가격보다 **가능성/이득 먼저**, 기능 나열 대신 구체적 이득 3–5개, 비교표 과하면 분석마비.

### ⚠️ Gumroad × App Store 충돌 (의사결정 필요)
- WinMacKey Pro 언락을 **Gumroad로 파는 것은 Mac App Store 밖(직접 다운로드/공증 빌드)에서만 허용**. App Store에 올리면 외부 페이월은 App Review §3.1.1 위반.
- → **Pro-unlock-via-Gumroad는 직접배포/공증 빌드 전용**으로 유지. (App Store 진출 시 별도 IAP 필요.)
- Gumroad는 브라우저로 넘어가므로 **브랜딩 일치 + "브라우저에서 결제 완료" 기대치 안내** 필수(매끄럽지 않은 핸드오프는 전환 저하).

### 라이선스 입력 UX
- BTT 모델: 구매 메일의 **활성화 링크/라이선스 파일 더블클릭 → 자동 활성화**(수동 키 붙여넣기보다 우월). 멀티맥 단일 라이선스(Rectangle Pro=3대) 지원 고려.
- `[미검증]` Bartender 라이선스 입력 필드/"trial expired→Buy Now" 모달 정확 카피.

---

## 4. 메뉴 / 설정 전환

### Raycast — 탭 + "설정은 대상 옆에"
- `⌘,`로 오픈. **상단 탭 바**: Account / General / Launcher / AI / Shortcuts / Keyboard / Extensions / Applications / (Teams)Organizations / Advanced / About.
- 핵심 교훈 = **설정을 그 대상 옆에서**: 모놀리식 설정창 강제 대신, 커맨드 선택 → Action Panel(`⌘K`) → Configure / Set Hotkey(`⌘⇧,`). 큰 목록은 **카테고리로 그룹화**. **전체 설정 export/import** 제공(멀티맥 마이그레이션).

### Bartender — 개념당 탭 + Advanced 버킷
- **탭 기반, "마지막 연 탭으로 오픈"**(반복 편집 편의 — 저비용 폴리시).
- 개념당 1탭(Items / Hotkeys / Triggers / Appearance / Advanced), **파워 옵션은 Advanced에 격리**해 기본 화면 단순 유지.
- **per-item 액션 선택자**: 항목별 left/right/Option+click → 액션 → WinMacKey 키/프로파일 할당 UI에 깔끔한 패턴.
- **Triggers**(앱/배터리/위치/WiFi/시간/스크립트 조건으로 프리셋 자동 적용) + **Presets/Profiles** 탭 → 자동전환 UX 직접 참고.

### Karabiner — 프로파일 + EventViewer
- **"Manage profiles"**로 복수 명명된 설정셋 (WinMacKey Pro 자동전환과 직결).
- **EventViewer**: 실시간 키 이벤트, PC/국제 키 정확한 이름, 프런트앱 bundle id 표시 → 앱 스코프 룰 작성용.
- 2-tier 룰: Simple Modifications(1키→1키) / Complex(조건·앱별·모디파이어 조합).

> **WinMacKey 설정 권장**: 소수 상위 탭(예: 키매핑 / 프로파일 / 단축키 / 권한·상태 / 고급) + 고급옵션 Advanced 격리 + "마지막 탭 기억" + **프로파일 export/import** + EventViewer류 라이브 키/bundle-id 인스펙터.

---

## 5. 신뢰(Trust) 케이스 스터디 — Bartender 2024 소유권 논란

권한 과다 앱(특히 Accessibility 보유)이 절대 피해야 할 실패 사례. WinMacKey에 직접 교훈.
- 원개발자 Ben Surtees가 **"Applause"에 매각**(2024-05 종료)했으나 **유저 공지 없이** 새 빌드 출시.
- MacUpdater가 **코드서명 인증서 변경**(Surtees Studios → App Sub 1 LLC) 감지로 발각 + **v5.0.52에 Amplitude 분석(위치 포함) 무단 추가**.
- 공식 사과(verbatim): *"We completed our transition with Ben at the end of May and should have made an announcement prior to our first release…"*, *"Amplitude has served its purpose and has been removed in version 5.0.53 onward."*
- ✅ **교훈**: 소유권·코드서명 ID·텔레메트리 변경은 **첫 빌드 출시 전에 릴리스 노트로 반드시 공지**. 서명 ID 노출 + "수집 데이터/판매 안 함" 명시가 권한 과다 유틸의 기본값.

---

## 6. WinMacKey 실행 플랜 (디자인 기준 수립)

### Phase 1 — 디자인 토큰/기준 정의
- [ ] 공통 컴포넌트 정의: **프라이밍 카드**(아이콘 + 한 줄 무엇 + 왜/이득 + "안 합니다" 문장 + 1차 CTA "System Settings 열기")
- [ ] **권한 상태 칩**(미부여 / 부여됨·재실행필요 / 활성) — Karabiner의 `[activated enabled]`처럼 *활성 상태*를 grant 상태와 구분
- [ ] **Pro 뱃지** 스타일(잠긴 기능 visible-but-locked) 정의
- [ ] 설정창 탭 IA 확정(키매핑 / 프로파일 / 단축키 / 권한·상태 / 고급)

### Phase 2 — 온보딩 흐름 구현
- [ ] 3스텝 진행률 체크리스트(스킵 가능, 완료 후 재노출 X, "?"로 재실행)
- [ ] Step1 Accessibility / Step2 Input Monitoring: 각 프라이밍 → 딥링크 → **1초 폴링 자동 진행**
- [ ] Step3 재실행 유도(Quit & Reopen) — grant는 재실행 후 적용
- [ ] 완료 직후 가치 행동: "지금 키 하나 리맵해보기"

### Phase 3 — 권한 견고성 (Karabiner 교훈)
- [ ] grant 됐지만 비활성/드라이버 미로드 상태 감지 + **재인증/리셋 경로**
- [ ] 서드파티 보안 SW 충돌 / "Allow 안 뜸" 케이스 도움말 페이지
- [ ] `tccutil reset` 폴백 안내, 실행마다 grant 재확인(절대 silent fail 금지)
- [ ] 가능하면 Input Monitoring을 Accessibility로 통합(grant 개수 축소) 검토

### Phase 4 — Pro 전환 흐름
- [ ] 자동 프로파일 전환을 Pro 뱃지로 visible-but-locked 노출
- [ ] 맥락 업셀: 수동 전환 N회 반복 / 잠긴 기능 클릭 / 10일+ 사용 시점
- [ ] 페이월: 이득 3–5개 benefit-led, Gumroad **브라우저 핸드오프 기대치 안내 + 브랜딩 일치**
- [ ] 라이선스 파일/링크 자동 활성화(수동 키 붙여넣기 지양), 멀티맥 정책 결정
- [ ] Pro-unlock-via-Gumroad는 **직접배포/공증 빌드 전용** 명문화 (App Store 분리)

### Phase 5 — 설정/메뉴 폴리시 + 신뢰
- [ ] "마지막 탭 기억", 고급옵션 Advanced 격리
- [ ] 프로파일 export/import, EventViewer류 라이브 키/bundle-id 인스펙터
- [ ] About에 서명 ID + "키 입력 저장·전송 안 함 / 데이터 판매 안 함" 명시(Bartender 논란 교훈)

---

## 7. 핸즈온 확인 필요 항목 (`[미검증]` 모음)
- Raycast 환영 슬라이드 카피·버튼 라벨, 로그인 강제 여부, 권한 다이얼로그 버튼 문구.
- Bartender 인앱 권한 프롬프트에 **원클릭 딥링크 버튼** 존재 여부, 라이선스 입력 필드/"trial expired→Buy Now" 모달 카피.
- BTT "2년 후에도 앱은 동작, 업데이트만 중단" (모델상 강한 추정, 직접 인용 미확보).
- Rectangle Pro $9.99 — 3rd-party 출처(공식 Pro 페이지엔 "Free for 10 days"만 노출).
- Apple HIG verbatim 인용은 검색 스니펫 기반 → 라이브 페이지에서 정확 문구 재확인. 전환 통계는 vendor 리포트(방향성 참고).

---

## 8. 출처 (Source URLs)

**Raycast**: manual.raycast.com/{quickstart,settings,command-aliases-and-hotkeys,window-management,script-commands,billing} · raycast.com/{pricing,pro} · developers.raycast.com/information/security · pageflows.com/post/desktop-web/onboarding/raycast/

**Bartender**: macbartender.com/Bartender5/{PermissionInfo,PermissionIssues,purchase.html} · macbartender.com/Bartender6/{support,purchase.html} · macbartender.com/b5blog/Lets-Try-This-Again/ · macrumors.com/2024/06/04/bartender-mac-app-new-owner/ · macrumors.com/2026/05/12/bartender-pro/ · tidbits.com/2024/06/05/ · 9to5mac.com/2024/06/04/ · brettterpstra.com/2026/05/13/bartender-pro-review/ · thesweetbits.com/tools/bartender-review/ · podfeet.com/blog/2023/11/bartender-5/

**Karabiner**: karabiner-elements.pqrs.org/docs/manual/misc/required-macos-settings/ · …/docs/help/troubleshooting/driver-alert-keeps-showing-up/ · …/docs/manual/configuration/configure-complex-modifications/ · github.com/pqrs-org/Karabiner-Elements/issues/{4299,3294,3941,4376} · github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice

**BetterTouchTool**: folivora.ai/buy · docs.folivora.ai/docs/getting-started/installation/ · community.folivora.ai/t/{licence-pricing-for-2-years,license-upgrade-from-standard-to-lifetime}

**Rectangle**: rectangleapp.com/ · rectangleapp.com/pro/ · mactools.pro/blog/{rectangle-pro-is-it-worth-it,rectangle-for-mac-download-setup-best-shortcuts}

**AltTab / Screen Recording**: github.com/lwouis/alt-tab-macos/issues/{3819,4209} · lazyscreenshots.com/blog/mac-screenshot-screen-recording-permission/

**Apple / TCC / Freemium / Onboarding**: developer.apple.com/design/human-interface-guidelines/{privacy,patterns/accessing-private-data,onboarding,patterns/launching,settings} · developer.apple.com/videos/play/tech-talks/110152/ · developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions · developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess() · gist.github.com/rmcdongit/f66ff91e0dad78d4d6346a75ded4b751 · jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html · nngroup.com/articles/permission-requests/ · appcues.com/blog/mobile-permission-priming · revenuecat.com/blog/growth/hard-paywall-vs-soft-paywall/ · superwall.com/blog/{3-proven-paywall…,4-lessons-learned…} · nngroup.com/articles/onboarding-tutorials/ · productfruits.com/blog/onboarding-checklist-examples
