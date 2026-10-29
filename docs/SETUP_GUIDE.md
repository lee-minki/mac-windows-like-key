# WinMac Key 설정 가이드

## 변경 요약

한영전환 방식이 다음처럼 분리되었습니다.
- 로컬 macOS: `Control+Space 시스템 단축키 주입`
- Windows VDI: `F16 릴레이 키 주입`
- Mac → Mac 원격 / 화면 공유: 별도 검증 전. 입력 전달 방식과 원격 Mac의 설치 필요 여부를 단정하지 않습니다.

### 개선된 점
- **업데이트·복구 진단 강화 (v1.8.5)**: 업데이트는 기존 앱 종료 후 교체하고 새 프로세스의 시작 확인까지 백업을 유지합니다. HID 매핑은 적용 후 실제 값을 읽어 확인하며, Doctor에서 권한·이벤트 탭·입력 관측·매핑 검증 결과를 구분합니다.
- **(v1.8.4) 내장·외장 키보드 동시 적용**: 연결된 키보드마다 자기 프로필을 VID:PID 범위로 항상 적용한다. 키 입력 순간 프로필을 바꾸지 않으므로 내장 키보드와 Keys-To-Go 2를 번갈아 사용해도 첫 키부터 각자의 배열로 동작한다. Horizon 포커스에서는 각 프로필의 Windows VDI 배열을 함께 적용한다.
- **(v1.8.3) 중복 실행 차단 + 포터블 4키 지원**: Applications 설치본을 우선해 개발 빌드와 동시에 입력 엔진이 켜지는 일을 막고, `Ctrl · Fn · Opt · Cmd` 키캡 배열을 정식 지원한다.
- **(v1.6.0) 프로필 위자드 — 키코드 기반 직접 매핑 표**: 캡처 없이 표에서 "각 키를 무엇으로 쓸지" 직접 고른다. macOS 가 모든 키보드를 표준 modifier 키코드(Ctrl/Opt/Cmd/Fn)로 정규화하므로 어떤 키보드든 누를 필요 없다 — Mac/Win 듀얼모드 키보드(로지텍 등)에서도 동일하게 동작. "한/영 전환만"은 1클릭으로 즉시 완료, "키 배치도 바꾸기"는 4행×2열 표 + Mac/Windows 키캡 토글 + "Windows 감각" 1클릭 프리셋. (이전: 물리 키 캡처 + Step 1~5)
- **F16 HID remap 아키텍처**: `hidutil`로 Right Command를 F16으로 HID 레벨 변환 — modifier flag 오염 원천 차단
- VDI에서 한/영+Shift+P 시 Win+P 팔업 문제 해결
- 빠른 영문 대문자 입력 시 Windows 키 조합 오발 해결
- 메뉴바 아이콘이 macOS 네이티브 입력소스 표시기로 동기화
- Windows VDI(Omnissa Horizon 등)에서 F16 패스스루 → Right Alt 변환으로 동작
- Karabiner DriverKit 완전 불필요
- IOKit 기반 외장 키보드 자동 감지 및 디바이스별 프로필 동시 적용

---

## STEP 0: 최초 실행 (서명·공증 완료)

v1.8.5 배포 DMG/ZIP은 macOS 14.0 이상 Apple Silicon (arm64)용입니다. Intel용 빌드·실행은 이번 릴리스에서 검증하지 않았습니다.

v1.3.8 이후 빌드는 **Apple Developer ID 서명 + 공증(Notarization)** 을 거쳐 배포됩니다.

1. DMG를 마운트한 뒤 `WinMacKey.app`을 **Applications** 폴더로 드래그
2. **더블클릭으로 바로 실행** — Gatekeeper 경고 없이 열립니다

> v1.3.8 부터 Apple 공증을 통과해 별도 우회 절차가 필요 없습니다.
> WinMac Key는 `hidutil`/CGEventTap 기반 메뉴바 유틸리티이며 시스템 파일을 건드리지 않습니다.

<details>
<summary>v1.3.7 이하 구버전 또는 직접 빌드한 미서명 빌드를 쓸 때만</summary>

미서명 빌드는 첫 실행 시 **"확인되지 않은 개발자"** 경고가 뜹니다. 둘 중 하나로 한 번만 허용하세요.

