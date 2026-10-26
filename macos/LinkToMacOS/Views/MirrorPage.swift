import AppKit
import LinkCore
import SwiftUI

/// 投屏页：还没设置好时，按步骤带用户做一次设置；设置好后，选模式、点开始。
/// 面向普通用户：技术细节（adb 路径、重启服务）收进“高级”。
struct MirrorPage: View {
    let library: PhoneLibrary
    @Environment(AppModel.self) private var model

    static let contentWidth: CGFloat = 640
    /// 离屏渲染截图时关掉轮询，免得它覆盖示例状态。
    nonisolated(unsafe) static var pollingEnabled = true

    var body: some View {
        let session = model.mirror
        ScrollView {
            VStack(spacing: 20) {
                if model.mirrorHelper.isRunning {
                    RunningCard(session: session, helper: model.mirrorHelper)
                } else if session.serviceReady == true {
                    ReadyCard(session: session, helper: model.mirrorHelper) { app in
                        model.startMirror(app: app)
                    }
                } else {
                    SetupCard(session: session, phoneName: library.deviceName)
                }
                AdvancedCard(session: session)
            }
            .frame(width: Self.contentWidth)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("投屏")
        .navigationSubtitle(library.deviceName)
        .task {
            // 页面可见时每 3 秒检查一次：插上数据线或服务连上后，状态能自己更新
            while !Task.isCancelled, Self.pollingEnabled {
                await session.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

// MARK: - 通用外观

private struct Panel: ViewModifier {
    var padding: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
    }
}

private extension View {
    func panel(padding: CGFloat = 22) -> some View { modifier(Panel(padding: padding)) }
}

/// 卡片顶部的大图标和标题。
private struct PanelHeader: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tint.gradient, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 第一次：设置

private struct SetupCard: View {
    let session: MirrorSession
    let phoneName: String
    @State private var showHowTo = false

    private var usbDevice: AdbDevice? { session.devices.first { $0.isUSB } }
    private var seenPhone: Bool { usbDevice != nil }
    private var authorized: Bool { usbDevice?.state == "device" }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelHeader(
                systemImage: "sparkles", tint: .accentColor,
                title: session.serviceOutdated ? "增强服务需要更新" : "先做一次设置",
                subtitle: session.serviceOutdated
                    ? "手机上的增强服务还是旧版本。用数据线连接电脑，在“投屏”页重新启动一次。"
                    : "设置好之后，投屏不用每次在手机上确认，还能直接点按和滑动。以后拔掉数据线也不影响。")

            if session.adbPath == nil {
                Label("没有找到 adb。可以在设置里手动选择。", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 0) {
                Step(number: 1, title: "打开手机的 USB 调试", state: seenPhone ? .done : .active, isLast: false) {
                    DisclosureGroup("怎么打开？", isExpanded: $showHowTo) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. 手机：设置 → 关于手机 → 软件信息，连续点按“版本号”7 次，打开开发者选项。")
                            Text("2. 手机：设置 → 开发者选项 → 打开“USB 调试”。")
                            Text("3. 三星手机：设置 → 安全和隐私 → 自动拦截器，需要关闭，否则会拦截 USB 调试命令。")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                    .font(.callout)
                }
                Step(number: 2, title: "连接数据线，并在手机上点“允许”",
                     state: authorized ? .done : (seenPhone ? .active : .pending), isLast: false) {
                    Group {
                        if authorized, let device = usbDevice {
                            Label("已连接 \(device.model ?? device.serial)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if seenPhone {
                            Label("请在手机弹出的“允许 USB 调试吗？”里点“允许”。", systemImage: "hand.tap")
                                .foregroundStyle(.orange)
                        } else {
                            Label("还没检测到手机，请用数据线连接。", systemImage: "cable.connector")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                Step(number: 3, title: "完成设置", state: authorized ? .active : .pending, isLast: true) {
                    Button {
                        Task { await session.startService() }
                    } label: {
                        if session.phase == .startingService {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在设置…") }
                        } else {
                            Text("完成设置")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(session.isBusy || session.adbPath == nil || !authorized)
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
        .panel()
    }
}

/// 步骤条里的一步：左边是圆圈（数字或对勾）加连接线，右边是标题和内容。
private struct Step<Content: View>: View {
    enum StepState { case pending, active, done }

    let number: Int
    let title: LocalizedStringKey
    let state: StepState
    let isLast: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(fill)
                    if state == .done {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text(verbatim: "\(number)").font(.system(size: 12, weight: .semibold)).foregroundStyle(state == .active ? .white : .secondary)
                    }
                }
                .frame(width: 26, height: 26)
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                content
            }
            .padding(.bottom, isLast ? 0 : 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .done: AnyShapeStyle(Color.green)
        case .active: AnyShapeStyle(Color.accentColor)
        case .pending: AnyShapeStyle(Color.secondary.opacity(0.18))
        }
    }
}

// MARK: - 设置好了：开始投屏

private struct ReadyCard: View {
    @Bindable var session: MirrorSession
    let helper: MirrorHelper
    let start: (PhoneApp?) -> Void
    @State private var choosingApp = false

    private var locked: Bool { helper.isLaunching }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PanelHeader(
                systemImage: "rectangle.on.rectangle", tint: .accentColor,
                title: "开始投屏", subtitle: "手机已经设置好，可以开始投屏了")

            // 两种方式，做成可选的大卡片
            HStack(spacing: 12) {
                ModeTile(
                    systemImage: "display.2", title: "独立显示",
                    detail: "在手机里新开一块屏幕，手机自己可以锁屏、关屏。",
                    selected: session.mode == .newDisplay
                ) { session.mode = .newDisplay }
                ModeTile(
                    systemImage: "iphone.gen3.radiowaves.left.and.right", title: "镜像手机屏幕",
                    detail: "把手机屏幕原样显示在 Mac 上，可以操控桌面和应用。",
                    selected: session.mode == .mirror
                ) { session.mode = .mirror }
            }
            .disabled(locked)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("画质").font(.headline)
                    Spacer()
                }
                Picker("画质", selection: $session.quality) {
                    ForEach(MirrorQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(locked)
                if session.quality == .native {
                    Text("原生：独立显示和手机屏幕一样大、dpi 也一样，应用显示与手机上完全一致；占用带宽很高，不适合热点。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle("投屏时关闭手机屏幕", isOn: $session.turnPhoneScreenOff)
                .disabled(locked)

            Button {
                if session.mode == .newDisplay { choosingApp = true } else { start(nil) }
            } label: {
                Group {
                    if helper.isLaunching {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在连接…") }
                    } else {
                        Text(session.mode == .newDisplay ? "选择应用并开始…" : "开始投屏")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(locked)

            if let message = helper.launchError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                    .textSelection(.enabled)
            }
        }
        .panel()
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
                    start(app)
                } onStartEmpty: {
                    choosingApp = false
                    start(nil)
                }
            }
            .frame(width: 480, height: 540)
        }
    }
}

/// 可选的模式卡片：图标、标题、一句话说明，选中时有强调色边框和对勾。
private struct ModeTile: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 正在投屏

private struct RunningCard: View {
    let session: MirrorSession
    let helper: MirrorHelper

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelHeader(
                systemImage: "dot.radiowaves.left.and.right", tint: .green,
                title: "正在投屏",
                subtitle: "投屏在“Link to macOS Mirror”里进行，它有自己的 Dock 图标和窗口。")
            HStack(spacing: 10) {
                Button("显示投屏窗口") { helper.showWindow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("停止投屏") { helper.stop() }
                    .controlSize(.large)
            }
        }
        .panel()
    }
}

// MARK: - 高级

/// 技术细节：adb 位置、重启或停止增强服务。默认折叠。
private struct AdvancedCard: View {
    let session: MirrorSession
    @State private var expanded = false

    private var usbDevice: AdbDevice? { session.devices.first { $0.isUSB } }

    var body: some View {
        DisclosureGroup("高级", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("adb 工具") {
                    Text(session.adbPath?.path ?? String(localized: "未找到"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    if session.serviceReady == true {
                        Button("重新启动增强服务") { Task { await session.startService() } }
                            .disabled(session.isBusy || session.adbPath == nil || usbDevice?.state != "device")
                        Button("停止增强服务") { Task { await session.stopService() } }
                            .disabled(session.isBusy || usbDevice == nil)
                    }
                    if session.adbPath == nil {
                        Button("选择 adb…") { chooseAdb() }
                    }
                }
                Text("手机重启后，需要再插一次数据线启动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            .font(.callout)
        }
        .padding(.horizontal, 4)
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
