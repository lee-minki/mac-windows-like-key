# Changelog

All notable changes to WinMac Key will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased] — v1.3.2

v1.3.1 외부 코드 리뷰에서 발견된 7건 일괄 패치. 가장 중요한 항목은 "엔진 OFF 시 시스템 영향 없음" 안전 경계 위반 (앱 실행만으로 hidutil 글로벌 매핑이 변경될 수 있던 버그).

### Fixed
- **HIGH: 앱 init 시점 HID 시스템 미터치 보장**: `KeyInterceptor.init()` 이 `setupDefaultMappings()` 를 호출해 `hidutil` 글로벌 매핑을 변경하던 버그. 사용자의 외부 hidutil 설정이 앱 실행만으로 지워질 수 있었다. `setupDefaultMappings` 를 `computeKeyMappings`(메모리만)와 `setupDefaultMappings`(메모리+HID)로 분리. init은 전자만 호출. HID 적용은 engine ON 경로(`refreshActiveProfileForCurrentContext`)에서만.
- **HIGH: Doctor restart 후 HID 재적용 누락**: `DoctorService.performFix(.restartEngine)` 이 `stop()` → `start()` 만 호출해 RightCmd→F16 매핑이 풀린 상태로 EventTap 만 켜지던 버그. UI는 엔진 ON 인데 한영전환 침묵. start 성공 후 `appState.refreshActiveProfileForCurrentContext()` 호출 추가.
- **MED: Reset/Emergency Recovery 후 모니터링 재시작**: `ResetService.resetAll` 과 `DoctorService.emergencyRecovery` 가 KeyboardDeviceManager / ContextManager 를 stop 후 재시작하지 않아 초기화 후 앱 재시작 전까지 디바이스 자동 전환·VDI 컨텍스트 감지가 죽어 있었다. 두 매니저 모두 monitoring 재시작 + lastActiveKeyboard 리셋.
- **MED: 권한 폴링 분리**: `startPermissionPolling` 이 Accessibility + Input Monitoring 둘 다 만족해야 종료해 Accessibility 만 허용한 사용자는 polling 이 영원히 돌고 자동 엔진 시작 알림이 발화되지 않던 버그. `startAccessibilityPolling` / `startInputMonitoringPolling` 분리. 각자 5분 timeout.
- **MED: release.sh 버전 가드**: 인자로 받은 `VERSION` 과 `Info.plist:CFBundleShortVersionString` 일치 검증. 불일치 시 즉시 거부. `set -euo pipefail` 도입. `check-version-consistency.sh` 자동 호출.
- **LOW: actor isolation 경고**: `AppState.findAllInstallations` 를 `nonisolated` 로 표기. background queue 에서 안전 호출.
- **LOW: VDI 로그 문구 정정**: "Fn=Ctrl, Option=Win, Command=Alt" → "Fn↔Ctrl swap applied". 실제 매핑(`vdiInternalKeyboardMappings`)과 일치.

### Added
- **검증 인프라**: `HIDRemapper` 에 `applyCallCount` / `clearCallCount` 카운터. `AppState.init` 끝에 DEBUG assertion 으로 "init 이 HID 안 건드림" invariant 자동 검증. `tests/hid_lifecycle_smoke.swift` smoke 테스트 추가. `docs/MANUAL_TEST_PLAN.md` 회귀 체크리스트 (10개 카테고리, 30+ 검증 항목).

---

## [1.3.1] — Skipped (consolidated into v1.3.2)

내부 빌드만 진행되고 외부 안내 보류. 아래 변경 사항은 모두 v1.3.2 에 포함됨.

### Added
- **Stable code signing identity 지원**: `scripts/setup-signing.sh` 로 self-signed cert 1회 생성 → 같은 identity로 서명된 빌드 간 손쉬운 사용 권한 영속 (Designated Requirement가 leaf cert SHA-1로 바인딩). Apple Developer Program 없이도 빌드/업데이트마다 권한 재요청 불필요. `SIGN_IDENTITY` 환경변수로 override, cert 없으면 ad-hoc fallback.
- **자동 업데이트 위치 가드**: `UpdateService` 가 `/Applications/` 외 위치(Downloads, Desktop 등)에서 실행 중이면 다운로드를 거부. `UpdateError.notInApplicationsFolder` 신규.
- **중복 설치 감지**: 앱 실행 시 `mdfind` 백그라운드로 동일 bundle ID의 모든 .app 위치를 탐색해 메뉴바에 경고 카드 표시. build/DerivedData/Volumes/Trash/tmp 경로는 자동 제외.
- **Orphan TCC 권한 감지·복구 UI**: 이전에 권한이 부여됐으나 csreq 변경(ad-hoc → self-signed 마이그레이션 등)으로 무효화된 상태를 자동 감지. 메뉴바에서 `tccutil reset Accessibility com.winmackey.app` 명령 클립보드 복사 또는 Terminal.app에서 자동 실행 (AppleScript).
- **Ed25519 자동 업데이트 무결성 검증**: `scripts/setup-update-signing.sh` 로 keypair 생성. public key는 앱에 임베드, private key는 `~/.config/winmackey/update-signing.key` 보관. `release.sh` 가 ZIP/DMG 빌드 후 `.sig` 동봉. 업데이트 다운로드 시 CryptoKit `Curve25519.Signing.PublicKey.isValidSignature` 로 검증, 실패하면 설치 거부. GitHub 계정 탈취로 인한 RCE 시나리오 방어.

