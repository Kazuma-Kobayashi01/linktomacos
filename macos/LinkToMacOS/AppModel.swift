import AppKit
import LinkCore
import Observation
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "app")

/// 一台在线的手机。
struct ConnectedDevice: Identifiable {
    var device: PairedDevice
    var status: DeviceStatus?
    var id: String { device.deviceId }
}

/// 一个带锁的值，可以在任意线程读写。
final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// 连接线程要同步把数据帧交给对应手机的 PhoneRemote，所以单独放一个带锁的表。
final class RemoteRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var remotes: [String: PhoneRemote] = [:]

    func remote(for deviceId: String) -> PhoneRemote? { lock.withLock { remotes[deviceId] } }

    @discardableResult
    func set(_ remote: PhoneRemote, for deviceId: String) -> PhoneRemote? {
        lock.withLock { let old = remotes[deviceId]; remotes[deviceId] = remote; return old }
    }

    @discardableResult
    func remove(_ deviceId: String) -> PhoneRemote? { lock.withLock { remotes.removeValue(forKey: deviceId) } }
}

@MainActor
@Observable
final class AppModel {
    enum ServerState: Equatable {
        case starting
        case listening(port: Int)
        case failed(String)
    }

    private(set) var serverState: ServerState = .starting
    private(set) var connected: [String: ConnectedDevice] = [:]
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var pairing: (payload: PairingPayload, expires: Date)?
    private(set) var lastRejection: String?
    /// 每台在线手机一个：相册、文件、缩略图、导出。
    private(set) var libraries: [String: PhoneLibrary] = [:]
    /// 每台已配对手机一个：设备信息、状态、历史。离线时保留最后已知的数据。
    private(set) var monitors: [String: DeviceMonitor] = [:]

    var activeDevice: ConnectedDevice? { connected.values.min { $0.device.pairedAt < $1.device.pairedAt } }
    var activeLibrary: PhoneLibrary? { activeDevice.flatMap { libraries[$0.id] } }
    /// 概览页显示哪台手机：在线的优先，否则是最早配对的那台。
    var activeMonitor: DeviceMonitor? {
        activeDevice.flatMap { monitors[$0.id] } ?? monitors.values.min { ($0.pairedAt ?? .distantPast) < ($1.pairedAt ?? .distantPast) }
    }

    /// 主窗口侧边栏的选中项。放在这里，菜单栏的“前往”命令也能切换。
    var sidebarSelection: SidebarItem? = .overview

    private let registry = RemoteRegistry()
    /// 当前活动手机的 id，网络线程上转发投屏消息时要用，所以单独放一个带锁的盒子。
    private let activeDeviceId = LockedValue<String?>(nil)
    private let serverBox = LockedValue<LinkServer?>(nil)

    let mirror = MirrorSession()
    private let notifications = NotificationPresenter()
    private let calls = CallAlerter()
    private let clipboard = ClipboardSync()
    let airSend = AirSendService()
    /// 投屏助手：独立的 App，自己的 Dock 图标和窗口。
    let mirrorHelper = MirrorHelper()
    private let widget = WidgetPublisher()
    /// 由菜单栏图标视图交给我们，用来从 AppDelegate（比如点了小组件）打开窗口。
    var openWindowAction: ((String) -> Void)?
    private var server: LinkServer?
    private var pairingStore: PairingStore?
    private var identity: LinkIdentity?
    private var activity: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []

    let macName = Host.current().localizedName ?? "Mac"

