# WinMacKey 비주얼 디자인 컨셉 플랜

> **목적**: 설치 직후 사용자가 실제로 보게 되는 화면(온보딩 위저드 · 권한 프라이밍 · Pro 페이월 · 설정창)의 **시각 디자인 기준**을 세운다.
> **방법**: 경쟁/참고 앱의 실제 UI 이미지를 수집 → **Gemini 멀티모달 LLM과 협업**해 시각 디자인 언어를 추출/비교 → WinMacKey 디자인 시스템으로 합성.
> **작성일**: 2026-05-30 · **짝 문서**: [`UX-Reference-Research.md`](./UX-Reference-Research.md) (텍스트/플로우 리서치)
> **수집 이미지**: [`references/`](./references/) (32장)

---

## ✅ 도입 확정 (Adoption Decision) — 2026-05-31

**이 문서의 디자인 기준을 실제 WinMacKey 앱(`~/worksapces/mac-windows-like-key`, SwiftUI)에 정식 적용/업데이트한다.** 참고용 레퍼런스로 끝내지 않는다.

- **상태**: 승인됨 (Approved for implementation). 레퍼런스 수집·목업(Phase A~B) → **앱 반영(Phase C)** 진행.
- **적용 범위**: 온보딩 위저드 · 권한 요청/상태 UX · Pro 페이월 · 설정창(5탭) · 앱 아이콘(후보 A) · 브랜드 컬러 토큰(시스템 블루=조작 / 브랜드 민트·틸=그래픽) · 외관(Free=시스템 외관 자동 추종 / Pro=커스텀 테마·액센트·라이트/다크 강제).
- **구현 방식**: 본 문서와 `mockups/winmackey-mockup.html`는 **시각 청사진**이며, 실제 구현은 `WinMacKeyApp.swift` 기반 **SwiftUI/AppKit 네이티브 뷰**로 이식한다(HTML 자체는 앱에 포함되지 않음).
- **연동 갱신 대상**: `docs/FEATURE_SPEC.md`, `docs/private/PRO_TIER_GATING_PLAN.md`(Pro 경계: 자동전환 → **자동전환 + 커스텀 테마/액센트/외관 강제**), `scripts/release.sh`(DMG 배경/레이아웃).
- **외관 게이팅 = (b) 확정(2026-06-01)**: Free는 시스템 라이트/다크 자동 추종(메뉴바 팝오버·아이콘·설정창 모두 — "안 따라온다" 위화감 0). Pro = 커스텀 테마·액센트 컬러·라이트/다크 수동 강제(override). Raycast 모델과 동일. 이유: 메뉴바 앱 특성상 팝오버는 시스템 추종이 기본 정합성이라 다크 자체를 잠그면 깨져 보임 + 원타임 제품 평판 리스크 회피.
- **스텝 구분 방식 = 확정(2026-06-01)**: 권한 STEP1/2 구분은 **① 큰 텍스트 라벨("STEP 2 · 두 번째 권한 · 다른 화면") + ② 서로 다른 일러스트 콘텐츠(접근성=사람 / 입력모니터링=키보드) + ③ "⚠︎ STEP 1과 다른 화면이에요" 경고 콜아웃**으로 한다. **의미색(블루=시스템/그린=브랜드)을 스텝 테마색으로 쓰지 않는다**(오인 방지·규칙 일관). 하이라이트 링은 양 스텝 동일한 중립 attention 스타일.
- **온보딩 구성 = 확정(2026-06-01)**: **환영(intro, 번호 없음) + 3개 번호 스텝(① 손쉬운 사용 ② 입력 모니터링 ③ 완료·재실행)**. 재실행은 grant 적용에 필수라 정식 스텝으로 둠. → 모든 세부결정 종결.

---

## 0. 협업 방식 (멀티모달 파이프라인)

```
[1] Playwright/curl 로 실제 UI 이미지 자산 수집  →  docs/design/references/
[2] gemini -y -p "@img1.png @img2.png ..."  로 이미지 멀티모달 분석
[3] 흐름별 시각 디자인 언어 추출 + 앱 간 비교  (Gemini)
[4] Claude 가 WinMacKey 디자인 시스템으로 합성 (이 문서)
```

