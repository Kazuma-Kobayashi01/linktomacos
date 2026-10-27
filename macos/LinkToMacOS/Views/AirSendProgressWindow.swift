import AppKit
import LinkCore

/// 收到手机发来的文件时弹出的进度窗口。用系统的 NSAlert 样式（图标、标题、说明、按钮），中间加一条进度条。
/// 不是模态的：不会卡住主程序，也不抢走正在用的应用的焦点。传完后按钮变成“好”和“在访达中显示”，几秒后自动收起。
@MainActor
final class AirSendProgressWindow: NSObject {
    /// 当前显示的提示窗口。传完或失败时换成一个新的 NSAlert：NSAlert 排好版之后再改按钮不可靠。
    private var alert = NSAlert()
    private let bar = NSProgressIndicator()
    private let detail = NSTextField(labelWithString: "")
    private var primary: NSButton!
    private var onCancel: (() -> Void)?
    private var revealing: URL?
    private var autoClose: Task<Void, Never>?
    private var closed = false
    /// 接收任务一结束就不再持有这个对象，可按钮的 target 是弱引用、自动收起也靠它：显示期间自己拉住自己，关窗时再放手。
    private var keepAlive: AirSendProgressWindow?

    init(device: String, files: [AirFile], onCancel: @escaping () -> Void) {
        super.init()
        self.onCancel = onCancel
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "正在从“\(device)”接收文件")
        alert.informativeText = Self.summary(of: files)

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        let stack = NSStackView(views: [bar, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 36)
        bar.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = stack

        primary = alert.addButton(withTitle: String(localized: "取消"))
        primary.target = self
        primary.action = #selector(cancelPressed)
        alert.layout()
    }

    /// 调试截图用。
    var snapshotWindow: NSWindow { alert.window }

    func show() {
        keepAlive = self
        let window = alert.window
        window.level = .floating
        window.center()
        window.orderFrontRegardless()
    }

    /// `completed` / `total` 是整批文件的总字节数。
    func update(completed: Int64, total: Int64) {
        guard !closed else { return }
        if total > 0 {
            bar.doubleValue = min(1, Double(completed) / Double(total))
            detail.stringValue = "\(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        }
    }

    func finish(saved: [URL], device: String) {
        guard !closed else { return }
        let done = makeAlert(
            style: .informational,
            title: saved.count == 1
                ? String(localized: "从“\(device)”收到 1 个文件")
                : String(localized: "从“\(device)”收到 \(saved.count) 个文件"),
            text: saved.map(\.lastPathComponent).joined(separator: "、"))
        let ok = done.addButton(withTitle: String(localized: "好"))
        ok.target = self
        ok.action = #selector(closePressed)
        if let first = saved.first {
            revealing = first
            let reveal = done.addButton(withTitle: String(localized: "在访达中显示"))
            reveal.target = self
            reveal.action = #selector(revealPressed)
        }
        swap(to: done)
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.close()
        }
    }

    func fail(_ message: String) {
        guard !closed else { return }
        let failed = makeAlert(style: .warning, title: String(localized: "接收失败"), text: message)
        let ok = failed.addButton(withTitle: String(localized: "好"))
        ok.target = self
        ok.action = #selector(closePressed)
        swap(to: failed)
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.close()
        }
    }

    private func makeAlert(style: NSAlert.Style, title: String, text: String) -> NSAlert {
        let next = NSAlert()
        next.alertStyle = style
        next.icon = NSApp.applicationIconImage
        next.messageText = title
        next.informativeText = text
        return next
    }

    /// 用 `next` 替换当前窗口，位置保持不变。
    private func swap(to next: NSAlert) {
        let old = alert.window
        next.layout()
        let window = next.window
        window.level = .floating
        window.setFrameOrigin(NSPoint(x: old.frame.midX - window.frame.width / 2, y: old.frame.maxY - window.frame.height))
        window.orderFrontRegardless()
        old.orderOut(nil)
        alert = next
    }

    func close() {
        guard !closed else { return }
        closed = true
        autoClose?.cancel()
        alert.window.orderOut(nil)
        keepAlive = nil
    }

    @objc private func cancelPressed() {
        onCancel?()
        close()
    }

    @objc private func closePressed() { close() }

    @objc private func revealPressed() {
        if let revealing { NSWorkspace.shared.activateFileViewerSelecting([revealing]) }
        close()
    }

    private static func summary(of files: [AirFile]) -> String {
        guard let first = files.first else { return "" }
        if files.count == 1 { return first.name }
        return first.name + "、" + String(localized: "等 \(files.count) 个项目")
    }
}
