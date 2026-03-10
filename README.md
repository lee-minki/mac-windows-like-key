# WinMac Key 🎹

<p align="center">
  <img src="WinMacKey/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="WinMac Key Icon">
</p>

<p align="center">
  <strong>macOS에서 Right Command로 한/영 전환</strong><br>
  <em>Right Command 한/영 전환 | 네이티브 VDI 지원 | 메뉴바 유틸리티</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a>
</p>

---

## ✨ Features

- **⌨️ Right Command / Right Option 전환**: macOS 입력 소스를 즉시 토글
- **🖥️ Native VDI Support**: 로컬 macOS/원격 Mac은 `Control+Space`, Windows VDI는 `F16 → Right Alt` 매핑으로 동작
- **📊 Event Viewer**: 실시간 키 입력 모니터링과 지연 시간 확인
- **🧩 Keyboard Profiles**: 현재 입력을 실키로 감지하고 `Mac 로컬` / `VDI` 목표 배치를 따로 저장
- **📍 Menu Bar Utility**: 상태 확인, 로그, Doctor, 업데이트 창에 빠르게 접근

---

## 📥 Installation

### Manual Download

1. [Releases](https://github.com/lee-minki/mac-windows-like-key/releases)에서 최신 DMG 또는 ZIP 다운로드
2. WinMac Key.app을 Applications 폴더로 드래그
3. 앱 실행 후 손쉬운 사용 권한 허용

### Build From Source

```bash
git clone https://github.com/lee-minki/mac-windows-like-key.git
cd mac-windows-like-key
xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/WinMacKey.app
```

---

## 🚀 Usage

### 1. 권한 설정

앱을 처음 실행하면 **손쉬운 사용** 권한을 요청합니다.

```
시스템 설정 → 보안 및 개인정보 보호 → 손쉬운 사용 → WinMac Key ✓
```

### 2. 입력 소스 단축키 확인

```
시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스
```

- **"이전 입력 소스 선택"** 이 켜져 있어야 합니다
- 단축키는 반드시 `Control + Space` 여야 합니다

### 3. 엔진 활성화

메뉴바에서 WinMac Key 아이콘 클릭 → 엔진 활성화 (`WM`)

### 4. Event Viewer로 확인

키 입력이 정상적으로 캡처되고 있는지 Event Viewer에서 확인하세요.

### 5. 키보드 프로필 참고

- 프로필 위저드에서는 먼저 키캡 프린팅이 `Mac 키보드`인지 `Windows 키보드`인지 선택합니다
- 다음 단계에서 스페이스바 왼쪽 modifier를 실제로 누르고 마지막에 `Space`를 눌러 현재 입력을 감지합니다
- `Windows 키보드`를 고르면 현재 입력 단계에서 `키캡 기준`과 `macOS 입력`을 함께 보여줘 `Win`/`Alt` 뒤바뀜을 바로 확인할 수 있습니다
- `Space` 앞에 감지된 키 개수에 따라 3키/4키가 자동으로 정해집니다
- `Mac 로컬` 단계는 항상 `Fn / Ctrl / Cmd / Opt` 기준으로 왼쪽부터 배치를 선택합니다
- `VDI` 단계는 항상 `Ctrl / Win / Alt` 기준으로 왼쪽부터 배치를 선택합니다
- 목표 슬롯을 직접 누른 뒤 기능 키를 선택하면 해당 위치를 바로 바꿀 수 있습니다
- 3키 키보드에서는 `RCtrl`, `Caps`, `RShift` 중 하나를 보조 `Fn` 키로 지정할 수 있습니다
- 프로필 이름은 구분용 라벨입니다
- 저장된 프로필은 현재 앱 컨텍스트에 따라 `Mac 로컬` 목표와 `VDI` 목표 사이를 자동으로 전환합니다
- 프로필 자동 할당은 키보드 장치명이 아니라 현재 앱의 Bundle ID 기준으로 동작합니다

### 6. 권장 추가 설정

- `Caps Lock 키로 ABC 입력 소스 전환`은 꺼두는 것을 권장합니다
- Windows VDI를 사용한다면 클라이언트에서 `F16 → Right Alt` 매핑을 추가하세요

---

## 💎 VDI 지원

별도 가상 키보드 드라이버 없이 동작합니다. WinMac Key는
- 로컬 macOS 및 원격 Mac 세션에서는 `Control+Space`
- Windows VDI 앱 포커스에서는 `F16`
를 상황에 맞게 전송합니다.

### 검증된 환경

| 앱 | Bundle ID |
|---|---|
| Omnissa Horizon Client | `com.omnissa.horizon.client.mac` |

> 그 외 VMware Fusion, Parallels Desktop, Microsoft RDP, VirtualBox도 코드에서 자동 감지하지만 아직 테스트되지 않았습니다.

---

## 🖥️ VMware / VDI 하이브리드 한영 전환

VMware Horizon 등 가상화 앱에서 한/영 전환이 안 되는 문제를 기본적으로 해결합니다.
**가상 키보드 드라이버 등 별도의 시스템 확장프로그램이 전혀 필요 없는 완전한 네이티브 방식**을 사용합니다.

WinMac Key가 Windows VDI 앱에 포커스된 것을 자동 감지하면 `F16` 릴레이 키를 발생시키고,
VDI 클라이언트(Omnissa 등)가 이를 윈도우의 `Right Alt`로 변환하도록 구성할 수 있습니다.

**→ [VDI 매핑 및 설정 가이드](docs/VDI_SETUP.md)**

---

## 🔧 Technical Details

### 시스템 요구사항

- macOS 14.0 (Sonoma) 이상
- Apple Silicon 또는 Intel Mac

### 사용 기술

- **CGEventTap**: 키보드 이벤트 인터셉트 및 키코드 리매핑
- **hidutil**: HID 레벨 modifier 키 리매핑 (Fn/Ctrl/Cmd/Option)
- **SwiftUI + MenuBarExtra**: 네이티브 메뉴바 유틸리티

### 성능

- 평균 지연 시간: **< 0.5ms**
- CPU 사용량: **< 0.5%**
- 메모리 사용량: **< 20MB**

---

## 🤝 Contributing

기여를 환영합니다!

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

MIT License - 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

---

## 💖 Support

이 프로젝트가 유용하다면 **$1 후원**을 고려해주세요!

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/lee-minki)

---

<p align="center">
  Made with ❤️ for macOS users who want better keyboard control
</p>
