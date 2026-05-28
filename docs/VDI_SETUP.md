# VMware / VDI 하이브리드 한영 전환 가이드

WinMac Key는 VDI (가상 데스크톱) 환경에서도 Windows와 동일한 감각으로 우측 Command 등을 이용해 한/영 전환을 할 수 있도록 설계되었습니다.

기존 버전과 달리 **별도의 가상 키보드 드라이버(Karabiner 등) 설치가 전혀 필요 없는 네이티브(Native) 방식**을 사용합니다.

---

## 💡 지원되는 환경 (검증됨)

- **Omnissa Horizon Client** (VMware Horizon)
- **Windows 10 / 11** (VDI 내부 OS)

---

## ⚙️ 동작 원리 (하이브리드 전환)

WinMac Key는 VDI 앱이 켜져 있는지 자동으로 감지하여 가장 안전한 방식으로 단축키를 중계합니다.

1. `hidutil`이 **Right Command**를 **F16**으로 HID 레벨에서 변환 (modifier flag 없음)
2. F16 이벤트가 **Omnissa Horizon Client**에 그대로 전달 (패스스루)
3. VDI 내장 매핑을 통해 윈도우의 **Right Alt** (한/영 전환)로 변환되어 전달됨
4. 윈도우 OS에서 자연스럽게 한영 전환이 동작함
5. Caps Lock은 WinMac Key가 직접 처리하지 않으며, 시스템/클라이언트 기본 동작에 맡깁니다.

---

## 🛠️ 설정 방법 (Omnissa Horizon 기준)

별도의 앱이나 드라이버 설치 없이, VDI 클라이언트 자체 설정만 맞춰주면 끝납니다.

### 1. Mac 로컬 설정

- 로컬 macOS에서 Control+Space를 쓰려면
  `시스템 설정` > `키보드` > `키보드 단축키...` > `입력 소스`에서
  **이전 입력 소스 선택**이 `^ Space` (Control+Space)로 설정되어 있는지 확인합니다.
- 원격 Mac / 화면 공유 세션은 아직 별도 검증 전이므로 로컬 macOS와 동일하게 동작한다고 가정하지 않습니다.

### 2. Omnissa Horizon Client 설정

1. Omnissa Horizon Client 실행
2. 상단 메뉴 막대  > **설정(Preferences)** (단축키: `Cmd + ,`)
3. **키보드 및 마우스 (Keyboard & Mouse)** 탭으로 이동
4. **키 매핑 (Key Mapping)** 탭 선택
5. **[ + ] 버튼을 눌러 새 매핑 추가:**
   - **Mac 단축키 (From):** `F16`
   - **Windows 단축키 (To):** `Right Alt` (우측 Alt)
6. 체크박스를 켜서 활성화(Enable) 상태로 만듭니다.

> ✅ **한/영 전환에 필수인 매핑은 `F16 → Right Alt (AltGr)` 단 하나입니다.** 이 항목의 체크박스가 켜져 있어야 WinMac Key 의 VDI 한영이 동작합니다.

#### (선택) Mac 단축키를 VDI 안에서도 쓰기

Horizon 키 매핑 탭에서 아래 항목들을 추가·활성화하면, VDI 안의 Windows 에서도 Mac 손가락 습관(⌘ 기반)을 그대로 쓸 수 있습니다. **한/영 전환과 무관한 편의 설정이며, 필요 없으면 끄거나 추가하지 않아도 됩니다.**

| Mac 단축키 | Windows 단축키 | 용도 |
|---|---|---|
| ⌘Z / ⌘X / ⌘C / ⌘V | Ctrl-Z / X / C / V | 실행취소·잘라내기·복사·붙여넣기 |
| ⌘A / ⌘S / ⌘F / ⌘P | Ctrl-A / S / F / P | 전체선택·저장·찾기·인쇄 |
| ⌘G | F3 | 다음 찾기 |
| ⌘W | Alt-F4 | 창 닫기 |
| Shift-Option-Tab | ⊞(Win)-Tab | 작업 보기(Task View) 창 전환 |

> ⚠️ **`기본값 복원`(Restore Defaults) 버튼을 누르면 `F16 → Right Alt` 매핑도 함께 사라집니다.** 복원 후에는 F16 매핑을 다시 추가하세요.

### 3. WinMac Key 실행

