import AppKit
import LinkCore
import Observation

/// 一台已连接手机的相册和文件视图所需的全部状态。连接断开时整个对象丢弃。
@MainActor
@Observable
final class PhoneLibrary {
    let remote: PhoneRemote
    let deviceName: String
    let thumbnails: ThumbnailLoader
    let transfers = TransferCenter()
    let exporter: ExportService

    /// nil 表示尚未取到（刚连上）。
    private(set) var access: AccessInfo?
    private(set) var albums: [Album] = []
    private(set) var imageCount = 0
    private(set) var videoCount = 0
    private(set) var overviewError: String?
    /// 需要弹给用户的错误（导出失败等）。
    var alertMessage: String?

    init(remote: PhoneRemote, deviceName: String) {
        self.remote = remote
        self.deviceName = deviceName
        thumbnails = ThumbnailLoader(remote: remote)
        exporter = ExportService(remote: remote, transfers: transfers)
    }

    var mediaAllowed: Bool { access?.media ?? true }
    var filesAllowed: Bool { access?.allFiles ?? true }

    /// 读取权限状态和相簿列表。
    func refreshOverview() async {
        do {
            let access = try await remote.access()
            self.access = access
            if access.media {
                let list = try await remote.albums()
                albums = list.albums
                imageCount = list.imageCount
                videoCount = list.videoCount
            }
            overviewError = nil
        } catch is CancellationError {
        } catch {
            overviewError = error.localizedDescription
        }
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        alertMessage = error.localizedDescription
    }
}

/// 限制同时进行的请求数。后来的请求优先（用户滚动时，最新进入屏幕的缩略图最重要）。
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.popLast() {
            next.resume()
        } else {
            running -= 1
        }
    }
}

/// 缩略图：内存缓存 + 限流。视图消失时任务被取消，排队中的请求不会发给手机。
final class ThumbnailLoader: @unchecked Sendable {
    fileprivate let remote: PhoneRemote
    fileprivate let cache = NSCache<NSString, NSImage>()
    fileprivate let previewCache = NSCache<NSString, NSImage>()
    fileprivate let limiter = AsyncLimiter(limit: 6)

    init(remote: PhoneRemote) {
        self.remote = remote
        cache.countLimit = 4000
        previewCache.countLimit = 12
    }

    private func key(_ id: Int64, _ size: Int) -> NSString { "\(id)@\(size)" as NSString }

    func cached(id: Int64, size: Int) -> NSImage? {
        cache.object(forKey: key(id, size))
    }

    func image(id: Int64, isVideo: Bool, size: Int, quality: Int = 80) async -> NSImage? {
        if let image = cached(id: id, size: size) { return image }
        await limiter.acquire()
        if Task.isCancelled {
            await limiter.release()
            return nil
        }
        let data = try? await remote.thumbnail(id: id, isVideo: isVideo, size: size, quality: quality)
        await limiter.release()
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key(id, size))
        return image
    }
}

extension ThumbnailLoader {
    /// 大图预览（长边 2000 像素）。单独缓存，只留最近几张，避免占用大量内存。
    func preview(id: Int64, isVideo: Bool) async -> NSImage? {
        let key = "\(id)" as NSString
        if let image = previewCache.object(forKey: key) { return image }
        await limiter.acquire()
        if Task.isCancelled {
            await limiter.release()
            return nil
        }
        let data = try? await remote.thumbnail(id: id, isVideo: isVideo, size: 2000, quality: 85)
        await limiter.release()
        guard let data, let image = NSImage(data: data) else { return nil }
        previewCache.setObject(image, forKey: key)
        return image
    }
}

/// 正在进行的下载，用来在窗口底部显示进度。
@MainActor
@Observable
final class TransferCenter {
    struct Transfer: Identifiable {
        let id = UUID()
        var name: String
        var completed: Int64 = 0
        var total: Int64
        var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    }

    private(set) var active: [Transfer] = []

    func track<T>(
        name: String, total: Int64,
        _ work: (@escaping @Sendable (Int64, Int64) -> Void) async throws -> T
    ) async throws -> T {
        let transfer = Transfer(name: name, total: total)
        active.append(transfer)
        defer { active.removeAll { $0.id == transfer.id } }
        return try await work { [weak self] completed, _ in
            Task { @MainActor in
                guard let self, let index = self.active.firstIndex(where: { $0.id == transfer.id }) else { return }
                self.active[index].completed = completed
            }
        }
    }
}
