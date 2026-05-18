import SwiftUI

/// P2 / M3 — 미등록 외장 키보드 첫 입력 시 보여주는 modal sheet.
/// AppState.firstSeenKeyboardCandidate 가 set 되면 자동으로 표시됨.
///
/// 사용자가 [Bind / Ignore / Not now] 중 하나를 고르거나 10초 timeout 으로 자동 종료.
/// 종료 = candidate = nil → sheet 닫힘.
///
/// 정책 (sealed): P2 plan §3.2 / §3.3
/// - Ignore 는 영구 (KeyboardProfileStore.ignore 호출 → UserDefaults 영구 저장)
/// - Not now 는 단순 dismiss (다음에 같은 디바이스 입력 시 다시 prompt)
/// - Bind 는 Settings 윈도우 (Profiles 탭) 를 띄워 사용자가 명시적으로 바인딩하게 위임
///   (이번 라운드에서는 jump-to-bind 자동화는 안 함 — M4 또는 별도 phase)
struct FirstSeenKeyboardPromptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    let device: KeyboardDeviceIdentifier

    /// 자동 dismiss 까지 남은 초. nil 이면 timer 미작동 (preview 등).
    @State private var remainingSeconds: Int? = 10
    @State private var timer: Timer?

    private static let timeoutSeconds: Int = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            deviceInfoCard
            description
            buttons
            timeoutFooter
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("새 키보드가 감지되었습니다")
                    .font(.headline)
                Text("자동 프로필 전환 대상에 추가하시겠어요?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device.displayName)
                .font(.system(.body, weight: .semibold))
            Text("VID:PID = 0x\(String(format: "%04X", device.vendorId)):0x\(String(format: "%04X", device.productId))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(device.isInternal ? "내장 키보드" : "외장 키보드")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이 키보드 입력 시 자동으로 적용할 프로필을 지금 바인딩할 수 있어요. 또는 이 키보드를 무시 목록에 영구 등록할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                ignoreAndDismiss()
            } label: {
                Label("이 키보드 무시", systemImage: "nosign")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("나중에") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Button {
                bindAndDismiss()
            } label: {
                Label("프로필 바인딩…", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var timeoutFooter: some View {
        if let seconds = remainingSeconds, seconds > 0 {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                Text("\(seconds)초 후 자동으로 닫힙니다")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func dismiss() {
        stopTimer()
        appState.firstSeenKeyboardCandidate = nil
    }

    private func ignoreAndDismiss() {
        appState.profileStore.ignore(device)
        LogService.shared.info(
            "User ignored keyboard: \(device.displayName) (\(device.matchingKey))",
            category: "Device"
        )
        dismiss()
    }

    private func bindAndDismiss() {
        // 이번 라운드: Settings 윈도우 띄워서 사용자가 Profiles 탭에서 명시 바인딩하도록 위임.
        // jump-to-bind 자동화는 follow-up phase (M4 또는 별도).
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI macOS 14+ Settings opener (responder chain).
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        dismiss()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        remainingSeconds = Self.timeoutSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                guard let current = remainingSeconds else { return }
                if current <= 1 {
                    dismiss()
                } else {
                    remainingSeconds = current - 1
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
