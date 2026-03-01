import SwiftUI

/// Doctor 진단 화면 — brew doctor 스타일
struct DoctorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var doctor = DoctorService()
    @State private var showRecoveryConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Checks List
            if doctor.checks.isEmpty && !doctor.isRunning {
                emptyState
            } else if doctor.isRunning {
                ProgressView("진단 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                checksList
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear {
            doctor.runAllChecks(appState: appState)
        }
        .confirmationDialog(
            "긴급 복구를 실행하시겠습니까?",
            isPresented: $showRecoveryConfirm,
            titleVisibility: .visible
        ) {
            Button("긴급 복구 실행", role: .destructive) {
                doctor.emergencyRecovery(appState: appState)
                // Re-run checks after recovery
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    doctor.runAllChecks(appState: appState)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("""
            다음 작업이 수행됩니다:
            • 엔진 정지 (CGEventTap 해제)
            • 모든 설정 초기화
            • VDI 모드 해제
            • 이벤트 로그 삭제
            
            모든 키 매핑이 즉시 중지되고 macOS 기본 동작으로 돌아갑니다.
            """)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("WinMac Key Doctor")
                    .font(.title2.bold())
                Text("시스템 건강 상태를 진단하고 문제를 해결합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Summary badge
            if !doctor.checks.isEmpty {
                summaryBadge
            }
        }
        .padding(16)
    }
    
    private var summaryBadge: some View {
        let errors = doctor.checks.filter { $0.status == .error }.count
        let warnings = doctor.checks.filter { $0.status == .warning }.count
        
        return Group {
            if errors > 0 {
                Label("\(errors) 오류", systemImage: "xmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.red)
                    .clipShape(Capsule())
            } else if warnings > 0 {
                Label("\(warnings) 경고", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange)
                    .clipShape(Capsule())
            } else {
                Label("정상", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green)
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "stethoscope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\"진단 실행\" 을 클릭하여 시스템 상태를 점검하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Checks List
    
    private var checksList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(doctor.checks) { check in
                    checkRow(check)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func checkRow(_ check: DoctorService.DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon
            statusIcon(check.status)
                .frame(width: 20)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(check.title)
                        .font(.subheadline.bold())
                    
                    Text(check.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Fix button
            if let action = check.fixAction, check.status != .ok {
                Button(fixButtonLabel(action)) {
                    doctor.performFix(action, appState: appState)
                    // Re-run after fix
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        doctor.runAllChecks(appState: appState)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(checkRowBackground(check.status))
    }
    
    private func statusIcon(_ status: DoctorService.DoctorCheck.Status) -> some View {
        switch status {
        case .ok:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .warning:
            return Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .error:
            return Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private func checkRowBackground(_ status: DoctorService.DoctorCheck.Status) -> Color {
        switch status {
        case .ok: return .clear
        case .warning: return .orange.opacity(0.05)
        case .error: return .red.opacity(0.05)
        }
    }
    
    private func fixButtonLabel(_ action: DoctorService.DoctorCheck.FixAction) -> String {
        switch action {
        case .openAccessibility: return "설정 열기"
        case .stopEngine: return "중지"
        case .restartEngine: return "재시작"
        case .resetAll: return "초기화"
        case .openSystemSettings: return "설정 열기"
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            // Emergency Recovery button
            Button(role: .destructive) {
                showRecoveryConfirm = true
            } label: {
                Label("긴급 복구", systemImage: "arrow.counterclockwise.circle.fill")
            }
            .buttonStyle(.bordered)
            .help("엔진 정지, 설정 초기화, 모든 키 매핑 해제")
            
            Spacer()
            
            if let date = doctor.lastRunDate {
                Text("마지막 진단: \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("진단 실행") {
                doctor.runAllChecks(appState: appState)
            }
            .buttonStyle(.borderedProminent)
            .disabled(doctor.isRunning)
        }
        .padding(16)
    }
}

#Preview {
    DoctorView()
        .environmentObject(AppState())
}
