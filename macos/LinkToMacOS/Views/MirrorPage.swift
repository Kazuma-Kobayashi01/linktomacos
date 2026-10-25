import AppKit
import LinkCore
import SwiftUI

/// 投屏页：检查 adb 和 USB 手机，启动增强服务，开始投屏。
struct MirrorPage: View {
    let library: PhoneLibrary
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let session = model.mirror
        ScrollView {
            VStack(spacing: 16) {
                ServiceCard(session: session)
                MirrorCard(session: session) { app in
                    await session.start(app: app)
                    if session.isRunning { openWindow(id: WindowID.mirror) }
                } showWindow: {
                    openWindow(id: WindowID.mirror)
                }
                HelpCard()
            }
            .padding(20)
        }
        .navigationTitle("投屏")
        .navigationSubtitle(library.deviceName)
        .task {
            // 页面可见时每 3 秒检查一次：插上数据线或服务连上后，状态能自己更新
            while !Task.isCancelled {
                await session.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private struct PageCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)) }
    }
}

private struct StatusRow: View {
    let title: LocalizedStringKey
    let ok: Bool?
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : (ok == false ? "xmark.circle.fill" : "questionmark.circle"))
                .foregroundStyle(ok == true ? Color.green : (ok == false ? Color.red : Color.secondary))
            Text(title)
            Spacer(minLength: 12)
            Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .font(.callout)
    }
}

private struct ServiceCard: View {
    let session: MirrorSession

    private var usbDevice: AdbDevice? { session.devices.first { $0.isUSB } }

    var body: some View {
        PageCard(title: "增强服务", systemImage: "bolt.horizontal.circle") {
            Text("增强服务运行在手机上，让投屏不需要每次授权，并且能真实地点按和滑动。用数据线连接电脑启动一次，之后拔掉也一直有效，直到手机重启。")
                .font(.callout).foregroundStyle(.secondary)

            VStack(spacing: 8) {
                StatusRow(title: "adb 工具", ok: session.adbPath != nil,
                          detail: session.adbPath?.path ?? String(localized: "未找到"))
                StatusRow(title: "USB 连接的手机", ok: usbDevice.map { $0.state == "device" },
                          detail: usbDevice.map { $0.state == "device" ? ($0.model ?? $0.serial) : String(localized: "等待手机授权") } ?? String(localized: "未检测到"))
                StatusRow(title: "手机上的增强服务", ok: session.serviceReady,
                          detail: session.serviceOutdated ? String(localized: "版本过旧，需要重新启动")
                              : session.serviceReady == true ? String(localized: "运行中")
                              : session.serviceReady == false ? String(localized: "未运行") : String(localized: "手机未连接"))
            }

            HStack {
                Button {
                    Task { await session.startService() }
                } label: {
                    if session.phase == .startingService {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在启动…") }
                    } else {
                        Text(session.serviceReady == true ? "重新启动增强服务" : "启动增强服务")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isBusy || session.adbPath == nil || usbDevice?.state != "device")

                if session.serviceReady == true {
                    Button("停止增强服务") { Task { await session.stopService() } }
                        .disabled(session.isBusy || usbDevice == nil)
                }
                if session.adbPath == nil {
                    Button("选择 adb…") { chooseAdb() }
                }
            }

            if let message = session.statusMessage {
                let isError: Bool = { if case .failed = session.phase { return true } else { return false } }()
                Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(isError ? Color.orange : Color.green)
                    .textSelection(.enabled)
            }
        }
    }

    private func chooseAdb() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "选择 adb 可执行文件")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Android/sdk/platform-tools")
        if panel.runModal() == .OK, let url = panel.url { session.chooseAdb(url) }
    }
}

private struct MirrorCard: View {
    @Bindable var session: MirrorSession
    let start: (PhoneApp?) async -> Void
    let showWindow: () -> Void
    @State private var choosingApp = false

    var body: some View {
        PageCard(title: "开始投屏", systemImage: "rectangle.on.rectangle") {
            Picker("模式", selection: $session.mode) {
                Text("独立显示").tag(MirrorMode.newDisplay)
                Text("镜像手机屏幕").tag(MirrorMode.mirror)
            }
            .pickerStyle(.segmented)
            .disabled(session.isRunning || session.isBusy)

            Text(session.mode == .newDisplay
                 ? "在手机里新建一个独立的显示器，应用开在上面，手机自己的屏幕不受影响，可以关掉或锁屏。窗口比例固定为手机比例，可以等比缩放。"
                 : "把手机屏幕原样显示在电脑上，窗口比例固定为手机比例。可以操控桌面和应用，手机屏幕默认关闭。")
                .font(.callout).foregroundStyle(.secondary)

            Picker("画质", selection: $session.quality) {
                ForEach(MirrorQuality.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(session.isRunning || session.isBusy)
            if session.quality == .native {
                Text("原生：独立显示和手机屏幕一样大、dpi 也一样，应用显示与手机上完全一致；占用带宽很高，不适合热点。").font(.caption).foregroundStyle(.secondary)
            }

            Toggle("投屏时关闭手机屏幕", isOn: $session.turnPhoneScreenOff)
                .toggleStyle(.checkbox)
                .disabled(session.isRunning || session.isBusy)

            HStack {
                if session.isRunning {
                    Button("显示投屏窗口", action: showWindow).buttonStyle(.borderedProminent)
                    Button("停止投屏") { Task { await session.stop() } }
                } else if session.mode == .newDisplay {
                    Button {
                        choosingApp = true
                    } label: {
                        if session.phase == .startingMirror {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在连接…") }
                        } else {
                            Text("选择应用并开始…")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.serviceReady != true || session.isBusy)
                } else {
                    Button {
                        Task { await start(nil) }
                    } label: {
                        if session.phase == .startingMirror {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在连接…") }
                        } else {
                            Text("开始投屏")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.serviceReady != true || session.isBusy)
                }
            }
            if session.serviceReady != true {
                Text("请先启动增强服务").font(.callout).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $choosingApp) {
            VStack(spacing: 0) {
                HStack {
                    Text("选择要打开的应用").font(.headline)
                    Spacer()
                    Button("取消") { choosingApp = false }
                }
                .padding([.horizontal, .top], 14)
                AppLauncherView(session: session, showsStartWithoutApp: true) { app in
                    choosingApp = false
                    Task { await start(app) }
                } onStartEmpty: {
                    choosingApp = false
                    Task { await start(nil) }
                }
            }
            .frame(width: 480, height: 540)
        }
    }
}

private struct HelpCard: View {
    var body: some View {
        PageCard(title: "第一次使用", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. 手机：设置 → 关于手机 → 软件信息，连续点按“版本号”7 次，打开开发者选项。")
                Text("2. 手机：设置 → 开发者选项 → 打开“USB 调试”。")
                Text("3. 三星手机：设置 → 安全和隐私 → 自动拦截器，需要关闭，否则会拦截 USB 调试命令。")
                Text("4. 用数据线连接电脑，手机弹出“允许 USB 调试吗？”时点允许。")
                Text("5. 点击“启动增强服务”。启动成功后可以拔掉数据线。")
                Text("手机重启后，需要再插一次数据线启动。")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}
