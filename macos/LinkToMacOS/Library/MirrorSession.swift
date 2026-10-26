import AppKit
import AVFoundation
import SwiftUI
import LinkCore
import Observation
import os

private let log = Logger(subsystem: "com.linktomacos.mac", category: "mirror")

/// 画质预设：长边像素上限和码率。
enum MirrorQuality: String, CaseIterable, Identifiable {
    case smooth, standard, high, native
    var id: String { rawValue }
    var maxSize: Int {
        switch self {
        case .smooth: 1280
        case .standard: 1920
        case .high: 2560
        case .native: 4096 // 不缩小：独立显示和手机屏幕一样大，dpi 也和手机一样
        }
    }
    var bitRate: Int {
        switch self {
        case .smooth: 4_000_000
        case .standard: 8_000_000
        case .high: 16_000_000
        case .native: 24_000_000
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .smooth: "流畅（适合热点）"
        case .standard: "标准"
        case .high: "高清"
        case .native: "原生"
        }
    }
}

/// 投屏会话：管理增强服务的启动、投屏的开始与结束、视频解码，以及输入转发。
@MainActor
@Observable
final class MirrorSession {
    enum Phase: Equatable {
        case idle
        case startingService
        case startingMirror
        case running
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var adbPath: URL?
    private(set) var devices: [AdbDevice] = []
    /// 手机上的增强服务是否在运行；nil 表示还不知道（没连上手机）。
    private(set) var serviceReady: Bool?
    /// 手机上的增强服务是旧版本，需要用 USB 重新启动。
    private(set) var serviceOutdated = false
    private(set) var videoSize: CGSize = .zero
    private(set) var statusMessage: String?
    /// 上一次打开应用失败的原因。
    private(set) var launchError: String?
    var quality: MirrorQuality = MirrorQuality(rawValue: UserDefaults.standard.string(forKey: "mirrorQuality") ?? "") ?? .standard {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "mirrorQuality") }
    }
    /// 下次投屏用的模式；正在投屏时看 `runningMode`。
    var mode: MirrorMode = MirrorMode(rawValue: UserDefaults.standard.string(forKey: "mirrorMode") ?? "") ?? .newDisplay {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mirrorMode") }
    }
    private(set) var runningMode: MirrorMode = .newDisplay
    /// 投屏时关闭手机自己的屏幕（投屏继续，节省电量，保护隐私）。
    var turnPhoneScreenOff: Bool = UserDefaults.standard.object(forKey: "mirrorScreenOff") as? Bool ?? true {
        didSet { UserDefaults.standard.set(turnPhoneScreenOff, forKey: "mirrorScreenOff") }
    }
    private(set) var phoneScreenIsOff = false
    private(set) var virtualDisplayId: Int?

    /// 手机上能启动的应用，按需加载。
    private(set) var apps: [PhoneApp] = []
    private(set) var appsError: String?
    let icons = AppIconLoader()
    /// 打开应用时先结束它：它已经在手机屏幕上打开时需要，否则系统会直接把那个窗口调到前面，而不是开在虚拟显示器上。
    var forceStopOnLaunch: Bool = UserDefaults.standard.bool(forKey: "mirrorForceStop") {
        didSet { UserDefaults.standard.set(forceStopOnLaunch, forKey: "mirrorForceStop") }
    }

    /// 投屏窗口的应用列表和最近应用弹窗，菜单命令也能打开它们。
    var showAppLauncher = false
    var showRecentApps = false
    /// 独立显示里这次打开过的应用，最近的在前。虚拟显示器关掉后这些应用也随之关闭，所以停止投屏时清空。
    private(set) var recentApps: [PhoneApp] = []

    let decoder = VideoDecoder()
    let audioPlayer = AudioPlayer()
    /// 把手机的声音转发到 Mac 的扬声器（手机本体静音）。暂时没有界面，用 `defaults write` 改：
    /// `defaults write com.linktomacos.mac mirrorAudio -bool false`。
    var forwardAudio: Bool { UserDefaults.standard.object(forKey: "mirrorAudio") as? Bool ?? true }
    /// 把 Mac 麦克风的声音传给手机（手机上的应用录音时拿到的是 Mac 的声音）。默认关闭，需要麦克风权限。暂时没有界面：
    /// `defaults write com.linktomacos.mac mirrorMicrophone -bool true`。
    var forwardMic: Bool { UserDefaults.standard.bool(forKey: "mirrorMicrophone") }
    var remoteProvider: () -> PhoneRemote? = { nil }
    var preferredModel: () -> String? = { nil }

    var isRunning: Bool { phase == .running }
    var isNewDisplay: Bool { runningMode == .newDisplay }
    var isBusy: Bool { phase == .startingService || phase == .startingMirror }

    // MARK: 环境检查

    func refresh() async {
        adbPath = AdbLauncher.locate()
        if let adb = adbPath { devices = (try? await AdbLauncher.devices(adb: adb)) ?? [] } else { devices = [] }
        await refreshServiceState()
    }

    func chooseAdb(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: AdbLauncher.defaultsKey)
        Task { await refresh() }
    }

    /// 不再使用手动选择的 adb，恢复自动查找。
    func resetAdb() {
        UserDefaults.standard.removeObject(forKey: AdbLauncher.defaultsKey)
        Task { await refresh() }
    }

    // MARK: 增强服务

    /// 通过 USB 启动手机上的 shell 服务，并等它连上手机 App。
    func startService() async {
        guard !isBusy else { return }
        guard let remote = remoteProvider() else { return fail(String(localized: "手机未连接")) }
        phase = .startingService
        statusMessage = nil
        do {
            guard let adb = AdbLauncher.locate() else { throw AdbError.notFound }
            adbPath = adb
            devices = try await AdbLauncher.devices(adb: adb)
            let device = try AdbLauncher.pickUSBDevice(devices, preferredModel: preferredModel())
            let status = try await remote.mirrorStatus()
            try await AdbLauncher.startService(adb: adb, serial: device.serial, apkPath: status.apkPath, port: status.port, secret: status.secret)

            // 等服务连上手机 App（通常 1～2 秒）
            for _ in 0..<24 {
                try await Task.sleep(for: .milliseconds(500))
                if (try? await remote.mirrorStatus())?.ready == true {
                    serviceReady = true
                    phase = .idle
                    statusMessage = String(localized: "增强服务已启动，现在可以拔掉数据线。")
                    return
                }
            }
            let tail = await AdbLauncher.serviceLog(adb: adb, serial: device.serial)
            throw AdbError.serviceDidNotStart(log: tail)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stopService() async {
        guard let adb = AdbLauncher.locate() else { return }
        _ = try? await AdbLauncher.stopService(adb: adb, serial: AdbLauncher.pickUSBDevice(await AdbLauncher.devices(adb: adb), preferredModel: preferredModel()).serial)
        await refresh()
    }

    // MARK: 投屏

    /// 开始投屏。可以指定开始时打开的应用。
    func start(app: PhoneApp? = nil) async {
        guard !isBusy, !isRunning else { return }
        guard let remote = remoteProvider() else { return fail(String(localized: "手机未连接")) }
        phase = .startingMirror
        statusMessage = nil
        launchError = nil
        decoder.reset()
        decoder.onNeedKeyframe = { [weak remote] in remote?.sendInput(.command("sync")) }
        decoder.onSize = { [weak self] size in Task { @MainActor in self?.videoSize = size } }
        audioPlayer.stop()
        var useMic = forwardMic
        if useMic, !(await Self.microphoneAllowed()) {
            useMic = false
            statusMessage = String(localized: "没有麦克风权限，这次投屏不会使用 Mac 的麦克风。可以在系统设置 → 隐私与安全性 → 麦克风里允许。")
        }
        do {
            let decoder = decoder
            let audioPlayer = audioPlayer
            let options = MirrorStartOptions(
                mode: mode, maxSize: quality.maxSize, bitRate: quality.bitRate, fps: 60,
                width: 0, height: 0,
                app: app?.package, forceStop: forceStopOnLaunch, audio: forwardAudio, mic: useMic)
            let info = try await remote.mirrorStart(
                options,
                video: { data in decoder.handle(packet: data) },
                audio: { data in audioPlayer.handle(packet: data) },
                events: { [weak self] event in Task { @MainActor in self?.handle(event) } })
            runningMode = info.mode == "mirror" ? .mirror : .newDisplay
            virtualDisplayId = info.displayId
            videoSize = CGSize(width: info.width, height: info.height)
            phase = .running
            recentApps = []
            if let app { noteLaunched(app) }
            if turnPhoneScreenOff { setPhoneScreen(off: true) }
            if useMic, let micStreamId = info.micStreamId, micStreamId > 0 {
                audioPlayer.startMic { [weak remote] pcm in remote?.sendMic(streamId: micStreamId, pcm) }
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// 麦克风权限：没问过就弹系统的授权框（要用户自己点），拒绝过就返回 false。
    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func stop() async {
        guard phase == .running || phase == .startingMirror else { return }
        phase = .idle
        if phoneScreenIsOff { setPhoneScreen(off: false) }
        await remoteProvider()?.mirrorStop()
        decoder.reset()
        audioPlayer.stop()
        virtualDisplayId = nil
        recentApps = []
    }

    /// 手动把独立显示转成横向或竖向。应用有明确的方向要求时，手机会自动转回去。
    func rotate() async {
        guard isRunning, isNewDisplay, videoSize.width > 0, let remote = remoteProvider() else { return }
        try? await remote.mirrorResize(width: Int(videoSize.height), height: Int(videoSize.width))
    }

    /// 打开或关闭手机自己的屏幕。投屏不受影响。
    func setPhoneScreen(off: Bool) {
        phoneScreenIsOff = off
        send(.command(off ? "screenOff" : "screenOn"))
    }

    // MARK: 应用

    func loadApps(force: Bool = false) async {
        guard force || apps.isEmpty, let remote = remoteProvider() else { return }
        icons.remote = remote
        do {
            apps = try await remote.listApps()
            appsError = nil
        } catch {
            appsError = error.localizedDescription
        }
    }

    /// 在正在投的显示器上打开应用：独立显示模式开在虚拟显示器上，镜像模式开在手机屏幕上。
    /// `forceStop` 为 nil 时按设置；切换到最近打开的应用时传 false，保留它的状态。
    func launch(_ app: PhoneApp, forceStop: Bool? = nil) async {
        guard isRunning, let remote = remoteProvider() else { return }
        do {
            try await remote.mirrorLaunch(package: app.package, forceStop: forceStop ?? forceStopOnLaunch)
            launchError = nil
            noteLaunched(app)
        } catch {
            launchError = error.localizedDescription
        }
    }

    /// 直接打开应用：已经在投屏就开在当前画面里，否则按当前模式开始投屏并打开它。
    func open(_ app: PhoneApp) async {
        if isRunning { await launch(app) } else { await start(app: app) }
    }

    /// 只检查手机上的增强服务有没有在运行（不碰 adb）。
    func refreshServiceState() async {
        guard let remote = remoteProvider() else {
            serviceReady = nil
            serviceOutdated = false
            return
        }
        let status = try? await remote.mirrorStatus()
        serviceReady = status?.ready
        serviceOutdated = status?.outdated ?? false
    }

    private func noteLaunched(_ app: PhoneApp) {
        recentApps.removeAll { $0.package == app.package }
        recentApps.insert(app, at: 0)
        if recentApps.count > 12 { recentApps.removeLast(recentApps.count - 12) }
    }

    func send(_ input: MirrorInput) {
        remoteProvider()?.sendInput(input)
    }

    /// 在手机上按一下实体键（Android 键值）：音量、媒体键等。
    func press(keyCode: Int) {
        send(MirrorInput(k: "key", a: 0, c: keyCode, m: 0))
        send(MirrorInput(k: "key", a: 1, c: keyCode, m: 0))
    }

    /// 把一段文字输入到手机当前的输入框里。
    func type(_ text: String) {
        guard !text.isEmpty else { return }
        send(MirrorInput(k: "text", text: text))
    }

    /// 投屏窗口置顶（浮在其他窗口上面）。
    var alwaysOnTop = false

    private func handle(_ event: MirrorEvent) {
        switch event.event {
        case "resized":
            if let w = event.width, let h = event.height { videoSize = CGSize(width: w, height: h) }
        case "error":
            fail(event.message ?? String(localized: "投屏出错"))
        case "stopped":
            if phase == .running { phase = .idle; phoneScreenIsOff = false; recentApps = []; decoder.reset(); audioPlayer.stop() }
        default:
            break
        }
    }

    private func fail(_ message: String) {
        log.error("mirror failed: \(message)")
        phase = .failed(message)
        statusMessage = message
    }
}

#if DEBUG
extension MirrorSession {
    /// 调试用：直接设置状态，用于离屏渲染投屏页和投屏窗口。
    func debugApply(serviceReady: Bool?, devices: [AdbDevice], phase: Phase = .idle, videoSize: CGSize = .zero) {
        self.serviceReady = serviceReady
        self.devices = devices
        self.phase = phase
        self.videoSize = videoSize
        self.adbPath = AdbLauncher.bundled ?? URL(fileURLWithPath: "/usr/local/bin/adb")
    }
}
#endif
