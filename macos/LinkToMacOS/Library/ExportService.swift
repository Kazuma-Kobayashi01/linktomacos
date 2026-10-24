import AppKit
import CryptoKit
import LinkCore
import UniformTypeIdentifiers

/// 把手机上的文件取到 Mac：缓存、存储到指定位置、拷贝到剪贴板、拖拽。
@MainActor
final class ExportService {
    struct Item: Hashable, Sendable {
        let name: String
        let source: DownloadSource
        /// 未知时为 0。
        let size: Int64

        init(media: MediaItem) {
            name = media.name
            source = .media(id: media.id)
            size = media.size
        }

        init(file entry: FileEntry, directory: String) {
            name = entry.name
            source = .file(path: directory.isEmpty ? entry.name : "\(directory)/\(entry.name)")
            size = entry.size
        }
    }

    private let remote: PhoneRemote
    private let transfers: TransferCenter

    init(remote: PhoneRemote, transfers: TransferCenter) {
        self.remote = remote
        self.transfers = transfers
    }

    nonisolated static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkToMacOS/exports", isDirectory: true)
    }

    /// 启动时清掉一天前的缓存。
    nonisolated static func pruneCache() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        guard let dirs = try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for dir in dirs {
            let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: dir) }
        }
    }

    private func cacheDirectory(for item: Item) -> URL {
        let digest = SHA256.hash(data: Data("\(item.source)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return Self.cacheRoot.appendingPathComponent(digest, isDirectory: true)
    }

    /// 返回本地缓存的文件；没有则下载。同一个文件重复请求直接复用。
    func localURL(for item: Item) async throws -> URL {
        let directory = cacheDirectory(for: item)
        let url = directory.appendingPathComponent(item.name)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
           item.size <= 0 || size == item.size {
            return url
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let remote = remote
        try await transfers.track(name: item.name, total: item.size) { progress in
            try await remote.download(item.source, to: url, progress: progress)
        }
        return url
    }

    func copyToPasteboard(_ items: [Item]) async throws {
        var urls: [URL] = []
        for item in items { urls.append(try await localURL(for: item)) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// 存到文件夹里；同名文件自动加序号，不覆盖。
    func save(_ items: [Item], to folder: URL) async throws {
        for item in items {
            let source = try await localURL(for: item)
            try FileManager.default.copyItem(at: source, to: Self.uniqueURL(in: folder, name: item.name))
        }
    }

    func saveAs(_ item: Item, to destination: URL) async throws {
        let source = try await localURL(for: item)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func open(_ item: Item) async throws {
        NSWorkspace.shared.open(try await localURL(for: item))
    }

    /// 拖到访达时才真正下载（文件承诺）。
    func promise(for item: Item) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        let type = UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { [weak self] completion in
            Task { @MainActor in
                do {
                    guard let self else { throw RemoteError.disconnected }
                    completion(try await self.localURL(for: item), false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    nonisolated static func uniqueURL(in folder: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