### Changed
- `scripts/release.sh` 가 self-signed identity를 실제 codesign 테스트로 자동 감지 후 manual 서명. unsigned .dmg 시대 종료.
- `WinMacKey/Services/KeyInterceptor.swift` 의 133줄 `handleEvent` C 콜백을 `handleTriggerKey` / `handleMappedKey` / `translateMapping` / `dispatchVerificationCallback` 4개 메서드로 분해. 동작 보존 리팩터로 트리거 처리·매핑·버퍼링·검증 책임 분리.
- `UpdateService.replaceApp` 의 `xattr -cr` 자동 호출 제거 — quarantine은 Ed25519 서명 검증으로 충분히 신뢰가 형성된 자산에 대해서만 사용자가 의도적으로 해제할 일.
- `UpdateService.relaunchApp` 을 `/bin/sh -c "open \"...\""` shell interpolation 에서 `Process` + `/usr/bin/open` 인자 배열로 교체.

### Removed
- `WinMacKey.entitlements` 에서 `com.apple.security.cs.allow-unsigned-executable-memory` 와 `com.apple.security.cs.disable-library-validation` 제거. 코드 grep 결과 0건 사용 — 향후 notarize 단계에서도 안전.

---

## [1.3.0] — Skipped (consolidated into v1.3.1)

내부 빌드만 진행되고 외부로 릴리스되지 않음. 아래 변경 사항은 모두 v1.3.1에 포함됨.

### Added
- **F16 HID remap 아키텍처**: `hidutil`로 Right Command를 F16으로 HID 레벨 변환 — modifier flag 오염 원천 차단
- **VDI F16 패스스루**: VDI 모드에서 F16이 Horizon에 직접 전달되어 suppress+재발행 불필요
- **IOKit 기반 외장 키보드 자동 감지**: `IOHIDManager`로 연결된 키보드를 VendorID/ProductID로 식별
- **디바이스별 프로필 자동 전환**: 외장 키보드 입력 시 할당된 프로필로 즉시 전환 (디바이스 > 앱 > 기본 우선순위)
- **Profiles 탭**: "키보드 할당" 버튼으로 키보드 디바이스별 프로필 할당
- **재부팅 후 자동 실행 옵션**: 로그인 항목 등록과 앱 실행 후 엔진 자동 시작 토글 추가
- **CHANGELOG.md**: 프로젝트 변경 이력 문서화

### Fixed
- **VDI에서 한/영+Shift+P 시 "다른 화면에 표시" 팔업 (Win+P)**: modifier flag 오염 원천 차단
- **VDI에서 빠른 영문 대문자 입력 시 Windows 키 조합 오발**: F16 non-modifier remap으로 해결
- 로컬 macOS에서 한영전환 직후 첫 글자가 영어로 들어가던 문제 완화
- 입력소스 전환 검증 실패를 성공으로 처리해 버퍼를 조기 해제하던 레이스 수정
- **Ghostty / Claude Code terminal regression 1차 안정화**: `[57379u]` raw sequence, Command shortcut 누출(`Cmd+N`, `Cmd+D`, 검색 UI`), `pasting text` 오버레이가 사라지는 단계까지 확인
- **진단/런타임 정렬**: Caps Lock 설명과 F16 기반 트리거 경로를 현재 동작에 맞게 정리
- **권한 안내 개선**: 손쉬운 사용 상태 확인과 설치 후 권한 재부여 흐름 정리
- **검증 베이스라인 추가**: 스모크 테스트 스크립트와 버전 메타데이터를 1.3.0 (build 5)로 정리

### Changed
- **트리거 표면 단순화**: Right Option 선택지를 제거하고 Right Command 단일 트리거 모델로 정리
- **터미널 경로 분기**: terminal-like 앱에서 direct input-source switch를 사용할 수 있도록 context/transport 경로 확장
- **플랫폼 관리 확장**: 키보드 디바이스/로그인 항목 관리용 서비스 구조 추가
- **트리거 감지**: CGEventTap `flagsChanged` → `keyDown/keyUp` (F16은 modifier가 아니므로)
- **modifier flag 스트리핑/쿨다운 제거**: F16은 modifier flag를 생성하지 않으므로 불필요
- HelpView 매뉴얼 전면 재작성 — 디바이스 프로필, VDI 고스트 키 방지 등 신기능 반영
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
