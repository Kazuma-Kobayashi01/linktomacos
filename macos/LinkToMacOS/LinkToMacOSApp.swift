import AppKit
import SwiftUI

@main
struct LinkToMacOSApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(appDelegate.model)
        } label: {
            Image(systemName: appDelegate.model.connected.isEmpty ? "iphone.slash" : "iphone")
        }
        .menuBarExtraStyle(.window)

        Window("配对新手机", id: WindowID.pairing) {
            PairingView()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum WindowID {
    static let pairing = "pairing"
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
