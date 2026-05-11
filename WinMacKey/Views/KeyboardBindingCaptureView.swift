import SwiftUI

/// "Press-to-bind" 키보드 바인딩 UX.
///
/// 사용자가 ProfilesView 에서 "Bind keyboard..." 버튼 클릭 시 sheet 로 표시됨.
/// 흐름:
///   1. Waiting: "키를 눌러주세요" + 10초 timeout
///   2. Captured: 감지된 키보드 정보 표시, 충돌 경고, 확인/취소 버튼
///   3. 확인 시 onConfirm(identifier) 호출 → 부모 view 가 profile 업데이트
///   4. 캡처 후에도 사용자가 다른 키 누르면 다시 captured 상태 갱신 가능
///
/// 대안 입력 경로: 하단에 "또는 연결된 키보드에서 선택" 목록 — 키 누르기 불편한 경우.
struct KeyboardBindingCaptureView: View {
    @ObservedObject var appState: AppState
    /// 바인딩 대상 프로필 이름 (헤더 표시용).
    let profileName: String
    /// 같은 디바이스에 이미 바인딩된 다른 프로필 (충돌 경고용).
    let existingBindingOnSameDevice: (profileName: String, deviceId: KeyboardDeviceIdentifier)?
    /// 사용자가 confirm 클릭 시 호출.
    let onConfirm: (KeyboardDeviceIdentifier) -> Void
    /// sheet 닫기.
    let onCancel: () -> Void

    private enum CaptureState {
        case waiting
        case captured(KeyboardDeviceIdentifier)
        case timedOut
    }

    @State private var state: CaptureState = .waiting
    @State private var remainingSeconds: Int = 10
    @State private var countdownTimer: Timer?

    private let captureTimeout: TimeInterval = 10.0

    var body: some View {
        VStack(spacing: 16) {
            // 헤더
            VStack(spacing: 4) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("키보드 바인딩")
                    .font(.headline)
                Text("'\(profileName)' 프로필에 사용할 키보드를 등록합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            // State 별 컨텐츠
            switch state {
            case .waiting:
                waitingContent
            case .captured(let identifier):
                capturedContent(identifier: identifier)
            case .timedOut:
                timedOutContent
            }

            // Fallback — 연결된 키보드 목록
            if appState.keyboardDeviceManager.connectedKeyboards.count > 1 {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("또는 연결된 키보드에서 선택")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(appState.keyboardDeviceManager.connectedKeyboards, id: \.matchingKey) { device in
                        Button {
                            handleCapture(device)
                        } label: {
                            HStack {
                                Image(systemName: device.isInternal ? "laptopcomputer" : "keyboard")
                                VStack(alignment: .leading) {
                                    Text(device.displayName)
                                        .font(.caption)
                                    Text(device.matchingKey)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if case .captured(let cap) = state, cap == device {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)

            // 버튼 영역
            HStack {
                Button("취소", role: .cancel) {
                    stopCapture()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if case .captured(let id) = state {
                    Button("바인딩") {
                        stopCapture()
                        onConfirm(id)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .frame(minHeight: 380)
        .onAppear {
            startCapture()
        }
        .onDisappear {
            stopCapture()
        }
    }

    // MARK: - State Subviews

    private var waitingContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text("바인딩할 키보드에서 아무 키나 눌러주세요")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("⏱ \(remainingSeconds) 초 후 자동 취소")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
    }

    private func capturedContent(identifier: KeyboardDeviceIdentifier) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("감지됨")
                .font(.callout.bold())

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("이름:") {
                    Text(identifier.displayName)
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("VID:PID:") {
                    Text(identifier.matchingKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("타입:") {
                    Text(identifier.isInternal ? "내장" : "외장")
                        .font(.caption)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )

            // 충돌 경고
            if let existing = existingBindingOnSameDevice,
               existing.deviceId == identifier
            {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("이미 다른 프로필에 바인딩됨")
                            .font(.caption.bold())
                        Text("'\(existing.profileName)' 프로필이 이 키보드를 사용 중입니다. 바인딩하면 이전됩니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            Text("💡 다른 키보드 누르면 그쪽으로 바뀝니다")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var timedOutContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("시간 초과")
                .font(.callout.bold())

            Text("입력이 감지되지 않았습니다. 다시 시도하시려면 '재시도' 를 눌러주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("재시도") {
                state = .waiting
                remainingSeconds = Int(captureTimeout)
                startCapture()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Capture lifecycle

    private func startCapture() {
        remainingSeconds = Int(captureTimeout)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if remainingSeconds > 0 {
                    remainingSeconds -= 1
                }
            }
        }

        appState.keyboardDeviceManager.startCapture(
            timeout: captureTimeout,
            onCapture: { identifier in
                handleCapture(identifier)
            },
            onTimeout: {
                countdownTimer?.invalidate()
                countdownTimer = nil
                state = .timedOut
            }
        )
    }

    /// 캡처 콜백 — 새 디바이스 감지되면 state 갱신. 사용자가 다른 키보드 누르면 다시 호출됨.
    private func handleCapture(_ identifier: KeyboardDeviceIdentifier) {
        state = .captured(identifier)
        // 자동 재캡처: 사용자가 다른 키보드로 변경 가능하도록 capture 재시작
        appState.keyboardDeviceManager.startCapture(
            timeout: captureTimeout,
            onCapture: { newIdentifier in
                handleCapture(newIdentifier)
            },
            onTimeout: {
                // 이미 captured 상태에서 timeout — 그대로 두기 (사용자 확인 대기)
            }
        )
    }

    private func stopCapture() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        appState.keyboardDeviceManager.cancelCapture()
    }
}