- Gemini CLI 0.42.0, 이미지 직접 입력(`@path.png`)으로 3회 분석 수행:
  1. **Raycast Pro 페이월** 1장 → 페이월 시각 패턴
  2. **Karabiner + Bartender 설정창 UI** 6장 → 네이티브 유틸 설정창 공통 패턴 + WinMacKey 권장
  3. **macOS 실제 권한 화면** 4장 → 온보딩 미러링 비주얼 가이드 + 함정

---

## 1. 수집한 레퍼런스 이미지 인벤토리

| 폴더 | 파일 | 무엇을 보여주나 | 용도 |
|---|---|---|---|
| `raycast/` | `raycast-pro.png` | Pro 페이월 풀페이지 | 페이월/업셀 시각 |
| `bartender/` | `Triggers2.png` | 조건부 자동 적용 설정 모달 | **Pro 자동전환 UI 직결** |
| `bartender/` | `Presets.png` | 프리셋(프로파일) 리스트 | 프로파일 탭 |
| `bartender/` | `QuickSearchBack.png` | 키보드 기반 빠른 검색 | 명령/검색 패턴 |
| `bartender/` | `StylingFull.jpg`, `menubarstyle.jpg`, `MenuBarItemSpacing.png`, `Widgets.png`, `BartenderBar.png` | 외형/스타일 설정 | 컬러·여백 감각 |
| `bartender/` | `screen-capture-menubar.png` | 권한 설명용 일러스트 | 권한 프라이밍 |
| `karabiner/` | `settings-accessibility.png` | **실제 Accessibility 권한 화면** | 온보딩 미러링 |
| `karabiner/` | `settings-input-monitoring.png` | **실제 Input Monitoring 화면** | 온보딩 미러링 |
| `karabiner/` | `settings-driver-extensions.png` | **Login Items & Extensions** | 온보딩 미러링 |
| `karabiner/` | `system-extensions.png` | 확장 활성 상태 로그 창 | 상태 검증 |
| `karabiner/` | `settings-services.png` | Background/Services 항목 | 참고 |
| `karabiner/` | `complex-mod-1~6.png` | **KE 설정창/룰 import 6단계 UI** | 설정창 골격 |
| `cleanshot/` | `cs-2,4,5,7,9.jpg` | CleanShot X 설정/온보딩 화면(UX 분해 글 발췌) | "설정=온보딩" 패턴, 키캡 단축키 UI |
| `ice/` | `ice-1~6.png` | Ice(무료 오픈소스 메뉴바 앱) 설정/기능 UI | **무료 티어 절제된 네이티브 UI** |

> ⚠️ 저작권: 디자인 학습용 사적 레퍼런스. 산출물에 원본 UI를 재배포·복제하지 말 것(패턴만 차용).
> 📌 확장 라운드(2026-05-31): CleanShot X·Ice 추가 수집·분석. AltTab은 사이트가 JS 렌더 SPA라 자산 추출 불가 → 제외.

---

## 2. Gemini 분석 — 앱별 시각 디자인 언어 (요약)

### 2-1. Raycast Pro 페이월 (다크 프리미엄)
- **컬러**: 풀 블랙 `#000000` ~ 딥그레이 `#121212~#1A1A1A` 다크모드 전용. 텍스트 화이트 `#FFFFFF` / 보조 그레이 `#888~#A0A0A0`. 포인트 = 제품샷 뒤 **네온 글로우 그라데이션**.
- **타이포**: 모던 산세리프(시스템/Inter 추정). 헤드라인 크고 볼드, **가격 숫자 극단적으로 크게**.
- **CTA**: **알약형(pill) 버튼**. Primary=화이트배경+블랙텍스트, Secondary=투명+얇은 흰 테두리. 섹션 하단·헤더 우측·카드 하단에 일관 배치.
- **기능 노출**: 히어로 제품샷 + 후광, **Bento 2×2 카드 그리드**(추상 기하 그래픽+텍스트), 캡슐 뱃지로 키워드 강조.
- **페이월 레이아웃**: 상단 Monthly/Yearly 토글(할인 뱃지) → 동일 너비 3단 세로 카드(Free/Pro/Pro+) → 팀/기업은 가로형 카드로 분리. `[플랜명]→[가격]→[혜택 체크리스트]→[CTA]` 하향식.

