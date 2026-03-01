import SwiftUI

/// 로그 뷰어 & 피드백 내보내기
struct LogView: View {
    @ObservedObject private var logService = LogService.shared
    @State private var filterText = ""
    @State private var selectedLevel: LogService.LogEntry.Level? = nil
    @State private var showCopiedToast = false
    
    var filteredEntries: [LogService.LogEntry] {
        var result = logService.entries
        
        if let level = selectedLevel {
            result = result.filter { $0.level == level }
        }
        
        if !filterText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(filterText) ||
                $0.category.localizedCaseInsensitiveContains(filterText)
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Log entries
            logList
            
            Divider()
            
            // Status bar
            statusBar
        }
        .frame(minWidth: 650, minHeight: 420)
        .overlay(alignment: .top) {
            if showCopiedToast {
                toastView
            }
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 10) {
            // Level filter
            Picker("", selection: $selectedLevel) {
                Text("전체").tag(nil as LogService.LogEntry.Level?)
                Text("ℹ️ Info").tag(LogService.LogEntry.Level.info as LogService.LogEntry.Level?)
                Text("⚠️ Warn").tag(LogService.LogEntry.Level.warning as LogService.LogEntry.Level?)
                Text("❌ Error").tag(LogService.LogEntry.Level.error as LogService.LogEntry.Level?)
                Text("🔍 Debug").tag(LogService.LogEntry.Level.debug as LogService.LogEntry.Level?)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            Spacer()
            
            TextField("검색...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            
            // Export menu
            Menu {
                Button("클립보드에 복사 (피드백용)") {
                    logService.copyToClipboard()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                }
                
                Button("Finder에서 열기") {
                    logService.revealInFinder()
                }
                
                Divider()
                
                Button("화면 로그 지우기") {
                    logService.clearMemoryLogs()
                }
                
                Button("전체 로그 삭제", role: .destructive) {
                    logService.clearAllLogs()
                }
            } label: {
                Label("내보내기", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Log List
    
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
            }
            .onChange(of: logService.entries.count) { _, _ in
                if let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func logRow(_ entry: LogService.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(dateFormat(entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level badge
            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 38, alignment: .center)
            
            // Category
            Text(entry.category)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 80, alignment: .leading)
            
            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(rowBackground(entry.level))
    }
    
    private func levelColor(_ level: LogService.LogEntry.Level) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
    
    private func rowBackground(_ level: LogService.LogEntry.Level) -> Color {
        switch level {
        case .error: return .red.opacity(0.06)
        case .warning: return .orange.opacity(0.04)
        default: return .clear
        }
    }
    
    private func dateFormat(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(logService.isLogging ? .green : .gray)
                    .frame(width: 6, height: 6)
                Text(logService.isLogging ? "기록 중" : "일시 정지")
                    .font(.caption)
            }
            
            Divider().frame(height: 12)
            
            Text("항목: \(filteredEntries.count) / \(logService.entries.count)")
                .font(.caption)
            
            Divider().frame(height: 12)
            
            Text("파일: \(logService.logFileSize)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Divider().frame(height: 12)
            
            Text(logService.logFileURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            
            Spacer()
            
            Toggle("로깅", isOn: $logService.isLogging)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Toast
    
    private var toastView: some View {
        Text("✅ 클립보드에 복사됨")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.green)
            .clipShape(Capsule())
            .shadow(radius: 4)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: showCopiedToast)
    }
}

#Preview {
    LogView()
}
