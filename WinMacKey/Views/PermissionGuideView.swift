import SwiftUI

/// SCR-01: 권한 가이드 화면
/// 초기 실행 시 시스템 권한(손쉬운 사용) 획득을 안내합니다.
struct PermissionGuideView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    
    var body: some View {
        VStack(spacing: 24) {
            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                
                Text("WinMac Key 설정")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("키보드 이벤트를 감지하려면 손쉬운 사용 권한이 필요합니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            Divider()
            
            // 단계별 가이드
            VStack(alignment: .leading, spacing: 16) {
                stepRow(
                    number: 1,
                    title: "시스템 설정 열기",
                    description: "아래 버튼을 클릭하여 보안 및 개인정보 보호 설정을 엽니다",
                    isCompleted: currentStep > 0
                )
                
                stepRow(
                    number: 2,
                    title: "손쉬운 사용 선택",
                    description: "좌측 메뉴에서 '손쉬운 사용'을 클릭합니다",
                    isCompleted: currentStep > 1
                )
                
                stepRow(
                    number: 3,
                    title: "WinMac Key 허용",
                    description: "앱 목록에서 WinMac Key를 찾아 체크박스를 활성화합니다",
                    isCompleted: appState.hasAccessibilityPermission
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            // 액션 버튼
            VStack(spacing: 12) {
                Button(action: openSettings) {
                    Label("시스템 설정 열기", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: checkPermission) {
                    Label("권한 다시 확인", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            // 권한 상태 표시
            HStack {
                Circle()
                    .fill(appState.hasAccessibilityPermission ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(appState.hasAccessibilityPermission ? "권한 획득됨" : "권한 필요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)
        }
        .padding(24)
        .frame(width: 400, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityPermissionGranted)) { _ in
            appState.checkPermissions()
        }
    }
    
    private func stepRow(number: Int, title: String, description: String, isCompleted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isCompleted ? .green : .blue)
                    .frame(width: 28, height: 28)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func openSettings() {
        currentStep = 1
        appState.permissionService.openAccessibilitySettings()
    }
    
    private func checkPermission() {
        appState.checkPermissions()
    }
}

#Preview {
    PermissionGuideView()
        .environmentObject(AppState())
}
