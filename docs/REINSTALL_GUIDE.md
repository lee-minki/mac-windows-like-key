# WinMac Key 재설치 가이드

이 문서는 이미 WinMac Key 를 쓰고 있는 사용자가 **수동으로 새 버전을 깔거나 깨끗하게 다시 설치**하려는 경우의 절차입니다.
신규 최초 설치는 [SETUP_GUIDE.md](SETUP_GUIDE.md) 를 참고하세요.

---

## 언제 재설치가 필요한가요?

| 상황 | 권장 |
|------|------|
| 앱 내 업데이트가 멈춰있거나 새 버전이 안 잡힘 | 수동 재설치 |
| `WM` 메뉴바 아이콘이 안 뜨거나 엔진이 켜지지 않음 | 수동 재설치 |
| 설정/프로필이 꼬여서 깨끗하게 처음부터 시작하고 싶음 | **클린 재설치** |
| 손쉬운 사용 권한이 자꾸 빠짐 / TCC 가 망가짐 | **클린 재설치** + TCC 리셋 |
| 키매핑이 의도와 다르게 적용됨 | 우선 [SETUP_GUIDE의 문제 해결](SETUP_GUIDE.md#문제-해결) 확인 후 재설치 |

> **안전성**: WinMac Key 의 모든 키 매핑은 `hidutil` 기반이라 **재부팅하면 자동으로 초기화**됩니다. 재설치 도중 키보드가 꼬여도 재부팅 한 번이면 원상복구되니 안심하셔도 됩니다.

---

## 빠른 절차 (체크리스트)

업그레이드 (설정 유지):

1. 메뉴바 `WM` → 종료
2. 새 DMG 다운로드 → `Applications` 에 덮어쓰기
3. 첫 실행: 더블클릭 (v1.3.8+ 공증 빌드는 경고 없이 바로 열림 / 구버전·미서명 빌드만 우클릭 → 열기)
4. 손쉬운 사용 권한이 풀려있으면 **다시 체크**
5. 메뉴바 `wm` → 엔진 ON → `WM`

클린 재설치 (설정 초기화):

1. 메뉴바 `WM` → 종료
2. 시스템 설정 → 손쉬운 사용 → WinMac Key **체크 해제**
3. 시스템 설정 → 로그인 항목 → WinMac Key **제거**
4. `Applications/WinMacKey.app` 휴지통으로
5. 사용자 데이터 삭제 (아래 명령)
6. (옵션) hidutil 매핑 수동 클리어 또는 재부팅
7. 새 DMG 다운로드 → 설치 → 첫 실행 우클릭 열기
8. STEP 1 ~ STEP 4 ([SETUP_GUIDE.md](SETUP_GUIDE.md)) 재수행

---

## 상세 절차

### 1. 현재 버전 확인

```bash
# 설치된 앱 버전
defaults read /Applications/WinMacKey.app/Contents/Info.plist CFBundleShortVersionString
```

또는 메뉴바 `WM` → **도움말 / About** 에서 확인.

GitHub 의 최신 버전과 비교 — 같으면 재설치 불필요할 수 있습니다.

- 최신 릴리스: <https://github.com/lee-minki/mac-windows-like-key/releases/latest>

### 2. 기존 설정 백업 (선택)

업그레이드 재설치라면 건너뛰어도 됩니다. **클린 재설치** 인데 프로필을 보존하고 싶으면 이걸 먼저 하세요.

```bash
# 모든 사용자 설정 백업 (프로필 / 매핑 / 단축키 포함)
cp ~/Library/Preferences/com.winmackey.app.plist ~/Desktop/winmackey-prefs-backup.plist

# Application Support 데이터 백업
cp -R ~/Library/Application\ Support/WinMacKey ~/Desktop/winmackey-appsupport-backup
```

복원하려면 같은 경로에 되돌려놓고 앱을 시작하면 됩니다.

### 3. 앱 종료 및 제거

```bash
# 모든 WinMacKey 프로세스 종료 (메뉴바 종료가 안 될 때만)
pkill -x WinMacKey

# 앱 본체 휴지통
mv /Applications/WinMacKey.app ~/.Trash/
```

### 4. 시스템 권한·로그인 항목 정리

**손쉬운 사용 권한**

```
시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → WinMac Key
```

`−` (마이너스) 버튼으로 항목 자체를 제거.

**로그인 항목**

```
시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → 로그인 시 열기
```

`WinMacKey` 가 있으면 `−` 로 제거.

> 권한을 단순히 체크 해제만 하면 다음 설치 때 권한이 자동 인식되지 않을 수 있습니다. **목록에서 항목 자체를 제거**하는 게 가장 깔끔합니다.

### 5. (클린 재설치만) 사용자 데이터 삭제

업그레이드 재설치라면 이 단계는 건너뜁니다.

```bash
# 사용자 설정 (프로필, 매핑, 단축키 등 모두 초기화됨)
rm -f ~/Library/Preferences/com.winmackey.app.plist

# Application Support 데이터
rm -rf ~/Library/Application\ Support/WinMacKey

# (선택) 앱 업데이트 캐시
rm -rf ~/Library/Caches/com.winmackey.app
```

### 6. (선택) hidutil 매핑 클리어

앱을 정상 종료했다면 매핑은 자동 해제되어 있습니다. 확신이 없거나 키가 이상하게 동작하면:

```bash
# 글로벌 매핑 클리어
hidutil property --set '{"UserKeyMapping":[]}'

# 내장 키보드 매핑 클리어
hidutil property --matching '{"Product":"Apple Internal Keyboard / Trackpad"}' \
  --set '{"UserKeyMapping":[]}'
```

또는 **재부팅 한 번**이면 동일한 효과입니다.

### 7. 새 DMG 다운로드 및 설치

1. <https://github.com/lee-minki/mac-windows-like-key/releases/latest> 접속
2. `WinMacKey-vX.Y.Z.dmg` 다운로드
3. DMG 더블클릭 → `WinMacKey.app` 을 **Applications** 폴더로 드래그
4. DMG 언마운트 (Finder 사이드바에서 ⏏)

### 8. Gatekeeper (v1.3.8+ 공증 빌드는 불필요)

**v1.3.8 부터 Apple 공증(notarized)** 빌드라, DMG 를 열고 드래그한 뒤 더블클릭하면 **경고 없이 바로 실행**됩니다. 이 단계는 건너뛰어도 됩니다.

> 아래는 **v1.3.7 이하 구버전이거나 직접 빌드한 미서명 빌드**에서 "확인되지 않은 개발자" 경고가 뜰 때만 필요합니다.

**방법 A**: Applications 에서 `WinMacKey.app` **우클릭 → 열기 → "열기"** 한 번 더.

**방법 B (터미널)**:

```bash
xattr -dr com.apple.quarantine /Applications/WinMacKey.app
open /Applications/WinMacKey.app
```

### 9. 권한 재허용

```
시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → WinMac Key ✓
```

체크박스가 안 보이면 앱이 자동으로 권한 요청 다이얼로그를 띄웁니다. 거기서 **시스템 설정 열기 → 항목 추가 → 체크**.

### 10. 동작 확인

1. 메뉴바에 `wm` (소문자) 아이콘이 떴는지 확인
2. 클릭 → 엔진 토글 ON → `WM` (대문자) 로 변경
3. 텍스트 편집기에서 **Right Command** 누르기
4. 메뉴바 입력소스 표시기가 `EN ↔ 한` 변경되면 성공
5. (VDI 사용자) Horizon 클라이언트 포커스 → Right Command → Windows 한영 동작 확인

### 11. 백업 복원 (클린 재설치 + 백업한 경우)

```bash
# 앱 종료
pkill -x WinMacKey

# 백업 복원
cp ~/Desktop/winmackey-prefs-backup.plist ~/Library/Preferences/com.winmackey.app.plist
cp -R ~/Desktop/winmackey-appsupport-backup/* ~/Library/Application\ Support/WinMacKey/

# 앱 재시작
open /Applications/WinMacKey.app
```

> 백업 복원 시 손쉬운 사용 권한은 자동으로 따라오지 않습니다. STEP 9 다시 한 번.

---

## 자동 업데이트 vs 수동 재설치

| 항목 | 앱 내 업데이트 | 수동 재설치 |
|------|-----------------------|------------|
| 트리거 | 메뉴바 `WM` → 업데이트 확인... | 사용자가 DMG 직접 다운로드 |
| 대상 버전 | GitHub Releases 의 **Published / Latest** 만 | 모든 릴리스 (Draft 제외) |
| 권한 재허용 | 보통 자동 유지 | 새 위치로 인식되어 재허용 필요할 수 있음 |
| 추천 상황 | 일상적 마이너 업데이트 | 자동 업데이트가 막힐 때 / 클린 재설치 |

> 새 릴리스 확인은 기본으로 켜져 있지만 설치는 자동으로 실행되지 않습니다. 사용자가 업데이트 창에서 확인해야 `/Applications/WinMacKey.app`을 제자리 교체합니다. GitHub의 **Draft와 Pre-release는 자동 업데이트가 건너뜁니다**.

### 버전이 두 개 동시에 보일 때

v1.8.3부터 Applications 설치본이 있으면 다른 위치의 복사본은 입력 엔진을 시작하지 않습니다. 기존에 등록된 개발 빌드는 완전히 종료하고, 시스템 설정의 로그인 항목에서 Applications가 아닌 경로의 WinMacKey 항목을 제거하세요. 앱 파일을 덮어쓰는 업그레이드는 프로필과 설정을 지우지 않습니다.

---

## 자주 묻는 질문

### Q. 재설치하면 키매핑 설정이 다 날아가나요?

업그레이드 재설치 (5단계 건너뜀) 는 **그대로 유지**됩니다. 클린 재설치는 의도적으로 초기화합니다. 보존이 필요하면 STEP 2 백업.

### Q. 재설치 중 키가 먹통이 되면?

**재부팅** 한 번이면 hidutil 매핑이 모두 풀려 시스템 기본 동작으로 돌아갑니다. 위험하지 않습니다.

### Q. 손쉬운 사용 권한 항목을 지워도 자동으로 다시 추가되나요?

새 앱을 실행하면 권한 요청 다이얼로그가 뜨고, 거기서 허용하면 자동으로 추가됩니다. 수동으로 시스템 설정에서 `+` 로 추가해도 됩니다.

### Q. 자동 업데이트로 받은 v1.3.6 다이얼로그가 안 떠요.

v1.3.6 이전에는 LSUIElement 앱에서 업데이트 창이 다른 앱 뒤에 숨는 버그가 있었습니다. **Mission Control (F3 또는 3-finger 위로 스와이프)** 로 모든 창 중 "소프트웨어 업데이트" 창을 찾아서 클릭하거나, 이 가이드의 수동 재설치 절차로 한 번에 최신 버전을 설치하세요.

### Q. 팀에 배포할 때 가장 빠른 길은?

1. 팀원에게 최신 DMG 링크 (Releases 페이지) 공유
2. 이 가이드의 **빠른 절차 (업그레이드)** 만 따라하게 안내
3. 기존 사용자 중 자동 업데이트가 막힌 사람만 **클린 재설치** 안내

---

## 참고

- 최초 설치: [SETUP_GUIDE.md](SETUP_GUIDE.md)
- VDI 설정: [VDI_SETUP.md](VDI_SETUP.md)
- 변경 이력: [../CHANGELOG.md](../CHANGELOG.md)
- 릴리스 페이지: <https://github.com/lee-minki/mac-windows-like-key/releases>