- **방법 1**: Applications 에서 `WinMacKey.app` **우클릭 → 열기** → 팝업의 **"열기"** 다시 클릭
- **방법 2**: 터미널에서 `xattr -dr com.apple.quarantine /Applications/WinMacKey.app`

</details>

---

## STEP 1: macOS 입력소스 전환 단축키 설정

**이것이 가장 중요합니다. 이 설정이 없으면 한영전환이 동작하지 않습니다.**

WinMac Key는 Right Command를 누르면 현재 컨텍스트에 따라 다음 중 하나를 전송합니다.
- 로컬 macOS: `Control+Space`
- Windows VDI: `F16`
- 원격 Mac / 화면 공유: 별도 검증 전까지 로컬 macOS와 동일 동작을 보장하지 않습니다.

### 설정 방법

1. **시스템 설정** 열기 (Apple 메뉴 → 시스템 설정)

2. **키보드** 클릭

3. **키보드 단축키...** 버튼 클릭

4. 왼쪽 목록에서 **입력 소스** 선택

5. **"이전 입력 소스 선택"** 항목 확인
   - 체크박스가 켜져 있어야 합니다
   - 단축키가 `^Space` (Control+Space) 여야 합니다

6. 만약 다른 키로 되어 있다면:
   - 기존 단축키를 더블클릭
   - `Control + Space` 를 눌러서 변경
   - "완료" 클릭

### 확인 방법

설정 후, **텍스트 편집기**에서 `Control + Space`를 직접 눌러보세요.
메뉴바의 입력소스 아이콘이 EN ↔ 한 으로 바뀌면 정상입니다.

> 주의: "다음 입력 소스 선택" (^Option+Space)이 아니라
> **"이전 입력 소스 선택"** (^Space)을 설정해야 합니다.

---

## STEP 2: 손쉬운 사용 권한

```
시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → WinMac Key 허용
```

이전 버전에서 이미 허용했다면 **재허용이 필요할 수 있습니다:**
1. WinMac Key 체크 해제
2. WinMac Key 앱 종료
3. 다시 체크
4. WinMac Key 앱 재시작

---

## STEP 3: 빌드 및 실행

### 빌드

```bash
cd ~/worksapces/mac-windows-like-key
xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey -configuration Debug -derivedDataPath build/DerivedData build
```

### 실행

```bash
WINMACKEY_ALLOW_NONSTANDARD_INSTANCE=1 build/DerivedData/Build/Products/Debug/WinMacKey.app/Contents/MacOS/WinMacKey
```

또는 Xcode에서 `Cmd+R`

> `/Applications/WinMacKey.app`이 설치된 상태에서는 다른 위치의 복사본이 입력 엔진을 시작하지 않습니다. 위 환경 변수는 개발 검증 전용이며 로그인 항목에는 개발 빌드를 등록하지 마세요.

### Keys-To-Go 2 포터블 배열

1. 키보드에서 `Fn + O`를 3초간 눌러 macOS 모드로 맞춥니다.
2. 설정의 키보드 프로필에서 **새 프로필 만들기**를 누릅니다.
3. **포터블 Mac 4키 (Ctrl · Fn · Opt · Cmd)**와 **키 배치 바꾸기**를 선택합니다.
4. Mac 추천값 `Cmd · Fn · Opt · Ctrl`, VDI 자동값 `Ctrl · Win · Win · Alt`를 확인합니다.
5. Keys-To-Go 2에서 아무 키나 한 번 누른 뒤 **이 키보드에만**으로 저장합니다.
6. 저장 후에는 내장 키보드와 Keys-To-Go 2 프로필이 동시에 유지됩니다. 키보드를 번갈아 눌러도 프로필을 다시 선택할 필요가 없습니다.

내장 키보드만 연결된 상태에서는 **이 키보드에만**이 내장 키보드를 자동 선택하므로 별도 키 입력 없이 바로 저장할 수 있습니다. 여러 키보드가 연결돼 대상이 모호할 때만 저장할 키보드에서 키를 한 번 누릅니다.

잘못 적용되면 먼저 엔진을 끄세요. 앱이 설정한 값이 그대로 남아 있는 항목만 적용 전 값으로 복원하며, 다른 도구가 이후 바꾼 항목은 보존합니다. 읽기·쓰기 실패로 복원이 확인되지 않으면 Doctor의 HID 결과를 확인한 뒤 아래 수동 초기화를 검토하세요.

### 엔진 활성화