### 2-2. 네이티브 유틸 설정창 공통 패턴 (Karabiner + Bartender)
- **레이아웃**: **좌측 반투명(Vibrancy) 사이드바 + 우측 메인 콘텐츠**. 상세 추가/편집은 **시트(Sheet)/플로팅 모달**로 분리해 메인 복잡도 ↓.
- **리스트**: Karabiner = 풀너비 리스트(얇은 구분선, 좌 드래그핸들·우 액션). Bartender = **인셋 그룹 리스트(둥근 카드)**. 공통 행 구조 = `[좌: 아이콘/타이틀/설명] | [우: 토글/설정버튼]`.
- **컬러/여백/Radius**: SF 시스템 폰트·시스템 여백. 활성/선택/완료 = **macOS 시스템 블루(Accent)**, 파괴적 액션 = 빨강. 배경 Vibrancy. **카드/모달 radius ≈ 10–12px**, 내부 컨트롤은 더 작게.
- **컨트롤**: macOS 기본 Switch 토글, 둥근 회색 Pop-up 드롭다운, `+` = 알약/둥근 사각 뱃지(아이콘+텍스트), Done = 파란 버튼.

### 2-3. 실제 권한 화면 + 온보딩 미러링 (Gemini 비주얼 가이드)
| 권한 | 사용자가 할 단 하나 | 함정 | 인앱 미러링 비주얼 |
|---|---|---|---|
| **Accessibility** | 앱 우측 토글 ON(파랑) | 목록 길어 스크롤 必, 토글 시 **Touch ID/암호 요구**에 당황 | 'Accessibility' 글자+해당 1줄만 남긴 미니UI, 토글에 **펄스 빨간 원** |
| **Input Monitoring** | 앱 우측 토글 ON | **접근성 화면과 똑같이 생김** → "아까 켰는데?" 착각·스킵 위험 ★ | 상단 'Input Monitoring'에 **형광펜 하이라이트** + "두 번째 권한" 말풍선 + 화살표 |
| **Driver/Login Items & Extensions** | 하단 Extensions의 `(i)` 클릭 → 토글 | **General 안에 깊이 숨음**, 한참 스크롤해야 등장 | `General > Login Items & Extensions` **빵부스러기** + 👇 스크롤 아이콘 + `(i)` **줌인 컷** |
| **System Extension 활성 확인** | 로그 맨 아래 `[activated enabled]` 확인 | 영어 터미널풍 화면에 **심리 장벽** | 나머지 로그 **블러** 처리, `[activated enabled]`만 스포트라이트 + **녹색 ✅** |

> **핵심 인사이트(Gemini)**: 접근성·입력모니터링 화면이 시각적으로 동일 → 두 스텝을 **색/라벨/번호로 명확히 구분**하지 않으면 사용자가 2번째를 오류로 오인해 이탈한다.

### 2-4. 확장 레퍼런스 — CleanShot X & Ice (2026-05-31)
**CleanShot X — "설정 화면 자체가 온보딩"**
- 별도 위저드 대신 **설정창을 온보딩으로** 활용(상단 탭 액센트 하이라이트 = 스텝 인디케이터 변형 가능).
- **키캡(Keycap) 모양 단축키 칩**: `⌘ C`처럼 실제 키 모양으로, 클릭 시 *"Record shortcut"* 입력대기 상태로 전환 → WinMacKey 키매핑 UI에 직접 차용.
- **Before/After 비교 그래픽**(예: `With wallpaper` vs `Transparent`)으로 텍스트 대신 결과를 보여줌 → Win/Mac 키 배열 차이 시각화에 응용.
- **팁의 인라인 통합**: 항목 바로 아래 회색 소형 텍스트로 단축키 팁(예: *"Hold ⇧ Shift while taking a screenshot…"*) → 별도 도움말 불필요.
- **하단 고정 `Restore Defaults`**: 리맵이 꼬여도 되돌릴 수 있다는 **심리적 안전망** 항상 노출.

