import Foundation

public enum RemoteError: Error, LocalizedError, Equatable {
    case disconnected
    case remote(String)
    case malformed
    case sizeMismatch

    public var errorDescription: String? {
        switch self {
        case .disconnected: "手机已断开连接"
        case .remote(let message): message
        case .malformed: "手机返回的数据格式不正确"
        case .sizeMismatch: "文件传输不完整"
        }
    }
}

/// 一次性的结果：先完成后等待也能拿到值。
final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    private var waiter: CheckedContinuation<T, Error>?

    func fulfill(_ value: Result<T, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(with: value)
    }

    func value() async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let result {
                lock.unlock()
                cont.resume(with: result)
            } else {
                waiter = cont
                lock.unlock()
            }
        }
    }
}

/// 把一条文件流写入本地文件。写盘放在串行队列里，不阻塞网络线程。
final class FileSink: @unchecked Sendable {
    let url: URL
    let total: Int64
    let done = OneShot<Void>()

    private let handle: FileHandle
    private let queue = DispatchQueue(label: "linktomacos.filesink")
    private let progress: (@Sendable (Int64, Int64) -> Void)?
    private var written: Int64 = 0
    private var failure: Error?

    init(url: URL, total: Int64, progress: (@Sendable (Int64, Int64) -> Void)?) throws {
        self.url = url
        self.total = total
        self.progress = progress
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ data: Data) {
        queue.async { [self] in
            guard failure == nil else { return }
            do {
                try handle.write(contentsOf: data)
                written += Int64(data.count)
                progress?(written, total)
            } catch {
                failure = error
            }
        }
    }

    func finish(ok: Bool, error: String?) {
        queue.async { [self] in
            try? handle.close()
            if let failure {
                done.fulfill(.failure(failure))
            } else if !ok {
                done.fulfill(.failure(RemoteError.remote(error ?? "传输失败")))
            } else if total >= 0, written != total {
                done.fulfill(.failure(RemoteError.sizeMismatch))
            } else {
                done.fulfill(.success(()))
            }
        }
    }

    func abort(_ error: Error) {
        queue.async { [self] in
            try? handle.close()
            done.fulfill(.failure(error))
        }
    }
}

/// 向已连接的手机发请求：读取相册、缩略图、文件夹列表、下载文件。
///
/// `handle(_:)` 在连接线程上同步调用；其中不做耗时操作。
public final class PhoneRemote: @unchecked Sendable {
    public typealias Send = @Sendable (LinkMessage) -> Void

    private struct Pending {
        var continuation: CheckedContinuation<JSONValue, Error>
        /// 在响应到达的线程上同步执行，用来赶在数据帧之前登记文件流。
        var onResponse: (@Sendable (JSONValue) -> Void)?
    }

    private let send: Send
    private let lock = NSLock()
    private var nextId = 1
    private var pending: [Int: Pending] = [:]
    private var sinks: [UInt32: FileSink] = [:]
    private var isClosed = false

    public init(send: @escaping Send) {
        self.send = send
    }

    // MARK: - 入站消息（由连接线程调用）

    /// 返回 true 表示消息已被处理。
    public func handle(_ message: LinkMessage) -> Bool {
        switch message {
        case .response(let response):
            let entry = lock.withLock { pending.removeValue(forKey: response.id) }
            guard let entry else { return true }  // 已取消请求的迟到响应
            if response.ok {
                let result = response.result ?? .null
                entry.onResponse?(result)
                entry.continuation.resume(returning: result)
            } else {
                entry.continuation.resume(throwing: RemoteError.remote(response.error ?? "未知错误"))
            }
            return true
        case .data(let streamId, let bytes):
            lock.withLock { sinks[streamId] }?.write(bytes)
            return true
        case .streamEnd(let end):
            let sink = lock.withLock { sinks.removeValue(forKey: UInt32(truncatingIfNeeded: end.streamId)) }
            sink?.finish(ok: end.ok, error: end.error)
            return true
        default:
            return false
        }
    }

    /// 连接断开：让所有等待中的请求和下载立即失败。
    public func close() {
        let (waiting, streams) = lock.withLock {
            isClosed = true
            let result = (Array(pending.values), Array(sinks.values))
            pending.removeAll()
            sinks.removeAll()
            return result
        }
        waiting.forEach { $0.continuation.resume(throwing: RemoteError.disconnected) }
        streams.forEach { $0.abort(RemoteError.disconnected) }
    }