    static let supportDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinkToMacOS", isDirectory: true)
    }()

    func start() {
        guard server == nil else { return }
        // 常驻后台收发心跳，避免被 App Nap 挂起
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Keep phone link alive")
        observeSleep()
        notifications.requestAuthorization()
        clipboard.send = { [weak self] clip in
            guard let self, let id = activeDevice?.id else { return }
            server?.send(.clipboard(clip), to: id)
        }
        airSend.deviceName = { [weak self] in self?.activeDevice?.device.name }
        airSend.remote = { [weak self] in self?.activeLibrary?.remote }
        airSend.send = { [weak self] message in
            guard let self, let id = activeDevice?.id else { return }
            server?.send(message, to: id)
        }
        airSend.sendAwaiting = { [weak self] message in
            guard let self, let id = activeDevice?.id, let server else { throw CancellationError() }
            try await server.sendAwaiting(message, to: id)
        }
        airSend.startWatchingOutbox()
        mirror.remoteProvider = { [weak self] in self?.activeLibrary?.remote }
        mirror.preferredModel = { [weak self] in self?.activeDevice?.device.model }
        // 投屏助手发来的请求和输入，转给当前手机
        mirrorHelper.forwardToPhone = { [serverBox, activeDeviceId] message in
            guard let id = activeDeviceId.value, let server = serverBox.value else { return }
            server.send(message, to: id)
        }
        Task { await mirrorHelper.startRelay() }
        Task.detached(priority: .background) { ExportService.pruneCache() }
        Task { await startServer() }
    }

    private func startServer() async {
        do {
            let identity = try LinkIdentity.loadOrCreate(in: Self.supportDirectory, commonName: "LinkToMacOS \(macName)")
            let store = PairingStore(directory: Self.supportDirectory)
            let server = LinkServer(identity: identity, pairing: store, macName: macName)
            self.identity = identity
            self.pairingStore = store
            self.server = server
            serverBox.value = server
            pairedDevices = store.pairedDevices
            for device in pairedDevices { monitors[device.deviceId] = DeviceMonitor(device: device, directory: Self.supportDirectory) }
            // 文件数据量大，在连接线程上直接交给 PhoneRemote，不经过主线程
            // 属于投屏助手的消息（响应、视频、音频、投屏事件）先转给助手
            server.setInboundHook { [registry, relay = mirrorHelper.relay] deviceId, message in
                if relay.routeFromPhone(message) { return true }
                return registry.remote(for: deviceId)?.handle(message) ?? false
            }
            try await server.start()
            for await event in server.events { handle(event) }
        } catch {
            log.error("server failed: \(error)")
            serverState = .failed(error.localizedDescription)
        }
    }

    private func handle(_ event: LinkEvent) {
        switch event {
        case .listening(let port):
            serverState = .listening(port: port)
        case .connected(let device, let newlyPaired, let address):
            connected[device.deviceId] = ConnectedDevice(device: device)
            clipboard.isActive = true
            activeDeviceId.value = activeDevice?.id
            let id = device.deviceId
            let remote = PhoneRemote { [weak server] message in server?.send(message, to: id) }
            registry.set(remote, for: id)?.close()
            let library = PhoneLibrary(remote: remote, deviceName: device.name)
            libraries[id] = library
            Task { await library.refreshOverview() }
            if newlyPaired {
                pairing = nil
                pairedDevices = pairingStore?.pairedDevices ?? []
            }
            let monitor = monitors[id] ?? DeviceMonitor(device: device, directory: Self.supportDirectory)
            monitors[id] = monitor
            monitor.attach(remote: remote, device: device, address: address)
            widget.publish(monitor, force: true)
            airSend.processOutbox()
        case .message(let deviceId, .deviceStatus(let status)):
            connected[deviceId]?.status = status
            monitors[deviceId]?.update(status)
            widget.publish(monitors[deviceId])
        case .message(let deviceId, .notification(let notification)):
            guard Prefs.bool(Prefs.showNotifications, default: true) else { break }
            notifications.post(notification, from: connected[deviceId]?.device.name ?? String(localized: "手机"))
        case .message(_, .notificationRemoved(let removed)):
            notifications.remove(key: removed.key)
        case .message(let deviceId, .callState(let call)):
            calls.handle(call, from: connected[deviceId]?.device.name ?? String(localized: "手机"))
        case .message(let deviceId, .airOffer(let offer)):
            airSend.receive(offer, from: connected[deviceId]?.device.name ?? String(localized: "手机"))
        case .message(let deviceId, .airText(let text)):
            airSend.receive(text: text.text, from: connected[deviceId]?.device.name ?? String(localized: "手机"))
        case .message(_, .clipboard(let clip)):
            clipboard.receive(clip)
        case .message(let deviceId, let message):
            log.debug("unhandled \(message.typeName) from \(deviceId)")
        case .disconnected(let deviceId, let reason):
            log.info("\(deviceId) disconnected: \(reason)")
            connected[deviceId] = nil
            registry.remove(deviceId)?.close()
            libraries[deviceId] = nil
            monitors[deviceId]?.detach()
            widget.publish(monitors[deviceId], force: true)
            // 手机离线后，Mac 上残留的手机通知已无法与手机同步，一并清掉；正在响的来电提示也停掉
            if connected.isEmpty { notifications.removeAll() }
            calls.stop()
            clipboard.isActive = !connected.isEmpty
            activeDeviceId.value = activeDevice?.id
            if connected.isEmpty { mirrorHelper.phoneDisconnected() }
        case .rejected(let reason):
            lastRejection = reason
        }
    }

    /// 开始投屏（可以带一个要先打开的应用）：交给投屏助手 App。
    func startMirror(app: PhoneApp? = nil) {
        guard let device = activeDevice?.device else { return }
        let target = app.map { (package: $0.package, label: $0.label) }
        mirrorHelper.start(
            params: MirrorHelper.params(session: mirror, deviceName: device.name, model: device.model, app: target),
            app: target)
    }

    // MARK: Dock

    /// 菜单栏常驻程序：主窗口开着时才出现在 Dock 里。投屏有自己的助手 App，它的 Dock 图标和这里无关。
    func setMainWindowVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    /// 打开主窗口并切到 `item`（小组件、菜单命令都走这里）。
    func showMainWindow(_ item: SidebarItem? = nil) {
        if let item { sidebarSelection = item }
        openWindowAction?(WindowID.main)
        NSApp.activate()
    }

    // MARK: - 配对

    func beginPairing() {
        guard let store = pairingStore, let identity, case .listening(let port) = serverState else { return }
        let (token, expires) = store.issueToken()
        let payload = PairingPayload(
            macName: macName, hosts: PairingPayload.localIPv4Addresses(), port: port,
            fingerprint: identity.fingerprint, token: token)
        pairing = (payload, expires)
    }

    func cancelPairing() {
        pairingStore?.cancelToken()
        pairing = nil
    }

    func unpair(_ device: PairedDevice) {
        // 正在投这台手机的屏，先停掉（会把手机屏幕还原）
        if activeDevice?.id == device.deviceId, mirrorHelper.isRunning {
            mirrorHelper.stop()
        }
        server?.send(.goodbye(reason: "unpaired"), to: device.deviceId)
        pairingStore?.remove(deviceId: device.deviceId)
        pairedDevices = pairingStore?.pairedDevices ?? []
        monitors[device.deviceId]?.deleteSavedData()
        monitors[device.deviceId] = nil
    }

    // MARK: - 生命周期：退出或睡眠前通知手机，让手机及时退出免打扰

    func prepareForQuit() async {
        calls.stop()
        clipboard.isActive = false
        await mirrorHelper.shutdown()
        await server?.shutdown(reason: "quit")
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.server?.disconnectAll(reason: "sleep") }
        })
    }
}

#if DEBUG
extension AppModel {
    /// 调试用：装一台在线的示例手机，用于离屏渲染菜单栏面板等界面。
    func installSampleDevice() {
        let monitor = DeviceMonitor.sample(online: true)
        monitors["sample"] = monitor
        connected["sample"] = ConnectedDevice(device: DeviceMonitor.sampleDevice(), status: monitor.status)
    }
}
#endif
