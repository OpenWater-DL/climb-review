import SwiftUI
import AVFoundation
import AVKit

// MARK: - ViewModel

class VideoPlayerViewModel: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var hasVideo = false
    @Published var videoTitle = "未加载视频"
    @Published var lastErrorMessage: String? = nil

    /// 起点时间（秒），nil 表示未设置
    @Published var startPoint: Double? = nil

    /// 打点列表
    @Published var markers: [Marker] = []

    private var timeObserver: Any?
    private var durationObserver: NSKeyValueObservation?
    private var playbackLikelyObserver: NSKeyValueObservation?

    init() {
        addTimeObserver()
    }

    deinit {
        removeTimeObserver()
        durationObserver?.invalidate()
        playbackLikelyObserver?.invalidate()
    }

    // MARK: 加载视频

    func loadVideo(url: URL) {
        // 先重置状态，避免残留
        isPlaying = false
        currentTime = 0
        duration = 0
        hasVideo = false
        videoTitle = "未加载视频"
        lastErrorMessage = nil
        startPoint = nil
        markers = []

        // 清理旧的观察者
        playbackLikelyObserver?.invalidate()
        playbackLikelyObserver = nil

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        durationObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.duration = item.duration.seconds.isNaN ? 0 : item.duration.seconds
                    self.hasVideo = true
                    self.videoTitle = url.deletingPathExtension().lastPathComponent
                    self.lastErrorMessage = nil
                    // 等待第一帧准备好再 seek，修复黑屏问题
                    self.waitForFirstFrame(item: item)
                case .failed:
                    self.duration = 0
                    self.hasVideo = false
                    self.videoTitle = "未加载视频"
                    self.lastErrorMessage = item.error?.localizedDescription ?? "视频加载失败，可能没有权限访问该文件。"
                default:
                    break
                }
            }
        }

        player.replaceCurrentItem(with: item)
        // 不再立即 seek，改在 waitForFirstFrame 中处理
    }

    /// 等待第一帧准备好后再 seek 到起点，确保正确显示首帧而非黑屏
    private func waitForFirstFrame(item: AVPlayerItem) {
        // 如果已经 likelyToKeepUp，直接 seek
        if item.isPlaybackLikelyToKeepUp {
            seekToStartAndPause()
            return
        }

        // 监听 isPlaybackLikelyToKeepUp，等待缓冲区有足够数据
        playbackLikelyObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.isPlaybackLikelyToKeepUp {
                self.playbackLikelyObserver?.invalidate()
                self.playbackLikelyObserver = nil
                self.seekToStartAndPause()
            }
        }

        // 超时保护：0.5 秒后强制 seek（避免某些情况下永远不触发）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.playbackLikelyObserver?.invalidate()
            self.playbackLikelyObserver = nil
            self.seekToStartAndPause()
        }
    }

    /// 跳转到起点并暂停，确保显示静态帧
    private func seekToStartAndPause() {
        let targetTime = startPoint ?? 0
        let time = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player.pause()
        currentTime = targetTime
    }

    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        hasVideo = false
        videoTitle = "未加载视频"
        lastErrorMessage = nil
        startPoint = nil
        markers = []
    }

    // MARK: 播放控制

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double, isUserScrubbing: Bool = true) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)

        // 关键修复：0 秒位置放宽容差，允许落到最近可解码关键帧，避免黑屏
        // 拖动/跳转到非 0 位置仍保持精准 seek
        let useRelaxedTolerance = clamped <= 0.02
        let tolerance: CMTime = useRelaxedTolerance ? .positiveInfinity : .zero

        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard let self, finished else { return }
            // 仅在非拖动场景下强制回写，避免与滑块实时回调打架
            if !isUserScrubbing || useRelaxedTolerance {
                self.currentTime = self.player.currentTime().seconds.isFinite ? self.player.currentTime().seconds : clamped
            }
        }

        if isUserScrubbing {
            currentTime = clamped
        }
    }

    func seekToStart() {
        seek(to: startPoint ?? 0)
    }

    func setStartPointToCurrent() {
        startPoint = currentTime
    }

    func clearStartPoint() {
        startPoint = nil
    }

    // MARK: 打点操作

    func addMarker(note: String) {
        let marker = Marker(time: currentTime, note: note)
        markers.append(marker)
        markers.sort { $0.time < $1.time }
    }

    func deleteMarker(_ marker: Marker) {
        markers.removeAll { $0.id == marker.id }
    }

    func updateMarker(_ marker: Marker, note: String) {
        if let idx = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[idx].note = note
        }
    }

    // MARK: 时间监听

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if !seconds.isNaN {
                self.currentTime = seconds
            }
            if let item = self.player.currentItem,
               item.duration.seconds > 0,
               seconds >= item.duration.seconds - 0.1 {
                self.isPlaying = false
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }
}

