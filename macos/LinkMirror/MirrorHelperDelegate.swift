import AppKit
import LinkCore
import os

private let log = Logger(subsystem: "com.linktomacos.mac.mirror", category: "helper")

/// 投屏助手的主体：连上主程序的中继，等主程序说“开始”，然后开投屏窗口；窗口关了或投屏结束，整个 App 退出。
@MainActor
final class MirrorHelperDelegate: NSObject, NSApplicationDelegate {
    private var client: RelayClient?
    private var remote: PhoneRemote?
    private var session: MirrorSession?
    private var controller: MirrorWindowController?
    private var deviceModel: String?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--relay-token"), arguments.indices.contains(index + 1) else {
            log.error("started without a relay token")
            NSApp.terminate(nil)
            return
        }
        Task { await connect(token: arguments[index + 1]) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 没有窗口时（还在连接或启动）点 Dock 图标：什么也不做。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return true
    }

    // MARK: 和主程序的连接

    private func connect(token: String) async {
        let client = RelayClient(token: token)
        let remote = PhoneRemote(firstRequestId: relayRequestIdBase) { [weak client] message in client?.send(message) }
        self.client = client
        self.remote = remote
        client.onMessage = { [weak self] message in
            if remote.handle(message) { return }  // 我们自己发的请求的响应、视频和音频数据、投屏事件
            Task { @MainActor in self?.handleControl(message) }
        }
        client.onClose = { [weak self] in
            // 主程序没了（退出或崩溃）：没有人可以转发了，也退出
            Task { @MainActor in self?.quit() }
        }
        for attempt in 0..<10 {
            do {
                try await client.connect()
                return
            } catch {
                log.error("relay connect failed (\(attempt)): \(error)")
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        quit()
    }

    /// 主程序发来的控制消息。
    private func handleControl(_ message: LinkMessage) {
        switch message {
        case .request(let request) where request.method == "helperStart":
            start(request.params)
        case .request(let request) where request.method == "helperLaunch":
            if let package = request.params["package"]?.stringValue {
                launch(package: package, label: request.params["label"]?.stringValue ?? package)
            }
        case .request(let request) where request.method == "helperShow":
            controller?.show()
            NSApp.activate()
        case .goodbye(let reason):
            if reason == "stop" {
                Task { await stopAndQuit() }
            } else {
                // 手机断开：让进行中的请求都失败，投屏会收到“已停止”事件，窗口随之关闭
                remote?.close()
            }
        default:
            break
        }
    }

    // MARK: 开始和结束

    private func start(_ params: JSONValue) {
        guard session == nil, let remote else { return }
        // 助手是另一个 App，用户默认值不共用：把主程序的设置写进自己的，再创建会话（创建时读取）
        let defaults = UserDefaults.standard
        if let value = params["quality"]?.stringValue { defaults.set(value, forKey: "mirrorQuality") }
        if let value = params["mode"]?.stringValue { defaults.set(value, forKey: "mirrorMode") }
        if let value = params["screenOff"]?.boolValue { defaults.set(value, forKey: "mirrorScreenOff") }
        if let value = params["forceStop"]?.boolValue { defaults.set(value, forKey: "mirrorForceStop") }
        if let value = params["audio"]?.boolValue { defaults.set(value, forKey: "mirrorAudio") }
        if let value = params["microphone"]?.boolValue { defaults.set(value, forKey: "mirrorMicrophone") }
        deviceModel = params["model"]?.stringValue

        let session = MirrorSession()
        session.remoteProvider = { remote }
        session.preferredModel = { [weak self] in self?.deviceModel }
        self.session = session

        let controller = MirrorWindowController(session: session, title: params["deviceName"]?.stringValue ?? String(localized: "投屏"))
        controller.onClosed = { [weak self] in
            Task { @MainActor in await self?.stopAndQuit() }
        }
        self.controller = controller

        var app: PhoneApp?
        if let package = params["app"]?.stringValue {
            app = try? JSONValue.object(["package": .string(package), "label": .string(params["appLabel"]?.stringValue ?? package)]).decoded(PhoneApp.self)
        }
        Task {
            await session.start(app: app)
            // 成功：显示手机；失败：用小窗口显示错误
            controller.show(compact: !session.isRunning)
        }
    }

    private func launch(package: String, label: String) {
        guard let session,
              let app = try? JSONValue.object(["package": .string(package), "label": .string(label)]).decoded(PhoneApp.self) else { return }
        Task { await session.launch(app) }
    }

    private func stopAndQuit() async {
        guard !quitting else { return }
        quitting = true
        await session?.stop()
        client?.close()
        NSApp.terminate(nil)
    }

    private func quit() {
        guard !quitting else { return }
        quitting = true
        NSApp.terminate(nil)
    }

    // MARK: 菜单

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(MenuAction(title: String(localized: "停止投屏"), key: "q") { [weak self] in
            Task { @MainActor in await self?.stopAndQuit() }
        })
        main.addItem(submenu: appMenu, title: "Link to macOS Mirror")

        let mirrorMenu = NSMenu()
        mirrorMenu.addItem(MenuAction(title: String(localized: "返回"), key: "[") { [weak self] in self?.session?.send(.command("back")) })
        mirrorMenu.addItem(MenuAction(title: String(localized: "主页"), key: "h", modifiers: [.command, .shift]) { [weak self] in
            self?.session?.send(.command("home"))
        })
        mirrorMenu.addItem(MenuAction(title: String(localized: "最近任务"), key: "r", modifiers: [.command, .shift]) { [weak self] in
            guard let session = self?.session else { return }
            if session.isNewDisplay { session.showRecentApps = true } else { session.send(.command("recents")) }
        })
        mirrorMenu.addItem(MenuAction(title: String(localized: "打开应用…"), key: "a", modifiers: [.command, .shift]) { [weak self] in
            self?.session?.showAppLauncher = true
        })
        mirrorMenu.addItem(.separator())
        mirrorMenu.addItem(MenuAction(title: String(localized: "开关手机屏幕"), key: "o", modifiers: [.command, .shift]) { [weak self] in
            guard let session = self?.session else { return }
            session.setPhoneScreen(off: !session.phoneScreenIsOff)
        })
        main.addItem(submenu: mirrorMenu, title: String(localized: "投屏"))

        let windowMenu = NSMenu()
        windowMenu.addItem(MenuAction(title: String(localized: "关闭"), key: "w") { [weak self] in self?.controller?.close() })
        main.addItem(submenu: windowMenu, title: String(localized: "窗口"))

        NSApp.mainMenu = main
    }
}

/// 用闭包响应的菜单项。
private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(title: String, key: String, modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        submenu.title = title
        addItem(item)
    }
}
