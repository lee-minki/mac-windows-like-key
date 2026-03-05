# VMware VDI 한/영 전환 설정 가이드

WinMac Key의 **VDI 모드**를 사용하면 VMware Horizon, VMware Fusion 등 가상화 앱에서도  
Right Command 키로 한/영 전환이 가능합니다.

## 왜 필요한가?

VMware는 일반적인 macOS 키 이벤트(`CGEventTap`)를 무시하고, **물리 HID 디바이스**에서 직접 키를 읽습니다.  
WinMac Key는 Karabiner DriverKit의 **가상 키보드**를 통해 이 제한을 우회합니다.

```
물리 키보드 → WinMac Key (가로챔) → 가상 키보드에서 Right Alt 발생
                                      └── VMware: "Right Alt구나!" ✅
```

---

## 설치 절차

### 1단계: Karabiner DriverKit 드라이버 설치

```bash
# GitHub Releases에서 .pkg 다운로드 후 설치
# https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases
```

또는 Karabiner-Elements가 이미 설치되어 있다면 드라이버도 함께 설치되어 있습니다.

### 2단계: 드라이버 활성화

```bash
open "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
```

시스템 설정 > 일반 > 로그인 항목에서 드라이버 확장을 **허용**하세요.

### 3단계: 데몬 실행 확인

```bash
sudo ls "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/"
# .sock 파일이 보이면 정상
```

### 4단계: KarabinerHelper 빌드

```bash
# 사전 요구사항
brew install xcodegen

# 빌드
./scripts/build_karabiner_helper.sh
```

### 5단계: WinMac Key 실행

앱을 실행하면 자동으로 Karabiner 드라이버를 감지하고 VDI 모드를 활성화합니다.  
메뉴바에서 **가상 HID 키보드** 상태가 🟢 Ready로 표시되면 준비 완료입니다.

---

## 진단

WinMac Key의 **Doctor** 기능에서 Karabiner 관련 상태를 확인할 수 있습니다:

| 항목 | 설명 |
|---|---|
| Karabiner 드라이버 | 설치 여부 |
| Karabiner 데몬 | 소켓 실행 여부 |
| 가상 HID 키보드 | 연결 상태 |

---

## 지원되는 가상화 앱

| 앱 | Bundle ID |
|---|---|
| VMware Horizon (Omnissa) | `com.vmware.horizon` |
| VMware Fusion | `com.vmware.fusion` |
| Parallels Desktop | `com.parallels.desktop.console` |
| Microsoft RDP | `com.microsoft.rdc.macos` |
| Apple Screen Sharing | `com.apple.ScreenSharing` |

---

## 문제 해결

### "가상 HID 미연결" 표시

1. Karabiner 드라이버가 설치되었는지 확인
2. `open "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"` 실행
3. 시스템 설정에서 드라이버 확장 허용

### "헬퍼 바이너리 없음" 표시

```bash
./scripts/build_karabiner_helper.sh
```

### Karabiner-Elements와 충돌

Karabiner-Elements와 WinMac Key를 동시에 사용하면 키 가로채기가 충돌할 수 있습니다.  
Karabiner에서 빈 프로필을 선택하거나, WinMac Key의 Doctor에서 충돌을 확인하세요.