1. 메뉴바에 `wm` (소문자) 이 보이면 클릭
2. 엔진 토글 ON
3. `WM` (대문자)로 변경 확인

### 재부팅 후 자동 실행 옵션

재부팅 후 매번 앱을 직접 켜기 싫다면 다음 두 옵션을 함께 켜세요.

1. 메뉴바 `wm/WM` 클릭 → **설정...**
2. **General → Startup** 카드에서 **로그인 시 자동 실행** ON
3. 같은 카드에서 **앱 실행 후 엔진 자동 시작** ON
4. **새 버전 자동 확인**은 기본 ON이며 필요하면 같은 카드에서 끌 수 있습니다.
5. 상태가 `승인 필요`로 나오면 **로그인 항목 설정 열기**를 눌러 시스템 설정에서 WinMac Key를 허용

주의:
- `로그인 시 자동 실행`은 macOS 로그인 항목에 앱을 등록합니다.
- `앱 실행 후 엔진 자동 시작`은 앱이 켜질 때 엔진까지 자동으로 켭니다.
- 손쉬운 사용 권한이 없으면 앱은 실행되지만 엔진 시작은 보류됩니다.

---

## STEP 4: Mac 로컬 동작 확인

1. 텍스트 편집기 열기
2. **Right Command** 키 누르기
3. 메뉴바의 입력소스 아이콘이 EN ↔ 한 변경 확인
4. 빠르게 여러번 전환 → 글자 씹힘 없는지 확인
5. 한글 입력 중 Right Command → 조합 중인 글자가 정상 commit 되는지 확인

---

## STEP 5: VDI 환경 설정 (Omnissa Horizon)

### 동작 원리

```
[Mac 로컬 포커스]
  Right Cmd → hidutil HID remap → F16 → suppress → Control+Space 합성 → macOS 입력소스 전환
  Caps Lock → 시스템 기본 동작 유지
  내장 키보드: Cmd · Fn · Opt · Ctrl (내장 장치 프로필)
  Keys-To-Go 2: Cmd · Fn · Opt · Ctrl (046D:B38C 장치 프로필)

[VDI 앱 포커스] (자동 전환)
  Right Cmd → hidutil HID remap → F16 → 패스스루 → Horizon이 F16 → Right Alt 변환
  Caps Lock → 시스템 기본 동작 유지 (앱이 소유하지 않음)
  내장 키보드 + Keys-To-Go 2: 각 장치 프로필의 Ctrl · Win · Win · Alt 배열 동시 적용

[원격 Mac / 화면 공유]
  Right Cmd → 별도 검증 필요
  Caps Lock → 시스템 기본 동작 유지
```

### Omnissa Horizon 클라이언트 설정

1. Horizon Client 실행
2. **Connection** 메뉴 → **Preferences** (또는 설정)
3. **Keyboard & Mouse** 탭
4. **Key Mappings** (키 매핑) 섹션 찾기
5. 매핑 추가:
   - Mac 단축키: `F16`
   - Windows 키: `Right Alt`
6. 저장

### VDI 동작 확인

1. Omnissa Horizon으로 Windows 데스크톱 연결
2. 메뉴바가 `WM`인지 확인 (엔진 ON)
3. Right Command 누르기
4. Windows 내에서 한영전환 되는지 확인
5. 필요 시 Windows 쪽 한/영 동작만 별도로 확인

---

## v1.8.5 실사용 확인 범위

2026-10-28 v1.8.5 설치 후 사용자가 Mac 입력창과 Horizon 메모장에서 내장 오른쪽 Command와 K380의 한/영 전환 키를 번갈아 각각 3회 시험했고, 기존 왼쪽 Ctrl/Command 단축키도 정상이라고 확인했습니다. 자동 테스트나 로그만으로 추정한 결과가 아닌 사용자 확인입니다.

이 결과를 모든 로지텍 모델이나 장시간 안정성으로 확대하지 않습니다. Keys-To-Go 2의 설정 예시는 아래에 별도로 설명하며, K380 시험 결과와 구분합니다. 이전의 일시적인 전환 실패 원인도 이 확인만으로 확정하지 않습니다.

원격 Mac / Apple Screen Sharing, 다른 원격 클라이언트, Windows App의 별도 개선 후보는 이번 확인에 포함되지 않습니다. 원격 Mac에서는 로컬 입력소스 표시만 보지 말고 원격 화면의 실제 입력 결과를 확인해야 합니다. 입력 전달 방식, 원격 입력소스의 영향, 양쪽 Mac의 앱 설치 필요 여부는 별도 검증 항목입니다.

