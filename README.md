# WinMac Key 🎹

<p align="center">
  <img src="assets/icon.png" width="128" alt="WinMac Key Icon">
</p>

<p align="center">
  <strong>macOS에서 CapsLock을 당신의 방식대로</strong><br>
  <em>The Silencer: 순수한 CapsLock | VMware 지원 (Pro)</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#pro-features">Pro Features</a> •
  <a href="#contributing">Contributing</a>
</p>

---

## ✨ Features

### Free Edition

- **🔇 The Silencer**: CapsLock을 순수한 CapsLock으로 - 지연 없이 즉각 반응
- **📊 Event Viewer**: 실시간 키 입력 모니터링 (0.1ms 단위 지연시간 표시)
- **📍 Menu Bar 상주**: 항상 접근 가능한 상태 표시

### Pro Edition ($1+ 후원)

- **🖥️ Context Awareness**: 앱별 자동 프로필 전환
- **🪟 VMware Support**: Windows 스캔코드 전송 (한/영 전환)
- **📝 Custom Profiles**: 무제한 프로필 생성

---

## 📥 Installation

### Homebrew (권장)

```bash
brew install --cask winmac-key
```

### Manual Download

1. [Releases](https://github.com/lee-minki/winmac-key/releases)에서 최신 DMG 다운로드
2. WinMac Key.app을 Applications 폴더로 드래그
3. 앱 실행 후 손쉬운 사용 권한 허용

---

## 🚀 Usage

### 1. 권한 설정

앱을 처음 실행하면 **손쉬운 사용** 권한을 요청합니다.

```
시스템 설정 → 보안 및 개인정보 보호 → 손쉬운 사용 → WinMac Key ✓
```

### 2. The Silencer 활성화

메뉴바에서 WinMac Key 아이콘 클릭 → 엔진 활성화

### 3. Event Viewer로 확인

키 입력이 정상적으로 캡처되고 있는지 Event Viewer에서 확인하세요.

---

## 💎 Pro Features

Pro 버전은 **$1 이상 후원**하신 분들을 위한 기능입니다.

[![Sponsor](https://img.shields.io/badge/Sponsor-❤️-pink?style=for-the-badge)](https://github.com/sponsors/lee-minki)

### VMware / Parallels 지원

가상화 앱에서 자동으로 Windows 모드로 전환하여 CapsLock이 한/영 전환으로 동작합니다.

### 지원되는 앱

| 앱 | Bundle ID |
|---|---|
| VMware Horizon | `com.vmware.horizon` |
| VMware Fusion | `com.vmware.fusion` |
| Parallels Desktop | `com.parallels.desktop.console` |
| Microsoft RDP | `com.microsoft.rdc.macos` |

---

## 🖥️ VMware VDI 한/영 전환

VMware Horizon 등 가상화 앱에서 한/영 전환이 안 되는 문제를 해결합니다.  
Karabiner DriverKit의 가상 키보드를 통해 Right Alt 키를 VMware에 직접 전달합니다.

**→ [VDI 설정 가이드](docs/VDI_SETUP.md)**

### 요구사항

- [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases) 설치
- `xcodegen` (`brew install xcodegen`)
- KarabinerHelper 빌드: `./scripts/build_karabiner_helper.sh`

---

## 🔧 Technical Details

### 시스템 요구사항

- macOS 13.0 (Ventura) 이상
- Apple Silicon 또는 Intel Mac

### 사용 기술

- **IOKit HIDManager**: 저수준 키보드 이벤트 후킹
- **SwiftUI**: 현대적인 macOS UI
- **MenuBarExtra**: 네이티브 메뉴바 통합

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
