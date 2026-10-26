import AppKit
import LinkCore
import Observation
import UniformTypeIdentifiers
import UserNotifications
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "airsend")

/// AirSend：和手机无感互传文件和文字。
///
/// - **收（手机 → Mac）**：手机发来“清单”，这里逐个下载到“下载/AirSend”，完成后弹通知（点通知在访达里显示）。文字放进剪贴板。
/// - **发（Mac → 手机）**：[send(urls:)] 把文件分块推给手机（逐块等待写入，不占内存）；文件夹先压成 zip。
/// - **共享菜单**：系统“共享 → AirSend”（见 AirSendShare 扩展）把任务放进收件目录，这里监听并发出去。
@MainActor
@Observable
final class AirSendService {
    struct Transfer: Identifiable {
        enum Direction { case send, receive }
        enum State: Equatable { case running(Double), done, failed(String) }

        let id = UUID()
        var name: String
        var size: Int64
        var direction: Direction
        var state: State
        /// 收到的文件在 Mac 上的位置。
        var location: URL?
        var date = Date()
    }

    private(set) var transfers: [Transfer] = []

    /// 由 AppModel 提供：当前手机的名字、能否发送、下载用的远程对象。
    var deviceName: () -> String? = { nil }
    var remote: () -> PhoneRemote? = { nil }
    var send: (LinkMessage) -> Void = { _ in }
    var sendAwaiting: (LinkMessage) async throws -> Void = { _ in }

    private var nextStream = airStreamBase
    private var watcher: DispatchSourceFileSystemObject?
    private var observer: NSObjectProtocol?
    private let center = UNUserNotificationCenter.current()

    static let chunkSize = 256 * 1024
    private static let maxHistory = 40

