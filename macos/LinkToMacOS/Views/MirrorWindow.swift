import LinkCore
import SwiftUI

// MARK: - 窗口

/// 投屏窗口用 AppKit 自己创建，不走 SwiftUI 的 Window：真正的无边框透明窗口（没有标题栏、红绿灯和任何系统外框），
/// 窗口本身就是一部带仿真边框和打孔摄像头的手机，右侧悬浮一条竖向工具栏。
/// 无边框窗口默认不能成为键盘焦点（打字要转给手机），所以用子类打开这一点。
final class PhoneWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class MirrorWindowController: NSObject, NSWindowDelegate {
    private var window: PhoneWindow?
    private let session: MirrorSession
    private let title: String
    var isOpen: Bool { window != nil }
    /// 窗口关闭时调用。
    var onClosed: () -> Void = {}

    init(session: MirrorSession, title: String) {
        self.session = session
        self.title = title
    }

    /// `compact`：投屏还没开始（或失败）时用小窗口，只显示进度或错误；开始后窗口会按手机比例重新定大小。
    func show(compact: Bool = false) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let chrome = MirrorContent.chrome
        let video = session.videoSize
        // 初始大小：按手机比例，长边 780；窗口显示后 VideoView 会再按屏幕大小和比例校正一次
        let aspect = video.width > 0 && video.height > 0 ? video.width / video.height : 0.466
        var size = aspect >= 1
            ? NSSize(width: 780 + chrome.width, height: 780 / aspect + chrome.height)
            : NSSize(width: 780 * aspect + chrome.width, height: 780 + chrome.height)
        if compact { size = NSSize(width: 380, height: 320) }

        let window = PhoneWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false  // 阴影由手机自己画
        window.isMovableByWindowBackground = false  // 拖动只在手机边框和空白处生效（见 DragArea），拖屏幕是触摸
        window.title = title
        window.delegate = self

        let hosting = NSHostingView(rootView: MirrorWindowRoot(
            session: session,
            onClose: { [weak self] in self?.close() },
            onPin: { [weak self] pinned in self?.window?.level = pinned ? .floating : .normal }))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// 关闭窗口。
    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClosed()
    }
}

struct MirrorWindowRoot: View {
    let session: MirrorSession
    let onClose: () -> Void
    let onPin: (Bool) -> Void

    var body: some View {
        Group {
            switch session.phase {
            case .running:
                MirrorContent(session: session)
            case .failed(let message):
                VStack(spacing: 14) {
                    ContentUnavailableView("投屏已中断", systemImage: "iphone.slash", description: Text(message))
                    Button("关闭", action: onClose)
                        .controlSize(.large)
                }
                .padding(20)
                .frame(minWidth: 340, minHeight: 260)
                .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
                .padding(14)
                .background(DragArea())
            default:
                ProgressView()
                    .controlSize(.large)
                    .frame(width: 160, height: 120)
                    .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
                    .padding(14)
                    .background(DragArea())
            }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .idle { onClose() }
        }
        .onChange(of: session.alwaysOnTop, initial: true) { _, pinned in onPin(pinned) }
    }
}

/// 窗口四周一圈很窄的缩放区：拖边或角，按手机比例等比缩放，画面始终充满边框。
/// 无边框窗口没有系统的缩放把手，这里自己做；除了这一圈，其余地方的鼠标事件都穿透给下面的画面和按钮。
private struct ResizeRing: NSViewRepresentable {
    let chrome: CGSize
    let videoSize: CGSize

    func makeNSView(context: Context) -> Ring { Ring() }

    func updateNSView(_ view: Ring, context: Context) {
        view.chrome = chrome
        view.videoSize = videoSize
    }

    final class Ring: NSView {
        var chrome: CGSize = .zero
        var videoSize: CGSize = .zero

        private static let band: CGFloat = 7
        private static let corner: CGFloat = 16

        private struct Edges: OptionSet {
            let rawValue: Int
            static let left = Edges(rawValue: 1)
            static let right = Edges(rawValue: 2)
            static let top = Edges(rawValue: 4)
            static let bottom = Edges(rawValue: 8)
        }

        private var edges: Edges = []
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        override var isFlipped: Bool { false }

