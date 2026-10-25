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

/// 不会变化的设备信息。
public struct DeviceInfo: Codable, Equatable, Sendable {
    public var manufacturer: String
    public var brand: String
    public var model: String
    public var device: String
    public var androidVersion: String
    public var sdk: Int
    public var securityPatch: String
    public var buildId: String
    public var abi: String
    public var cpuCores: Int
    public var memoryTotal: Int64
    public var screenWidth: Int
    public var screenHeight: Int
    public var densityDpi: Int
    public var refreshRate: Double
    /// 芯片厂商（如 QTI、Samsung、Mediatek、Google）和型号代号（如 SM8550），较新版本的手机才有。
    public var socManufacturer: String?
    public var socModel: String?
    public var hardware: String?
    public var language: String
    public var timezone: String
    public var appVersion: String
}

/// 存储占用。`other` 不在手机上直接给出，由总量减去可用和各类媒体得到。
public struct StorageBreakdown: Codable, Equatable, Sendable {
    public var total: Int64
    public var free: Int64
    public var images: Int64
    public var videos: Int64
    public var audio: Int64
    /// 手机是否授予了相册读取权限；没有时图片、视频、音频都是 0。
    public var hasMedia: Bool

    public var used: Int64 { max(0, total - free) }
    public var other: Int64 { max(0, used - images - videos - audio) }
}

/// 投屏增强服务（shell 服务）的状态，以及 Mac 通过 USB 启动它所需的信息。
public struct MirrorStatus: Codable, Equatable, Sendable {
    public var ready: Bool
    /// 手机上跑着的服务是旧版本（App 重装后服务进程还在跑旧代码），需要重新启动。老版本的手机 App 不发这个字段。
    public var outdated: Bool?
    public var port: Int
    /// 握手用的共享密钥（十六进制）。只通过加密连接传递，不写日志。
    public var secret: String
    public var apkPath: String
    public var sdk: Int
}

public struct MirrorStartInfo: Codable, Equatable, Sendable {
    public var streamId: Int
    public var width: Int
    public var height: Int
    public var deviceWidth: Int
    public var deviceHeight: Int
    /// 被投显示器的编号。较新版本的手机才有。
    public var displayId: Int?
    /// "new" 或 "mirror"。较新版本的手机才有。
    public var mode: String?
    /// 音频数据流的编号（Opus 包，格式和视频包一样）。没有请求音频，或手机不支持时没有这个字段或为 0。
    public var audioStreamId: Int?
    /// Mac 麦克风的数据流编号：往这个流上发 PCM（48 kHz、单声道、16 位小端，每包 20 ms）。没有请求麦克风，或手机不支持时没有或为 0。
    public var micStreamId: Int?
}

/// 投屏模式。
public enum MirrorMode: String, Codable, Sendable, CaseIterable {
    /// 在手机里新建一个独立的虚拟显示器，应用开在上面；手机自己的屏幕可以关掉，窗口缩放时应用会重新排版。
    case newDisplay = "new"
    /// 镜像手机主屏。
    case mirror = "mirror"
}

public struct MirrorStartOptions: Sendable {
    public var mode: MirrorMode
    public var maxSize: Int
    public var bitRate: Int
    public var fps: Int
    /// 独立显示模式的初始尺寸（像素）。
    public var width: Int
    public var height: Int
    /// 独立显示模式下，开始时自动打开的应用包名。
    public var app: String?
    public var forceStop: Bool
    /// 把手机的声音（Opus）转发过来，手机本体静音。
    public var audio: Bool
    /// 把 Mac 麦克风的声音注入手机：手机上的应用录音时拿到的是 Mac 的声音。
    public var mic: Bool

    public init(mode: MirrorMode = .newDisplay, maxSize: Int = 1920, bitRate: Int = 8_000_000, fps: Int = 60,
                width: Int = 0, height: Int = 0, app: String? = nil, forceStop: Bool = false, audio: Bool = false, mic: Bool = false) {
        self.mode = mode; self.maxSize = maxSize; self.bitRate = bitRate; self.fps = fps
        self.width = width; self.height = height; self.app = app; self.forceStop = forceStop; self.audio = audio; self.mic = mic
    }

    var params: JSONValue {
        var object: [String: JSONValue] = [
            "mode": .string(mode.rawValue), "maxSize": .int(Int64(maxSize)), "bitRate": .int(Int64(bitRate)),
            "fps": .int(Int64(fps)), "width": .int(Int64(width)), "height": .int(Int64(height)),
            "forceStop": .bool(forceStop), "audio": .bool(audio), "mic": .bool(mic),
        ]
        if let app { object["app"] = .string(app) }
        return .object(object)
    }
}

/// 手机上能启动的应用。图标另外按需取。
public struct PhoneApp: Codable, Identifiable, Hashable, Sendable {
    public var package: String
    public var label: String
    public var id: String { package }
}

struct PhoneAppList: Codable, Sendable {
    var apps: [PhoneApp]
}
