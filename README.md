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

- **⌨️ Right Command 전환**: `hidutil` HID remap으로 Right Command를 F16으로 변환, modifier flag 오염 원천 차단
- **🖥️ Native VDI Support**: VDI에서는 F16 릴레이로 한/영 전환을 전달하고, 로컬 Mac에서는 `Control+Space`를 합성
- **🔌 Per-Device Auto Profile**: IOKit 기반 내장/외장 키보드 감지 — 키보드별 프로필 자동 전환
- **🛡️ VDI Ghost Key Prevention**: F16 HID remap으로 modifier flag 오염 원천 차단 (Win+P, Alt+key 등 방지)
- **📝 IME Commit Guard**: 입력소스 변경 확인 + 최소 홀드로 첫 글자 영어 입력과 전환 누락 완화
- **📊 Event Viewer**: 실시간 키 입력 모니터링과 지연 시간 확인
- **🧩 Keyboard Profiles**: 현재 입력을 실키로 감지하고 `Mac 로컬` / `VDI` 목표 배치를 따로 저장
- **🔁 Login Startup**: 재부팅 후 자동 실행과 앱 실행 시 엔진 자동 시작 옵션 제공
- **📍 Menu Bar Utility**: 상태 확인, 로그, Doctor, 업데이트 창에 빠르게 접근

---

## 📥 Installation

### Manual Download

1. [Releases](https://github.com/lee-minki/mac-windows-like-key/releases)에서 최신 DMG 또는 ZIP 다운로드
2. WinMac Key.app을 Applications 폴더로 드래그
3. **최초 실행만**: Applications에서 `WinMacKey.app` 우클릭 → "열기" → 한 번 더 "열기"
   (또는 터미널: `xattr -dr com.apple.quarantine /Applications/WinMacKey.app`)
4. 앱 실행 후 손쉬운 사용 권한 허용

> 현재 Apple Developer ID 서명이 없는 빌드라 최초 실행 시 Gatekeeper 경고가 뜹니다. 위 절차로 한 번만 허용해주면 이후엔 일반 앱처럼 더블클릭으로 실행됩니다.

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
- 프로필 자동 할당은 키보드 디바이스(VendorID/ProductID) 또는 앱의 Bundle ID 기준으로 동작합니다
- Profiles 탭에서 **"Bind keyboard…"** 버튼을 누르면 모달이 뜨고, 바인딩할 키보드의 키를 한 번 누르면 디바이스 정보(이름·VID:PID·내장/외장)를 확인한 뒤 바인딩이 완료됩니다 (v1.3.6+ Press-to-bind UX)
- 한 디바이스에는 하나의 프로필만 바인딩됩니다. 다른 프로필에 이미 바인딩된 키보드를 다시 바인딩하면 자동으로 이전됩니다
- 키보드 전환 시 프로필이 자동으로 따라갑니다 (디바이스 프로필 > 앱 프로필 > 기본 프로필)

### 6. 권장 추가 설정

- `Caps Lock 키로 ABC 입력 소스 전환`은 로컬 macOS에서 순수 Caps Lock을 쓰려면 꺼두는 것을 권장합니다
- Windows VDI를 사용한다면 클라이언트에서 `F16 → Right Alt` 매핑을 추가하세요
- 재부팅 후 바로 쓰려면 `설정 → General → Startup`에서 `로그인 시 자동 실행`과 `앱 실행 후 엔진 자동 시작`을 함께 켜세요
- Ghostty, Terminal.app, iTerm2 같은 터미널류 앱 경로는 F16 노출과 Command shortcut 누출을 막기 위한 별도 경로가 적용되어 있습니다. 1차 안정화는 되었지만 broader verification 전까지 `[57379u` raw sequence나 `Cmd+N` shortcut 누출이 보이면 terminal regression으로 기록해 확인하세요.

---

## 💎 VDI 지원

별도 가상 키보드 드라이버 없이 동작합니다. WinMac Key는 `hidutil`로 Right Command를 F16으로 HID 레벨 remap하여:
- 로컬 macOS에서는 F16을 suppress하고 `Control+Space` 합성
- Windows VDI 앱 포커스에서는 F16을 **패스스루** — Horizon이 Right Alt로 직접 변환
- **Mac → Mac 원격접속** (Screen Sharing 등) 에서는 F16을 패스스루 — 원격 Mac 의 WinMacKey 가 자체 처리

을 상황에 맞게 처리합니다.

### 🖥️ Mac → Mac 원격접속 (v1.3.5+)

맥북에서 맥미니/맥스튜디오 등에 Apple Screen Sharing 으로 원격접속 시 한영전환:

1. **로컬 맥북에만 WinMacKey 설치** (원격 Mac 에는 설치 불필요)
2. Screen Sharing 으로 원격 Mac 연결
3. 원격 Mac 창에 포커스 → 맥북의 Right Command 누름
4. **맥북의 입력소스가 토글** (메뉴바 EN ↔ 한)
5. 이후 타이핑 → 맥북의 입력소스에서 변환된 문자가 Screen Sharing 거쳐 원격 화면에 입력

#### 작동 원리

Apple Screen Sharing 은 **키 스캔코드가 아니라 변환된 character(Unicode)** 를 원격에 전달합니다. 즉 로컬 맥북의 IME 가 'a' → 'ㅁ' 으로 변환하면 원격 화면에 'ㅁ' 이 들어갑니다. 따라서 한영전환 처리는 로컬 맥북에서 일어나면 충분하고, 원격 Mac 의 입력소스 상태는 결과에 영향을 주지 않습니다.

#### 주의 사항

- 맥북 메뉴바의 입력소스 표시기 (EN / 한) 가 토글됩니다 — 이게 정상 동작
- 원격 Mac 자체의 입력소스는 안 바뀝니다 (Screen Sharing 이 character 단위 forward 라 무관)
- VDI (Omnissa Horizon) 와 동작 모델이 다름 — VDI 는 F16 패스스루, Mac 원격은 로컬 토글

#### 다른 원격접속 도구

Jump Desktop, AnyDesk, RealVNC, TeamViewer 등은 키 forwarding 방식이 다를 수 있습니다. 동작 여부 실측 권장.

### 검증된 환경

| 앱 | Bundle ID |
|---|---|
| Omnissa Horizon Client | `com.omnissa.horizon.client.mac` |

> 그 외 VMware Fusion, Parallels Desktop, Microsoft RDP, VirtualBox도 코드에서 자동 감지하지만 아직 테스트되지 않았습니다.

---

## 🖥️ VMware / VDI 하이브리드 한영 전환

VMware Horizon 등 가상화 앱에서 한/영 전환이 안 되는 문제를 기본적으로 해결합니다.
**가상 키보드 드라이버 등 별도의 시스템 확장프로그램이 전혀 필요 없는 완전한 네이티브 방식**을 사용합니다.

WinMac Key가 Windows VDI 앱에 포커스된 것을 자동 감지하면 F16을 패스스루하여
Horizon 등 VDI 클라이언트가 이를 윈도우의 `Right Alt`로 변환하도록 구성할 수 있습니다.

**→ [VDI 매핑 및 설정 가이드](docs/VDI_SETUP.md)**

---

## 🔧 Technical Details

### 시스템 요구사항

- macOS 14.0 (Sonoma) 이상
- Apple Silicon 또는 Intel Mac

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