    /// 收到的文件的保存位置。
    static var receiveFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("AirSend", isDirectory: true)
    }

    /// 共享扩展放任务的目录，和 AirSendShare/ShareViewController.swift 里的一致。
    static let outbox: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LinkToMacOS/AirSend/outbox", isDirectory: true)

    // MARK: 共享菜单的任务

    private struct Job: Codable {
        var id: String
        var files: [String] = []
        var texts: [String] = []
        var cleanup: [String] = []
    }

    func startWatchingOutbox() {
        guard watcher == nil else { return }
        try? FileManager.default.createDirectory(at: Self.outbox, withIntermediateDirectories: true)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.linktomacos.airsend.job"), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.processOutbox() } }
        let fd = open(Self.outbox.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.processOutbox() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        processOutbox()
    }

    /// 手机连上时也检查一遍：共享时手机还没连上的任务，这时候发出去。
    func processOutbox() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: Self.outbox.path) else { return }
        for name in names where name.hasSuffix(".job") {
            let file = Self.outbox.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file), let job = try? JSONDecoder().decode(Job.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            guard deviceName() != nil else {
                // 手机没连上：保留任务，连上后再发；太久（10 分钟）的丢掉
                if let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate, Date().timeIntervalSince(created) > 600 {
                    try? FileManager.default.removeItem(at: file)
                    notify(title: String(localized: "没能发送到手机"), body: String(localized: "手机没有连接。"))
                }
                continue
            }
            try? FileManager.default.removeItem(at: file)
            if !job.texts.isEmpty { send(text: job.texts.joined(separator: "\n")) }
            if !job.files.isEmpty {
                Task {
                    await sendFiles(job.files.map { URL(fileURLWithPath: $0) })
                    for path in job.cleanup { try? FileManager.default.removeItem(atPath: path) }
                }
            } else {
                for path in job.cleanup { try? FileManager.default.removeItem(atPath: path) }
            }
        }
    }

    // MARK: 发（Mac → 手机）

    func send(urls: [URL]) {
        guard deviceName() != nil else {
            notify(title: String(localized: "没能发送到手机"), body: String(localized: "手机没有连接。"))
            return
        }
        Task { await sendFiles(urls) }
    }

    func send(text: String) {
        guard !text.isEmpty else { return }
        guard let device = deviceName() else {
            notify(title: String(localized: "没能发送到手机"), body: String(localized: "手机没有连接。"))
            return
        }
        send(.airText(AirText(text: text)))
        log.info("sent text (\(text.count) characters)")
        notify(title: String(localized: "已发送到“\(device)”"), body: text, silent: true)
    }

    private func sendFiles(_ urls: [URL]) async {
        var sent: [String] = []
        for url in urls {
            if await push(url) { sent.append(url.lastPathComponent) }
        }
        guard !sent.isEmpty, let device = deviceName() else { return }
        notify(
            title: String(localized: "已发送到“\(device)”"),
            body: sent.count == 1 ? sent[0] : String(localized: "\(sent.count) 个项目"), silent: true)
    }

    /// 发一个文件（文件夹先压缩）。成功返回 true。
    private func push(_ original: URL) async -> Bool {
        var file = original
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory) else { return false }
        let name: String
        if isDirectory.boolValue {
            let zip = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/\(original.lastPathComponent).zip")
            try? FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard await Self.zip(original, to: zip) else {
                addTransfer(Transfer(name: original.lastPathComponent, size: 0, direction: .send, state: .failed(String(localized: "无法压缩文件夹"))))
                return false
            }
            file = zip
            temporary = zip.deletingLastPathComponent()
            name = zip.lastPathComponent
        } else {
            name = original.lastPathComponent
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let streamId = nextStream
        nextStream = nextStream >= Int(Int32.max) - 1 ? airStreamBase : nextStream + 1
        let id = addTransfer(Transfer(name: name, size: size, direction: .send, state: .running(0)))
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            send(.airPush(AirPush(streamId: streamId, name: name, size: size, mime: mime)))
            var sentBytes: Int64 = 0
            while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                try await sendAwaiting(.data(streamId: UInt32(truncatingIfNeeded: streamId), bytes: chunk))
                sentBytes += Int64(chunk.count)
                if size > 0 { update(id, state: .running(Double(sentBytes) / Double(size))) }
            }
            send(.streamEnd(StreamEnd(streamId: streamId, ok: true)))
            update(id, state: .done)
            return true
        } catch {
            log.error("send failed: \(error)")
            send(.streamEnd(StreamEnd(streamId: streamId, ok: false, error: error.localizedDescription)))
            update(id, state: .failed(error.localizedDescription))
            return false
        }
    }

    private static func zip(_ directory: URL, to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", directory.path, destination.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }

    // MARK: 收（手机 → Mac）

    func receive(_ offer: AirOffer, from device: String) {
        guard let remote = remote() else { return }
        let folder = Self.receiveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // 进度窗口（设置里可以关）；取消按钮取消整批下载
        final class TaskBox { var task: Task<Void, Never>? }
        let box = TaskBox()
        let window = Prefs.bool(Prefs.showAirSendProgress, default: true)
            ? AirSendProgressWindow(device: device, files: offer.files) { box.task?.cancel() }
            : nil
        window?.show()
        let total = offer.files.reduce(Int64(0)) { $0 + $1.size }

        box.task = Task {
            var saved: [URL] = []
            var finishedBytes: Int64 = 0
            var failure: String?
            for (index, file) in offer.files.enumerated() {
                if Task.isCancelled { break }
                let destination = Self.uniqueURL(in: folder, name: file.name)
                let id = addTransfer(Transfer(name: file.name, size: file.size, direction: .receive, state: .running(0), location: destination))
                let base = finishedBytes
                do {
                    try await remote.download(.airsend(offer: offer.id, index: index), to: destination) { [weak self] done, fileTotal in
                        Task { @MainActor in
                            if fileTotal > 0 { self?.update(id, state: .running(Double(done) / Double(fileTotal))) }
                            window?.update(completed: base + done, total: total)
                        }
                    }
                    update(id, state: .done)
                    saved.append(destination)
                    finishedBytes += file.size
                } catch {
                    log.error("receive failed: \(error)")
                    let cancelled = error is CancellationError || Task.isCancelled
                    update(id, state: .failed(cancelled ? String(localized: "已取消") : error.localizedDescription))
                    if !cancelled { failure = error.localizedDescription }
                }
            }
            guard !saved.isEmpty else {
                if let failure { window?.fail(failure) } else { window?.close() }
                return
            }
            window?.finish(saved: saved, device: device)
            let title = saved.count == 1
                ? String(localized: "从“\(device)”收到 1 个文件")
                : String(localized: "从“\(device)”收到 \(saved.count) 个文件")
            // 进度窗口开着时，窗口本身就是提示；通知只在窗口关闭（设置里关了）时发
            if window == nil {
                notify(title: title, body: saved.map(\.lastPathComponent).joined(separator: "、"), reveal: saved.first)
            }
        }
    }

    func receive(text: String, from device: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) && !trimmed.contains(" ") ? URL(string: trimmed) : nil
        notify(title: String(localized: "从“\(device)”收到文字（已拷贝）"), body: text, open: link)
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "_")
        var url = folder.appendingPathComponent(clean)
        var n = 2
        let base = (clean as NSString).deletingPathExtension
        let ext = (clean as NSString).pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    // MARK: 记录和通知

    @discardableResult
    private func addTransfer(_ transfer: Transfer) -> UUID {
        transfers.insert(transfer, at: 0)
        if transfers.count > Self.maxHistory { transfers.removeLast(transfers.count - Self.maxHistory) }
        return transfer.id
    }

    private func update(_ id: UUID, state: Transfer.State) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[index].state = state
    }

    func clearFinished() {
        transfers.removeAll { if case .running = $0.state { false } else { true } }
    }

    /// `reveal`：点通知在访达里显示这个文件；`open`：点通知打开这个链接。
    private func notify(title: String, body: String, reveal: URL? = nil, open: URL? = nil, silent: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = silent ? nil : .default
        content.threadIdentifier = "airsend"
        if let reveal { content.userInfo["airsendReveal"] = reveal.path }
        if let open { content.userInfo["airsendOpen"] = open.absoluteString }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

#if DEBUG
extension AirSendService {
    /// 调试用：几条示例记录（正在发送、已收到、失败），用于离屏渲染 AirSend 页面。
    func loadSample() {
        transfers = [
            Transfer(name: "Holiday video.mp4", size: 184_000_000, direction: .send, state: .running(0.42)),
            Transfer(name: "Screenshot_20261026.jpg", size: 512_000, direction: .receive, state: .done, location: URL(fileURLWithPath: "/tmp/a.jpg")),
            Transfer(name: "Report.pdf", size: 1_800_000, direction: .send, state: .done),
            Transfer(name: "Archive.zip", size: 9_400_000, direction: .receive, state: .failed("The connection was interrupted.")),
        ]
    }
}
#endif
