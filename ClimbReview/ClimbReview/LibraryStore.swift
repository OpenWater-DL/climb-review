import Foundation
import Combine

// MARK: - LibraryStore（持久化）

class LibraryStore: ObservableObject {
    @Published var data: LibraryData = LibraryData()

    private let saveURL: URL
    let thumbnailsDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClimbReview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("library.json")
        thumbnailsDirectory = dir.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: 持久化

    func save() {
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            print("LibraryStore save error: \(error)")
        }
    }

    private func load() {
        guard let raw = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(LibraryData.self, from: raw) else { return }
        data = decoded
    }

    // MARK: 视频条目 CRUD

    /// 通过 URL 添加（推荐，来自 NSOpenPanel 的 URL 有完整访问权限）
    @discardableResult
    func addEntry(url: URL) -> VideoEntry {
        let filePath = url.path
        if let idx = data.entries.firstIndex(where: { $0.filePath == filePath }) {
            var updated = data.entries[idx]
            updated.filePath = filePath
            updated.title = url.deletingPathExtension().lastPathComponent
            // 重复导入时刷新 bookmark，避免重启后无权限
            updated.bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            data.entries[idx] = updated
            save()

            // 若封面缺失则补充生成
            if updated.thumbnailPath == nil {
                let capturedEntry = updated
                let thumbDir = thumbnailsDirectory
                ThumbnailService.shared.generateThumbnail(for: capturedEntry, videoURL: url, thumbnailsDirectory: thumbDir) { [weak self] path in
                    guard let self, let path else { return }
                    if let idx = self.data.entries.firstIndex(where: { $0.id == capturedEntry.id }) {
                        self.data.entries[idx].thumbnailPath = path
                        self.save()
                    }
                }
            }
            return updated
        }
        var entry = VideoEntry(filePath: filePath)
        // 在沙盒内 NSOpenPanel 打开的 URL 有临时访问权，立即生成持久 bookmark
        entry.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        data.entries.append(entry)
        save()

        // 异步生成首帧封面
        let capturedEntry = entry
        let thumbDir = thumbnailsDirectory
        ThumbnailService.shared.generateThumbnail(for: capturedEntry, videoURL: url, thumbnailsDirectory: thumbDir) { [weak self] path in
            guard let self, let path else { return }
            if let idx = self.data.entries.firstIndex(where: { $0.id == capturedEntry.id }) {
                self.data.entries[idx].thumbnailPath = path
                self.save()
            }
        }

        return entry
    }

    @discardableResult
    func addEntry(filePath: String) -> VideoEntry {
        let url = URL(fileURLWithPath: filePath)
        return addEntry(url: url)
    }

    func updateEntry(_ entry: VideoEntry) {
        if let idx = data.entries.firstIndex(where: { $0.id == entry.id }) {
            data.entries[idx] = entry
            save()
        }
    }

    func deleteEntry(id: UUID) {
        // 联动删除封面文件
        if let entry = data.entries.first(where: { $0.id == id }),
           let thumbPath = entry.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }
        data.entries.removeAll { $0.id == id }
        // 同时从所有组中移除
        for i in data.groups.indices {
            data.groups[i].entryIDs.removeAll { $0 == id }
        }
        save()
    }

    // MARK: 分组 CRUD

    func addGroup(name: String) {
        let group = VideoGroup(name: name, entryIDs: [])
        data.groups.append(group)
        save()
    }

    func renameGroup(id: UUID, newName: String) {
        if let idx = data.groups.firstIndex(where: { $0.id == id }) {
            data.groups[idx].name = newName
            save()
        }
    }

    func deleteGroup(id: UUID) {
        data.groups.removeAll { $0.id == id }
        save()
    }

    func addEntry(_ entryID: UUID, toGroup groupID: UUID) {
        if let idx = data.groups.firstIndex(where: { $0.id == groupID }) {
            if !data.groups[idx].entryIDs.contains(entryID) {
                data.groups[idx].entryIDs.append(entryID)
                save()
            }
        }
    }

    func removeEntry(_ entryID: UUID, fromGroup groupID: UUID) {
        if let idx = data.groups.firstIndex(where: { $0.id == groupID }) {
            data.groups[idx].entryIDs.removeAll { $0 == entryID }
            save()
        }
    }

    // MARK: 便利查询

    func entries(inGroup group: VideoGroup) -> [VideoEntry] {
        group.entryIDs.compactMap { id in data.entries.first { $0.id == id } }
    }

    func allTags() -> [String] {
        Array(Set(data.entries.flatMap { $0.tags })).sorted()
    }

    func entries(withTag tag: String) -> [VideoEntry] {
        data.entries.filter { $0.tags.contains(tag) }
    }
}
