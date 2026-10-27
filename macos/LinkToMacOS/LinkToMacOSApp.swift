import AppKit
import SwiftUI

@main
struct LinkToMacOSApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        #if DEBUG
        MainActor.assumeIsolated { SnapshotRenderer.runIfRequested() }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Link to macOS", id: WindowID.main) {
            MainWindow()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: MainWindow.windowWidth, height: 720)
        .defaultLaunchBehavior(Prefs.bool(Prefs.openMainWindowAtLaunch, default: true) ? .presented : .suppressed)
        .commands { AppCommands(model: appDelegate.model) }

        Window("配对新手机", id: WindowID.pairing) {
            PairingView()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }
    }
}

/// 菜单栏图标。顺便把 openWindow 交给 AppModel：AppDelegate 里（比如点了桌面小组件）也要能打开窗口。
struct MenuBarIcon: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.logo(connected: !model.connected.isEmpty))
            .onAppear { model.openWindowAction = { openWindow(id: $0) } }
    }
}

extension MenuBarIcon {
    /// 菜单栏图标：应用图标的镂空线稿，模板图像（随菜单栏深浅自动着色）；没连上手机时淡一些。
    /// 菜单栏按图像自身的尺寸显示，不认 SwiftUI 的 frame，所以在这里把尺寸定好。
    static func logo(connected: Bool) -> NSImage {
        // 画布高 18、宽 22，图案 19.5 × 15.8 居中：和系统的 Wi‑Fi、音量等图标视觉大小、垂直位置一致
        let canvas = NSSize(width: 22, height: 18)
        let logo = NSSize(width: 19.5, height: 15.8)
        guard let base = NSImage(named: "MenuBarLogo") else { return NSImage(systemSymbolName: "iphone", accessibilityDescription: nil) ?? NSImage() }
        let image = NSImage(size: canvas, flipped: false) { rect in
            let target = NSRect(x: (rect.width - logo.width) / 2, y: (rect.height - logo.height) / 2, width: logo.width, height: logo.height)
            base.draw(in: target, from: .zero, operation: .sourceOver, fraction: connected ? 1 : 0.5)
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum WindowID {
    static let main = "main"
    static let pairing = "pairing"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { model.start() }
    }

    /// 桌面小组件点击：linktomacos://overview
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "linktomacos" }) else { return }
        MainActor.assumeIsolated {
            switch url.host {
            case "overview": model.showMainWindow(.overview)
            default: model.showMainWindow()
            }
        }
    }

    /// 退出前先向手机发 goodbye（最多等 1 秒），手机据此立刻退出免打扰。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await model.prepareForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