## 내장·외장 키보드 매핑 전환

내장 키보드와 바인딩된 외장 키보드는 각각의 장치 범위에서 동시에 매핑됩니다. Horizon 포커스 진입·이탈 때 각 프로필의 `Mac 로컬` / `VDI` 목표가 함께 전환됩니다. 마지막으로 사용한 키보드는 표시용이며 다른 키보드의 배열을 덮어쓰지 않습니다.

현재 구성의 스페이스 왼쪽 네 키는 물리적으로 왼쪽부터 다음과 같습니다.

| 키보드 | 원래 키캡 순서 | Mac 로컬 목표 | Windows VDI 목표 |
|---|---|---|---|
| 맥북 내장 | Fn · Ctrl · Opt · Cmd | Cmd · Fn · Opt · Ctrl | Ctrl · Win · Win · Alt |
| Keys-To-Go 2 | Ctrl · Fn · Opt · Cmd | Cmd · Fn · Opt · Ctrl | Ctrl · Win · Win · Alt |

저장된 사용자 프로필의 목표값이 우선합니다. 이번 안정성 개선은 목표 배열과 Right Command → F16 전달 방식을 바꾸지 않습니다.

### VDI 앱 상태

| 구분 | 앱 | Bundle ID |
|---|---|---|
| 검증됨 | Omnissa Horizon Client | `com.omnissa.horizon.client.mac` |
| 자동 감지 / 미검증 | Omnissa Horizon Protocol | `com.omnissa.horizon.protocol` |
| 자동 감지 / 미검증 | VMware Horizon (Legacy) | `com.vmware.horizon` |
| 자동 감지 / 미검증 | VMware Fusion | `com.vmware.fusion` |
| 자동 감지 / 미검증 | Parallels Desktop | `com.parallels.desktop.console` |
| 자동 감지 / 미검증 | Microsoft RDP | `com.microsoft.rdc.macos` |

> 자동 감지는 앱 포커스 분기만 의미합니다. 실제 VDI 한/영 전환은 각 클라이언트의 `F16 → Right Alt` 매핑과 별도 검증이 필요합니다.

---

## 시스템 안전성

### 매핑 적용 확인과 복원

- 재부팅하면 모든 매핑이 자동으로 초기화됩니다
- 글로벌·장치별 매핑을 쓰기 전 현재 값을 읽고, 쓰기 후 다시 읽어 기대한 값과 비교합니다. 명령 종료 코드가 0이어도 읽은 값이 다르면 검증 실패입니다.
- 하나의 키보드가 여러 HID 서비스로 보일 수 있어 IOKit의 `UserKeyMapping` 속성을 서비스별로 확인·적용합니다. `hidutil`과 같은 HID 계층이며 새 드라이버는 추가하지 않습니다. 기본 프로필과 장치별 프로필의 목표값은 그대로 사용합니다.
- 다른 도구의 관련 없는 매핑을 보존합니다. 엔진 OFF·정상 종료 시 앱이 소유한 항목만 조건부 복원합니다. 다른 도구가 같은 키를 바꾼 경우 그 값을 덮어쓰지 않습니다.
- 읽기에 실패하면 빈 매핑으로 간주하지 않습니다. 복원을 확인하지 못한 상태는 진단에 남습니다.
- 강제 종료나 전원 장애에서는 정상 종료 복원을 보장하지 않습니다. 문제가 남으면 아래 수동 초기화 또는 재부팅으로 복구합니다.

### 수동 초기화 (비상시)

앱이 크래시하거나 매핑이 꼬였을 때:

먼저 엔진을 끄거나 앱을 정상 종료하세요. 아래 명령은 **지정 범위의 다른 도구 매핑도 삭제**하므로 조건부 복원 실패 후에만 사용합니다. 외장 키보드에는 해당 VID/PID 범위를 별도로 지정해야 합니다.

```bash
# 모든 HID 매핑 즉시 해제
hidutil property --set '{"UserKeyMapping":[]}'

# 내장 키보드 매핑도 해제
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --set '{"UserKeyMapping":[]}'

# Keys-To-Go 2 (046D:B38C) 매핑 해제
hidutil property --matching '{"VendorID":1133,"ProductID":45964}' --set '{"UserKeyMapping":[]}'
```

