import SwiftUI

/// 업데이트 확인 뷰
/// GitHub Releases에서 자동 다운로드 + 설치 + 재시작
struct UpdateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showInstallConfirm = false

    private var updateService: UpdateService { appState.updateService }
    
    var body: some View {
        VStack(spacing: 20) {
            // 헤더
            header
            
            Divider()
            
            // 현재 버전 정보
            currentVersionInfo
            
            // 다운로드/설치 진행 중
            if updateService.isDownloading {
                downloadProgressView
            }
            // 업데이트 상태
            else if updateService.isCheckingForUpdates {
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
        .frame(width: 400, height: 380)
        .task {
            await updateService.checkForUpdates()
        }
        .confirmationDialog(
            "업데이트를 설치하시겠습니까?",
            isPresented: $showInstallConfirm,
            titleVisibility: .visible
        ) {
            Button("설치 및 재시작") {
                Task {
                    await updateService.downloadAndInstall()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("""
            v\(updateService.latestVersion ?? "?")을 다운로드하고 설치합니다.
            앱이 자동으로 재시작됩니다.
            접근성 권한은 유지됩니다.
            """)
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
    
    private var downloadProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: updateService.downloadProgress)
                .progressViewStyle(.linear)
            
            Text(updateService.updateStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("\(Int(updateService.downloadProgress * 100))%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.blue)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var updateAvailableView: some View {
        VStack(spacing: 16) {
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
            
            if updateService.isDownloading {
                // 다운로드 중에는 버튼 비활성화
                Button("설치 중...") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if updateService.updateAvailable {
                Button("다운로드 및 설치") {
                    showInstallConfirm = true
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
    @EnvironmentObject var appState: AppState
    @State private var showUpdateSheet = false

    private var updateService: UpdateService { appState.updateService }
    
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
                .environmentObject(appState)
        }
        .task {
            if updateService.autoCheckEnabled {
                await updateService.checkForUpdates()
            }
        }
    }
}

#Preview {
    UpdateView()
        .environmentObject(AppState())
}
