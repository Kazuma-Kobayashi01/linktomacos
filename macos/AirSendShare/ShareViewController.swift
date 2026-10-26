import AppKit
import UniformTypeIdentifiers

/// 系统“共享”菜单里的 AirSend：把选中的文件、图片、链接、文字交给 Link to macOS 主程序，由它发到手机。
///
/// 本扩展在沙盒里（共享扩展必须沙盒化，否则系统不认），不连接手机，也不显示复杂界面：把要发的内容写成一个任务文件，放进主程序的收件目录，
/// 通知主程序（必要时先把它启动起来），然后关闭。文件直接引用原路径，不复制；
/// 只有没有文件路径的内容（比如图片数据）才会拷贝一份到任务目录。
final class ShareViewController: NSViewController {
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 96))
        root.material = .popover
        root.state = .active
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        label.stringValue = String(localized: "正在交给 Link to macOS…")
        label.font = .systemFont(ofSize: 13)
        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor in await process() }
    }

    // MARK: 读取分享内容

    private struct Job: Codable {
        var id: String
        var files: [String] = []
        var texts: [String] = []
        /// 发完后要删掉的临时目录（我们自己拷贝过来的内容）。
        var cleanup: [String] = []
    }

    @MainActor
    private func process() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var job = Job(id: UUID().uuidString)
        let workDirectory = AirSendShareConstants.outbox.appendingPathComponent(job.id, isDirectory: true)

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await loadURL(provider, UTType.fileURL.identifier), url.isFileURL { job.files.append(url.path) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = await loadURL(provider, UTType.url.identifier) { job.texts.append(url.absoluteString) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadText(provider) { job.texts.append(text) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                if let copy = await copyFile(provider, into: workDirectory) {
                    job.files.append(copy.path)
                    if !job.cleanup.contains(workDirectory.path) { job.cleanup.append(workDirectory.path) }
                }
            }
        }

        guard !job.files.isEmpty || !job.texts.isEmpty else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            return
        }
        do {
            try FileManager.default.createDirectory(at: AirSendShareConstants.outbox, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(job)
            let file = AirSendShareConstants.outbox.appendingPathComponent("\(job.id).job")
            try data.write(to: file, options: .atomic)
        } catch {
            extensionContext?.cancelRequest(withError: error)
            return
        }
        wakeMainApp()
        label.stringValue = String(localized: "已交给 Link to macOS")
        spinner.stopAnimation(nil)
        try? await Task.sleep(for: .milliseconds(700))
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func loadURL(_ provider: NSItemProvider, _ type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url)
                case let data as Data: continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                switch item {
                case let text as String: continuation.resume(returning: text)
                case let data as Data: continuation.resume(returning: String(data: data, encoding: .utf8))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 没有文件路径的内容（图片数据等）：系统给的是临时副本，在回调里拷贝到自己的目录。
    private func copyFile(_ provider: NSItemProvider, into directory: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 通知主程序有新任务；主程序没在运行就先把它打开。
    private func wakeMainApp() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AirSendShareConstants.mainBundleIdentifier)
        if running.isEmpty {
            // …/Link to macOS.app/Contents/PlugIns/AirSend.appex
            let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
        DistributedNotificationCenter.default().postNotificationName(
            AirSendShareConstants.jobNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

enum AirSendShareConstants {
    static let mainBundleIdentifier = "com.linktomacos.mac"
    static let jobNotification = Notification.Name("com.linktomacos.airsend.job")
    /// 主程序的收件目录。扩展在沙盒里，`homeDirectoryForCurrentUser` 是它自己的容器，所以用 passwd 里的真实主目录；
    /// 沙盒对这个目录开了例外（见 project.yml 里的 entitlements）。
    static let outbox: URL = {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/LinkToMacOS/AirSend/outbox", isDirectory: true)
    }()
}
