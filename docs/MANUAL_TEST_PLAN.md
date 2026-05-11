# Manual Test Plan — IME · HID · Permission 회귀 검증

이 체크리스트는 KeyInterceptor / HIDRemapper / PermissionService / AppState lifecycle 을 건드리는 모든 패치 후 반드시 통과해야 한다. 자동 테스트로 잡기 어려운 영역이라 사람이 한 번 돌린다.

## 사전 준비

```bash
# 1. 외부 hidutil 상태 백업 (사용자가 다른 도구로 hidutil 매핑을 두고 있을 수 있음)
hidutil property --get UserKeyMapping > /tmp/wmkey-test-precondition.json
cat /tmp/wmkey-test-precondition.json

# 2. 빌드된 .app 경로 확인
APP=/Applications/WinMacKey.app  # 또는 build/DerivedData/Build/Products/Debug/WinMacKey.app
ls -la "$APP"

# 3. 이전 세션의 흔적 클린업 (필요 시)
killall WinMacKey 2>/dev/null
```

## 체크리스트

각 항목은 **PASS / FAIL** 둘 중 하나로 명시. 한 건이라도 FAIL이면 commit 금지.

### A. 앱 실행만으로 시스템 영향 없음 (HIGH #1 invariant)

- [ ] **A-1**: `hidutil property --get UserKeyMapping` 결과 기록 (앱 실행 전)
- [ ] **A-2**: 앱 실행 (engine OFF 상태). 메뉴바에 `wm` 소문자 표시 확인
- [ ] **A-3**: `hidutil property --get UserKeyMapping` 결과가 **A-1과 동일**
- [ ] **A-4**: DEBUG 빌드일 경우, 콘솔에 `"Invariant violated"` 메시지 없음
- [ ] **A-5**: 로그 파일(`~/Library/Application Support/WinMacKey/winmackey.log`)에 `"Lifecycle invariant violation"` 없음

### B. 엔진 ON 시 HID 적용 (정상 동작)

- [ ] **B-1**: 메뉴바 → 토글 ON. `WM` 대문자로 변경 확인
- [ ] **B-2**: `hidutil property --get UserKeyMapping` 결과에 RightCmd(`0x7000000E7`) → F16(`0x70000006B`) 매핑 포함
- [ ] **B-3**: 기본 프로필이라면 추가로 Fn↔Cmd↔Ctrl 매핑도 포함

### C. IME 한영 전환 — 핵심 동작

- [ ] **C-1**: 텍스트 편집기에서 Right Cmd 1회 → 입력소스가 EN ↔ 한 전환
- [ ] **C-2**: Right Cmd 빠르게 5회 → 매 전환마다 정상, 씹힘 없음
- [ ] **C-3**: 한글 입력 중 `안녕하` 입력 후 Right Cmd → "안녕하" commit + 영문 모드 전환
- [ ] **C-4**: 영문 입력 중 `hello` 후 Right Cmd → "hello" 유지 + 한글 모드 전환

### D. VDI 모드 (Omnissa Horizon 가용 시)

- [ ] **D-1**: Horizon 클라이언트 실행 → Windows VDI 연결 → 텍스트 입력 창 포커스
- [ ] **D-2**: Right Cmd → Windows에서 한영 전환 (Horizon의 F16 → Right Alt 매핑 필요)
- [ ] **D-3**: Right Cmd + Shift+P 빠르게 → "다른 화면에 표시" 팝업 **안 뜸**
- [ ] **D-4**: 한영 전환 직후 빠르게 영문 대문자 입력 → Windows 키 조합 오발 없음

### E. 터미널 컨텍스트 (Ghostty / Claude Code 등)

- [ ] **E-1**: Ghostty 또는 다른 terminal 앱 포커스
- [ ] **E-2**: Right Cmd → 한영 전환 정상
- [ ] **E-3**: 출력에 `[57379u` 또는 raw escape sequence 누출 **없음**
- [ ] **E-4**: `Cmd+N`, `Cmd+T` 등 단축키가 정상 동작 (수동 search UI 누출 없음)

### F. 키보드 디바이스 자동 전환 (외장 키보드 가용 시)

- [ ] **F-1**: 외장 키보드 연결 + 외장용 프로필을 "Assign current keyboard"로 바인딩
- [ ] **F-2**: 외장 키보드로 키 입력 → Profiles 탭에서 활성 프로필이 외장용으로 표시
- [ ] **F-3**: 내장 키보드로 키 입력 → 활성 프로필이 기본/내장용으로 즉시 전환