        private func edges(at point: NSPoint) -> Edges {
            var result: Edges = []
            let band = Self.band, corner = Self.corner
            let nearLeft = point.x < band, nearRight = point.x > bounds.width - band
            let nearBottom = point.y < band, nearTop = point.y > bounds.height - band
            if nearLeft { result.insert(.left) }
            if nearRight { result.insert(.right) }
            if nearBottom { result.insert(.bottom) }
            if nearTop { result.insert(.top) }
            // 角：靠近两条边的交点时，同时算两条边
            if point.x < corner && point.y < corner { result.formUnion([.left, .bottom]) }
            if point.x > bounds.width - corner && point.y < corner { result.formUnion([.right, .bottom]) }
            if point.x < corner && point.y > bounds.height - corner { result.formUnion([.left, .top]) }
            if point.x > bounds.width - corner && point.y > bounds.height - corner { result.formUnion([.right, .top]) }
            return result
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            return bounds.contains(local) && !edges(at: local).isEmpty ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            let band = Self.band, corner = Self.corner, w = bounds.width, h = bounds.height
            func add(_ rect: NSRect, _ position: NSCursor.FrameResizePosition) {
                addCursorRect(rect, cursor: .frameResize(position: position, directions: .all))
            }
            add(NSRect(x: 0, y: corner, width: band, height: h - 2 * corner), .left)
            add(NSRect(x: w - band, y: corner, width: band, height: h - 2 * corner), .right)
            add(NSRect(x: corner, y: 0, width: w - 2 * corner, height: band), .bottom)
            add(NSRect(x: corner, y: h - band, width: w - 2 * corner, height: band), .top)
            add(NSRect(x: 0, y: 0, width: corner, height: corner), .bottomLeft)
            add(NSRect(x: w - corner, y: 0, width: corner, height: corner), .bottomRight)
            add(NSRect(x: 0, y: h - corner, width: corner, height: corner), .topLeft)
            add(NSRect(x: w - corner, y: h - corner, width: corner, height: corner), .topRight)
        }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            edges = edges(at: convert(event.locationInWindow, from: nil))
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, !edges.isEmpty, videoSize.width > 0, videoSize.height > 0 else { return }
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x
            let dy = mouse.y - startMouse.y  // 屏幕坐标，向上为正
            let ratio = startFrame.width / startFrame.height

            // 先算宽度的变化量；拖上下边时，把高度变化按比例换成宽度变化
            var widthDelta: CGFloat = 0
            let horizontal = edges.contains(.left) || edges.contains(.right)
            let vertical = edges.contains(.top) || edges.contains(.bottom)
            if horizontal { widthDelta = edges.contains(.right) ? dx : -dx }
            if vertical {
                let heightDelta = edges.contains(.top) ? dy : -dy
                let fromHeight = heightDelta * ratio
                widthDelta = horizontal ? (abs(fromHeight) > abs(widthDelta) ? fromHeight : widthDelta) : fromHeight
            }

            let minimum = window.minSize.width
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            let maximum = visible.map { min($0.width, ($0.height - chrome.height) * videoSize.width / videoSize.height + chrome.width) } ?? 4000
            let width = min(max(startFrame.width + widthDelta, minimum), max(minimum, maximum))
            // 画面宽度 = 窗口宽度 - 固定部分，高度按画面比例算，再加固定部分：画面总是正好充满边框
            let height = (width - chrome.width) * videoSize.height / videoSize.width + chrome.height

            var frame = NSRect(x: 0, y: 0, width: width, height: height)
            frame.origin.x = edges.contains(.left) ? startFrame.maxX - width : startFrame.minX
            frame.origin.y = edges.contains(.top) ? startFrame.minY : startFrame.maxY - height
            window.setFrame(frame, display: true)
        }
    }
}

/// 在这块区域按下鼠标就拖动窗口。铺在手机后面：边框、四周空白处能拖，画面和按钮仍然正常响应。
private struct DragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Handle: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// 投屏窗口里的内容：手机，加右侧悬浮工具栏。
struct MirrorContent: View {
    let session: MirrorSession

    /// 画面以外占的固定尺寸，截图和窗口比例计算都用它。
    static var chrome: CGSize { PhoneBody.chrome }

