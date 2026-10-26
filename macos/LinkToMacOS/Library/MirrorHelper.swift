import AppKit
import LinkCore
import Observation
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "mirror-helper")

/// 投屏助手（独立的 App，自己的 Dock 图标）的管理：启动它、告诉它开始、转发它和手机之间的消息、让它停止。
///
/// 助手不直接连手机：它连本机的中继（`RelayServer`），请求、输入和麦克风数据经这里转给手机，
/// 手机发来的、属于助手的响应、视频和音频数据、投屏事件，经这里转给它。
@MainActor
@Observable
final class MirrorHelper {
    static let appName = "Link to macOS Mirror"

    /// 助手已连上中继，正在投屏。
    private(set) var isRunning = false
    /// 已经启动助手，等它连上。
    private(set) var isLaunching = false
    private(set) var launchError: String?

    private let token: String
    @ObservationIgnored let relay: RelayServer
    private var pendingStart: JSONValue?
    private var launchTimeout: Task<Void, Never>?
    /// 转给当前手机的发送函数（在网络线程上调用）。由 AppModel 设置。
    @ObservationIgnored nonisolated(unsafe) var forwardToPhone: @Sendable (LinkMessage) -> Void = { _ in }

    init() {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token = bytes.map { String(format: "%02x", $0) }.joined()
        relay = RelayServer(token: token)
    }

    func startRelay() async {
        relay.onFromHelper = { [weak self] message in self?.forwardToPhone(message) }
        relay.onClientChange = { [weak self] connected in
            Task { @MainActor in self?.clientChanged(connected) }
        }
        do {
            try await relay.start()
        } catch {
            log.error("relay failed to start: \(error)")
            launchError = error.localizedDescription
        }
    }

    private var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(Self.appName).app")
    }

    // MARK: 开始和结束

    /// 开始投屏：助手没在运行就启动它，等它连上后让它开始；已经在运行就把窗口带到前面（要打开应用的话让它打开）。
    func start(params: JSONValue, app: (package: String, label: String)?) {
        if isRunning {
            if let app {
                relay.sendToHelper(.request(RPCRequest(id: 0, method: "helperLaunch", params: .object(["package": .string(app.package), "label": .string(app.label)]))))
            } else {
                showWindow()
            }
            return
        }
        guard !isLaunching else { return }
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            launchError = String(localized: "找不到投屏助手。请重新安装 Link to macOS。")
            return
        }
        launchError = nil
        pendingStart = params
        isLaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--relay-token", token]
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.launchFailed(error.localizedDescription) }
            }
        }
        launchTimeout?.cancel()
        launchTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.launchFailed(String(localized: "投屏助手没有启动。"))
        }
    }

    func stop() {
        relay.sendToHelper(.goodbye(reason: "stop"))
    }

    func showWindow() {
        relay.sendToHelper(.request(RPCRequest(id: 0, method: "helperShow")))
    }

    /// 手机断开了：让助手结束投屏。
    func phoneDisconnected() {
        guard isRunning else { return }
        relay.sendToHelper(.goodbye(reason: "phone-gone"))
    }

    func shutdown() async {
        stop()
        await relay.shutdown()
    }

    private func clientChanged(_ connected: Bool) {
        if connected {
            isRunning = true
            isLaunching = false
            launchTimeout?.cancel()
            if let params = pendingStart {
                pendingStart = nil
                relay.sendToHelper(.request(RPCRequest(id: 0, method: "helperStart", params: params)))
            }
        } else {
            isRunning = false
            // 助手意外退出时手机上的投屏可能还开着：补发一次停止（助手正常退出时它已经停过了，重复无害）
            forwardToPhone(.request(RPCRequest(id: relayRequestIdBase, method: "mirrorStop")))
        }
    }

    private func launchFailed(_ message: String) {
        guard isLaunching else { return }
        isLaunching = false
        pendingStart = nil
        launchError = message
    }

    /// 把主程序里的投屏设置、手机信息打成助手需要的参数。助手是另一个 App，用户默认值不共用，所以由这里交给它。
    static func params(session: MirrorSession, deviceName: String, model: String, app: (package: String, label: String)?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "mode": .string(session.mode.rawValue),
            "quality": .string(session.quality.rawValue),
            "screenOff": .bool(session.turnPhoneScreenOff),
            "forceStop": .bool(session.forceStopOnLaunch),
            "audio": .bool(session.forwardAudio),
            "microphone": .bool(session.forwardMic),
            "deviceName": .string(deviceName),
            "model": .string(model),
        ]
        if let app {
            fields["app"] = .string(app.package)
            fields["appLabel"] = .string(app.label)
        }
        return .object(fields)
    }
}