    // MARK: - 请求

    public func call(
        _ method: String,
        _ params: JSONValue = .object([:]),
        onResponse: (@Sendable (JSONValue) -> Void)? = nil
    ) async throws -> JSONValue {
        let id = allocateId()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let failure: Error? = lock.withLock {
                    if isClosed { return RemoteError.disconnected }
                    if Task.isCancelled { return CancellationError() }
                    pending[id] = Pending(continuation: continuation, onResponse: onResponse)
                    return nil
                }
                if let failure {
                    continuation.resume(throwing: failure)
                    return
                }
                send(.request(RPCRequest(id: id, method: method, params: params)))
            }
        } onCancel: {
            cancelRequest(id)
        }
    }

    private func allocateId() -> Int {
        lock.withLock {
            defer { nextId += 1 }
            return nextId
        }
    }

    private func cancelRequest(_ id: Int) {
        guard let entry = lock.withLock({ pending.removeValue(forKey: id) }) else { return }
        entry.continuation.resume(throwing: CancellationError())
        send(.request(RPCRequest(id: allocateId(), method: "cancel", params: .object(["id": .int(Int64(id))]))))
    }

    // MARK: - 业务方法

    public func access() async throws -> AccessInfo {
        try await call("access").decoded(AccessInfo.self)
    }

    public func albums() async throws -> AlbumList {
        try await call("listAlbums").decoded(AlbumList.self)
    }

    public func media(album: Int64? = nil, kind: MediaKind = .all, offset: Int, limit: Int) async throws -> MediaPage {
        var params: [String: JSONValue] = [
            "kind": .string(kind.rawValue), "offset": .int(Int64(offset)), "limit": .int(Int64(limit)),
        ]
        if let album { params["album"] = .int(album) }
        return try await call("listMedia", .object(params)).decoded(MediaPage.self)
    }

    /// JPEG 数据。`size` 是长边像素数。
    public func thumbnail(id: Int64, isVideo: Bool, size: Int, quality: Int = 80) async throws -> Data {
        let params: JSONValue = .object([
            "id": .int(id), "video": .bool(isVideo), "size": .int(Int64(size)), "quality": .int(Int64(quality)),
        ])
        let result = try await call("thumbnail", params)
        guard let base64 = result["data"]?.stringValue, let data = Data(base64Encoded: base64) else {
            throw RemoteError.malformed
        }
        return data
    }

    public func directory(_ path: String) async throws -> DirListing {
        try await call("listDir", .object(["path": .string(path)])).decoded(DirListing.self)
    }

    /// 流式下载到 `url`。取消任务会同时通知手机停止发送。失败时删除不完整的文件。
    @discardableResult
    public func download(
        _ source: DownloadSource,
        to url: URL,
        progress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> DownloadInfo {
        final class Box: @unchecked Sendable {
            var sink: FileSink?
            var streamId: UInt32?
            var error: Error?
        }
        let box = Box()
        do {
            let result = try await call("download", source.params) { [self] result in
                guard let streamId = result["streamId"]?.int64Value, let size = result["size"]?.int64Value else {
                    box.error = RemoteError.malformed
                    return
                }
                do {
                    let sink = try FileSink(url: url, total: size, progress: progress)
                    box.sink = sink
                    box.streamId = UInt32(truncatingIfNeeded: streamId)
                    lock.withLock { sinks[box.streamId!] = sink }
                } catch {
                    box.error = error
                }
            }
            if let error = box.error { throw error }
            guard let sink = box.sink, let streamId = box.streamId else { throw RemoteError.malformed }
            try await withTaskCancellationHandler {
                try await sink.done.value()
            } onCancel: { [self] in
                lock.withLock { _ = sinks.removeValue(forKey: streamId) }
                sink.abort(CancellationError())
                send(.request(RPCRequest(id: allocateId(), method: "cancel", params: .object(["streamId": .int(Int64(streamId))]))))
            }
            return DownloadInfo(
                name: result["name"]?.stringValue ?? url.lastPathComponent,
                size: result["size"]?.int64Value ?? 0,
                mime: result["mime"]?.stringValue ?? "",
                modified: result["modified"]?.int64Value ?? 0)
        } catch {
            if let streamId = box.streamId { lock.withLock { _ = sinks.removeValue(forKey: streamId) } }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