    var body: some View {
        HStack(spacing: 0) {
            PhoneBody(session: session)
                .padding(.leading, PhoneBody.margin)
                .padding(.vertical, PhoneBody.margin)
            MirrorSideBar(session: session)
                .frame(width: MirrorSideBar.width)
        }
        .background(DragArea())
        .overlay { ResizeRing(chrome: PhoneBody.chrome, videoSize: session.videoSize) }
    }
}

/// 仿真手机：金属中框、黑色边框、圆角屏幕和打孔摄像头。屏幕里是投屏画面。
private struct PhoneBody: View {
    @Bindable var session: MirrorSession

    static let margin: CGFloat = 12
    static let bezel: CGFloat = 5.5
    /// 画面以外占的固定尺寸：左边距 + 两侧边框 + 右侧按键栏；上下边距 + 上下边框。
    static var chrome: CGSize {
        CGSize(width: margin + 2 * bezel + MirrorSideBar.width, height: 2 * margin + 2 * bezel)
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = CGSize(width: max(1, proxy.size.width - 2 * Self.bezel), height: max(1, proxy.size.height - 2 * Self.bezel))
            let radius = 0.06 * min(screen.width, screen.height)
            let outer = radius + Self.bezel
            ZStack {
                // 金属中框：左右两侧亮、中间暗，像拉丝金属的反光
                RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: Color(white: 0.66), location: 0),
                        .init(color: Color(white: 0.34), location: 0.1),
                        .init(color: Color(white: 0.48), location: 0.5),
                        .init(color: Color(white: 0.30), location: 0.9),
                        .init(color: Color(white: 0.60), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                    .allowsHitTesting(false)
                // 黑色玻璃边框
                RoundedRectangle(cornerRadius: outer - 1.5, style: .continuous)
                    .fill(Color.black)
                    .padding(1.5)
                    .allowsHitTesting(false)
                // 屏幕
                VideoView(
                    decoder: session.decoder, videoSize: session.videoSize, chrome: Self.chrome,
                    onInput: { session.send($0) })
                    .frame(width: screen.width, height: screen.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        camera(in: screen)
                            .allowsHitTesting(false)
                    }
                // 玻璃的斜向高光
                RoundedRectangle(cornerRadius: outer - 1.2, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(1.2)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
        }
    }

    /// 打孔摄像头：竖屏时在顶部居中，横屏时在左侧居中（手机转过来摄像头就在左边）。
    private func camera(in screen: CGSize) -> some View {
        let portrait = session.videoSize.width <= session.videoSize.height
        let d = max(7, 0.034 * min(screen.width, screen.height))
        let inset = max(4, 0.014 * min(screen.width, screen.height))
        return Lens(diameter: d)
            .offset(
                x: portrait ? (screen.width - d) / 2 : inset,
                y: portrait ? inset : (screen.height - d) / 2)
    }
}

/// 摄像头镜头：黑色圆孔、深灰圈、一点蓝紫色的镀膜反光。
private struct Lens: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().strokeBorder(Color(white: 0.2), lineWidth: max(0.7, diameter * 0.07))
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.42).opacity(0.9), .clear],
                                     center: .center, startRadius: 0, endRadius: diameter * 0.32))
                .frame(width: diameter * 0.62, height: diameter * 0.62)
            Circle().fill(.white.opacity(0.4))
                .frame(width: diameter * 0.13, height: diameter * 0.13)
                .offset(x: -diameter * 0.15, y: -diameter * 0.15)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 右侧悬浮工具栏：关闭、关屏、电源、音量、导航键（◁ ○ ▢）、更多。空白处和边缘可以拖动窗口。
private struct MirrorSideBar: View {
    static let width: CGFloat = 56
    @Bindable var session: MirrorSession