### 현재 매핑 상태 확인

```bash
# 글로벌 매핑
hidutil property --get UserKeyMapping

# 내장 키보드 매핑
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --get UserKeyMapping
```

---

## 메뉴바 아이콘

| 상태 | 아이콘 |
|------|--------|
| 엔진 OFF | `wm` (소문자, 회색) |
| 엔진 ON | `WM` (대문자, 굵게) |

한영 상태는 macOS 기본 입력소스 표시기가 담당합니다.
(메뉴바 우측의 EN / 한 아이콘)

---

## 문제 해결

### "Right Command를 눌러도 전환이 안 돼요"

메뉴바 → **Doctor**에서 진단을 실행하세요. 다음 상태를 따로 확인합니다.

1. **손쉬운 사용 / 입력 모니터링**: 현재 OS가 보고한 권한입니다. 과거 허용 이력이 있어도 지금 미허용인 이유를 서명 문제로 단정하지 않습니다. 필요한 권한만 시스템 설정에서 직접 확인하세요. TCC 초기화는 기존 확인 절차를 거친 경우에만 실행됩니다.
2. **엔진 / 이벤트 탭**: 엔진 ON과 이벤트 탭의 존재·유효성·활성 상태는 별개입니다.
3. **입력 관측 / F16 관측**: 일반 키와 Right Command를 누른 뒤 다시 진단하면 최근 관측 시간을 볼 수 있습니다. 앱 자체 합성 이벤트는 제외하며 입력한 문자는 기록하지 않습니다. 입력 관측이 없거나 오래됐다는 사실만으로 고장이라고 판정하지 않습니다.
4. **보안 입력(Secure Input)**: 켜져 있으면 이벤트 관측에 영향을 줄 수 있습니다. 비밀번호 입력을 마친 뒤 재확인하세요. 이 상태만으로 원인을 확정하거나 앱이 보안 입력을 해제하지 않습니다.
5. **HID 매핑 검증**: 마지막 적용·복원에서 읽어 확인한 결과입니다. 나중에 다른 도구가 변경했는지 계속 감시한다는 뜻은 아닙니다.

로컬 Mac에서는 **입력소스 전환 단축키가 Control+Space인지** 확인하세요(STEP 1). VDI는 아래의 Horizon 설정을 확인합니다. F16이 관측되었다고 원격 Windows 전환까지 성공한 것은 아닙니다.

### "Ghostty / Codex / Claude Code에서 `[57379u]` 같은 문자열이 입력돼요"

1. 최신 경로는 Ghostty/Codex 같은 terminal context에서 `F16 suppress + direct input-source switch + short terminal settle replay`를 사용합니다.
2. raw sequence뿐 아니라 검색 UI, `Cmd+N`, `Cmd+D` 같은 Command shortcut 누출이 없는지 먼저 확인하세요.
3. 현재까지는 `pasting text` 오버레이가 사라진 단계까지 확인되었습니다. 남은 확인 포인트는 미세한 끊김이 계속 있는지입니다.
4. 앱을 업데이트한 뒤 WinMac Key 엔진을 한 번 껐다가 다시 켭니다.
5. Ghostty 또는 Codex desktop이 현재 포커스 앱인지, 그리고 다른 리매퍼가 `Right Command` 또는 `F16`을 함께 처리하지 않는지 확인하세요.

### "VDI에서 한영전환이 안 돼요"

1. Omnissa Horizon 키 매핑 설정 확인 (STEP 5)
2. F16 → Right Alt 매핑이 있는지 확인
3. Windows 내에서 Right Alt가 한영전환 키로 설정되어 있는지 확인

### "VDI에서 Fn 키가 Ctrl로 안 바뀌어요"

```bash
# 현재 내장 키보드 매핑 확인
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --get UserKeyMapping
```

VDI 앱에 포커스가 있는 상태에서 위 명령 실행 → Fn→Ctrl 매핑이 보여야 합니다.

### "설정이 꼬였어요"

```bash
# 방법 1: 앱 내 초기화
# 메뉴바 WM → 설정 초기화...

# 방법 2: 터미널에서 수동 초기화
hidutil property --set '{"UserKeyMapping":[]}'
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --set '{"UserKeyMapping":[]}'

# 방법 3: 재부팅 (모든 hidutil 매핑이 자동 해제)
```
