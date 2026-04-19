import Foundation
import AVFoundation
import AppKit

// MARK: - ThumbnailService

/// 视频封面缩略图生成服务（单例）
/// 压缩策略：最大宽度 320px，JPEG compressionFactor 0.6
final class ThumbnailService {

    static let shared = ThumbnailService()
    private init() {}

    /// 添加视频时，异步抽取第一帧生成封面
    func generateThumbnail(
        for entry: VideoEntry,
        videoURL: URL,
        thumbnailsDirectory: URL,
        completion: @escaping (String?) -> Void
    ) {
        let outputURL = thumbnailsDirectory.appendingPathComponent("\(entry.id.uuidString).jpg")
        extractFrame(from: videoURL, at: .zero, outputURL: outputURL, completion: completion)
    }

    /// 播放界面手动设置：异步截取指定时间帧作为封面
    func captureThumbnail(
        for entryID: UUID,
        videoURL: URL,
        at seconds: Double,
        thumbnailsDirectory: URL,
        completion: @escaping (String?) -> Void
    ) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let outputURL = thumbnailsDirectory.appendingPathComponent("\(entryID.uuidString).jpg")
        extractFrame(from: videoURL, at: time, outputURL: outputURL, completion: completion)
    }

    // MARK: - 核心抽帧 + 压缩逻辑

    private func extractFrame(
        from videoURL: URL,
        at time: CMTime,
        outputURL: URL,
        completion: @escaping (String?) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640) // 过采样后再缩小，提升质量

            generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                guard let cgImage = cgImage, error == nil else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                // 缩放到最大宽度 320px
                let compressed = Self.compressImage(cgImage, maxWidth: 320, compressionFactor: 0.6)
                do {
                    try compressed?.write(to: outputURL)
                    DispatchQueue.main.async { completion(outputURL.path) }
                } catch {
                    print("ThumbnailService write error: \(error)")
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        }
    }

    /// 将 CGImage 缩放并编码为 JPEG Data
    private static func compressImage(
        _ cgImage: CGImage,
        maxWidth: CGFloat,
        compressionFactor: CGFloat
    ) -> Data? {
        let origW = CGFloat(cgImage.width)
        let origH = CGFloat(cgImage.height)
        let scale = origW > maxWidth ? maxWidth / origW : 1.0
        let newSize = NSSize(width: origW * scale, height: origH * scale)

        let nsImage = NSImage(cgImage: cgImage, size: newSize)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }

        // 缩放到目标尺寸
        let scaledRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        scaledRep?.size = newSize

        NSGraphicsContext.saveGraphicsState()
        if let ctx = scaledRep.flatMap({ NSGraphicsContext(bitmapImageRep: $0) }) {
            NSGraphicsContext.current = ctx
            bitmapRep.draw(in: NSRect(origin: .zero, size: newSize))
        }
        NSGraphicsContext.restoreGraphicsState()

        return scaledRep?.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionFactor]
        )
    }
}