    var body: some View {
        VStack(spacing: 4) {
            SideButton("停止投屏", systemImage: "xmark", help: "停止投屏") {
                Task { await session.stop() }
            }
            .foregroundStyle(.secondary)

            SideButton(
                session.phoneScreenIsOff ? "打开手机屏幕" : "关闭手机屏幕",
                systemImage: session.phoneScreenIsOff ? "moon.fill" : "moon",
                help: "开关手机自己的屏幕，投屏不受影响（⇧⌘O）"
            ) { session.setPhoneScreen(off: !session.phoneScreenIsOff) }
            .foregroundStyle(session.phoneScreenIsOff ? Color.accentColor : .secondary)

            SideButton("电源键", systemImage: "power", help: "电源键：锁屏 / 唤醒手机") {
                session.send(.command("power"))
            }

            Separator()

            SideButton("调大音量", systemImage: "speaker.plus", help: "调大音量") { session.press(keyCode: AndroidKey.volumeUp) }
            SideButton("调小音量", systemImage: "speaker.minus", help: "调小音量") { session.press(keyCode: AndroidKey.volumeDown) }

            Separator()

            SideButton("返回", systemImage: "arrowtriangle.backward", help: "返回（Esc、⌘[ 或右键）") {
                session.send(.command("back"))
            }
            if session.isNewDisplay {
                SideButton("打开应用", systemImage: "circle", help: "在这个窗口里打开应用（⇧⌘A）") {
                    session.showAppLauncher.toggle()
                }
                .popover(isPresented: $session.showAppLauncher, arrowEdge: .leading) {
                    AppLauncherView(session: session) { app in
                        session.showAppLauncher = false
                        Task { await session.launch(app) }
                    }
                    .frame(width: 420, height: 460)
                }
                SideButton("最近打开", systemImage: "square", help: "切换到这次打开过的应用（⇧⌘R）") {
                    session.showRecentApps.toggle()
                }
                .popover(isPresented: $session.showRecentApps, arrowEdge: .leading) {
                    RecentAppsView(session: session)
                }
            } else {
                SideButton("主页", systemImage: "circle", help: "主页（⇧⌘H 或中键）") {
                    session.send(.command("home"))
                }
                SideButton("最近任务", systemImage: "square", help: "最近任务（⇧⌘R）") {
                    session.send(.command("recents"))
                }
            }

            Separator()

            Menu {
                Section("声音") {
                    Button("静音", systemImage: "speaker.slash") { session.press(keyCode: AndroidKey.volumeMute) }
                    Button("播放 / 暂停", systemImage: "playpause") { session.press(keyCode: AndroidKey.mediaPlayPause) }
                    Button("上一首", systemImage: "backward.end") { session.press(keyCode: AndroidKey.mediaPrevious) }
                    Button("下一首", systemImage: "forward.end") { session.press(keyCode: AndroidKey.mediaNext) }
                }
                Section("手机") {
                    if session.isNewDisplay {
                        Button("旋转方向", systemImage: "rotate.right") { Task { await session.rotate() } }
                    } else {
                        Button("展开通知栏", systemImage: "bell") { session.send(.command("notifications")) }
                        Button("唤醒手机屏幕", systemImage: "sun.max") { session.send(.command("wake")) }
                    }
                    Button("粘贴 Mac 剪贴板里的文字", systemImage: "doc.on.clipboard") {
                        if let text = NSPasteboard.general.string(forType: .string) { session.type(text) }
                    }
                }
                Section("窗口") {
                    Toggle("窗口置顶", systemImage: "pin", isOn: $session.alwaysOnTop)
                }
                Divider()
                Button("停止投屏", systemImage: "stop.circle", role: .destructive) { Task { await session.stop() } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background {
            // 材质底板不接收鼠标，下面铺一层拖动区域：工具栏上没有按钮的地方也能拖动窗口
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial).allowsHitTesting(false)
                DragArea().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .frame(maxHeight: .infinity, alignment: .center)
        .frame(width: Self.width)
    }

    /// 工具栏里的分组线。
    private struct Separator: View {
        var body: some View {
            Divider().frame(width: 22).padding(.vertical, 3).allowsHitTesting(false)
        }
    }
}

/// Android 键值（android.view.KeyEvent）。
enum AndroidKey {
    static let volumeUp = 24
    static let volumeDown = 25
    static let volumeMute = 164
    static let mediaPlayPause = 85
    static let mediaNext = 87
    static let mediaPrevious = 88
}

private struct SideButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

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
                .font(.system(size: 13, weight: .medium))
                .frame(width: 34, height: 30)
                .background(hovering ? Color.primary.opacity(0.1) : Color.clear, in: .rect(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
