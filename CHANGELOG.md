# Changelog

All notable changes to WinMac Key will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased] — v1.3.0

### Added
- **IOKit 기반 외장 키보드 자동 감지**: `IOHIDManager`로 연결된 키보드를 VendorID/ProductID로 식별
- **디바이스별 프로필 자동 전환**: 외장 키보드 입력 시 할당된 프로필로 즉시 전환 (디바이스 > 앱 > 기본 우선순위)
- **VDI 고스트 키 방지**: 트리거 릴리즈 후 50ms 쿨다운으로 Alt+key 조합 오발 차단 (딜레이 0ms)
- **VDI first-key settle buffer**: 트리거 직후 15ms 동안 첫 키를 정렬해 `F16 → Right Alt` 변환 레이스 완화
- **Profiles 탭**: "Assign current keyboard" 버튼으로 키보드 디바이스별 프로필 할당
- **Debug 탭**: 연결된 키보드 디바이스 목록 및 활성 키보드 표시
- **CHANGELOG.md**: 프로젝트 변경 이력 문서화

### Fixed
- VDI 환경에서 한영전환 후 Shift+영문 입력 시 Windows 화면녹화(Win+Shift+R) 등 단축키 오발
- VDI 환경에서 한영전환 후 영문 대문자 입력 시 의도치 않은 앱 실행
- 로컬 macOS에서 한영전환 직후 첫 글자가 영어로 들어가던 문제 완화
- 입력소스 전환 검증 실패를 성공으로 처리해 버퍼를 조기 해제하던 레이스 수정

### Changed
- HelpView 매뉴얼 전면 재작성 — 디바이스 프로필, VDI 고스트 키 방지 등 신기능 반영
- UpdateView 릴리스 노트 마크다운 렌더링 개선
- README, VDI_SETUP, SETUP_GUIDE 문서 업데이트

---

## [1.2.3] — 2026-03-09

### Fixed
- GitHub Actions release workflow 권한 설정 수정 (`contents: write`)

---

## [1.2.2] — 2026-03-09

### Fixed
- GitHub release 빌드 호환성 수정 (DMG 생성 플로우)

---

## [1.2.1] — 2026-03-09

### Added
- IME 입력소스 커밋 윈도우 (70ms 버퍼링) — 빠른 한영전환 시 글자 누락 방지
- VDI 포커스 시 내장 키보드 자동 매핑 전환 (Fn→Ctrl, Ctrl→Fn)

### Fixed
- 한영전환 직후 글자 씹힘/중복 입력 문제 개선
- HID-CGEventTap 이중 매핑 버그 수정

---

## [1.2.0] — 2026-03-07

### Added
- **Control+Space 기반 한영전환**: `TISSelectInputSource` API 의존성 완전 제거
- **네이티브 VDI 지원**: 별도 가상 키보드 드라이버 없이 F16 릴레이 키로 VDI 한영전환
- **hidutil HID 레벨 매핑**: Fn/Globe 키 포함 modifier 키 리매핑
- **프로필 시스템**: Mac 로컬 / VDI 컨텍스트별 목표 배치 저장 및 자동 전환
- **프로필 위저드**: 실키 감지, 3키/4키 자동 판단, Mac/VDI 배치 개별 설정
- Karabiner DriverKit 완전 불필요

### Changed
- 한영전환 메커니즘을 `TISSelectInputSource` → `Control+Space 합성` 으로 전환
- 메뉴바 아이콘이 macOS 네이티브 입력소스 표시기와 동기화

---

## [0.1.0] — 2026-03-01

### Added
- 인앱 도움말 매뉴얼 (HelpView)
- GitHub Releases 기반 앱 내 자동 업데이트
- 파일 기반 로깅 및 로그 뷰어
- Doctor 진단/복구 기능
- Event Viewer 실시간 키 입력 모니터링
- CGEventTap 자동 재활성화 (타임아웃 복구)

### Fixed
- tap-only 한/영 전환 정확도 개선
- 키 리매핑 로직 전면 재작성
- EventViewer, ContextManager, 레이턴시 표시 수정

---

## [1.0.0] — 2026-02-28

### Added
- 초기 릴리즈
- CGEventTap 기반 키보드 이벤트 인터셉트
- Right Command tap-only 한/영 전환
- 키코드 리매핑 (fn ↔ Cmd ↔ Ctrl)
- 메뉴바 유틸리티 (MenuBarExtra)
- 앱별 컨텍스트 인식 (VDI 자동 감지)