**Ice — 무료/오픈소스의 절제된 네이티브 UI (무료 티어 모델)**
- **macOS System Settings 그대로**: 둥근 인셋 그룹 리스트 + 좌측 사이드바(최상단 앱 이름 크게) → 커스텀 테마 배제, "OS의 일부" 같은 신뢰감.
- **설명 텍스트 계층화**: 항목명 아래 연회색 부연(예: *"Show hidden menu bar items in a separate bar…"*) → 툴팁 없이 기능 파악.
- **시각적 메타포 드롭존**: 텍스트 설명 대신 가로 긴 영역 박스에 드래그 배치 → 키매핑 구성 UI에 응용.
- 시사점: **무료 티어는 화려함 빼고 네이티브 절제**로, Pro 페이월(§2-1 다크 프리미엄)과 무드를 의도적으로 대비.

### 2-5. 자체 제작 에셋 = WinMacKey 브랜드 베이스라인 ★ (`design_asset_handoff_2026-05-30/`)
팀이 직접 만든 핸드오프 에셋. **이것이 이 문서의 generic 토큰보다 우선하는 실제 브랜드 기준**이다.
- **브랜드 시각언어**: 오프화이트(웜) 키캡 + 그래파이트 베이스 + **민트/틸 그린 릴레이 액센트(추정 `#359B8B~#42B8A3`)**. 스큐어모픽 3D 키캡. 모티프 = `⌘` · `한⇄A` 스왑 화살표 · 방패(권한/안전) · 데이터 흐름 입자 · 측면 네온 상태광.
- **제품 본질(노트 확정)**: 아이콘 의미는 "**Right Command = 한/영 전환 키**". F16/릴레이는 setup·VDI·매뉴얼 보조 메시지에만. "Win+Mac 연결" 메시지는 지양.
- **에셋 목록 & 용도**:
  | 파일 | 용도 | 상태/주의 |
  |---|---|---|
  | `01_icon_candidate_a` (⌘+한⇄A 키캡) | **권장 앱 아이콘 베이스** | 출시 전 정확 벡터 심볼로 1024px 재제작, 소형(16/32px) 가독성 QA |
  | `02_icon_candidate_b` (F16 릴레이) | 기술/릴레이 설명용 | F16을 1차 브랜드로 쓰지 말 것 |
  | `03_cleaning_mode_pro` (방패+키보드) | Pro/Power Tools 카드 | 기능 **planned/미구현** — 출시기능처럼 표기 금지 |
  | `04_installer_dmg_background` (⌘→Applications) | DMG 드래그 설치 배경 | App Store풍 폴더 마크 교체 + release.sh Finder 레이아웃 작업 필요 |
  | `05_permission_onboarding` (토글2개+키보드→방패→⌘→한/A) | 권한 온보딩 일러스트 | **가짜 시스템UI로 쓰지 말 것**, 실제 단계는 실 스크린샷 |
  | `06_vdi_relay_manual` (Mac→F16→VDI Alt) | VDI 매뉴얼 다이어그램 | 텍스트 과다·생성 UI → 레이아웃 참고만, 벡터 재작도 |
  | `prepared/AppIcon_candidate_A/B.appiconset` | Xcode 비교 투입용 | 비교용, 소형 QA 전 배포 금지 |

- **★ 컬러 분배 규칙(Gemini 교차검증 결론)**: 브랜드 민트/틸은 macOS "On/성공" 색과 동계라 네이티브 무드와 **충돌하지 않음**. 단 **조작 가능성 기준으로 엄격 분리**:
  - **시스템 블루(또는 사용자 Accent)** → 실제 조작 컨트롤(토글·체크박스·드롭다운·포커스 링·선택 배경). "클릭하면 바뀌는 요소"는 전부 시스템 색.
  - **브랜드 민트/틸** → 앱 아이콘·온보딩 일러스트·Empty State·**읽기전용 상태 인디케이터**(권한 활성 점/성공 토스트)·**Pro 뱃지/페이월 강조**. = 관상용·정보전달 그래픽에만 국한.
- **일러스트(05) 실사용 주의**: ① 진짜 시스템 창 오인 방지 → 옅은 박스/드롭섀도우로 "그림"임을 명시 + 실제 스케일보다 작게. ② 일러스트 옆/아래 **진짜 동작 버튼**(`[시스템 설정 열기]`)을 분리 배치해 클릭 유도. ③ **다크모드 전용 일러스트 별도 제작**(현재 라이트 최적화, 다크에서 흰 패널이 튐).

