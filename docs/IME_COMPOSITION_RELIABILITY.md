# 로컬 한글 조합 신뢰성 — 2026-11-26

추적 이슈: [GitHub #6](https://github.com/lee-minki/mac-windows-like-key/issues/6). 상태는 **원인·실기 해결 여부 미확정**이다. 이 문서는 같은 이슈의 로컬 진단, 변경, 검증 기록을 연결한다.

브랜치는 `codex/ime-composition-reliability`, 기준 commit은 `0658385cdc72060a192a24349a2a00cceec75c32`이며 변경 버전은 1.8.6/build 29이다. 사용자 요청에 따라 기존 정식판의 서명 재료를 복구하여 같은 Developer ID로 빌드했다. 아래 시각별 기록은 ad-hoc 시험·복구, 정식 공증·배포, 설치 결과를 구분한다. 실제 타이핑 개선은 별도 사용자 확인 전까지 미확인이다.

## 확인한 증상과 증거

로컬 Codex 대화 입력칸에서 `지금은`이 조합 도중 사라지는 것처럼 보이며 `지ㅁ은`으로 입력됐고, 같은 창에서 여러 번 재시도한 뒤 ‘한’ 표시 상태에서 영문이 출력됐다는 사용자 보고다. 실제 Delete 이벤트는 기록하지 않았으므로 Backspace 주입으로 단정하지 않는다.

| 2026-11-26 KST | 확인 내용 |
|---|---|
| 11:30:03.314–315 | WinMacKey가 ChatGPT local/terminal 컨텍스트로 변경 |
| 11:30:06.223, 08.196, 09.984, 11.810, 13.354 | KIM_Extension의 `Encountered error aligning with client`, `com.apple.inputmethod.oxygen.error Code=1` 오류 5회 |
| 11:30:32.042–37.839 | 이후 F16 요청과 terminal direct TIS 전환. 일부 보류 이벤트가 약 120–135ms 뒤 재생됨 |
| 11:31:54–11:36:54.909 | 제한된 읽기 전용 관찰기 실행 후 종료. 전환키·입력 소스·전면 앱·Secure Input 상태만 기록 |

오류 5회는 위 F16 요청보다 앞선다. 이후 전환을 앞선 오류의 원인으로 삼을 수 없다. KIM 오류는 입력기와 텍스트 클라이언트의 상태 정렬을 조사할 근거이며, 최초 원인이 WinMacKey/macOS/앱/다른 입력 도구 중 무엇인지는 밝히지 못했다.

ABC→두벌식 메뉴 비교에서 첫 영문 줄은 영어 상태에서 입력했다는 사용자 정정이 있었다. 창 이동도 있었으므로 메뉴로 두벌식을 선택한 뒤에도 실패했다는 증거, 또는 메뉴 선택으로 복구됐다는 증거에서 제외한다. 나중의 정상 전환도 간헐 문제의 해결 증거가 아니다.

확인 당시 macOS는 26.7.1(25G241), Codex/ChatGPT 호스트는 26.1117.31558/build 29513(`com.openai.codex`), WinMacKey는 단일 1.8.5/build 28이었다. 별도 Horizon 일반 입력 지연은 사용자가 VDI 재부팅 후 사라졌다고 보고했다. 이번 로컬 조합 문제와 같은 원인이라고 연결하지 않는다.

## 1차 후보 변경

- `StateManager`: 새 일반/직접/VDI 전환과 언어 페어 변경 전 이전 검증 작업을 취소한다. 작업 세대를 확인해 취소된 대기 작업이 다시 깨어나도 재시도, 직접 전환, 완료 콜백으로 새 요청에 개입하지 않게 한다.
- `AppState`: 앱 활성화 변경, VDI 패스스루, 엔진 OFF, 설정 초기화에서도 이전 검증을 취소한다. 같은 terminal 분류의 앱 간 이동도 포함한다.
- `DoctorService`: 엔진 정지·재시작·긴급 복구 전에 검증을 취소한다. 같은 TIS 스냅샷의 입력 소스 이름·ID를 정보로 표시하고, 앱의 조합·출력 및 VDI 내부 상태는 미확인으로 명시한다.
- 설정 가이드·VDI 가이드·HTML 설명서에서 입력 소스 선택과 실제 한글 조합 성공을 구분한다. “TIS를 우회하므로 조합 누락이 없다”는 부정확한 보장을 제거한다.

기존 40×2ms 검증, 최대 2회 단축키 재시도, 직접 전환 fallback, terminal 직접 TIS와 120ms 보류 정책, Horizon `F16 → Right Alt`, 장치별 매핑은 유지한다. 이것은 지연 작업의 수명 보강이며 11:30의 조합 오류 원인이 증명됐다는 뜻은 아니다.

## 보류한 변경

빠른 재전환(<120ms) 시 이전 버퍼가 새 입력 소스로 재생될 수 있고, 앱 이동 때 보류 키의 대상 앱이 묶여 있지 않은 경계 사례는 별도 설계가 필요하다. 이번 기록의 최소 전환 간격은 348ms라 빠른 재전환 사례를 이번 원인으로 볼 수 없다.

단순히 `CGEvent.post` 호출을 TIS 전환 앞에 옮겨도 대상 앱이 그 키를 처리했다는 응답은 아니다. 포커스 변경 뒤 전역 재생은 다른 창에 입력할 수 있다. 따라서 보류 시간 연장, 전역 재생 변경, 자동 입력기 재시작은 이번 후보에 넣지 않았다. 이 항목은 #6에서 계속 미완료로 추적한다.

## 자동 검증

검증 결과(2026-11-26 11:47 KST): **자동 테스트와 Debug 빌드 통과**.

- `scripts/run-tests.sh`: exit 0, smoke 프로그램 18개와 버전·release workflow·reset key 검사 통과. 새 검증 작업 테스트 7개 시나리오, 입력 진단 테스트 전체 28개 시나리오 포함.
- Debug 빌드: exit 0, `BUILD SUCCEEDED`. 서명 검증용 배포 빌드가 아니며 아래 명령은 코드 서명을 끈 컴파일 검사다.
- `git diff --check`: 통과. 독립 읽기 전용 코드 검토에서도 확인된 실질 회귀는 없었다. 실제 입력 검증을 대체하지 않는다.
- 기존 `KeyboardDeviceManager`의 Sendable, `PermissionGuideView`의 actor 격리, `WinMacKeyApp`의 capture 경고 및 AppIntents 메타데이터 생략 경고는 남아 있다. 이번 변경의 경고라고 단정하거나 경고 없는 빌드로 기록하지 않는다.
- `/Applications/WinMacKey.app`은 PID 1171의 **1.8.5/build 28**로 다시 확인했다. 후보 실행·설치, HID·개인정보 설정 변경은 하지 않았다.

```bash
bash scripts/run-tests.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey \
  -configuration Debug -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
git diff --check
```

새 `input_source_verification_smoke`는 실제 StateManager에 입력을 보내지 않는 가짜 backend와 수동 poll clock을 넣어 7개 시나리오를 확인한다. 오래된 작업의 직접 전환 이후 재시도, 컨텍스트 취소 후 콜백, 새 작업 덮어쓰기, 정상 완료, 재시도/fallback 상한, VDI 진입, 페어 변경을 포함한다. 실제 TIS 변경·키 주입·권한 요청을 하지 않는다. Doctor 정책 테스트는 한국어/ABC/미확인 모두 조합 성공으로 판정하지 않는지 확인한다.

자동 테스트는 실제 앱의 한글 조합이나 Windows 키 수신을 검증하지 않는다.

## 로컬 시험 설치 및 복구 — 2026-11-26

| 시각(KST) | 실제 확인 |
|---|---|
| 13:19 | 기존 정식 앱·설정·Application Support 및 HID 읽기 스냅샷 보관. 기존 앱 복사본의 서명·실행 파일 SHA-256 일치 확인 |
| 13:24:20 | Release ad-hoc 1.8.6/build 29를 정식 앱 경로에 교체. 빌드 성공 및 `codesign --verify --deep --strict` 통과. Developer ID 서명·공증 완료를 뜻하지 않음 |
| 13:24:32 | 후보 PID 21903 단일 실행. 앱 자체 검사에서 Accessibility=false, Input Monitoring 미허용. 설정 점검 창이 열렸으며 입력 엔진 자동 시작은 차단됨 |
| 13:26:39–40 | 사용자 후속 요청에 따라 정식 1.8.5/build 28로 복구. 원본 SHA-256 일치, PID 22232 단일 실행, Accessibility=true, engine/event tap 시작 및 키보드 감지 확인 |

후보 실행 파일 SHA-256: `4e5690fe1c1d23b0eb53f8dc1799360aa2cf396356c60eeea5be5e7bb2a62e1c`.

설정 export 비교에서 바뀐 키는 업데이트 확인 시각과 설정 점검 창 위치뿐이었다. 키보드 프로필·전환 설정은 동일했다. 개인정보 권한을 변경하거나 일반 입력 문자를 추가 기록하지 않았다. 후보와 기존 정식본 백업은 로컬에 보존했다. 시험본 엔진이 시작되지 않아 **실제 한글 조합 개선을 시험한 것으로 처리하지 않는다**. 복구한 정식본의 엔진 시작 또한 기존 간헐 오류 해결의 증거가 아니다.

13:26 KST 정식 배포 준비 당시 확인: 이 Mac의 로그인·시스템 키체인에서 사용 가능한 코드 서명 identity는 0개였고 기본 위치의 업데이트 서명키도 없었다. GitHub 저장소 secrets와 environments는 각각 0개다. 현재 workflow는 자격 증명이 없으면 ad-hoc으로 빌드하고 DMG artifact만 만들므로 정식 Release 발행·서명·공증을 보장하지 않는다. 기존 Developer ID 인증서/개인키, 공증 프로필, 기존 업데이트 공개키와 대응하는 Ed25519 키가 있는 서명 환경을 확인한 뒤, 산출물 검증 → 배포 → 실제 다운로드본 검증 → 설치 순서로 진행한다. 기존 키를 새 키로 임의 교체하지 않는다.

## 기존 서명 환경 복구와 공증 대기 — 2026-11-26 13:43 KST

사용자의 정식판 배포·설치 요청에 따라 10/27 v1.8.5 배포 기록을 추적했다. 보관된 Time Machine 백업을 읽기 전용으로 열어 당시의 Developer ID 인증서·개인키와 Ed25519 업데이트 키를 확인했다. 기존 인증서 지문 및 앱에 내장된 업데이트 공개키가 일치하며, 새 키를 생성하거나 신뢰 키를 바꾸지 않았다. 개인정보 권한도 변경하지 않았다.

- 기존 Developer ID로 서명한 **1.8.6/build 29 Release arm64 빌드 성공**.
- `codesign --verify --deep --strict` 통과. Hardened Runtime·secure timestamp 확인, `get-task-allow` 없음.
- 현재 설치된 정식 1.8.5와 designated requirement가 동일하다. 이는 서명 연속성 확인이며 실제 권한 유지·입력 개선 검증을 대신하지 않는다.
- 기존 `winmackey-notary` 프로필로 Apple 요청 시 **필수 약관 미동의 또는 만료(HTTP 403)** 응답을 받았다. 당시 공증 제출 ZIP을 준비하고 계정 상태를 추가 확인했다. 웹에는 개발자 계약이 수락 완료로 표시되어 있어 미동의가 원인이라고 단정하지 않았다. 이후 API 재확인과 제출 결과는 다음 절에 기록한다.
- 공증 `Accepted`, 앱·DMG staple, 기존 공개키로 최종 자산 서명 검증, GitHub 다운로드 재검증 전에는 정식 배포·설치 완료로 처리하지 않는다. 실행 앱은 기존 1.8.5/build 28이다.
- 서명 작업 후 임시 키체인은 잠그고 원래 키체인 검색 목록을 복원했다. 비밀키·암호 내용은 문서나 공개 이슈에 기록하지 않는다. 상세 위치 및 검증 메타데이터는 로컬 `build/official-release-20261126/`에만 보관했다.

이번 결과도 [이슈 #6](https://github.com/lee-minki/mac-windows-like-key/issues/6)에 이어 기록하며, 실기 확인 전 이슈를 닫지 않는다.

## 정식 공증 진행 — 2026-11-26

추가 확인에서 기존 공증 프로필의 API 요청이 정상화됐다. 앱 제출 `e6b3f798-95c8-4f99-a414-8cdd6538fee6`는 `Accepted`이며 앱 staple·검증을 통과했다. 계정 또는 약관을 대신 변경하지 않았다. DMG 제출 `8888eaa9-3baa-4fac-bd90-3d1fa69b24e8`도 `Accepted`이며 staple·검증을 통과했다. ZIP·DMG는 기존 Ed25519 공개키로 최종 서명을 검증했고 SHA-256 목록을 만들었다. DMG 컨테이너에는 별도 Developer ID 코드 서명이 없어 `spctl --type open --context context:primary-signature`는 `no usable signature`를 반환하므로 이 검사를 통과로 기록하지 않는다. 컨테이너는 Apple 공증 티켓과 Ed25519 자산 서명을 가지며, 내부 앱의 Developer ID 서명·Gatekeeper 실행 허용을 별도로 검증한다. GitHub 다운로드본 검증·설치 결과는 완료 후 같은 기록과 #6에 이어 기록한다.

## 정식 배포·다운로드 검증·설치 — 2026-11-26 14:00 KST

- 정식 [v1.8.6 릴리스](https://github.com/lee-minki/mac-windows-like-key/releases/tag/v1.8.6)를 Latest로 게시했다. 코드 커밋은 `57daa017fcb5afe9cf5c5e79b36eb2c47ed076c9`이다. 빌드 전 기록과 비교해 Swift·프로젝트·Info.plist를 포함한 앱 입력 파일 48개가 동일하며, 최종 문서 갱신은 앱 번들에 포함되지 않는다.
- 게시 자산 5개의 GitHub SHA-256을 로컬 최종본과 대조했다. GitHub에서 다시 다운로드한 ZIP·DMG와 두 `.sig`는 `SHA256SUMS.txt`와 일치하며, 기존 공개키로 두 Ed25519 서명을 검증했다.
- 다운로드 ZIP에서 추출한 앱과 DMG 내부 앱의 엄격한 코드 서명, 앱 공증 티켓, Gatekeeper 실행 허용을 확인했다. DMG 공증 티켓도 검증했다. 앱은 Developer ID 서명이며 DMG 컨테이너 자체의 별도 코드 서명 여부는 위 검사 결과와 구분한다.
- 기존 앱·설정·Application Support 및 HID 읽기 스냅샷을 백업하고, 기존 앱을 정상 종료한 뒤 다운로드본을 `/Applications/WinMacKey.app`에 설치했다.
- **14:00:32–33 KST: 1.8.6/build 29 단일 실행, Accessibility=true, 입력 엔진·CGEventTap 시작 및 연결 키보드 감지 확인.** 기존 정식판과 같은 designated requirement를 유지하며 개인정보 권한을 변경하지 않았다.
- 태그 push로 생성된 GitHub Actions run `45758335364`는 단계 실행 전 `cancelled`로 끝났다. CI 성공으로 기록하지 않으며, 위 자동 테스트·빌드 결과는 로컬 실행 결과다.
- 배포 후 임시 복구 키체인을 제거하고 원래 키체인 검색 목록을 재확인했다. 읽기 전용 Time Machine 백업도 정상 분리했으며 원본 인증서·키는 변경하지 않았다.
- 설치 전후 preferences에서 바뀐 키는 `LastUpdateCheck`뿐이다. 키보드 프로필·전환 설정은 동일하다. 기존 1.8.5 앱과 설정 백업은 로컬에 보존했다.
- 실행 파일 SHA-256: `142451da6bf6e3cd678ec8288a909a8934622705cec416bb15c936e84e789b17`.

서명·공증·설치 및 엔진 시작은 확인됐지만, **조합 누락·언어 표시 불일치 개선 여부와 실제 Horizon 키 수신은 아직 사용자 실사용 확인 전**이다. 이슈 #6은 열어 둔다. 실패 시각, 앱(로컬/VDI/리디렉션 구분), 키보드, 실제 출력 결과를 같은 이슈에 이어 기록한다. 상시 로그 업로드나 일반 문자 수집을 추가하지 않았다.

## 실기 확인과 복구

다음 실기 항목은 **모두 미확인**이다. 정식 1.8.6 설치·엔진 시작을 확인했으며, 사용자가 실제 키보드로 별도 검증해야 한다.

| 경로 | 필요한 확인 |
|---|---|
| Codex / 기본 텍스트 편집기 | 동일한 짧은 문장의 조합·지우기·반복 입력, ‘한’/ABC와 실제 출력 일치. 같은 창 유지와 앱 이동을 따로 기록 |
| Ghostty | 한영 전환과 첫 글자, Command 단축키·Return/Tab/Escape 누출 여부 |
| 전환 경계 | 빠른 재전환, 전환 직후 앱 이동, 엔진 정지. 보류 키 경계는 현재 미해결이므로 결과를 별도로 기록 |
| Horizon | F16 관측, Windows `가/A`, 실제 입력 결과를 각각 확인. VDI 내부와 리디렉션된 로컬 Chrome을 구분 |
| 내장/외장 키보드 | 같은 Mac에서 각 장치의 로컬/VDI 프로필 및 앱 이동 후 첫 키 확인 |

실패 시 작성 중인 초안을 먼저 보존하고 시각·앱·기대/실제 테스트 문구를 기록한다. Doctor의 선택 소스나 F16 관측만으로 성공을 판정하지 않는다. 후보 설치로 새 문제가 생기면 초안을 보존한 뒤 후보를 종료하고 보관한 이전 설치본으로 되돌린다. 동시에 두 버전을 실행하지 않는다. 관련 없는 HID·개인정보 권한을 초기화하는 절차는 이번 변경에 포함하지 않는다.

## 기록 연결 규칙

- 이슈 #6: 공개 재현·원인 범위·후보 변경·검증 요약의 기준. 코드 테스트만 통과하면 닫지 않는다.
- 이 문서: 저장소의 변경·검증 기록. 후속 commit/PR을 만들 때 `Refs #6`으로 연결하고, 실기 해결 전 `Fixes/Closes #6`을 사용하지 않는다.
- 로컬 `WinMacKey-20261126-input-diagnosis.md`: 상세 진단 요약과 이슈/이 문서 링크.
- 로컬 원본 `WinMacKey-20261126-1130-ime-errors.log`, `WinMacKey-Head-Switch-Watch-20261126-1795660314-10211.jsonl`: 공개 업로드하지 않는다. 업무 화면·입력 내용·사용자 경로는 GitHub 요약에서 제외한다.
- 테스트/빌드 로그: 작업 공간의 `build/ime-tests-20261126.log`, `build/ime-build-20261126.log`. GitHub에는 검사 이름·결과·미확인 범위만 반영한다.

이 연결은 이번 작업의 기록 상호 참조이며, 자동 업로드나 상시 입력 기록을 설정한 것은 아니다.