### G. Doctor 재시작 (HIGH #2)

- [ ] **G-1**: 엔진 ON 상태 → 메뉴바 → Doctor (진단/복구) 윈도우 열기
- [ ] **G-2**: 진단 통과 후 Doctor 안에서 어떤 항목에 "재시작" 액션이 있다면 실행
- [ ] **G-3**: 재시작 직후 Right Cmd → 한영 전환 **여전히 동작**
- [ ] **G-4**: `hidutil property --get UserKeyMapping` → RightCmd→F16 매핑 **여전히 존재**

### H. 설정 초기화 / Emergency Recovery (MED #3)

- [ ] **H-1**: 엔진 ON 상태 → 외장 키보드 프로필 바인딩 셋업 완료
- [ ] **H-2**: 메뉴바 → "설정 초기화" → "초기화" 확인
- [ ] **H-3**: 앱 재시작 없이 외장 키보드로 입력 → 마지막 활성 디바이스 추적이 **여전히 동작**
- [ ] **H-4**: 같은 식으로 VDI 앱 포커스 전환 → 컨텍스트 감지가 **여전히 동작**

### I. 권한 부여 후 자동 엔진 시작 (MED #4)

- [ ] **I-1**: 사전: `tccutil reset Accessibility com.winmackey.app` 으로 권한 리셋
- [ ] **I-2**: "앱 실행 후 엔진 자동 시작" 옵션 ON
- [ ] **I-3**: 앱 실행 → 권한 요청 다이얼로그 → 손쉬운 사용 허용
- [ ] **I-4**: 권한 허용 1~2초 내 메뉴바 `WM`으로 자동 전환

### J. 앱 종료 시 hidutil 복원

- [ ] **J-1**: 엔진 ON 상태에서 hidutil 매핑 적용된 것 확인
- [ ] **J-2**: 메뉴바 → "WinMac Key 종료"
- [ ] **J-3**: `hidutil property --get UserKeyMapping` 결과가 **A-1과 동일** (외부 사전 상태로 복귀)

### K. Pre-existing hidutil ownership 보존 (v1.3.3+, v1.3.4 보강)

다른 hidutil 도구 매핑이 앱에 의해 지워지지 않는지 검증.

```bash
# 1. 미리 외부 hidutil 매핑 설정 (예: Karabiner 흉내)
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E0,"HIDKeyboardModifierMappingDst":0x7000000E1}]}'

# Global + Internal keyboard 각각 baseline 저장
hidutil property --get UserKeyMapping > /tmp/wmkey-global-baseline.json
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --get UserKeyMapping > /tmp/wmkey-internal-baseline.json
```

- [ ] **K-1**: 위 매핑이 적용된 상태에서 앱 실행 → 메뉴바 `wm` 확인 (engine OFF)
- [ ] **K-2**: Global + Internal `hidutil --get` 결과가 **K-1 직전과 동일** (앱 실행만으론 변경 없음)
- [ ] **K-3**: 엔진 ON → Global 에 WinMacKey 매핑 등장
- [ ] **K-4**: 엔진 OFF → Global `hidutil --get` 결과가 K-1 사전 상태로 복원 ← **v1.3.4 fix**
- [ ] **K-5**: 엔진 ON → 앱 종료 → Global 결과가 K-1 사전 상태로 복원
- [ ] **K-6**: VDI 진입 → 엔진 OFF → Internal `hidutil --get` 결과가 K-1 사전 상태로 복원 ← **v1.3.4 fix (VDI internal cleanup)**

```bash
# 정리
hidutil property --set '{"UserKeyMapping":[]}'
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --set '{"UserKeyMapping":[]}'
```

### L. TCC reset 자동 실행 confirmation (v1.3.3+)

- [ ] **L-1**: 메뉴바에 stale grant 경고가 표시된 상황 만들기 (이전 빌드 권한 잔존)
- [ ] **L-2**: "터미널에서 실행…" 버튼 클릭
- [ ] **L-3**: confirmation dialog 가 표시됨 (제목: "TCC 권한 등록을 초기화하시겠습니까?")
- [ ] **L-4**: "취소" 클릭 → Terminal 안 열림
- [ ] **L-5**: 다시 "터미널에서 실행…" → "실행" 클릭 → Terminal 열리고 `tccutil reset Accessibility com.winmackey.app` 자동 실행
- [ ] **L-6**: "명령 복사" 버튼 클릭 → 클립보드에 명령 복사 (Terminal 안 열림)

