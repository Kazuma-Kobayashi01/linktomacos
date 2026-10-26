import AppKit

// 投屏助手：一个独立的 App（有自己的 Dock 图标），由主程序启动，只负责显示手机画面和转发输入。
// 它不直接连手机：请求、视频、输入都经本机的中继交给主程序，由主程序转发（见 LinkCore/Relay.swift）。
let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { MirrorHelperDelegate() }
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
