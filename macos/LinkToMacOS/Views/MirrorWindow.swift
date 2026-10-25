import LinkCore
import SwiftUI

/// 投屏窗口：精简的标题栏（只有红绿灯和标题），手机画面，底部一条小导航栏。
/// 窗口比例固定为手机比例（加上导航栏的高度），可以随意缩放。
struct MirrorWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let session = model.mirror
        Group {
            switch session.phase {
            case .running:
                VStack(spacing: 0) {
                    VideoView(
                        decoder: session.decoder, videoSize: session.videoSize,
                        chromeHeight: MirrorNavBar.height,
                        onInput: { session.send($0) })
                    MirrorNavBar(session: session)
                }
            case .failed(let message):
                ContentUnavailableView("投屏已中断", systemImage: "iphone.slash", description: Text(message))
            default:
                ProgressView()
            }
        }
        .frame(minWidth: 200, minHeight: 260)
        .navigationTitle(model.activeDevice?.device.name ?? String(localized: "投屏"))
        .focusedSceneValue(\.mirrorSession, session)
        .onDisappear {
            Task { await session.stop() }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .idle { dismissWindow(id: WindowID.mirror) }
        }
    }
}

/// 底部导航栏：中间是三个导航键（◁ ○ ▢），左边开关手机屏幕，右边是更多操作。
private struct MirrorNavBar: View {
    static let height: CGFloat = 30
    @Bindable var session: MirrorSession

    var body: some View {
        HStack(spacing: 0) {
            BarButton(
                session.phoneScreenIsOff ? "打开手机屏幕" : "关闭手机屏幕",
                systemImage: session.phoneScreenIsOff ? "moon.fill" : "moon",
                help: "开关手机自己的屏幕，投屏不受影响（⇧⌘O）"
            ) { session.setPhoneScreen(off: !session.phoneScreenIsOff) }
            .foregroundStyle(session.phoneScreenIsOff ? Color.accentColor : .secondary)

            Spacer(minLength: 4)
            HStack(spacing: 18) {
                BarButton("返回", systemImage: "arrowtriangle.backward", help: "返回（Esc、⌘[ 或右键）") {
                    session.send(.command("back"))
                }
                if session.isNewDisplay {
                    BarButton("打开应用", systemImage: "circle", help: "在这个窗口里打开应用（⇧⌘A）") {
                        session.showAppLauncher.toggle()
                    }
                    .popover(isPresented: $session.showAppLauncher, arrowEdge: .bottom) {
                        AppLauncherView(session: session) { app in
                            session.showAppLauncher = false
                            Task { await session.launch(app) }
                        }
                        .frame(width: 420, height: 460)
                    }
                    BarButton("最近打开", systemImage: "square", help: "切换到这次打开过的应用（⇧⌘R）") {
                        session.showRecentApps.toggle()
                    }
                    .popover(isPresented: $session.showRecentApps, arrowEdge: .bottom) {
                        RecentAppsView(session: session)
                    }
                } else {
                    BarButton("主页", systemImage: "circle", help: "主页（⇧⌘H 或中键）") {
                        session.send(.command("home"))
                    }
                    BarButton("最近任务", systemImage: "square", help: "最近任务（⇧⌘R）") {
                        session.send(.command("recents"))
                    }
                }
            }
            Spacer(minLength: 4)

            Menu {
                if session.isNewDisplay {
                    Button("旋转方向") { Task { await session.rotate() } }
                    Divider()
                } else {
                    Button("展开通知栏") { session.send(.command("notifications")) }
                    Button("唤醒手机屏幕") { session.send(.command("wake")) }
                    Divider()
                }
                Button("停止投屏") { Task { await session.stop() } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28)
            .help("更多")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct BarButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// 独立显示里打开过的应用，点一下切回去（不会重新启动它）。
private struct RecentAppsView: View {
    let session: MirrorSession

    var body: some View {
        Group {
            if session.recentApps.isEmpty {
                Text("还没有打开过应用").foregroundStyle(.secondary).padding(20)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 6), count: min(4, session.recentApps.count)), spacing: 8) {
                    ForEach(session.recentApps) { app in
                        AppCell(app: app, icons: session.icons)
                            .onTapGesture {
                                session.showRecentApps = false
                                Task { await session.launch(app, forceStop: false) }
                            }
                    }
                }
                .padding(12)
            }
        }
    }
}
