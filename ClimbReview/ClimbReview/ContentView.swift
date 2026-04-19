import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModelA = VideoPlayerViewModel()
    @StateObject private var viewModelB = VideoPlayerViewModel()
    @StateObject private var store = LibraryStore()

    @State private var showLibrary = false
    @State private var entryIDForA: UUID? = nil
    @State private var entryIDForB: UUID? = nil
    @State private var accessURLA: URL? = nil
    @State private var accessURLB: URL? = nil
    @State private var loadErrorMessage: String? = nil
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            // 背景底色
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                playerView
                    .padding(16)
            }
            
            // 视频库覆盖层
            if showLibrary {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            showLibrary = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(9)
                
                LibraryView(store: store) { entry, slot in
                    loadEntry(entry, slot: slot)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showLibrary = false
                    }
                }
                .frame(width: 800, height: 600)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear { setupSync() }
        .onChange(of: store.data.entries) { _ in
            cleanupMissingEntries()
        }
        .alert("无法打开视频", isPresented: Binding(
            get: { loadErrorMessage != nil },
            set: { if !$0 { loadErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(loadErrorMessage ?? "")
        }
    }

    // MARK: 顶部工具栏

    private var topBar: some View {
        HStack(spacing: 16) {
            Text("CLIMB REVIEW")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundColor(AppTheme.textPrimary.opacity(0.6))

            Spacer()

            HStack(spacing: 12) {
                Button { syncPlayFromStart() } label: {
                    Label("同步播放", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(!viewModelA.hasVideo && !viewModelB.hasVideo)

                Button { syncPause() } label: {
                    Label("同步暂停", systemImage: "pause.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(!viewModelA.isPlaying && !viewModelB.isPlaying)
            }

            Divider().frame(height: 20)

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showLibrary.toggle()
                }
            } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(showLibrary ? AppTheme.primary : AppTheme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(showLibrary ? AppTheme.primary.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("打开视频库")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.background)
    }

    // MARK: 播放器视图

    private var playerView: some View {
        HStack(spacing: 20) {
            VideoPlayerPanel(panelTitle: "SIDE A", viewModel: viewModelA, entryID: entryIDForA, store: store)
                .alpineCard()
            VideoPlayerPanel(panelTitle: "SIDE B", viewModel: viewModelB, entryID: entryIDForB, store: store)
                .alpineCard()
        }
    }

    // MARK: 从库加载条目

    private func loadEntry(_ entry: VideoEntry, slot: VideoSlot) {
        let vm = slot == .a ? viewModelA : viewModelB

        stopAccessing(slot: slot)
        guard let url = resolveURL(for: entry, slot: slot) else { return }

        vm.loadVideo(url: url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let err = vm.lastErrorMessage {
                presentLoadError(err)
                return
            }
            if let sp = entry.startPoint { vm.startPoint = sp }
            vm.markers = entry.markers
            if slot == .a { self.entryIDForA = entry.id }
            else          { self.entryIDForB = entry.id }
        }
    }

    // MARK: 访问权限与清理

    private func resolveURL(for entry: VideoEntry, slot: VideoSlot) -> URL? {
        // 优先尝试 Security-Scoped Bookmark（沙盒持久权限）
        if let bookmarkData = entry.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let accessOK = url.startAccessingSecurityScopedResource()
                if accessOK {
                    setAccessURL(url, slot: slot)
                    // Stale bookmark 自动刷新
                    if isStale, let fresh = try? url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        var updated = entry
                        updated.bookmarkData = fresh
                        store.updateEntry(updated)
                    }
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                    // 文件已移动或删除
                    stopAccessing(slot: slot)
                    presentLoadError("视频文件不存在或已移动，请重新导入或删除无效条目。")
                    return nil
                }
                // bookmark 解析成功但 startAccessing 失败，fallback 到路径直接访问
            }
            // bookmark 解析失败（如 Debug 重签导致 App-Scope 失效），fallback 到路径直接访问
        }

        // Fallback：直接使用文件路径（非 App Store 沙盒环境，或 bookmark 失效时）
        let url = entry.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            presentLoadError("视频文件不存在或已移动，请重新导入或删除无效条目。")
            return nil
        }
        return url
    }

    private func setAccessURL(_ url: URL, slot: VideoSlot) {
        switch slot {
        case .a:
            accessURLA = url
        case .b:
            accessURLB = url
        }
    }

    private func stopAccessing(slot: VideoSlot) {
        switch slot {
        case .a:
            accessURLA?.stopAccessingSecurityScopedResource()
            accessURLA = nil
        case .b:
            accessURLB?.stopAccessingSecurityScopedResource()
            accessURLB = nil
        }
    }

    private func cleanupMissingEntries() {
        if let id = entryIDForA,
           !store.data.entries.contains(where: { $0.id == id }) {
            entryIDForA = nil
            stopAccessing(slot: .a)
            viewModelA.unload()
        }
        if let id = entryIDForB,
           !store.data.entries.contains(where: { $0.id == id }) {
            entryIDForB = nil
            stopAccessing(slot: .b)
            viewModelB.unload()
        }
    }

    private func presentLoadError(_ message: String) {
        loadErrorMessage = message
    }

    // MARK: ViewModel → LibraryStore 实时同步

    private func setupSync() {
        // A：markers
        viewModelA.$markers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { markers in
                guard let id = entryIDForA,
                      var entry = store.data.entries.first(where: { $0.id == id })
                else { return }
                entry.markers = markers
                store.updateEntry(entry)
            }
            .store(in: &cancellables)

        // A：startPoint
        viewModelA.$startPoint
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { sp in
                guard let id = entryIDForA,
                      var entry = store.data.entries.first(where: { $0.id == id })
                else { return }
                entry.startPoint = sp
                store.updateEntry(entry)
            }
            .store(in: &cancellables)

        // B：markers
        viewModelB.$markers
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { markers in
                guard let id = entryIDForB,
                      var entry = store.data.entries.first(where: { $0.id == id })
                else { return }
                entry.markers = markers
                store.updateEntry(entry)
            }
            .store(in: &cancellables)

        // B：startPoint
        viewModelB.$startPoint
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { sp in
                guard let id = entryIDForB,
                      var entry = store.data.entries.first(where: { $0.id == id })
                else { return }
                entry.startPoint = sp
                store.updateEntry(entry)
            }
            .store(in: &cancellables)
    }

    // MARK: 同步播放

    private func syncPlayFromStart() {
        viewModelA.seekToStart()
        viewModelB.seekToStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if viewModelA.hasVideo { viewModelA.play() }
            if viewModelB.hasVideo { viewModelB.play() }
        }
    }

    private func syncPause() {
        viewModelA.pause()
        viewModelB.pause()
    }

}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    ContentView()
}
