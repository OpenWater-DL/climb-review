import Foundation

// MARK: - 打点数据模型

struct Marker: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: Double       // 时间戳（秒）
    var note: String       // 文字描述
    var createdAt: Date = Date()
}
