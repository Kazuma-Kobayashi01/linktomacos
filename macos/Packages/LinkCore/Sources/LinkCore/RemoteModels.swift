import Foundation

public struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var mime: String
    public var size: Int64
    public var width: Int
    public var height: Int
    /// 视频时长，毫秒；图片为 0。
    public var duration: Int64
    /// 拍摄（或添加）时间，毫秒时间戳。
    public var date: Int64
    public var isVideo: Bool
    /// 所在相簿名称。
    public var album: String

    public var dateValue: Date { Date(timeIntervalSince1970: TimeInterval(date) / 1000) }
}

public struct Album: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var count: Int
    public var coverId: Int64
    public var coverIsVideo: Bool
}

public struct AlbumList: Codable, Sendable {
    public var albums: [Album]
    public var imageCount: Int
    public var videoCount: Int
}

public struct MediaPage: Codable, Sendable {
    public var total: Int
    public var items: [MediaItem]
}

public struct FileEntry: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var isDir: Bool
    public var size: Int64
    /// 毫秒时间戳。
    public var modified: Int64
    public var id: String { name }

    public var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified) / 1000) }
}

public struct DirListing: Codable, Sendable {
    public var path: String
    public var entries: [FileEntry]
}

/// 手机端是否已授予所需权限。
public struct AccessInfo: Codable, Equatable, Sendable {
    public var media: Bool
    public var allFiles: Bool
}

public enum MediaKind: String, Sendable {
    case all, image, video
}

public enum DownloadSource: Sendable, Hashable {
    case media(id: Int64)
    /// 相对于手机内部存储根目录的路径，如 `Download/a.pdf`。
    case file(path: String)

    var params: JSONValue {
        switch self {
        case .media(let id): .object(["source": "media", "id": .int(id)])
        case .file(let path): .object(["source": "file", "path": .string(path)])
        }
    }
}

public struct DownloadInfo: Sendable {
    public var name: String
    public var size: Int64
    public var mime: String
    public var modified: Int64
}
