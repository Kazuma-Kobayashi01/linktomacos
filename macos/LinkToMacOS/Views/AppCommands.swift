import LinkCore
import SwiftUI

/// 菜单栏命令和快捷键。
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mirrorSession) private var mirror

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("配对新手机…") {
                model.beginPairing()
                openWindow(id: WindowID.pairing)
                NSApp.activate()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(before: .windowList) {
            Button("主窗口") { showMain() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandMenu("前往") {
            Button("概览") { go(.overview) }.keyboardShortcut("1")
            Button("投屏") { go(.mirror) }.keyboardShortcut("2").disabled(model.activeLibrary == nil)
            Divider()
            Button("所有项目") { go(.library) }.keyboardShortcut("3").disabled(model.activeLibrary == nil)
            Button("视频") { go(.videos) }.keyboardShortcut("4").disabled(model.activeLibrary == nil)
            Divider()
            Button("应用") { go(.apps) }.keyboardShortcut("5").disabled(model.activeLibrary == nil)
            Divider()
            Button("内部存储") { go(.files("")) }.keyboardShortcut("6").disabled(model.activeLibrary == nil)
            Button("下载") { go(.files("Download")) }.keyboardShortcut("7").disabled(model.activeLibrary == nil)
        }

        // 只在投屏窗口在前台时可用
        CommandMenu("投屏") {
            let running = mirror?.isRunning == true
            let newDisplay = mirror?.isNewDisplay == true
            Button("返回") { mirror?.send(.command("back")) }
                .keyboardShortcut("[")
                .disabled(!running)
            Button("主页") { mirror?.send(.command("home")) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!running || newDisplay)
            Button("最近任务") {
                if newDisplay { mirror?.showRecentApps = true } else { mirror?.send(.command("recents")) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!running)
            Button("打开应用…") { mirror?.showAppLauncher = true }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!running || !newDisplay)
            Divider()
            Button(mirror?.phoneScreenIsOff == true ? "打开手机屏幕" : "关闭手机屏幕") {
                if let mirror { mirror.setPhoneScreen(off: !mirror.phoneScreenIsOff) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!running)
            Divider()
            Button("停止投屏") { Task { await mirror?.stop() } }
                .disabled(!running)
        }
    }

    private func showMain() {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    private func go(_ item: SidebarItem) {
        model.sidebarSelection = item
        showMain()
    }
}
