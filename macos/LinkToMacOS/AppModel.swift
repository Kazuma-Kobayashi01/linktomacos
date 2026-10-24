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

    private let notifications = NotificationPresenter()
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
            pairedDevices = store.pairedDevices
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
        case .connected(let device, let newlyPaired):
            connected[device.deviceId] = ConnectedDevice(device: device)
            if newlyPaired {
                pairing = nil
                pairedDevices = pairingStore?.pairedDevices ?? []
            }
        case .message(let deviceId, .deviceStatus(let status)):
            connected[deviceId]?.status = status
        case .message(let deviceId, .notification(let notification)):
            notifications.post(notification, from: connected[deviceId]?.device.name ?? "手机")
        case .message(_, .notificationRemoved(let removed)):
            notifications.remove(key: removed.key)
        case .message(let deviceId, let message):
            log.debug("unhandled \(message.typeName) from \(deviceId)")
        case .disconnected(let deviceId, let reason):
            log.info("\(deviceId) disconnected: \(reason)")
            connected[deviceId] = nil
            // 手机离线后，Mac 上残留的手机通知已无法与手机同步，一并清掉
            if connected.isEmpty { notifications.removeAll() }
        case .rejected(let reason):
            lastRejection = reason
        }
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
        server?.send(.goodbye(reason: "unpaired"), to: device.deviceId)
        pairingStore?.remove(deviceId: device.deviceId)
        pairedDevices = pairingStore?.pairedDevices ?? []
    }

    // MARK: - 生命周期：退出或睡眠前通知手机，让手机及时退出免打扰

    func prepareForQuit() async {
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
