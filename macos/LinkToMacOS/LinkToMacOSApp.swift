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
            Image(systemName: appDelegate.model.connected.isEmpty ? "iphone.slash" : "iphone")
        }
        .menuBarExtraStyle(.window)

        Window("LinkToMacOS", id: WindowID.main) {
            MainWindow()
                .environment(appDelegate.model)
        }
        .defaultSize(width: 1120, height: 720)
        .defaultLaunchBehavior(Prefs.bool(Prefs.openMainWindowAtLaunch, default: true) ? .presented : .suppressed)
        .commands { AppCommands(model: appDelegate.model) }

        Window("投屏", id: WindowID.mirror) {
            MirrorWindow()
                .environment(appDelegate.model)
        }
        .defaultSize(width: 400, height: 867)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

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

enum WindowID {
    static let main = "main"
    static let pairing = "pairing"
    static let mirror = "mirror"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { model.start() }
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
