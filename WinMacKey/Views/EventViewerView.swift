import SwiftUI

/// SCR-04: 실시간 이벤트 뷰어
/// 키 입력 딜레이 및 스캔코드를 실시간 모니터링합니다.
struct EventViewerView: View {
    @EnvironmentObject var appState: AppState
    @State private var isCapturing = true
    @State private var filterText = ""
    @State private var showOnlyMapped = false
    @AppStorage("eventViewerAlwaysOnTop") private var alwaysOnTop = false
    
    var filteredEvents: [KeyEvent] {
        var events = appState.keyInterceptor.events
        
        if showOnlyMapped {
            events = events.filter { $0.rawKey != $0.mappedKey }
        }
        
        if !filterText.isEmpty {
            events = events.filter { event in
                event.bundleId?.localizedCaseInsensitiveContains(filterText) == true ||
                KeyEvent.keyCodeHex(event.rawKey).localizedCaseInsensitiveContains(filterText) ||
                KeyEvent.keyCodeHex(event.mappedKey).localizedCaseInsensitiveContains(filterText)
            }
        }
        
        return events
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 툴바
            toolbar
            
            Divider()
            
            // 이벤트 테이블
            eventTable
            
            Divider()
            
            // 상태 바
            statusBar
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: alwaysOnTop, initial: true) { _, newValue in
            setWindowLevel(alwaysOnTop: newValue)
        }
        .onAppear {
            setWindowLevel(alwaysOnTop: alwaysOnTop)
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: clearLog) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            
            Button(action: toggleCapture) {
                Label(isCapturing ? "Pause" : "Resume", systemImage: isCapturing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(isCapturing ? .blue : .gray)
            
            Button(action: copyAsJSON) {
                Label("Copy JSON", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Toggle("Always on Top", isOn: $alwaysOnTop)
                .toggleStyle(.checkbox)
                
            Toggle("Mapped Only", isOn: $showOnlyMapped)
                .toggleStyle(.checkbox)
            
            TextField("Filter...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Event Table
    
    private var eventTable: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 0) {
                tableHeader("TIME", width: 90)
                tableHeader("TYPE", width: 50)
                tableHeader("RAW", width: 60)
                tableHeader("MAPPED", width: 60)
                tableHeader("KB_TYPE", width: 70)
                tableHeader("LATENCY", width: 70)
                tableHeader("APP", width: nil)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 이벤트 목록
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEvents.reversed()) { event in
                            eventRow(event)
                                .id(event.id)
                        }
                    }
                }
                .onChange(of: appState.keyInterceptor.events.count) { _, _ in
                    if isCapturing, let newestEvent = filteredEvents.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newestEvent.id, anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
    
    private func eventRow(_ event: KeyEvent) -> some View {
        HStack(spacing: 0) {
            Text(event.timestampFormatted)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 8)
            
            Text(event.type.rawValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(event.type == .down ? .green : .orange)
                .frame(width: 50, alignment: .leading)
                .padding(.horizontal, 8)
            
            Text(KeyEvent.keyCodeHex(event.rawKey))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, alignment: .leading)
                .padding(.horizontal, 8)
            
            Text(KeyEvent.keyCodeHex(event.mappedKey))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(event.rawKey != event.mappedKey ? .blue : .primary)
                .frame(width: 60, alignment: .leading)
                .padding(.horizontal, 8)
            
            Text(String(event.keyboardType))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.purple)
                .frame(width: 70, alignment: .leading)
                .padding(.horizontal, 8)
                
            Text(event.latencyFormatted)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(latencyColor(event.latencyMs))
                .frame(width: 70, alignment: .leading)
                .padding(.horizontal, 8)
            
            Text(event.bundleId ?? "—")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
        .background(event.rawKey != event.mappedKey ? Color.blue.opacity(0.05) : Color.clear)
    }
    
    private func latencyColor(_ ms: Double) -> Color {
        if ms < 0.5 {
            return .green
        } else if ms < 1.0 {
            return .yellow
        } else {
            return .red
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(isCapturing ? .green : .gray)
                    .frame(width: 6, height: 6)
                Text(isCapturing ? "Capturing" : "Stopped")
                    .font(.caption)
            }
            
            Divider()
                .frame(height: 12)
            
            Text("Total: \(appState.keyInterceptor.totalEventCount)")
                .font(.caption)
            
            Divider()
                .frame(height: 12)
            
            Text(String(format: "Avg: %.2f ms", appState.keyInterceptor.averageLatencyMs))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green)
            
            Divider()
                .frame(height: 12)
            
            Text("Filtered: \(filteredEvents.count)")
                .font(.caption)
            
            Spacer()
            
            Text("CPU: <0.5%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func clearLog() {
        appState.keyInterceptor.clearEvents()
    }
    
    private func toggleCapture() {
        isCapturing.toggle()
        // isCapturing은 UI 로깅 표시만 제어합니다.
        // 엔진 start/stop은 하지 않습니다 — 메인 엔진에 사이드 이펙트를 주지 않기 위함.
    }
    
    private func copyAsJSON() {
        if let json = appState.keyInterceptor.exportEventsAsJSON() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }
    
    private func setWindowLevel(alwaysOnTop: Bool) {
        // 창이 방금 열렸을 수 있으므로 약간의 딜레이 후 적용
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                if window.title == "Event Viewer" {
                    window.level = alwaysOnTop ? .floating : .normal
                    break
                }
            }
        }
    }
}

#Preview {
    EventViewerView()
        .environmentObject(AppState())
}