---

## 3. WinMacKey 디자인 시스템 제안 (합성)

### 3-1. 컬러 토큰 (라이트 우선 + 다크 대응, 시스템 Accent 존중)
| 토큰 | 라이트 | 다크 | 용도 |
|---|---|---|---|
| `bg/window` | 시스템 윈도우 배경(Vibrancy) | 〃 | 창 배경 |
| `bg/sidebar` | 반투명 사이드바 | 〃 | 좌측 내비 |
| `bg/card` | `#FFFFFF` / 살짝 회색 | `#1C1C1E` | 인셋 그룹 카드 |
| `accent` | **시스템 블루(사용자 Accent 따름)** | 〃 | **조작 컨트롤 전용**: 토글·체크박스·드롭다운·포커스·선택·Primary CTA |
| `brand/relay` | **민트/틸 `#359B8B~#42B8A3`** | 〃 | **브랜드 전용(비조작)**: 아이콘·일러스트·Empty State·읽기전용 상태점·성공 토스트·Pro 뱃지 |
| `success` | `#34C759` | 〃 | 권한 활성(또는 brand/relay로 대체 가능) |
| `warning` | `#FF9F0A` | 〃 | 권한 필요(주의) |
| `danger` | `#FF3B30` | 〃 | 미부여·삭제 |
| `text/primary` `text/secondary` | 시스템 라벨 색 | 〃 | 본문/보조 |

