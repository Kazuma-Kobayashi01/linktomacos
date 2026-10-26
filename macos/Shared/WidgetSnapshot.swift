import Foundation

/// 主程序写给桌面小组件看的数据快照。小组件在沙盒里，只能读这一个目录（沙盒例外，见 project.yml）。
struct WidgetSnapshot: Codable, Equatable {
    struct Point: Codable, Equatable {
        var time: Date
        var battery: Int
        var charging: Bool
    }

    var deviceName: String
    var model: String
    var online: Bool
    /// 最后一次收到手机状态的时间。
    var lastSeen: Date?
    var battery: Int?
    var charging: Bool
    var storageUsed: Int64?
    var storageTotal: Int64?
    var memoryUsed: Int64?
    var memoryTotal: Int64?
    /// 联网方式：Wi‑Fi 或 5G / LTE 等。
    var network: String?
    /// 信号格数 0–4。
    var signalLevel: Int?
    /// 最近 24 小时的电量，最多约 48 个点。
    var history: [Point]
    var updated: Date

    static let directoryComponents = "Library/Application Support/LinkToMacOS/widget"

    /// 真实的主目录。小组件在沙盒里，`NSHomeDirectory()` 是它自己的容器，要用 passwd 里的。
    private static var realHome: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    static var directory: URL {
        URL(fileURLWithPath: realHome, isDirectory: true).appendingPathComponent(directoryComponents, isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// 图库里和还没有数据时显示的示例。
    static let sample = WidgetSnapshot(
        deviceName: "Galaxy S23 Ultra", model: "SM-S9180", online: true, lastSeen: Date(),
        battery: 76, charging: true,
        storageUsed: 157_790_000_000, storageTotal: 496_190_000_000,
        memoryUsed: 6_955_000_000, memoryTotal: 11_585_000_000,
        network: "Wi‑Fi", signalLevel: 3,
        history: (0..<48).map { i in
            Point(time: Date().addingTimeInterval(Double(i - 48) * 1800), battery: min(100, 30 + i), charging: i > 30)
        },
        updated: Date())
}
