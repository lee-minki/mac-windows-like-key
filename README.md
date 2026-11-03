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

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift" alt="Swift / SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/signed-Apple%20notarized-success?logo=apple" alt="Apple notarized">
</p>

---

> **TL;DR (English):** A native macOS menu-bar utility for people who use Windows-style keyboards or VDI on a Mac.
> It remaps **Right Command → Korean/English IME toggle** via a HID-level `hidutil` remap (no modifier-flag pollution),
> keeps **per-device keyboard profiles active simultaneously** (built-in and external) through IOKit, and passes F16 to
> **Omnissa Horizon** without a virtual keyboard driver or system extension. Apple Screen Sharing remains unverified.
> See the [setup guide](docs/SETUP_GUIDE.md).
> Official v1.8.5 downloads are signed, Apple-notarized builds for Apple Silicon.

---

## ✨ Features

- **⌨️ Right Command 전환**: 기본 방식은 오른쪽 ⌘를 `F16`으로 변환합니다. 개발본의 로컬 옵션은 `F17`을 macOS 입력 소스 단축키로 사용합니다.
- **🖥️ Native VDI Support**: Horizon에서는 `F16`을 클라이언트에 전달합니다.
- **🔌 Simultaneous Per-Device Profiles**: 내장·외장 키보드 프로필을 VID:PID별로 동시에 적용해 번갈아 입력해도 첫 키부터 정확
- **🛡️ VDI Ghost Key Prevention**: F16 HID remap으로 modifier flag 오염 원천 차단 (Win+P, Alt+key 등 방지)
- **📝 IME Commit Guard**: 입력소스 변경 확인 + 최소 홀드로 첫 글자 영어 입력과 전환 누락 완화
- **📊 Event Viewer**: 실시간 키 입력 모니터링과 지연 시간 확인
- **🧩 Keyboard Profiles**: 현재 입력을 실키로 감지하고 `Mac 로컬` / `VDI` 목표 배치를 따로 저장
- **🔁 Login Startup**: 재부팅 후 자동 실행과 앱 실행 시 엔진 자동 시작 옵션 제공
- **📍 Menu Bar Utility**: 상태 확인, 로그, Doctor, 업데이트 창에 빠르게 접근
- **🧍 Single Instance**: Applications 설치본을 우선하고 다른 복사본의 동시 입력 엔진 실행을 차단

---

## 📥 Installation

### Manual Download

