#if DEBUG
import AppKit
import LinkCore
import SwiftUI
import WidgetKit

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
        renderWidgets(into: directory)
        renderPages(model: model, into: directory)
        renderAirSendWindow(into: directory)
        renderMenuBarLogo(into: directory)
        exit(0)
    }

    /// 菜单栏图标和系统图标并排对比（深色 / 浅色菜单栏，已连接 / 未连接），放大 6 倍看细节。
    @MainActor
    private static func renderMenuBarLogo(into directory: String) {
        let scale: CGFloat = 6
        let barHeight: CGFloat = 24
        let symbols = ["bluetooth", "wifi", "speaker.wave.2.fill", "magnifyingglass", "battery.75percent"]
        let width: CGFloat = 220
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(barHeight * 2 * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: barHeight * 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (index, (background, foreground)) in [(NSColor(white: 0.12, alpha: 1), NSColor.white), (NSColor(white: 0.93, alpha: 1), NSColor.black)].enumerated() {
            let originY = CGFloat(index) * barHeight
            background.setFill()
            NSRect(x: 0, y: originY, width: width, height: barHeight).fill()
            var x: CGFloat = 8
            func draw(_ image: NSImage) {
                let tinted = NSImage(size: image.size)
                tinted.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: image.size))
                foreground.set()
                NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: x, y: originY + (barHeight - image.size.height) / 2, width: image.size.width, height: image.size.height))
                x += image.size.width + 8
            }
            for name in symbols {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let symbol = NSImage(systemSymbolName: name == "bluetooth" ? "wifi" : name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                    draw(symbol)
                }
            }
            draw(MenuBarIcon.logo(connected: true))
            draw(MenuBarIcon.logo(connected: false))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menubar-logo.png"))
    }

    /// AirSend 接收进度窗口：传输中 / 完成。
    @MainActor
    private static func renderAirSendWindow(into directory: String) {
        let files = [AirFile(name: "IMG_20261026_1432.jpg", size: 4_200_000), AirFile(name: "Report.pdf", size: 1_800_000)]
        let window = AirSendProgressWindow(device: "Galaxy S23 Ultra", files: files) {}
        window.update(completed: 2_700_000, total: 6_000_000)
        for (name, finish) in [("progress", false), ("done", true)] {
            if finish { window.finish(saved: [URL(fileURLWithPath: "/tmp/IMG.jpg"), URL(fileURLWithPath: "/tmp/Report.pdf")], device: "Galaxy S23 Ultra") }
            let w = window.snapshotWindow
            w.contentView?.layoutSubtreeIfNeeded()
            guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("airsend-window-\(name).png"))
        }
    }

    /// 通用：把一个视图渲染成浅色、深色两张 PNG。
    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize, name: String, into directory: String, model: AppModel) {
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let hosting = NSHostingView(rootView: view.environment(model).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(label).png"))
        }
    }

    /// 菜单栏面板、投屏页（设置前 / 设置好 / 投屏中）、AirSend 页、投屏窗口（竖屏 / 横屏）。
    @MainActor
    private static func renderPages(model: AppModel, into directory: String) {
        // 菜单栏面板：没有手机 / 已连接
        render(MenuView(), size: CGSize(width: 320, height: 330), name: "menu-empty", into: directory, model: model)
        model.installSampleDevice()
        render(MenuView(), size: CGSize(width: 320, height: 470), name: "menu-connected", into: directory, model: model)

        // 投屏页
        MirrorPage.pollingEnabled = false
        let library = PhoneLibrary(remote: PhoneRemote { _ in }, deviceName: "Galaxy S23 Ultra")
        let usb = AdbDevice(serial: "x", state: "device", model: "SM_S9180", isUSB: true)
        let waiting = AdbDevice(serial: "x", state: "unauthorized", model: nil, isUSB: true)
        for (name, ready, devices, phase) in [
            ("mirror-setup-1", Optional(false), [AdbDevice](), MirrorSession.Phase.idle),
            ("mirror-setup-2", Optional(false), [waiting], .idle),
            ("mirror-setup-3", Optional(false), [usb], .idle),
            ("mirror-ready", Optional(true), [usb], .idle),
            ("mirror-running", Optional(true), [usb], .running),
        ] {
            model.mirror.debugApply(serviceReady: ready, devices: devices, phase: phase)
            render(MirrorPage(library: library), size: CGSize(width: 760, height: name == "mirror-ready" ? 780 : 560), name: name, into: directory, model: model)
        }

        // AirSend 页
        model.airSend.loadSample()
        render(AirSendView(), size: CGSize(width: 760, height: 900), name: "airsend", into: directory, model: model)

        // 投屏窗口：竖屏 / 横屏
        let chrome = MirrorContent.chrome
        for (name, video) in [("mirrorwindow-portrait", CGSize(width: 360, height: 772)), ("mirrorwindow-landscape", CGSize(width: 772, height: 360))] {
            model.mirror.debugApply(serviceReady: true, devices: [usb], phase: .running,
                                    videoSize: CGSize(width: video.width > video.height ? 2316 : 1080, height: video.width > video.height ? 1080 : 2316))
            render(MirrorContent(session: model.mirror), size: CGSize(width: video.width + chrome.width, height: video.height + chrome.height), name: name, into: directory, model: model)
        }
    }

    /// 小组件：小 / 中 / 大，浅色 / 深色，有数据 / 离线 / 还没有数据。
    @MainActor
    private static func renderWidgets(into directory: String) {
        let sizes: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("large", .systemLarge, CGSize(width: 364, height: 382)),
        ]
        var offline = WidgetSnapshot.sample
        offline.online = false
        offline.charging = false
        offline.lastSeen = Date().addingTimeInterval(-26 * 60)
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (stateName, snapshot) in [("online", Optional(WidgetSnapshot.sample)), ("offline", Optional(offline)), ("empty", nil)] {
                for (sizeName, family, size) in sizes {
                    let view = LinkWidgetView(entry: LinkWidgetEntry(date: Date(), snapshot: snapshot), familyOverride: family)
                        .padding(16)
                        .frame(width: size.width, height: size.height)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor)))
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(origin: .zero, size: size)
                    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: appearance)
                    window.contentView = hosting
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                    hosting.cacheDisplay(in: hosting.bounds, to: rep)
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("widget-\(sizeName)-\(stateName)-\(appearanceName).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
    }
}
#endif