- WinMac Key를 실행한 뒤 메뉴바에서 엔진을 켭니다. (`WM` 상태)
- VDI 창에 포커스가 맞춰지면, 우측 Command를 누를 때마다 F16 릴레이를 타고 윈도우 한영이 부드럽게 전환됩니다.
- Caps Lock은 앱이 직접 중계하지 않습니다. 필요 시 시스템/클라이언트 기본 동작을 별도로 확인하세요.
- 외장 키보드 프로필을 쓸 경우 먼저 키캡 프린팅이 `Windows 키보드`인지 고르고, 다음 단계에서 스페이스바 왼쪽 modifier를 실제로 누른 뒤 `Space`로 현재 입력을 확정합니다.
- 현재 입력 단계에서는 `키캡 기준`과 `macOS 입력`을 함께 보여줘 `Win`/`Alt`가 실제로 어떻게 들어오는지 바로 볼 수 있습니다.
- `Space` 앞에 감지된 개수에 따라 3키/4키가 자동으로 정해지며, `Mac 로컬` 배치와 `VDI` 배치를 각각 따로 잡을 수 있습니다.
- 로컬 Mac 단계는 `Fn / Ctrl / Cmd / Opt`, VDI 단계는 `Ctrl / Win / Alt`만 보여주고, 슬롯을 직접 눌러 바로 교체할 수 있습니다.

---

## 🛡️ VDI 고스트 키 방지

한영전환 직후 빠르게 타이핑할 때 Windows 화면녹화(Win+Shift+R), "다른 화면에 표시"(Win+P) 등이 발생하는 문제를 방지합니다.

### 이전 원인

이전 버전에서는 Right Command(modifier 키)를 CGEventTap으로 가로채서 한영전환을 처리했습니다. modifier 키의 플래그가 후속 키스트로크에 잔존하면서 Win+Key 조합으로 오발되는 문제가 있었습니다.

### 현재 해결 방식 (v1.3.0+)

WinMac Key는 `hidutil` HID 레벨 remap을 사용하여 트리거 키(Right Command)를 **F16**(일반 function key)로 변환합니다.

- F16은 **modifier 키가 아니므로** 후속 키스트로크에 modifier flag가 발생하지 않음
- Win+P, Win+Shift+R 등의 조합 오발이 **원천적으로 차단**됨
- VDI 모드에서는 F16을 그대로 패스스루해 Horizon이 Right Alt로 변환

---

## ❓ 문제 해결 (Troubleshooting)

### Q. 전환할 때마다 윈도우 시작 메뉴가 같이 열립니다

A. 매핑이 `Win` 키나 꼬인 `Alt` 로 넘어간 경우입니다. Horizon 키 매핑 설정에서 `F16 → Right Alt`가 정확히 잡혀 있는지 확인하세요.

### Q. VDI에서 Caps Lock이 기대대로 동작하지 않거나 로컬 Mac만 반응합니다

A.

1. WinMac Key는 Caps Lock을 직접 중계하지 않습니다.
2. VDI 클라이언트와 원격 Windows의 기본 Caps Lock 처리 경로를 먼저 확인하세요.
3. 로컬 macOS에서만 Caps Lock 반응을 원치 않는 경우, 시스템 `Caps Lock 키로 ABC 입력 소스 전환` 설정을 확인하세요.

### Q. 한영전환 후 Shift+영문을 치면 화면녹화나 앱이 실행됩니다

A. v1.3.0 이상으로 업데이트하세요. F16 HID remap 아키텍처로 modifier flag 오염이 원천 차단됩니다.

### Q. 눌러도 아무 반응이 없습니다

A.

1. Horizon Client에 `F16 → Right Alt` 매핑이 정확히 들어가 있는지 확인하세요.
2. WinMac Key는 Right Command 단일 트리거 모델입니다. 메뉴바가 `WM` 상태인지, 손쉬운 사용 권한이 허용되어 있는지 확인하세요.
3. Karabiner-Elements에서 Complex Rules (특히 Right Command -> F16/F18, 한/영 등)가 켜져 있다면, **WinMac Key와 충돌하므로 반드시 꺼야 합니다.** F18은 과거 relay 실험/외부 규칙 잔재로만 취급하세요.

### Q. 글자가 밀리거나 씹히는 현상은 없나요?

A. 네! 기존 `TISSelectInputSource` API의 고질적인 버그(조합 중인 한국어 글자 지워짐)를 원천적으로 우회하는 **OS 레벨 단축키 합성**을 사용하기 때문에 매우 매끄럽게 입력됩니다.