1. [Releases](https://github.com/lee-minki/mac-windows-like-key/releases)에서 최신 DMG 또는 ZIP 다운로드
2. WinMac Key.app을 Applications 폴더로 드래그
3. **더블클릭으로 바로 실행** (v1.3.8+ 는 Apple 공증 빌드라 Gatekeeper 경고 없음)
4. 앱 실행 후 손쉬운 사용 권한 허용

> v1.3.8 부터 **Apple Developer ID 서명 + 공증(Notarization)** 을 거쳐 배포되므로 별도 우회 없이 더블클릭으로 실행됩니다. (v1.3.7 이하 구버전이나 직접 빌드한 미서명 빌드만 우클릭 → "열기" 또는 `xattr -dr com.apple.quarantine /Applications/WinMacKey.app` 가 한 번 필요합니다.)

이미 사용 중이라면 → **[재설치 가이드](docs/REINSTALL_GUIDE.md)** (업그레이드 / 클린 재설치 / 자동 업데이트가 막혔을 때)

### Build From Source

```bash
git clone https://github.com/lee-minki/mac-windows-like-key.git
cd mac-windows-like-key
xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey -configuration Debug -derivedDataPath build/DerivedData build
WINMACKEY_ALLOW_NONSTANDARD_INSTANCE=1 build/DerivedData/Build/Products/Debug/WinMacKey.app/Contents/MacOS/WinMacKey
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

이 개발본에는 **Mac에서 입력 소스를 직접 전환하는 선택 옵션**도 있습니다. 오른쪽 ⌘를 macOS의 ‘다음 입력 소스 선택’ 키(`F17`)로 쓰면, 일반 입력칸에서 전환할 때 WinMac Key가 키를 먼저 감지할 필요가 없습니다. 사용하는 방법과 원래 설정으로 돌아가는 방법은 [설정 가이드](docs/SETUP_GUIDE.md#native-local-ime)를 참고하세요.

### 3. 엔진 활성화

메뉴바에서 WinMac Key 아이콘 클릭 → 엔진 활성화 (`WM`)

### 4. Event Viewer로 확인

키 입력이 정상적으로 캡처되고 있는지 Event Viewer에서 확인하세요.

### 5. 키보드 프로필 참고

- 프로필 위자드는 **3화면 표 기반** (캡처 없음, v1.8.3+):
  - **시작·의도**: 프로필 이름 + 의도 선택 — `"한/영 전환만"`(1클릭 즉시 완료, 식별 프로필) / `"키 배치도 바꾸기"`(표 화면으로)
  - **매핑 표**: 선택한 키보드 형태의 3행/4행 × `Mac 에서` / `VDI 에서` 2열 picker. 각 행에서 목표 키를 직접 선택
  - **확인·저장**: 매핑 요약 확인 후 저장
- Keys-To-Go 2처럼 왼쪽 키가 `Ctrl · Fn · Opt · Cmd` 순서면 **포터블 Mac 4키**를 선택합니다. `키 배치 바꾸기`의 추천값은 `Cmd · Fn · Opt · Ctrl`입니다.
- 매핑 표를 만드는 데는 키 입력이 필요 없습니다. **이 키보드에만** 저장할 때 연결 장치가 하나면 자동 선택되고, 여러 대면 대상 외장 키보드의 키를 한 번 눌러 식별합니다.
- 기존 프로필의 보조 Fn 키 설정은 편집 시 자동 보존 (UI 미노출, 변경하려면 삭제 후 재생성)
- 프로필 이름은 구분용 라벨입니다
- 장치에 바인딩한 프로필은 모두 동시에 적용되며, 현재 앱 컨텍스트에 따라 각 장치가 `Mac 로컬` 목표와 `VDI` 목표 사이를 함께 전환합니다
- 프로필 자동 할당은 키보드 디바이스(VendorID/ProductID) 또는 앱의 Bundle ID 기준으로 동작합니다
- Profiles 탭에서 **"Bind keyboard…"** 버튼을 누르면 모달이 뜨고, 바인딩할 키보드의 키를 한 번 누르면 디바이스 정보(이름·VID:PID·내장/외장)를 확인한 뒤 바인딩이 완료됩니다 (v1.3.6+ Press-to-bind UX)
- 한 디바이스에는 하나의 프로필만 바인딩됩니다. 다른 프로필에 이미 바인딩된 키보드를 다시 바인딩하면 자동으로 이전됩니다
- 키 입력으로 단일 프로필을 갈아끼우지 않습니다. 바인딩된 내장·외장 프로필은 장치별로 항상 적용되고, `마지막 입력` 표시는 상태 확인용입니다

### 6. 권장 추가 설정

- `Caps Lock 키로 ABC 입력 소스 전환`은 로컬 macOS에서 순수 Caps Lock을 쓰려면 꺼두는 것을 권장합니다
- Omnissa Horizon을 사용한다면 Horizon 클라이언트에서 `F16 → Right Alt` 매핑을 추가하세요.
- 재부팅 후 바로 쓰려면 `설정 → General → Startup`에서 `로그인 시 자동 실행`과 `앱 실행 후 엔진 자동 시작`을 함께 켜세요
- 기본 F16 방식에서는 Ghostty, Terminal.app, iTerm2, Codex desktop 같은 터미널류 앱이 F16을 로컬에서 숨기고 입력소스를 직접 전환한 뒤, 첫 일반 문자만 짧게 보류·재생합니다. Command/Control/Option 조합과 Return/Tab/Escape는 즉시 통과합니다. `[57379u` raw sequence, `Cmd+N` shortcut 누출, 전환 직후 첫 글자의 로마자 입력이 보이면 terminal regression으로 기록해 확인하세요.
- 새 릴리스 확인은 기본으로 켜져 있으며, 설치는 사용자 확인 후 `/Applications/WinMacKey.app`을 제자리 교체합니다. GitHub의 Draft/Pre-release는 자동 업데이트 대상이 아닙니다.

---

## 💎 VDI 지원

Omnissa Horizon에 포커스하면 WinMac Key는 로컬 F17 옵션 사용 여부와 관계없이 오른쪽 ⌘에서 나온 F16을 클라이언트로 전달합니다. Horizon에서 `F16 → Right Alt` 매핑을 켠 뒤 원격 Windows 입력칸에서 한글과 영문이 번갈아 입력되는지 확인하세요.

### 🖥️ Apple 화면 공유 (Mac → Mac, 실기 검증 대기)

WinMac Key는 화면 공유 창에 포커스하면 오른쪽 ⌘를 눌렀을 때 `Control+Space`로 **로컬 Mac의 입력 소스 전환을 요청**합니다. 원격 Mac에 실제로 입력되는 문자는 아직 검증하지 않았습니다.

1. 화면 공유에 연결해 원격 Mac의 텍스트 편집기에서 입력칸을 선택하세요.
2. 오른쪽 ⌘를 한 번 누르고 한글을 입력한 뒤, 한 번 더 눌러 영어를 입력하세요. 로컬 메뉴바 표시와 원격 입력칸에 나온 문자를 각각 확인하세요.

원격 Mac의 입력 소스나 WinMac Key 설치 여부가 결과에 미치는 영향은 확인되지 않았습니다. Jump Desktop, AnyDesk, RealVNC, TeamViewer의 한영 전환도 각 클라이언트에서 별도로 확인해야 합니다. [원격 환경별 시험과 설정](docs/VDI_SETUP.md)

### v1.8.5에서 검증한 환경

| 앱 | Bundle ID |
|---|---|
| Omnissa Horizon Client | `com.omnissa.horizon.client.mac` |

2026-10-28 v1.8.5 설치 후 사용자가 Mac 입력창과 Horizon 메모장에서 내장 오른쪽 Command와 K380의 한/영 전환 키를 번갈아 각각 3회 시험했고, 기존 왼쪽 Ctrl/Command 단축키도 정상이라고 확인했습니다. 이는 해당 구성의 실사용 확인이며 장시간 안정성, 모든 키보드 모델 또는 다른 원격 클라이언트의 동작을 보장하지 않습니다.

> 그 외 VMware Fusion, Parallels Desktop, Microsoft RDP, VirtualBox도 코드에서 자동 감지하지만 아직 테스트되지 않았습니다. Windows App의 별도 개선 후보도 이번 v1.8.5 검증에 포함되지 않습니다.

---

## 🖥️ VMware / VDI 하이브리드 한영 전환

Mac의 Microsoft Windows App으로 직접 RDP에 연결하면 그 클라이언트가 받은 F16을 원격 Windows에서 어떻게 처리하는지 확인해야 합니다. Horizon 안에서 `mstsc.exe`를 실행하는 경우에는 바깥 VDI와 안쪽 RDP 입력칸을 각각 시험하세요.

**→ [VDI 매핑 및 설정 가이드](docs/VDI_SETUP.md)**

---

## 🔧 Technical Details

### 시스템 요구사항

- macOS 14.0 (Sonoma) 이상
- v1.8.5 배포 DMG/ZIP: Apple Silicon (arm64)
- Intel용 빌드·실행은 이번 릴리스에서 검증하지 않았습니다.

### 사용 기술

- **CGEventTap**: 키보드 이벤트 인터셉트 및 키코드 리매핑
- **IOHIDManager**: 키보드 디바이스 열거, 연결/해제 감지, 활성 키보드 추적
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
