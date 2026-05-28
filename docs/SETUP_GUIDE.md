# WinMac Key v1.5.0 설정 가이드

## 변경 요약

한영전환 방식이 다음처럼 분리되었습니다.
- 로컬 macOS: `Control+Space 시스템 단축키 주입`
- Windows VDI: `F16 릴레이 키 주입`
- Mac → Mac 원격 / 화면 공유: 로컬 맥북의 입력소스만 토글 → 변환된 문자가 원격 화면에 forward (원격 Mac 에는 설치 불필요, v1.3.5+)

### 개선된 점
- **(v1.4.0) 프로필 위자드 Fn(🌐) 감지**: 내장 맥북의 Fn 키를 IOHID 레벨에서 직접 감지(Apple Vendor Top Case). 감지가 막히는 맥에서는 Step 2 의 `+ Fn 🌐` 버튼으로 4키 구성을 등록할 수 있습니다. (위자드의 핵심 구분은 표기가 아니라 좌측 3키 vs 4키)
- **F16 HID remap 아키텍처**: `hidutil`로 Right Command를 F16으로 HID 레벨 변환 — modifier flag 오염 원천 차단
- VDI에서 한/영+Shift+P 시 Win+P 팔업 문제 해결
- 빠른 영문 대문자 입력 시 Windows 키 조합 오발 해결
- 메뉴바 아이콘이 macOS 네이티브 입력소스 표시기로 동기화
- Windows VDI(Omnissa Horizon 등)에서 F16 패스스루 → Right Alt 변환으로 동작
- Karabiner DriverKit 완전 불필요
- IOKit 기반 외장 키보드 자동 감지 및 디바이스별 프로필 자동 전환

---

## STEP 0: 최초 실행 (서명·공증 완료)

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
open build/DerivedData/Build/Products/Debug/WinMacKey.app
```

또는 Xcode에서 `Cmd+R`

### 엔진 활성화

1. 메뉴바에 `wm` (소문자) 이 보이면 클릭
2. 엔진 토글 ON
3. `WM` (대문자)로 변경 확인

### 재부팅 후 자동 실행 옵션

재부팅 후 매번 앱을 직접 켜기 싫다면 다음 두 옵션을 함께 켜세요.

1. 메뉴바 `wm/WM` 클릭 → **설정...**
2. **General → Startup** 카드에서 **로그인 시 자동 실행** ON
3. 같은 카드에서 **앱 실행 후 엔진 자동 시작** ON
4. 상태가 `승인 필요`로 나오면 **로그인 항목 설정 열기**를 눌러 시스템 설정에서 WinMac Key를 허용

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
  내장 키보드: Fn→Cmd, Cmd→Ctrl, Ctrl→Fn (Mac 프로필)

[VDI 앱 포커스] (자동 전환)
  Right Cmd → hidutil HID remap → F16 → 패스스루 → Horizon이 F16 → Right Alt 변환
  Caps Lock → 시스템 기본 동작 유지 (앱이 소유하지 않음)
  내장 키보드: Fn→Ctrl, Ctrl→Fn (VDI 프로필 - 자동 적용)

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

## 내장 키보드 자동 매핑 전환

VDI 앱에 포커스가 가면 **내장 키보드의 Fn 매핑이 자동으로 변경**됩니다.
외장 키보드는 저장된 프로필이 있다면 같은 시점에 `Mac 로컬` 목표와 `VDI` 목표 사이를 자동 전환합니다.

| 모드 | 물리 Fn | 물리 Ctrl | 물리 Cmd |
|------|---------|----------|---------|
| Mac 로컬 | → Cmd | → Fn | → Ctrl |
| VDI 모드 | → Ctrl | → Fn | (글로벌 매핑) |

- VDI 앱을 열면 자동으로 VDI 매핑 적용
- VDI 앱에서 나오면 자동으로 Mac 매핑 복귀
- 외장 USB 키보드는 프로필을 만들지 않았다면 기본 배치로 동작하고, 프로필을 만들었다면 저장된 VDI 배치로 함께 전환됩니다
- 내장 키보드도 Profiles 탭에서 "Assign current keyboard"로 등록하면 항상 해당 프로필이 우선 적용됩니다
- 외장 키보드를 Profiles 탭에서 "Assign current keyboard"로 등록하면, 키보드를 꽂는 순간 해당 프로필이 자동 적용됩니다

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

### hidutil 매핑은 안전합니다

- 재부팅하면 모든 매핑이 자동으로 초기화됩니다
- WinMac Key 앱 종료 시 모든 매핑을 자동 해제합니다 (글로벌 + 디바이스별)
- 앱이 비정상 종료되어도 재부팅하면 원상복구됩니다

### 수동 초기화 (비상시)

앱이 크래시하거나 매핑이 꼬였을 때:

```bash
# 모든 HID 매핑 즉시 해제
hidutil property --set '{"UserKeyMapping":[]}'

# 내장 키보드 매핑도 해제
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' --set '{"UserKeyMapping":[]}'
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

1. 엔진이 켜져 있는지 확인 (메뉴바 `WM`)
2. 손쉬운 사용 권한 확인
3. **macOS 입력소스 전환 단축키가 Control+Space인지 확인** (STEP 1)
4. Event Viewer → Right Cmd 이벤트가 잡히는지 확인

### "Ghostty / Claude Code에서 `[57379u]` 같은 문자열이 입력돼요"

1. 최신 경로는 Ghostty 같은 terminal context에서 `F16 suppress + direct input-source switch`를 사용합니다.
2. raw sequence뿐 아니라 검색 UI, `Cmd+N`, `Cmd+D` 같은 Command shortcut 누출이 없는지 먼저 확인하세요.
3. 현재까지는 `pasting text` 오버레이가 사라진 단계까지 확인되었습니다. 남은 확인 포인트는 미세한 끊김이 계속 있는지입니다.
4. 앱을 업데이트한 뒤 WinMac Key 엔진을 한 번 껐다가 다시 켭니다.
5. Ghostty가 현재 포커스 앱인지, 그리고 다른 리매퍼가 `Right Command` 또는 `F16`을 함께 처리하지 않는지 확인하세요.

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
