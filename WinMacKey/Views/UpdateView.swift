import SwiftUI

/// 업데이트 확인 뷰
/// 수동 업데이트 체크 및 다운로드 기능을 제공합니다.
struct UpdateView: View {
    @StateObject private var updateService = UpdateService()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 헤더
            header
            
            Divider()
            
            // 현재 버전 정보
            currentVersionInfo
            
            // 업데이트 상태
            if updateService.isCheckingForUpdates {
                checkingView
            } else if updateService.updateAvailable {
                updateAvailableView
            } else if updateService.latestVersion != nil {
                upToDateView
            }
            
            // 에러 표시
            if let error = updateService.error {
                errorView(error)
            }
            
            Spacer()
            
            // 액션 버튼
            actionButtons
            
            // 마지막 체크 시간
            if let timeSince = updateService.timeSinceLastCheck {
                Text("마지막 확인: \(timeSince)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 400, height: 350)
        .task {
            // 처음 열 때 자동으로 체크
            await updateService.checkForUpdates()
        }
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("소프트웨어 업데이트")
                    .font(.title2.bold())
                
                Text("WinMac Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var currentVersionInfo: some View {
        HStack {
            Text("현재 버전")
                .foregroundStyle(.secondary)
            Spacer()
            Text("v\(updateService.currentVersion)")
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal)
    }
    
    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("업데이트 확인 중...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var updateAvailableView: some View {
        VStack(spacing: 16) {
            // 새 버전 정보
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("새 버전 사용 가능!")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text("v\(updateService.latestVersion ?? "?")")
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
            }
            .padding()
            .background(.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 릴리스 노트
            if let notes = updateService.releaseNotes, !notes.isEmpty {
                GroupBox("릴리스 노트") {
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 80)
                }
            }
        }
    }
    
    private var upToDateView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("최신 버전입니다")
                    .font(.headline)
                
                Text("WinMac Key가 최신 버전으로 업데이트되어 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func errorView(_ error: UpdateError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var actionButtons: some View {
        HStack {
            Button("GitHub Releases") {
                updateService.openReleasesPage()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if updateService.updateAvailable {
                Button("다운로드 및 설치") {
                    Task {
                        await updateService.downloadAndInstall()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("업데이트 확인") {
                    Task {
                        await updateService.checkForUpdates()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateService.isCheckingForUpdates)
            }
        }
    }
}

// MARK: - Settings에서 사용할 간단한 업데이트 Row

struct UpdateSettingsRow: View {
    @StateObject private var updateService = UpdateService()
    @State private var showUpdateSheet = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("버전")
                    
                    if updateService.updateAvailable {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                }
                
                Text("v\(updateService.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("업데이트 확인") {
                showUpdateSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .sheet(isPresented: $showUpdateSheet) {
            UpdateView()
        }
        .task {
            // 앱 시작 시 자동 체크 (설정된 경우)
            if updateService.autoCheckEnabled {
                await updateService.checkForUpdates()
            }
        }
    }
}

#Preview {
    UpdateView()
}
