#if DEBUG
import AppKit
import SwiftUI

/// 调试用：`LINKTOMACOS_SNAPSHOT=<目录>` 启动时，用示例数据把主页离屏渲染成 PNG 后立即退出，
/// 不启动服务、不连接手机、不显示任何窗口。用于检查界面在浅色/深色、宽/窄窗口下的效果。
enum SnapshotRenderer {
    @MainActor
    static func runIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["LINKTOMACOS_SNAPSHOT"] else { return }
        let model = AppModel()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (suffix, width, online) in [("wide", 1100.0, true), ("narrow", 760.0, true), ("offline", 1100.0, false)] {
                let view = OverviewView(monitor: .sample(online: online))
                    .environment(model)
                    .frame(width: width, height: 2400)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2400)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let url = URL(fileURLWithPath: directory).appendingPathComponent("overview-\(name)-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        exit(0)
    }
}
#endif
