import LinkCore
import SwiftUI

/// 菜单栏命令和快捷键。
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

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
            Button("AirSend") { go(.airsend) }.keyboardShortcut("8").disabled(model.activeLibrary == nil)
            Divider()
            Button("所有项目") { go(.library) }.keyboardShortcut("3").disabled(model.activeLibrary == nil)
            Button("视频") { go(.videos) }.keyboardShortcut("4").disabled(model.activeLibrary == nil)
            Divider()
            Button("应用") { go(.apps) }.keyboardShortcut("5").disabled(model.activeLibrary == nil)
            Divider()
            Button("内部存储") { go(.files("")) }.keyboardShortcut("6").disabled(model.activeLibrary == nil)
            Button("下载") { go(.files("Download")) }.keyboardShortcut("7").disabled(model.activeLibrary == nil)
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
