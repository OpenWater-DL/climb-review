import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件库主视图

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    /// 双击条目时回调，传出 VideoEntry 供主界面加载
    var onOpen: (VideoEntry, VideoSlot) -> Void

    @State private var selection: LibrarySelection = .all
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var searchText = ""
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarList
                    .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
                    .frame(width: 200)
                    .transition(.move(edge: .leading))
                
                Divider()
            }
            
            entryGrid
                .background(AppTheme.background.opacity(0.5))
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: 侧边栏

    private var sidebarList: some View {
        List(selection: $selection) {
            // 全部
            Label("全部视频", systemImage: "film.stack.fill")
                .tag(LibrarySelection.all)

            // 分组
            Section {
                ForEach(store.data.groups) { group in
                    Label(group.name, systemImage: "folder.fill")
                        .tag(LibrarySelection.group(group.id))
                        .contextMenu {
                            Button("删除分组", role: .destructive) {
                                store.deleteGroup(id: group.id)
                            }
                        }
                }
                
                Button {
                    newGroupName = ""
                    showNewGroup = true
                } label: {
                    Label("新建分组", systemImage: "plus.circle")
                        .foregroundColor(AppTheme.primary)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
            } header: {
                Text("我的分组")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary.opacity(0.8))
            }

            // 标签
            let tags = store.allTags()
            if !tags.isEmpty {
                Section {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag.fill")
                            .tag(LibrarySelection.tag(tag))
                    }
                } header: {
                    Text("标签")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary.opacity(0.8))
                }
            }
        }
        .listStyle(.sidebar)
        .alert("新建分组", isPresented: $showNewGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                if !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.addGroup(name: newGroupName.trimmingCharacters(in: .whitespaces))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 条目网格

    private var currentEntries: [VideoEntry] {
        let base: [VideoEntry]
        switch selection {
        case .all:
            base = store.data.entries
        case .group(let id):
            let group = store.data.groups.first { $0.id == id }
            base = group.map { store.entries(inGroup: $0) } ?? []
        case .tag(let t):
            base = store.entries(withTag: t)
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText) ||
            $0.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var entryGrid: some View {
        VStack(spacing: 0) {
            // 搜索栏与内部工具栏
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(showSidebar ? AppTheme.primary : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("切换侧边栏")

                Button {
                    addVideoToLibrary()
                } label: {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .help("导入视频")

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索标题、标签、备注…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 240)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))

            Divider()

            if currentEntries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "film.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无视频\n点击左上角 + 添加")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(currentEntries) { entry in
                            EntryCardView(
                                entryID: entry.id,
                                store: store,
                                groups: store.data.groups,
                                onOpenA: { onOpen(entry, .a) },
                                onOpenB: { onOpen(entry, .b) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: 添加视频到库

    private func addVideoToLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = store.addEntry(url: url)
            }
        }
    }
}

// MARK: - 侧边栏选中状态

enum LibrarySelection: Hashable {
    case all
    case group(UUID)
    case tag(String)
}

// MARK: - 加载到哪个槽

enum VideoSlot {
    case a, b
}

// MARK: - 条目卡片

struct EntryCardView: View {
    let entryID: UUID
    @ObservedObject var store: LibraryStore
    let groups: [VideoGroup]
    let onOpenA: () -> Void
    let onOpenB: () -> Void

    @State private var showDetail = false
    @State private var showDeleteConfirm = false
    @State private var isTargeted = false
    @State private var thumbnail: NSImage? = nil

    /// 始终从 store 获取最新 entry，确保封面更新时自动刷新
    private var entry: VideoEntry? {
        store.data.entries.first { $0.id == entryID }
    }

    var body: some View {
        guard let entry else { return AnyView(EmptyView()) }
        return AnyView(cardContent(entry: entry))
    }

    @ViewBuilder
    private func cardContent(entry: VideoEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 缩略图区
            ZStack {
                Rectangle()
                    .fill(AppTheme.background)
                    .frame(height: 120)
                
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 32))
                        Text("未加载预览")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(AppTheme.primary.opacity(0.3))
                }
                
                // 渐变蒙层
                LinearGradient(colors: [.black.opacity(0.4), .clear, .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 120)
            .onAppear { loadThumbnail(path: entry.thumbnailPath) }
            .onChange(of: entry.thumbnailPath) { path in loadThumbnail(path: path) }
            .overlay(alignment: .topTrailing) {
                if entry.startPoint != nil {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(AppTheme.accent)
                        .clipShape(Circle())
                        .padding(8)
                        .shadow(radius: 4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !entry.markers.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                        Text("\(entry.markers.count)")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // 标题
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                // 标签
                if !entry.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.primary.opacity(0.1))
                                .foregroundColor(AppTheme.primary)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 8)

                // 操作按钮
                HStack(spacing: 8) {
                    Button { onOpenA() } label: {
                        Text("SIDE A")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(AppTheme.primary.opacity(0.1))
                            .foregroundColor(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button { onOpenB() } label: {
                        Text("SIDE B")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(AppTheme.primary.opacity(0.1))
                            .foregroundColor(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDetail = true
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.textSecondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .shadow(color: AppTheme.shadowColor, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { _ in false }
        .sheet(isPresented: $showDetail) {
            EntryDetailView(entryID: entryID, store: store, groups: groups)
        }
        .contextMenu {
            Button("删除视频", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .alert("删除该视频？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteEntry(id: entry.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从视频库中移除该条目，并删除对应封面文件。")
        }
    }

    private func loadThumbnail(path: String?) {
        guard let path else {
            thumbnail = nil
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOfFile: path)
            DispatchQueue.main.async { thumbnail = img }
        }
    }
}

// MARK: - 条目详情编辑 Sheet

struct EntryDetailView: View {
    let entryID: UUID
    @ObservedObject var store: LibraryStore
    let groups: [VideoGroup]
    @Environment(\.dismiss) private var dismiss

    @State private var newTag = ""
    @State private var showDeleteConfirm = false

    private var entry: VideoEntry? {
        store.data.entries.first { $0.id == entryID }
    }

    var body: some View {
        guard let entry else {
            return AnyView(Text("视频已被删除").padding())
        }
        return AnyView(detailContent(entry: entry))
    }

    @ViewBuilder
    private func detailContent(entry: VideoEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("视频详情")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            Form {
                Section("基本信息") {
                    LabeledContent("文件名") {
                        Text(entry.title)
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("路径") {
                        Text(entry.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    if let sp = entry.startPoint {
                        LabeledContent("已设起点") {
                            Text(formatTime(sp))
                                .foregroundColor(.orange)
                        }
                    }
                    LabeledContent("打点数量") {
                        Text("\(entry.markers.count) 个")
                    }
                }

                Section("备注") {
                    TextEditor(text: Binding(
                        get: { entry.note },
                        set: { newNote in
                            var updated = entry
                            updated.note = newNote
                            store.updateEntry(updated)
                        }
                    ))
                    .frame(height: 60)
                }

                Section("标签") {
                    FlowTagView(tags: Binding(
                        get: { entry.tags },
                        set: { newTags in
                            var updated = entry
                            updated.tags = newTags
                            store.updateEntry(updated)
                        }
                    ))
                    HStack {
                        TextField("添加标签…", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addTag(entry: entry) }
                        Button("添加") { addTag(entry: entry) }
                            .buttonStyle(.bordered)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("所在分组") {
                    ForEach(groups) { group in
                        let inGroup = group.entryIDs.contains(entry.id)
                        Toggle(group.name, isOn: Binding(
                            get: { inGroup },
                            set: { val in
                                if val { store.addEntry(entry.id, toGroup: group.id) }
                                else { store.removeEntry(entry.id, fromGroup: group.id) }
                            }
                        ))
                    }
                    if groups.isEmpty {
                        Text("暂无分组，可在侧边栏创建")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("管理") {
                    Button("删除视频", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .formStyle(.grouped)
            .alert("删除该视频？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    store.deleteEntry(id: entry.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将从视频库中移除该条目，并删除对应封面文件。")
            }
        }
        .frame(width: 420, height: 540)
    }

    private func addTag(entry: VideoEntry) {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !entry.tags.contains(t) else { return }
        var updated = entry
        updated.tags.append(t)
        store.updateEntry(updated)
        newTag = ""
    }

    private func formatTime(_ s: Double) -> String {
        let i = Int(s)
        return String(format: "%d:%02d", i / 60, i % 60)
    }
}

// MARK: - 标签流式布局

struct FlowTagView: View {
    @Binding var tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text(tag)
                        .font(.caption)
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - 简易流式布局容器

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