- **외관 = (b) 확정(2026-06-01)**: **Free = 시스템 라이트/다크 자동 추종**(전 화면). **Pro = 커스텀 테마 · 액센트 컬러 · 라이트/다크 수동 강제(override)**. 다크 그 자체는 Free에서도 시스템 따라 나옴 → 깨져 보일 일 없음.
- ∴ 라이트·다크 **양쪽 토큰을 처음부터 다 정의**(위 표). 메뉴바 팝오버·아이콘·설정창 전부 양 모드 대응 필수.
- **페이월 다크 프리미엄 무드 = "Pro 프리미엄 테마"의 미리보기**(라이트 Free 기본과 의도적 대비 — #3 해소). ※ "다크=Pro"가 아니라 "프리미엄 테마=Pro"로 리프레이밍됨.

### 3-2. 타이포 / 간격 / 모양
- **폰트**: SF Pro(시스템). 위계 = LargeTitle(온보딩 헤드라인) / Title3(섹션) / Body(본문) / Footnote·Secondary(설명).
- **간격**: macOS 표준 8pt 그리드. 카드 내부 패딩 12–16, 행 높이 ≥ 44.
- **Radius**: 창/모달/카드 **10–12px**, 버튼/필드 6–8px, 토글은 시스템 기본.
- **재질**: 사이드바·배경 Vibrancy 적극 사용 → "맥다운" 인상.

### 3-3. 컴포넌트 라이브러리 (정의해야 할 것)
- `PrimingCard` — 아이콘 + [한 줄 무엇] + [왜/이득] + **["저장·전송 안 함" 안심 문장]** + Primary CTA("시스템 설정 열기")
- `PermissionStatusChip` — 미부여(danger)/부여됨·재실행필요(warning)/활성(success) **3-상태**. (grant ≠ active 구분 — Karabiner 교훈)
- `MiniSystemSettingsIllustration` — 실제 권한 화면을 단순화한 미니 일러스트 + 펄스/하이라이트/줌인/스포트라이트 콜아웃 (§2-3 매핑대로)
- `InsetGroupList` / `MappingRow` — `[드래그핸들][Win키아이콘 → Mac키아이콘][설명] | [토글][수정][삭제]`
- `ProBadge` — 잠긴 기능에 붙는 캡슐 뱃지(visible-but-locked)
- `ShortcutRecorderField` / `KeycapChip` — 우측 정렬 단축키 입력 박스 + **키캡 모양 칩**(`⌘ C`), 클릭 시 "Record shortcut" 입력대기 (CleanShot 차용)
- `BeforeAfterCompare` — Win/Mac 키 배열 차이를 두 일러스트로 비교 (CleanShot 차용)
- `PlanCard` — 페이월 3단 카드 (`플랜명→가격(대형)→혜택→pill CTA`)
- `FieldCaption` — 항목명 아래 연회색 부연 설명(인라인 팁) — 툴팁 대체 (Ice/CleanShot 공통 컨벤션)

---

## 4. 화면별 비주얼 컨셉 (설치 직후 순서대로)

### ① 온보딩 위저드 (환영 + 3 번호 스텝, 진행률 바, 스킵·재실행 가능)
- 좌측 스텝 인디케이터(환영 ✓ · 1 · 2 · 3) + 우측 `PrimingCard`. HIG: 빠르고·스킵 가능·재노출 금지.
- **미러링 방식 = 옵션 A 채택(2026-05-31)**: 권한 스텝 메인 비주얼은 **팀 자체 일러스트(에셋 05 계열, brand 민트/틸)**, 실제 macOS 스크린샷은 **작은 썸네일/"실제 화면 보기"**로만 보조. 이유 = 실 스크린샷에 좌표 박은 하이라이트는 macOS 버전마다 어긋남(목업 STEP2에서 확인). "그림"임 명시(옅은 박스+섀도우, 스케일 다운) + 실제 동작 버튼 분리. 앱 아이덴티티 = 아이콘 A(`⌘`+`한⇄A`).
- **온보딩도 시스템 외관 추종**((b) 확정 영향): Free 사용자도 시스템이 다크면 온보딩이 다크로 뜸 → **권한 일러스트(05) 다크 변형 필요**(라이트만 만들면 다크 맥에서 흰 패널이 튐).
- **Step 1 — Accessibility**: `MiniSystemSettingsIllustration`(펄스 강조). "Touch ID/암호를 물어볼 수 있어요(정상)" 미리 안내.
- **Step 2 — Input Monitoring**: 구분 방식 확정대로 **"STEP 2 · 두 번째 권한 · 다른 화면" 큰 라벨 + 다른 일러스트 콘텐츠(키보드) + "⚠︎ STEP 1과 다른 화면이에요" 경고 콜아웃**(착각·이탈 방지 ★). 의미색을 스텝 테마색으로 쓰지 않음.
- **Step 3 — 완료·재실행**: grant 적용 위해 "Quit & Reopen" Primary 버튼 + `[activated enabled]`류 상태 확인(녹색 ✅). 완료 직후 "지금 오른쪽 ⌘ 눌러보기" 가치 행동 인라인 데모.

### ② 권한·상태 탭 (상시)
- 각 권한을 `PermissionStatusChip`로 한눈에. 미부여/주의 시 `[시스템 설정 열기]` 딥링크 버튼(정확한 Pane URL — UX 문서 §2 참조).
- 실행마다 grant 재확인. **silent fail 금지**: 누락 시 명시적 blocked 카드.
- 하단에 재인증/리셋(`tccutil`) 도움말 링크 + 서드파티 보안SW 충돌 안내.

### ③ Pro 페이월
- **Pro 기능 = ① 키보드 연결 시 프로필 자동 전환 + ② 커스텀 테마·액센트 컬러·라이트/다크 수동 강제**(2026-06-01 (b) 확정). 평소 둘 다 `ProBadge` 달고 visible-but-locked. (다크 자체는 Free서도 시스템 추종 — 잠그는 건 "커스텀/강제"만.)
- 트리거: 수동 프로파일 전환 N회 / 잠긴 자동전환 클릭 / **설정에서 커스텀 테마·외관 강제 시도** / 10일+ 사용. 나그 모달 ❌, 맥락 시점 ✅.
- 레이아웃: Raycast식 — 이득 3–5개 benefit-led, `PlanCard`(가격 대형), pill CTA. **Gumroad 브라우저 핸드오프 기대치 안내 + 브랜딩 일치**.
- **페이월 다크 프리미엄 = "Pro 프리미엄 테마 미리보기"** 역할(라이트 Free 기본과 의도적 대비, #3 해소).

### ④ 설정창 (5탭, 좌 사이드바 + 우 메인)
| 탭 | 골격 | 핵심 컴포넌트 |
|---|---|---|
| **키매핑** | 인셋 그룹 카드 리스트 + 상단 파란 `[+ 새 키매핑]` → 시트 모달. **하단 고정 `Restore Defaults`**(안전망, CleanShot 차용) | `MappingRow`(Win→Mac `KeycapChip`), 삭제는 빨강 |
| **프로파일** | Bartender Presets식 큼직한 리스트 | `[아이콘][이름(볼드)+설명] | [편집][적용]`, EventViewer류 인스펙터 |
| **단축키** | 그룹 카드 + 우측 `ShortcutRecorderField` | 키 입력 박스 |
| **권한·상태** | §②와 동일 | `PermissionStatusChip` |
| **고급** | 인셋 그룹 내 토글/체크박스 나열 | 파워옵션 격리, 프로파일 export/import |

- 폴리시: "마지막 연 탭 기억"(Bartender). About에 **서명 ID + "키 입력 저장·전송 안 함 / 데이터 판매 안 함"** 명시(Bartender 2024 논란 교훈).

---

## 5. 다음 단계 플랜

### Phase A — 디자인 토큰/컴포넌트 정의 (선행)
- [ ] §3-1 컬러 토큰·§3-2 타이포/간격/radius 를 SwiftUI `Color`/`Font` 확장 또는 Figma 변수로 확정
- [ ] 자체 에셋(§2-5)에서 **브랜드 민트/틸 정확 hex 추출** → `brand/relay` 토큰 확정 (현재 추정치)
- [ ] **컬러 분배 규칙 린트**: 조작 컨트롤=시스템 블루 / 브랜드색=비조작만 (코드리뷰 체크리스트화)
- [ ] §3-3 7개 컴포넌트 스펙(상태·변형) 문서화 → 와이어프레임

### Phase B — 와이어프레임/목업 (협업 가능)
- [ ] 온보딩 3스텝 + 권한 미러링 일러스트 4종 와이어프레임
- [ ] 페이월 1화면, 설정창 5탭 골격
- [ ] (옵션) Pencil(.pen)로 목업 생성 또는 SwiftUI 프리뷰 프로토타입
- [ ] **아이콘 A 최종화**: 정확 벡터 심볼로 1024px master 재제작 + 16/32/128/512px 라이트·다크 Finder QA (AI PNG 텍스트 소형 깨짐 주의)
- [ ] **권한 일러스트(05) 다크모드 변형** 제작 + "그림임" 시각 분리 적용
- [ ] DMG 배경(04) App Store풍 마크 교체 + `release.sh` Finder 레이아웃 단계 추가(별도 작업)

### Phase C — 구현 연결
- [ ] `UX-Reference-Research.md` §6 Phase 2~5(온보딩/권한견고성/Pro/설정) 구현 태스크와 매핑
- [ ] 권한 딥링크 URL·검증 API(`AXIsProcessTrusted`/`IOHIDCheckAccess`, 호출 순서 함정)는 UX 문서 §2 참조

### 추가 레퍼런스 수집
- [x] CleanShot X 온보딩/설정 화면 5장 — 수집·분석 완료 (2026-05-31, §2-4)
- [x] Ice(무료 메뉴바 앱) 설정 UI 6장 — 수집·분석 완료 (2026-05-31, §2-4)
- [~] AltTab — 사이트 JS 렌더 SPA로 자산 추출 실패. 필요 시 GitHub 이슈 첨부 이미지/리뷰영상에서 수동 수집
- [ ] Raycast/Bartender **실제 인앱 첫 실행 위저드** 동영상 프레임 — Page Flows/Mobbin은 paywall, YouTube 워크스루 프레임 캡처 필요
- [ ] CleanShot X·AltTab 권한 프라이밍 모달 실물(현재는 설정 화면 위주)

---

## 6. 한계 / 검증 필요
- 수집 이미지는 **마케팅 페이지·공식 문서 임베드 자산** 위주. Raycast/Bartender의 *실제 첫 실행 위저드* 스크린은 아직 미수집(리뷰 영상에서 추가 가능).
- Karabiner 권한 화면은 macOS 버전에 따라 레이아웃 상이 → WinMacKey 미러링은 **타깃 macOS 버전별로 갱신** 필요.
- 컬러 hex·폰트는 Gemini 추정치 → 실제 토큰 확정 시 시스템 컬러 API/디자인 검수로 검증.
