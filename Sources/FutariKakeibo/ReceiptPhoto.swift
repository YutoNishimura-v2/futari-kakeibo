import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ReceiptPhotoError: LocalizedError {
    case unreadable, tooLarge, changed, conflictingAttachments

    var errorDescription: String? {
        switch self {
        case .unreadable: return "写真を読み込めませんでした。"
        case .tooLarge: return "写真を2 MB以内に圧縮できませんでした。"
        case .changed: return "レシート写真が更新されました。表示を確認してからお試しください。"
        case .conflictingAttachments: return "別々の端末で異なる写真が追加されました。両方の写真を保存しています。"
        }
    }
}

struct ReceiptPhoto: Transferable {
    static let longEdge = 1600
    static let maximumBytes = 2_000_000
    let jpeg: Data

    private init(jpeg: Data) {
        self.jpeg = jpeg
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try prepare(received.file)
        }
    }

    static func targetSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        guard longest > longEdge else { return (width, height) }
        let scale = Double(longEdge) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }

    static func fits(byteCount: Int) -> Bool {
        (1...maximumBytes).contains(byteCount)
    }

    private static func prepare(_ url: URL) throws -> Self {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let target = targetSize(width: width, height: height) else { throw ReceiptPhotoError.unreadable }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ReceiptPhotoError.unreadable }

        for quality in [0.82, 0.65, 0.45] {
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes as CFMutableData,
                                                                       UTType.jpeg.identifier as CFString, 1, nil)
            else { throw ReceiptPhotoError.unreadable }
            let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            CGImageDestinationAddImage(destination, image, options)
            guard CGImageDestinationFinalize(destination) else { throw ReceiptPhotoError.unreadable }
            if fits(byteCount: bytes.length) {
                return Self(jpeg: bytes as Data)
            }
        }
        throw ReceiptPhotoError.tooLarge
    }
}
