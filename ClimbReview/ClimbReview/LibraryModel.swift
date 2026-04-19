import Foundation

// MARK: - 视频条目

struct VideoEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var filePath: String           // 视频文件的绝对路径（只记路径，不复制）
    var bookmarkData: Data? = nil  // Security-Scoped Bookmark，用于沙盒内持久访问
    var title: String              // 显示名称（默认取文件名）
    var tags: [String]             // 标签列表，如 ["红点", "室内", "技术"]
    var note: String               // 备注
    var addedAt: Date = Date()
    var startPoint: Double? = nil  // 起点时间（秒）
    var markers: [Marker]          // 打点列表
    var thumbnailPath: String? = nil  // 封面缩略图文件路径（jpg），nil 表示未生成

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    init(filePath: String) {
        self.filePath = filePath
        self.title = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        self.tags = []
        self.note = ""
        self.markers = []
    }
}

// MARK: - 视频组

struct VideoGroup: Identifiable, Codable {
    var id = UUID()
    var name: String               // 组名，如 "比赛复盘"、"训练记录"
    var entryIDs: [UUID]           // 组内视频条目的 id
    var createdAt: Date = Date()
}

// MARK: - 库数据根

struct LibraryData: Codable {
    var entries: [VideoEntry] = []
    var groups: [VideoGroup] = []
}
