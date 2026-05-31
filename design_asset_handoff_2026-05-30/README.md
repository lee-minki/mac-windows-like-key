# WinMacKey Asset Handoff 2026-05-30

이 폴더는 WinMacKey 아이콘/설치/권한/매뉴얼/Pro 기능 시각 에셋을 다음 작업 에이전트에게 넘기기 위한 격리 handoff입니다.

기존 앱 리소스는 수정하지 않았습니다. 실제 앱의 `WinMacKey/Resources/Assets.xcassets/AppIcon.appiconset` 교체는 별도 검토 후 진행하세요.

## 핵심 방향

- 메인 앱 아이콘의 의미는 "Right Command가 한/영 전환 키가 된다"가 가장 정확합니다.
- "Windows와 Mac을 연결"보다 "우측 Command 키 + 한/A 전환"이 제품 본질에 가깝습니다.
- F16은 사용자가 기억할 브랜드 메시지가 아니라 내부 릴레이/VDI 설명용 보조 메시지입니다.
- 키보드 클리닝 모드는 현재 미구현 계획 기능입니다. Pro/Power Tools 컨셉으로만 표시하고, 출시 기능처럼 쓰면 안 됩니다.

## 폴더 구조

- `generated/`: 원본 AI 생성 PNG. 프롬프트 결과를 그대로 보존했습니다.
- `prepared/`: Xcode 비교 투입용 후보 에셋. 현재는 앱 아이콘 후보 A/B의 `.appiconset`만 포함합니다.
- `prompts/`: 이미지 생성 프롬프트 원문.
- `notes/`: 다음 에이전트용 판단 근거, 품질 메모, 작업 순서.

## 추천 선택

1. 메인 아이콘은 `generated/01_icon_candidate_a_right_command_han_a.png`를 우선 검토하세요.
2. 기술 설명/릴레이 문맥은 `generated/02_icon_candidate_b_f16_relay.png` 또는 `generated/06_vdi_relay_manual_illustration.png`를 참고하세요.
3. 클리닝 모드는 `generated/03_feature_candidate_c_cleaning_mode_pro.png`가 가장 바로 쓰기 쉽지만, 기능 상태 표기는 "planned"로 유지하세요.

## 즉시 비교 가능한 앱 아이콘 후보

- `prepared/AppIcon_candidate_A.appiconset`
- `prepared/AppIcon_candidate_B.appiconset`

둘 다 기존 `Contents.json` 구조를 복사하고, 생성 이미지를 표준 macOS app icon 크기로 리샘플링한 비교용입니다. 최종 배포 전에는 작은 크기에서 `⌘`, `한/A`, 화살표가 뭉개지지 않는지 다시 렌더링해야 합니다.

## 현재 체크아웃 근거

- `README.md:23-24`: Right Command를 F16으로 변환하고, 로컬 Mac/VDI 동작이 분기된다고 설명합니다.
- `WinMacKey/WinMacKeyApp.swift:548-554`: 실제 HID IME trigger가 Right Command에서 F16으로 등록됩니다.
- `WinMacKey/WinMacKeyApp.swift:228-237`: VDI에서는 F16 패스스루, 로컬에서는 F16 suppress 후 입력소스 전환 경로입니다.
- `docs/FEATURE_SPEC.md:162-170`: 키보드 클리닝 모드는 명세만 있고 미구현입니다.
- `docs/private/PRO_TIER_GATING_PLAN.md:15-17`: 현재 Pro 경계는 디바이스별 자동 전환 하나로 잡혀 있습니다.
- `scripts/release.sh:216-234`: 현재 DMG는 staging 폴더를 `hdiutil create`로 패키징하는 기본 구조입니다. 커스텀 배경/아이콘 위치 지정은 아직 별도 작업이 필요합니다.
- `docs/private/GUMROAD_LISTING.md:60-67`: 상품 페이지용 스크린샷은 메뉴바, 한/영 데모, 설정, VDI, Doctor/Event Viewer, 설치 컷이 권장되어 있습니다.

## 다음 작업자에게

1. 후보 A/B를 실제 macOS Dock, Finder, 메뉴바 환경에서 16/32/128/512px로 비교하세요.
2. 최종 아이콘은 AI PNG를 그대로 쓰기보다, 정확한 벡터 심볼 `⌘`, `한/A`, swap arrow를 얹은 1024px master로 다시 제작하세요.
3. 권한/설치 매뉴얼 이미지는 생성 이미지가 아니라 실제 macOS 스크린샷 위에 안전한 주석을 얹어 만드세요.
4. 클리닝 모드를 Pro 기능으로 넣을 경우 `docs/FEATURE_SPEC.md`와 `docs/private/PRO_TIER_GATING_PLAN.md`의 경계도 같이 갱신해야 합니다.
5. DMG 배경을 실제 릴리스에 반영하려면 `scripts/release.sh`에 배경 이미지, Finder window bounds, 아이콘 위치 지정 단계를 추가해야 합니다.