### M. Update install .app 검증 (v1.3.3+)

테스트 어려움 — release.sh 가 정상 산출물을 만드는 한 자동 통과. 인공 변조 테스트는 별도 환경 필요.

- [ ] **M-1**: `./scripts/release.sh <next-version> --no-release` 로 정상 빌드된 자산은 통과
- [ ] **M-2**: 앱 내 "업데이트 확인" → 자동 설치 시 verifyExtractedApp 단계가 메시지로 표시
- [ ] **M-3**: (인공) 변조 자산: dmg 안의 .app Info.plist 의 CFBundleIdentifier 변경 후 같은 키로 재서명 → 업데이트 시 거부 메시지

### N. 로그 / 클립보드 프라이버시 (v1.3.3+)

- [ ] **N-1**: 메뉴바 → 로그 뷰어 → "클립보드 복사" 버튼
- [ ] **N-2**: confirmation dialog 표시됨 (제목: "로그를 클립보드에 복사하시겠습니까?")
- [ ] **N-3**: "취소" 클릭 → 클립보드 변경 없음
- [ ] **N-4**: "복사" 클릭 → 클립보드에 로그 내용 들어감
- [ ] **N-5**: Event Viewer 에서 익명화된 표시 (`app-xxxxxxxx`, `modifier`/`letter`/`function` 카테고리) 확인 (privacy mode ON 시)

### O. Mac → Mac 원격접속 한영전환 (v1.3.5+)

본인 맥북에서 맥미니 등에 Apple Screen Sharing 으로 원격접속 시 한영전환.

**핵심**: Screen Sharing 은 character 단위로 forward 하므로 **로컬 맥북의 입력소스 토글만으로** 원격 화면에 올바른 문자가 들어감. 원격 Mac 에는 WinMacKey 설치 불필요.

**사전 준비**:
- 맥북에 WinMacKey v1.3.5+ 설치, 손쉬운 사용 권한 + 엔진 ON
- 맥북 macOS 입력소스 단축키 = `Control+Space`
- 맥미니: 그냥 보통 Mac 상태 (WinMacKey 설치 안 해도 됨)

**검증 절차**:
- [ ] **O-1**: 맥북에서 Screen Sharing.app 으로 맥미니 연결
- [ ] **O-2**: 원격 (맥미니) 의 텍스트 편집기에 포커스
- [ ] **O-3**: 맥북 입력소스 = 영어 상태에서 "abc" 타이핑 → 맥미니 텍스트에 "abc" 들어감
- [ ] **O-4**: 맥북에서 Right Command 누름 → **맥북 메뉴바 입력소스가 EN ↔ 한 으로 토글** (정상 동작)
- [ ] **O-5**: 이어서 "asd" 타이핑 → 맥미니 텍스트에 "ㅁㄴㅇ" 들어감
- [ ] **O-6**: 다시 Right Command → 맥북 영어로 토글 → "qwe" → "qwe" 들어감
- [ ] **O-7**: 맥미니 자체 입력소스는 변경되든 안 되든 무관 (참고용 — Screen Sharing 이 character forward 라 결과에 영향 없음)

**실패 시 분석**:
- O-4 위반 (맥북 입력소스 안 바뀜) → 로컬 모드 동작 안 함. Doctor 로 진단.
- O-5 위반 (영어가 들어감) → 맥북 입력소스가 실제로 한국어로 안 바뀌었거나 한국어 입력 소스가 macOS 에 추가 안 됨.
- O-3 자체가 안 됨 → Screen Sharing 자체 문제 (WinMacKey 무관).

**다른 원격접속 도구 (Jump Desktop, AnyDesk, ARD)**:
이론적으로 같은 character forwarding 이라면 동일 동작. 실측 권장. 예외적으로 raw scan code forwarding 하는 도구가 있다면 다른 동작 가능.

## 통과 기준

- 모든 체크 PASS → 패치 commit 가능
- 한 건이라도 FAIL → 원인 분석 후 fix, 처음부터 다시 돌림

## 사후 정리

```bash
# 외부 hidutil 사전 상태 복원 검증
diff /tmp/wmkey-test-precondition.json <(hidutil property --get UserKeyMapping)
# 동일하면 OK
```
