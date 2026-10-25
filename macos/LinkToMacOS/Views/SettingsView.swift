import LinkCore
import ServiceManagement
import SwiftUI

/// 设置窗口（⌘,）。
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
            MirrorSettings().tabItem { Label("投屏", systemImage: "rectangle.on.rectangle") }
            DeviceSettings().tabItem { Label("设备", systemImage: "iphone") }
            ShortcutSettings().tabItem { Label("快捷键", systemImage: "command") }
            AboutSettings().tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 通用

private struct GeneralSettings: View {
    @AppStorage(Prefs.openMainWindowAtLaunch) private var openMainWindow = true
    @AppStorage(Prefs.showNotifications) private var showNotifications = true
    @AppStorage(Prefs.notificationSound) private var notificationSound = true
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 LinkToMacOS", isOn: Binding(get: { loginItemStatus == .enabled }, set: setLoginItem))
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("需要在系统设置里允许").foregroundStyle(.secondary)
                        Spacer()
                        Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("启动时打开主窗口", isOn: $openMainWindow)
            }

            Section {
                Toggle("在 Mac 上显示手机通知", isOn: $showNotifications)
                Toggle("播放提示音", isOn: $notificationSound).disabled(!showNotifications)
            } header: {
                Text("通知")
            } footer: {
                Text("转发哪些应用的通知、连接时是否开启免打扰，在手机上的 LinkToMacOS 里设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}

// MARK: - 投屏

private struct MirrorSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var session = model.mirror
        Form {
            Section {
                Picker("模式", selection: $session.mode) {
                    Text("独立显示").tag(MirrorMode.newDisplay)
                    Text("镜像手机屏幕").tag(MirrorMode.mirror)
                }
                Picker("画质", selection: $session.quality) {
                    ForEach(MirrorQuality.allCases) { Text($0.title).tag($0) }
                }
                if session.quality == .native {
                    Text("原生：独立显示和手机屏幕一样大、dpi 也一样，应用显示与手机上完全一致；占用带宽很高，不适合热点。").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("投屏时关闭手机屏幕", isOn: $session.turnPhoneScreenOff)
                Toggle("先结束应用再打开", isOn: $session.forceStopOnLaunch)
            } header: {
                Text("默认设置")
            } footer: {
                Text("这些设置在下次开始投屏时生效。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("adb 工具") {
                LabeledContent("路径") {
                    Text(session.adbPath?.path ?? String(localized: "未找到"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("恢复自动查找") { session.resetAdb() }
                    Button("选择 adb…") { chooseAdb(session) }
                }
            }
        }
        .formStyle(.grouped)
        .task { await session.refresh() }
    }

    private func chooseAdb(_ session: MirrorSession) {
        let panel = NSOpenPanel()
        panel.message = String(localized: "选择 adb 可执行文件")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Android/sdk/platform-tools")
        if panel.runModal() == .OK, let url = panel.url { session.chooseAdb(url) }
    }
}

// MARK: - 设备

private struct DeviceSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var unpairing: PairedDevice?
    private var unpairingName: String { unpairing?.name ?? "" }

    var body: some View {
        Form {
            Section("已配对的手机") {
                if model.pairedDevices.isEmpty {
                    Text("还没有配对手机").foregroundStyle(.secondary)
                }
                ForEach(model.pairedDevices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).fontWeight(.medium)
                            HStack(spacing: 6) {
                                let online = model.connected[device.deviceId] != nil
                                Circle().fill(online ? Color.green : Color.gray).frame(width: 6, height: 6)
                                Text(online ? "已连接" : "离线")
                                Text("·")
                                Text(device.model)
                                Text("·")
                                Text("配对于 \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("取消配对…", role: .destructive) { unpairing = device }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("配对新手机…") {
                        model.beginPairing()
                        openWindow(id: WindowID.pairing)
                        NSApp.activate()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            Text("取消与“\(unpairingName)”的配对？"),
            isPresented: Binding(get: { unpairing != nil }, set: { if !$0 { unpairing = nil } }),
            presenting: unpairing
        ) { device in
            Button("取消配对", role: .destructive) { model.unpair(device) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("取消后，这台手机需要重新扫码才能连接。Mac 上保存的这台手机的设备信息和历史记录也会删除。")
        }
    }
}

// MARK: - 快捷键

private struct ShortcutSettings: View {
    private struct Item: Identifiable {
        let keys: String
        let title: LocalizedStringKey
        var id: String { keys }
    }

    private let groups: [(LocalizedStringKey, [Item])] = [
        ("通用", [
            Item(keys: "⌘,", title: "设置"),
            Item(keys: "⌘0", title: "打开主窗口"),
            Item(keys: "⇧⌘N", title: "配对新手机"),
            Item(keys: "⌘R", title: "刷新当前页面"),
        ]),
        ("前往", [
            Item(keys: "⌘1", title: "概览"),
            Item(keys: "⌘2", title: "投屏"),
            Item(keys: "⌘3", title: "所有项目"),
            Item(keys: "⌘4", title: "视频"),
            Item(keys: "⌘5", title: "应用"),
            Item(keys: "⌘6", title: "内部存储"),
            Item(keys: "⌘7", title: "下载"),
        ]),
        ("照片和文件", [
            Item(keys: "Space", title: "预览所选照片"),
            Item(keys: "⌘A", title: "全选"),
            Item(keys: "⌘C", title: "拷贝，可在访达里粘贴"),
            Item(keys: "⌘[ / ⌘]", title: "后退 / 前进"),
            Item(keys: "⌘↑", title: "上一级文件夹"),
        ]),
        ("投屏窗口", [
            Item(keys: "Esc / ⌘[", title: "返回（或按右键）"),
            Item(keys: "⇧⌘H", title: "主页（或按中键）"),
            Item(keys: "⇧⌘R", title: "最近任务"),
            Item(keys: "⇧⌘A", title: "打开应用（独立显示）"),
            Item(keys: "⇧⌘O", title: "关闭或打开手机屏幕"),
            Item(keys: "⌘C / ⌘V", title: "在手机上拷贝 / 粘贴"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section(group.0) {
                    ForEach(group.1) { item in
                        LabeledContent {
                            Text(item.keys).font(.body.monospaced()).foregroundStyle(.secondary)
                        } label: {
                            Text(item.title)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }
}

// MARK: - 关于

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("LinkToMacOS").font(.title.bold())
            Text("版本 \(version)").foregroundStyle(.secondary)
            Text("让 Android 手机与 Mac 互联：通知、相册与文件、投屏。")
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 6)
            Text("投屏服务的实现参考了开源项目 scrcpy（Apache License 2.0）。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