// MARK: - Panel View

struct VideoPlayerPanel: View {
    let panelTitle: String
    @ObservedObject var viewModel: VideoPlayerViewModel
    var entryID: UUID? = nil
    var store: LibraryStore? = nil

    @State private var isTargeted = false
    @State private var showStartPointEditor = false
    @State private var startPointInput = ""
    @State private var showMarkersPanel = false
    @State private var isCapturingCover = false
    @State private var isHovering = false
    @State private var isHoveringClearButton = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // 视频区域 + 打点列表侧栏
                HStack(spacing: 0) {
                    // 视频
                    VideoView(player: viewModel.player, hasVideo: viewModel.hasVideo)
                        .overlay {
                            if !viewModel.hasVideo {
                                dropHintOverlay
                            }
                        }
                        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                            handleDrop(providers: providers)
                        }
                        .overlay {
                            if isTargeted {
                                RoundedRectangle(cornerRadius: 0)
                                    .stroke(AppTheme.primary, lineWidth: 3)
                            }
                        }

                    // 打点列表侧栏
                    if showMarkersPanel {
                        Divider()
                        MarkerListView(viewModel: viewModel, showPanel: $showMarkersPanel)
                            .frame(width: 240)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()

                // 悬浮标题栏
                headerOverlay
                
                // 起点信息悬浮层（右下角）
                startPointOverlay
            }
            // 整个 ZStack 检测悬停，确保悬浮层上的交互不会导致悬停状态丢失
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }

            Divider()

            // 控制栏（含打点按钮）
            controlBar
        }
        .background(AppTheme.cardBackground)
        .animation(.easeInOut(duration: 0.2), value: showMarkersPanel)
    }

    // MARK: 悬浮标题栏
    
    private var headerOverlay: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(panelTitle)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                Text(viewModel.videoTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // 打点列表按钮
                IconLabelButton(
                    icon: "mappin.and.ellipse",
                    label: "打点列表",
                    badge: viewModel.markers.isEmpty ? nil : "\(viewModel.markers.count)",
                    isDisabled: !viewModel.hasVideo,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMarkersPanel.toggle()
                        }
                    }
                )

                // 添加视频按钮
                IconLabelButton(
                    icon: "folder.badge.plus",
                    label: "添加视频",
                    badge: nil,
                    isDisabled: false,
                    action: { openFilePicker() }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .offset(y: (isHovering && !showMarkersPanel) ? 0 : -10)
        .opacity((isHovering && !showMarkersPanel) ? 1 : 0)
    }

    // MARK: 起点信息悬浮层（左下角）
    
    private var startPointOverlay: some View {
        VStack {
            Spacer()
            HStack {
                // 起点信息在左侧
                HStack(spacing: 12) {
                    if let sp = viewModel.startPoint {
                        // 已设置起点状态
                        HStack(spacing: 8) {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                            
                            Text("起点：\(formatTime(sp))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                            
                            // 取消起点按钮 - 无底纯线风格，悬停显示背景
                            Button {
                                viewModel.clearStartPoint()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.25))
                                    .opacity(isHoveringClearButton ? 1 : 0)
                            )
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    isHoveringClearButton = hovering
                                }
                            }
                        }
                    } else {
                        // 未设置起点状态
                        Button {
                            viewModel.setStartPointToCurrent()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 12))
                                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                Text("将当前设置为起点")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .disabled(!viewModel.hasVideo)
                    }
                }
                .padding(.leading, 12)
                .padding(.bottom, 8)
                
                Spacer()
                
                // 设为封面按钮在右侧
                if viewModel.hasVideo, entryID != nil {
                    CoverButton(
                        isCapturing: isCapturingCover,
                        action: { setCoverToCurrent() }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        // 跟随标题栏的悬停显示逻辑
        .opacity((isHovering && viewModel.hasVideo) ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }

    private var startPointEditorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动输入起点时间（秒）")
                .font(.headline)
            HStack {
                TextField("例如：12.5", text: $startPointInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("秒")
                    .foregroundColor(.secondary)
            }
            Text("当前视频时长：\(formatTime(viewModel.duration))")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("确认") {
                    if let val = Double(startPointInput),
                       val >= 0, val <= viewModel.duration {
                        viewModel.startPoint = val
                        viewModel.seek(to: val)
                    }
                    showStartPointEditor = false
                }
                .buttonStyle(.borderedProminent)
                Button("取消") {
                    showStartPointEditor = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    // MARK: 拖放提示

    private var dropHintOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("拖入视频文件\n或点击「打开视频」")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    // MARK: 控制栏

    private var controlBar: some View {
        VStack(spacing: 12) {
            // 进度条（含起点 + 打点标记）
            ZStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { viewModel.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.duration, 0.01)
                )
                .accentColor(AppTheme.primary)
                .disabled(!viewModel.hasVideo)

                // 起点线 + 打点线
                if viewModel.duration > 0 {
                    GeometryReader { geo in
                        let trackWidth = geo.size.width - 24
                        // 起点标记
                        if let sp = viewModel.startPoint {
                            let x = 12 + trackWidth * (sp / viewModel.duration)
                            Rectangle()
                                .fill(AppTheme.accent)
                                .frame(width: 2, height: 10)
                                .position(x: x, y: geo.size.height / 2)
                        }
                        // 打点标记（蓝色菱形）
                        ForEach(viewModel.markers) { marker in
                            let x = 12 + trackWidth * (marker.time / viewModel.duration)
                            Circle()
                                .fill(AppTheme.primary)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: geo.size.height / 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 20)

            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 50, alignment: .leading)

                Spacer()

                HStack(spacing: 24) {
                    Button {
                        viewModel.seek(to: max(viewModel.currentTime - 5, 0))
                    } label: {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.textPrimary)
                    .disabled(!viewModel.hasVideo)

                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(AppTheme.primary)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(color: AppTheme.primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.hasVideo)

                    Button {
                        viewModel.seek(to: min(viewModel.currentTime + 5, viewModel.duration))
                    } label: {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.textPrimary)
                    .disabled(!viewModel.hasVideo)
                }

                Spacer()

                // 打点按钮
                AddMarkerButton(viewModel: viewModel)

                Text(formatTime(viewModel.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground)
    }

    // MARK: 设为封面

    private func setCoverToCurrent() {
        guard let entryID,
              let store,
              let entry = store.data.entries.first(where: { $0.id == entryID }),
              let item = viewModel.player.currentItem,
              let asset = item.asset as? AVURLAsset else { return }

        isCapturingCover = true
        let currentTime = viewModel.currentTime

        ThumbnailService.shared.captureThumbnail(
            for: entryID,
            videoURL: asset.url,
            at: currentTime,
            thumbnailsDirectory: store.thumbnailsDirectory
        ) { [self] path in
            isCapturingCover = false
            guard let path else { return }
            var updated = entry
            updated.thumbnailPath = path
            store.updateEntry(updated)
        }
    }

    // MARK: 打开文件

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            // 同步写入 store 以生成持久 bookmark，确保重启后仍可访问
            store?.addEntry(url: url)
            viewModel.loadVideo(url: url)
        }
    }

    // MARK: 拖放处理

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                // 同步写入 store 以生成持久 bookmark，确保重启后仍可访问
                self.store?.addEntry(url: url)
                self.viewModel.loadVideo(url: url)
            }
        }
        return true
    }

    // MARK: 工具函数

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - 添加打点按钮（带 Popover 输入）

// MARK: - 设为封面按钮（极简悬停提示）

struct CoverButton: View {
    let isCapturing: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 悬停背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .opacity(isHovering ? 1 : 0)
                
                // 内容容器 - 固定高度
                VStack(spacing: 8) {
                    if isCapturing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                            .offset(y: 4) // 初始状态整体下移
                    }
                    
                    Text("设为封面")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                        .opacity(isHovering ? 1 : 0)
                        .offset(y: isHovering ? 0 : -2)
                }
                .padding(.vertical, 6)
            }
            .frame(width: 44, height: 48) // 固定高度
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .offset(y: isHovering ? -5 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 图标+文字悬停按钮（通用组件）

struct IconLabelButton: View {
    let icon: String
    let label: String
    let badge: String?
    let isDisabled: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 悬停背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .opacity(isHovering ? 1 : 0)
                
                // 内容容器
                VStack(spacing: 8) {
                    ZStack {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                            .offset(y: 4)
                        
                        // 角标
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -8)
                        }
                    }
                    
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                        .opacity(isHovering ? 1 : 0)
                        .offset(y: isHovering ? 0 : -2)
                }
                .padding(.vertical, 6)
            }
            .frame(width: 44, height: 48)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .offset(y: isHovering ? -5 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 添加打点按钮（带 Popover 输入）

struct AddMarkerButton: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @State private var showPopover = false
    @State private var noteInput = ""

    var body: some View {
        Button {
            viewModel.pause()
            noteInput = ""
            showPopover = true
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.body)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasVideo)
        .help("在当前时间打点")
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("在 \(formatTime(viewModel.currentTime)) 添加打点")
                    .font(.headline)
                TextField("描述这个时刻…", text: $noteInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { confirmAdd() }
                HStack {
                    Button("确认添加") { confirmAdd() }
                        .buttonStyle(.borderedProminent)
                        .disabled(noteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("取消") { showPopover = false }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
    }

    private func confirmAdd() {
        let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.addMarker(note: trimmed)
        showPopover = false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 打点列表侧栏

struct MarkerListView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var showPanel: Bool
    @State private var editingMarker: Marker? = nil
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 侧栏标题
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPanel = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("关闭列表")

                Text("打点标记")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(viewModel.markers.count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.primary.opacity(0.1))
                    .foregroundColor(AppTheme.primary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(AppTheme.cardBackground)

            Divider()

            if viewModel.markers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.textSecondary.opacity(0.3))
                    Text("暂无打点标记")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.markers) { marker in
                        MarkerRowView(
                            marker: marker,
                            isEditing: editingMarker?.id == marker.id,
                            editText: $editText,
                            onJump: {
                                viewModel.seek(to: marker.time)
                            },
                            onEditStart: {
                                editingMarker = marker
                                editText = marker.note
                            },
                            onEditCommit: {
                                viewModel.updateMarker(marker, note: editText)
                                editingMarker = nil
                            },
                            onEditCancel: {
                                editingMarker = nil
                            },
                            onDelete: {
                                viewModel.deleteMarker(marker)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(AppTheme.background.opacity(0.3))
    }
}

// MARK: - 单条打点行

struct MarkerRowView: View {
    let marker: Marker
    let isEditing: Bool
    @Binding var editText: String
    let onJump: () -> Void
    let onEditStart: () -> Void
    let onEditCommit: () -> Void
    let onEditCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 时间戳 - 点击跳转
                Button {
                    onJump()
                } label: {
                    Text(formatTime(marker.time))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 12) {
                    Button { onEditStart() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.textSecondary)

                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.textSecondary)
                }
            }

            if isEditing {
                HStack(spacing: 6) {
                    TextField("编辑描述…", text: $editText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { onEditCommit() }
                    
                    Button { onEditCommit() } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppTheme.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button { onEditCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(marker.note)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - AVKit VideoView 包装

struct VideoView: NSViewRepresentable {
    let player: AVPlayer
    let hasVideo: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
