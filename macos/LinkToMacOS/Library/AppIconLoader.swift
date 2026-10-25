import AppKit
import LinkCore

/// 手机应用的图标：按需向手机取，内存缓存，限制同时进行的请求数。
final class AppIconLoader: @unchecked Sendable {
    var remote: PhoneRemote?
    private let cache = NSCache<NSString, NSImage>()
    private let limiter = AsyncLimiter(limit: 4)

    func cached(_ package: String) -> NSImage? { cache.object(forKey: package as NSString) }

    func image(for package: String) async -> NSImage? {
        if let image = cached(package) { return image }
        guard let remote else { return nil }
        await limiter.acquire()
        if Task.isCancelled {
            await limiter.release()
            return nil
        }
        let data = try? await remote.appIcon(package: package)
        await limiter.release()
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: package as NSString)
        return image
    }
}
