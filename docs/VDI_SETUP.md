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

1. 사용자가 **Right Command** (우측 커맨드)를 누름
2. WinMac Key가 이를 가로채서 **F16** 릴레이 키를 전송
3. **Omnissa Horizon Client** 등 VDI 클라이언트가 해당 키를 감지
4. VDI 내장 매핑을 통해 윈도우의 **Right Alt** (한/영 전환)로 변환되어 전달됨
5. 윈도우 OS에서 자연스럽게 한영이 전환됨!

---

## 🛠️ 설정 방법 (Omnissa Horizon 기준)

별도의 앱이나 드라이버 설치 없이, VDI 클라이언트 자체 설정만 맞춰주면 끝납니다.

### 1. Mac 로컬 설정

- 로컬 macOS 및 원격 Mac 세션을 쓸 예정이라면,
  `시스템 설정` > `키보드` > `키보드 단축키...` > `입력 소스`에서
  **이전 입력 소스 선택**이 `^ Space` (Control+Space)로 설정되어 있는지 확인합니다.

### 2. Omnissa Horizon Client 설정

1. Omnissa Horizon Client 실행
2. 상단 메뉴 막대  > **설정(Preferences)** (단축키: `Cmd + ,`)
3. **키보드 및 마우스 (Keyboard & Mouse)** 탭으로 이동
4. **키 매핑 (Key Mapping)** 탭 선택
5. **[ + ] 버튼을 눌러 새 매핑 추가:**
   - **Mac 단축키 (From):** `F16`
   - **Windows 단축키 (To):** `Right Alt` (우측 Alt)
6. 체크박스를 켜서 활성화(Enable) 상태로 만듭니다.

### 3. WinMac Key 실행

- WinMac Key를 실행한 뒤 메뉴바에서 엔진을 켭니다. (`WM` 상태)
- VDI 창에 포커스가 맞춰지면, 우측 Command(또는 Option)를 누를 때마다 이 매핑을 타고 윈도우 한영이 부드럽게 전환됩니다.
- 외장 키보드 프로필을 쓸 경우 `Windows / VDI` 표기를 선택한 뒤, 현재 입력과 `Mac 로컬` / `VDI` 목표 배치를 각각 따로 저장할 수 있습니다.
- 위저드에서는 `Win (Cmd)`, `Alt (Opt)`처럼 실제 macOS 입력명까지 함께 표시되므로, 키캡 인쇄와 실제 입력이 달라도 목록에서 직접 고르면 됩니다.

---

## ❓ 문제 해결 (Troubleshooting)

### Q. 전환할 때마다 윈도우 시작 메뉴가 같이 열립니다

A. 매핑이 `Win` 키나 꼬인 `Alt` 로 넘어간 경우입니다. Horizon 키 매핑 설정에서 `F16 → Right Alt`가 정확히 잡혀 있는지 확인하세요.

### Q. 눌러도 아무 반응이 없습니다

A.

1. Horizon Client에 `F16 → Right Alt` 매핑이 정확히 들어가 있는지 확인하세요.
2. WinMac Key의 Dashboard 메뉴에서 "트리거 키"가 본인이 누르는 키(`rightCmd` 등)로 잘 설정되어 있는지 확인하세요.
3. Karabiner-Elements에서 Complex Rules (특히 Right Command -> F18, 한/영 등)가 켜져 있다면, **WinMac Key와 충돌하므로 반드시 꺼야 합니다.**

### Q. 글자가 밀리거나 씹히는 현상은 없나요?

A. 네! 기존 `TISSelectInputSource` API의 고질적인 버그(조합 중인 한국어 글자 지워짐)를 원천적으로 우회하는 **OS 레벨 단축키 합성**을 사용하기 때문에 매우 매끄럽게 입력됩니다.
